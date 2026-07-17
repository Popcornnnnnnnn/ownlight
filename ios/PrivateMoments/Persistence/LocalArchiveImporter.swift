import Foundation

struct LocalArchiveImportPreview {
    let version: Int
    let exportedAt: String
    let generator: String
    let counts: LocalArchiveImportCounts
    let privacy: LocalArchiveImportPrivacy
}

struct LocalArchiveImportResult {
    let imported: LocalArchiveImportCounts
}

struct LocalArchiveImportCounts: Decodable, Equatable {
    let posts: Int
    let postMedia: Int
    let comments: Int
    let tags: Int
    let checkInItems: Int
    let checkInEntries: Int
    let checkInMedia: Int
    let aiSummaries: Int
    let weeklyReviews: Int
    let mediaFilesIncluded: Int
    let missingMedia: Int
}

struct LocalArchiveImportPrivacy: Decodable, Equatable {
    let containsCredentials: Bool
    let containsProviderAPIKeys: Bool
    let containsPrivateTranscriptText: Bool
    let encrypted: Bool
    let note: String
}

enum LocalArchiveImportError: LocalizedError, Equatable {
    case missingArchiveEntry(String)
    case unsupportedArchiveVersion(Int)
    case unsupportedCompression
    case invalidArchive(String)
    case targetDatabaseNotEmpty

    var errorDescription: String? {
        switch self {
        case .missingArchiveEntry(let path):
            return "Archive is missing \(path)."
        case .unsupportedArchiveVersion(let version):
            return "Archive version \(version) is not supported."
        case .unsupportedCompression:
            return "Archive uses an unsupported compression method."
        case .invalidArchive(let message):
            return "Archive is invalid: \(message)"
        case .targetDatabaseNotEmpty:
            return "Import is only available when this iPhone has no existing local records."
        }
    }
}

enum LocalArchiveImporter {
    static func preview(archiveURL: URL) throws -> LocalArchiveImportPreview {
        let package = try readPackage(archiveURL: archiveURL)
        return LocalArchiveImportPreview(
            version: package.manifest.version,
            exportedAt: package.manifest.exportedAt,
            generator: package.manifest.generator,
            counts: package.manifest.counts,
            privacy: package.manifest.privacy
        )
    }

    static func importArchive(from archiveURL: URL, into database: LocalDatabase) throws -> LocalArchiveImportResult {
        let package = try readPackage(archiveURL: archiveURL)
        guard try isTargetEmpty(database) else {
            throw LocalArchiveImportError.targetDatabaseNotEmpty
        }

        var copiedMediaURLs: [URL] = []

        do {
            let mediaPaths = try materializeMediaFiles(from: package.entries, copiedMediaURLs: &copiedMediaURLs)
            var removedWelcomeSample = false
            try database.transaction {
                removedWelcomeSample = try database.softDeleteWelcomeSampleForArchiveImport(deletedAt: Date())
                guard try isTargetEmpty(database) else {
                    throw LocalArchiveImportError.targetDatabaseNotEmpty
                }

                for tag in package.archive.tags {
                    try database.upsertTag(tag)
                }
                for alias in package.archive.tagAliases {
                    try database.upsertTagAlias(alias)
                }
                for item in package.archive.checkInItems {
                    try database.upsertCheckInItemOnly(item)
                }
                for entry in package.archive.checkInEntries {
                    try database.upsertCheckInEntryOnly(entry)
                }
                for postRecord in package.archive.posts {
                    try database.insert(postRecord.post)
                    for mediaRecord in postRecord.media {
                        try database.insert(mediaRecord.timelineMedia(paths: mediaPaths.timeline[mediaRecord.id]))
                    }
                    for comment in postRecord.comments {
                        try database.insert(comment)
                    }
                    for summary in postRecord.aiSummaries {
                        try database.upsertAISummary(summary)
                    }
                    for assignedTag in postRecord.tags {
                        try database.upsertAssignedTag(assignedTag)
                    }
                }
                for mediaRecord in package.archive.checkInMedia {
                    try database.upsertCheckInMediaOnly(mediaRecord.checkInMedia(path: mediaPaths.checkIn[mediaRecord.id]))
                }
                for summary in package.archive.checkInAISummaries {
                    try database.upsertCheckInAISummary(summary)
                }
            }
            if removedWelcomeSample {
                AppSettings.welcomeSampleDeleted = true
            }

            AppSettings.localWeeklyReviews = package.archive.weeklyReviews

            return LocalArchiveImportResult(imported: package.manifest.counts)
        } catch {
            for url in copiedMediaURLs {
                try? FileManager.default.removeItem(at: url)
            }
            throw error
        }
    }

    private static func readPackage(archiveURL: URL) throws -> LocalArchivePackage {
        let didStartAccessing = archiveURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                archiveURL.stopAccessingSecurityScopedResource()
            }
        }

        let entries = try StoredZipReader.read(url: archiveURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let manifestData = entries["manifest.json"] else {
            throw LocalArchiveImportError.missingArchiveEntry("manifest.json")
        }
        let manifest = try decoder.decode(LocalArchiveImportManifest.self, from: manifestData)
        guard manifest.version == 1 else {
            throw LocalArchiveImportError.unsupportedArchiveVersion(manifest.version)
        }

        guard let archiveData = entries["data/archive.json"] else {
            throw LocalArchiveImportError.missingArchiveEntry("data/archive.json")
        }
        let archive = try decoder.decode(LocalArchiveImportData.self, from: archiveData)
        return LocalArchivePackage(entries: entries, manifest: manifest, archive: archive)
    }

    private static func isTargetEmpty(_ database: LocalDatabase) throws -> Bool {
        let count = try database.realLocalObjectCountIgnoringWelcomeSample()
        return count == 0 && AppSettings.localWeeklyReviews.isEmpty
    }

    private static func materializeMediaFiles(
        from entries: [String: Data],
        copiedMediaURLs: inout [URL]
    ) throws -> LocalArchiveImportedMediaPaths {
        let mediaDirectory = try AppDirectories.mediaDirectory()
        let importId = UUID().uuidString
        let stagingDirectory = try AppDirectories.applicationSupportDirectory()
            .appending(path: "import-staging", directoryHint: .isDirectory)
            .appending(path: importId, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: stagingDirectory)
        }

        var timeline: [String: LocalArchiveImportedTimelineMediaPaths] = [:]
        var checkIn: [String: String] = [:]

        for (path, data) in entries where path.hasPrefix("media/") {
            let stagedURL = stagingDirectory.appending(path: safePathComponent(path))
            try data.write(to: stagedURL, options: [.atomic])

            if let parsed = parseMediaPath(path, prefix: "media/moments/") {
                let finalURL = mediaDirectory.appending(path: "\(importId)-\(safePathComponent(parsed.id))-\(parsed.variant).\(parsed.ext)")
                try FileManager.default.copyItem(at: stagedURL, to: finalURL)
                copiedMediaURLs.append(finalURL)
                var paths = timeline[parsed.id] ?? LocalArchiveImportedTimelineMediaPaths()
                paths.set(finalURL.path, variant: parsed.variant)
                timeline[parsed.id] = paths
            } else if let parsed = parseMediaPath(path, prefix: "media/check-ins/"), parsed.variant == "compressed" {
                let finalURL = mediaDirectory.appending(path: "\(importId)-\(safePathComponent(parsed.id))-compressed.\(parsed.ext)")
                try FileManager.default.copyItem(at: stagedURL, to: finalURL)
                copiedMediaURLs.append(finalURL)
                checkIn[parsed.id] = finalURL.path
            }
        }

        return LocalArchiveImportedMediaPaths(timeline: timeline, checkIn: checkIn)
    }

    private static func parseMediaPath(_ path: String, prefix: String) -> (id: String, variant: String, ext: String)? {
        guard path.hasPrefix(prefix) else {
            return nil
        }

        let remainder = String(path.dropFirst(prefix.count))
        let parts = remainder.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return nil
        }

        let filename = parts[1]
        let fileParts = filename.split(separator: ".", maxSplits: 1).map(String.init)
        guard fileParts.count == 2 else {
            return nil
        }

        return (id: parts[0], variant: fileParts[0], ext: safePathComponent(fileParts[1]))
    }

    private static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}

private struct LocalArchivePackage {
    let entries: [String: Data]
    let manifest: LocalArchiveImportManifest
    let archive: LocalArchiveImportData
}

private struct LocalArchiveImportManifest: Decodable {
    let version: Int
    let exportedAt: String
    let generator: String
    let counts: LocalArchiveImportCounts
    let privacy: LocalArchiveImportPrivacy
}

private struct LocalArchiveImportData: Decodable {
    let posts: [LocalArchiveImportPostRecord]
    let tags: [TimelineTag]
    let tagAliases: [TimelineTagAlias]
    let checkInItems: [CheckInItem]
    let checkInEntries: [CheckInEntry]
    let checkInMedia: [LocalArchiveImportCheckInMediaRecord]
    let checkInAISummaries: [CheckInAISummary]
    let weeklyReviews: [ReviewPayload]
}

private struct LocalArchiveImportPostRecord: Decodable {
    let post: TimelinePost
    let media: [LocalArchiveImportTimelineMediaRecord]
    let comments: [TimelineComment]
    let aiSummaries: [TimelineAISummary]
    let tags: [TimelineAssignedTag]
}

private struct LocalArchiveImportTimelineMediaRecord: Decodable {
    let id: String
    let postId: String
    let kind: String
    let originalPreserved: Bool
    let uploadStatus: String
    let mimeType: String?
    let durationSeconds: Double?
    let transcriptionStatus: String
    let transcriptionError: String?
    let transcriptionUpdatedAt: Date?
    let transcriptLength: Int?
    let sortOrder: Int
    let checksum: String?
    let createdAt: Date
    let updatedAt: Date

    func timelineMedia(paths: LocalArchiveImportedTimelineMediaPaths?) -> TimelineMedia {
        TimelineMedia(
            id: id,
            postId: postId,
            kind: kind,
            localCompressedPath: paths?.compressed ?? "",
            localOriginalStagingPath: paths?.original,
            localThumbnailPath: paths?.thumbnail,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: originalPreserved,
            uploadStatus: paths?.compressed == nil ? "missing" : uploadStatus,
            mimeType: mimeType,
            durationSeconds: durationSeconds,
            transcriptionText: nil,
            transcriptionStatus: transcriptionStatus,
            transcriptionError: transcriptionError,
            transcriptionUpdatedAt: transcriptionUpdatedAt,
            sortOrder: sortOrder,
            checksum: checksum,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct LocalArchiveImportCheckInMediaRecord: Decodable {
    let id: String
    let entryId: String
    let kind: String
    let uploadStatus: String
    let uploadError: String?
    let mimeType: String?
    let durationSeconds: Double?
    let transcriptionStatus: String
    let transcriptionError: String?
    let transcriptionUpdatedAt: Date?
    let transcriptLength: Int?
    let sortOrder: Int
    let checksum: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    func checkInMedia(path: String?) -> CheckInMedia {
        CheckInMedia(
            id: id,
            entryId: entryId,
            kind: kind,
            localCompressedPath: path ?? "",
            remoteCompressedPath: nil,
            uploadStatus: path == nil ? "missing" : uploadStatus,
            uploadError: uploadError,
            mimeType: mimeType,
            durationSeconds: durationSeconds,
            transcriptionText: nil,
            transcriptionStatus: transcriptionStatus,
            transcriptionError: transcriptionError,
            transcriptionUpdatedAt: transcriptionUpdatedAt,
            sortOrder: sortOrder,
            checksum: checksum,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

private struct LocalArchiveImportedMediaPaths {
    let timeline: [String: LocalArchiveImportedTimelineMediaPaths]
    let checkIn: [String: String]
}

private struct LocalArchiveImportedTimelineMediaPaths {
    var compressed: String?
    var original: String?
    var thumbnail: String?

    mutating func set(_ path: String, variant: String) {
        switch variant {
        case "compressed":
            compressed = path
        case "original":
            original = path
        case "thumbnail":
            thumbnail = path
        default:
            break
        }
    }
}

private enum StoredZipReader {
    static func read(url: URL) throws -> [String: Data] {
        let data = try Data(contentsOf: url)
        var offset = 0
        var entries: [String: Data] = [:]

        while offset + 4 <= data.count {
            let signature = try data.uint32LE(at: offset)
            if signature == 0x02014b50 || signature == 0x06054b50 {
                break
            }

            guard signature == 0x04034b50 else {
                throw LocalArchiveImportError.invalidArchive("Unexpected ZIP header.")
            }
            guard offset + 30 <= data.count else {
                throw LocalArchiveImportError.invalidArchive("Truncated ZIP local header.")
            }

            let compressionMethod = try data.uint16LE(at: offset + 8)
            guard compressionMethod == 0 else {
                throw LocalArchiveImportError.unsupportedCompression
            }

            let compressedSize = Int(try data.uint32LE(at: offset + 18))
            let nameLength = Int(try data.uint16LE(at: offset + 26))
            let extraLength = Int(try data.uint16LE(at: offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + nameLength
            let contentStart = nameEnd + extraLength
            let contentEnd = contentStart + compressedSize

            guard contentEnd <= data.count else {
                throw LocalArchiveImportError.invalidArchive("Truncated ZIP file content.")
            }
            guard let name = String(data: data[nameStart..<nameEnd], encoding: .utf8) else {
                throw LocalArchiveImportError.invalidArchive("Invalid ZIP entry name.")
            }

            entries[name] = Data(data[contentStart..<contentEnd])
            offset = contentEnd
        }

        return entries
    }
}

private extension Data {
    func uint16LE(at offset: Int) throws -> UInt16 {
        guard offset + 2 <= count else {
            throw LocalArchiveImportError.invalidArchive("Unexpected end of data.")
        }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) throws -> UInt32 {
        guard offset + 4 <= count else {
            throw LocalArchiveImportError.invalidArchive("Unexpected end of data.")
        }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
