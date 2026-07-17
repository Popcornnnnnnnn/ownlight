import Foundation

struct LocalArchiveExportResult {
    let url: URL
    let filename: String
    let mediaFilesIncluded: Int
    let missingMediaCount: Int
}

enum LocalArchiveExporter {
    @MainActor
    static func export(from store: TimelineStore) async throws -> LocalArchiveExportResult {
        let items = store.items.filter { !WelcomeSampleContent.isSample($0) }
        let tags = store.tags.filter { !WelcomeSampleContent.isSampleTagId($0.id) }
        let tagAliases = store.tagAliases.filter { alias in
            !WelcomeSampleContent.isSampleTagId(alias.tagId)
                && !alias.id.hasPrefix("welcome-sample-")
        }
        let snapshot = LocalArchiveSnapshot(
            exportedAt: Date(),
            items: items,
            tags: tags,
            tagAliases: tagAliases,
            checkInItems: store.checkInItems,
            checkInEntries: store.checkInEntries,
            checkInMedia: store.checkInMedia,
            checkInAISummaries: store.checkInAISummaries,
            weeklyReviews: store.weeklyReviews
        )

        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try buildArchive(from: snapshot)
        }.value
    }

    private static func buildArchive(from snapshot: LocalArchiveSnapshot) throws -> LocalArchiveExportResult {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: snapshot.exportedAt)
            .replacingOccurrences(of: ":", with: "-")
        let filename = "private-moments-archive-\(timestamp).zip"
        let outputURL = FileManager.default.temporaryDirectory.appending(path: filename)
        try? FileManager.default.removeItem(at: outputURL)

        var mediaFiles: [LocalArchiveMediaFile] = []
        var missingMedia: [LocalArchiveMissingMedia] = []

        for item in snapshot.items {
            for media in item.media {
                try Task.checkCancellation()
                collectTimelineMedia(media, mediaFiles: &mediaFiles, missingMedia: &missingMedia)
            }
        }

        for media in snapshot.checkInMedia {
            try Task.checkCancellation()
            collectCheckInMedia(media, mediaFiles: &mediaFiles, missingMedia: &missingMedia)
        }

        let archive = LocalArchiveData(
            posts: snapshot.items.map(LocalArchivePostRecord.init(item:)),
            tags: snapshot.tags,
            tagAliases: snapshot.tagAliases,
            checkInItems: snapshot.checkInItems,
            checkInEntries: snapshot.checkInEntries,
            checkInMedia: snapshot.checkInMedia.map(LocalArchiveCheckInMediaRecord.init(media:)),
            checkInAISummaries: snapshot.checkInAISummaries,
            weeklyReviews: snapshot.weeklyReviews
        )
        let manifest = LocalArchiveManifest(
            version: 1,
            exportedAt: formatter.string(from: snapshot.exportedAt),
            generator: "Ownlight iOS",
            counts: LocalArchiveCounts(
                posts: archive.posts.count,
                postMedia: archive.posts.reduce(0) { $0 + $1.media.count },
                comments: archive.posts.reduce(0) { $0 + $1.comments.count },
                tags: archive.tags.count,
                checkInItems: archive.checkInItems.count,
                checkInEntries: archive.checkInEntries.count,
                checkInMedia: archive.checkInMedia.count,
                aiSummaries: archive.posts.reduce(0) { $0 + $1.aiSummaries.count } + archive.checkInAISummaries.count,
                weeklyReviews: archive.weeklyReviews.count,
                mediaFilesIncluded: mediaFiles.count,
                missingMedia: missingMedia.count
            ),
            privacy: LocalArchivePrivacy(
                containsCredentials: false,
                containsProviderAPIKeys: false,
                containsPrivateTranscriptText: false,
                encrypted: false,
                note: "This archive can contain private text, comments, AI summaries, reviews, check-ins, and media files. It does not include provider credentials or private transcript text."
            ),
            missingMedia: missingMedia
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        var writer = try StoredZipWriter(url: outputURL)
        try writer.addFile(path: "manifest.json", data: encoder.encode(manifest))
        try writer.addFile(path: "data/archive.json", data: encoder.encode(archive))
        try writer.addFile(path: "preview/moments.md", data: Data(markdownPreview(snapshot: snapshot).utf8))
        try writer.addFile(path: "README.md", data: Data(readme(manifest: manifest).utf8))

        for file in mediaFiles {
            try Task.checkCancellation()
            try writer.addFile(path: file.archivePath, data: try Data(contentsOf: file.sourceURL))
        }

        try writer.finish()
        return LocalArchiveExportResult(
            url: outputURL,
            filename: filename,
            mediaFilesIncluded: mediaFiles.count,
            missingMediaCount: missingMedia.count
        )
    }

    private static func collectTimelineMedia(
        _ media: TimelineMedia,
        mediaFiles: inout [LocalArchiveMediaFile],
        missingMedia: inout [LocalArchiveMissingMedia]
    ) {
        collectFile(
            ownerType: "moment_media",
            ownerId: media.id,
            variant: "compressed",
            storedPath: media.localCompressedPath,
            archivePath: "media/moments/\(safePathComponent(media.id))/compressed.\(preferredExtension(kind: media.kind, mimeType: media.mimeType, path: media.localCompressedPath))",
            mediaFiles: &mediaFiles,
            missingMedia: &missingMedia
        )

        if let thumbnailPath = media.localThumbnailPath, !thumbnailPath.isEmpty {
            collectFile(
                ownerType: "moment_media",
                ownerId: media.id,
                variant: "thumbnail",
                storedPath: thumbnailPath,
                archivePath: "media/moments/\(safePathComponent(media.id))/thumbnail.\(preferredExtension(kind: "image", mimeType: nil, path: thumbnailPath))",
                mediaFiles: &mediaFiles,
                missingMedia: &missingMedia
            )
        }

        if let originalPath = media.localOriginalStagingPath, !originalPath.isEmpty {
            collectFile(
                ownerType: "moment_media",
                ownerId: media.id,
                variant: "original",
                storedPath: originalPath,
                archivePath: "media/moments/\(safePathComponent(media.id))/original.\(preferredExtension(kind: media.kind, mimeType: media.mimeType, path: originalPath))",
                mediaFiles: &mediaFiles,
                missingMedia: &missingMedia
            )
        }
    }

    private static func collectCheckInMedia(
        _ media: CheckInMedia,
        mediaFiles: inout [LocalArchiveMediaFile],
        missingMedia: inout [LocalArchiveMissingMedia]
    ) {
        collectFile(
            ownerType: "checkin_media",
            ownerId: media.id,
            variant: "compressed",
            storedPath: media.localCompressedPath,
            archivePath: "media/check-ins/\(safePathComponent(media.id))/compressed.\(preferredExtension(kind: media.kind, mimeType: media.mimeType, path: media.localCompressedPath))",
            mediaFiles: &mediaFiles,
            missingMedia: &missingMedia
        )
    }

    private static func collectFile(
        ownerType: String,
        ownerId: String,
        variant: String,
        storedPath: String,
        archivePath: String,
        mediaFiles: inout [LocalArchiveMediaFile],
        missingMedia: inout [LocalArchiveMissingMedia]
    ) {
        guard !storedPath.isEmpty,
              let localPath = try? AppDirectories.localFilePath(fromStoredPath: storedPath),
              FileManager.default.fileExists(atPath: localPath) else {
            missingMedia.append(LocalArchiveMissingMedia(
                ownerType: ownerType,
                ownerId: ownerId,
                variant: variant,
                reason: "local_file_missing"
            ))
            return
        }

        mediaFiles.append(LocalArchiveMediaFile(
            sourceURL: URL(fileURLWithPath: localPath),
            archivePath: archivePath
        ))
    }

    private static func preferredExtension(kind: String, mimeType: String?, path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension
        if !ext.isEmpty {
            return safePathComponent(ext.lowercased())
        }
        if kind == "audio" {
            return "m4a"
        }
        if kind == "video" {
            return "mp4"
        }
        if mimeType == "image/png" {
            return "png"
        }
        return "jpg"
    }

    private static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }

    private static func markdownPreview(snapshot: LocalArchiveSnapshot) -> String {
        var lines = [
            "# Ownlight Archive",
            "",
            "Exported: \(ISO8601DateFormatter().string(from: snapshot.exportedAt))",
            "",
            "## Moments",
            ""
        ]

        for item in snapshot.items.sorted(by: { $0.post.occurredAt > $1.post.occurredAt }) {
            lines.append("### \(ISO8601DateFormatter().string(from: item.post.occurredAt))")
            let text = item.post.text.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(text.isEmpty ? "_No text_" : text)
            if !item.comments.isEmpty {
                lines.append("")
                lines.append("Comments:")
                for comment in item.comments {
                    lines.append("- \(comment.text)")
                }
            }
            if let summary = item.aiSummaries.first(where: \.isReady) {
                lines.append("")
                lines.append("AI summary: \(summary.documentTitle ?? summary.oneLiner ?? summary.summaryText ?? "Ready")")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func readme(manifest: LocalArchiveManifest) -> String {
        """
        # Ownlight Archive

        This archive was exported from the iPhone app.

        - `manifest.json` describes counts, privacy properties, and missing local media.
        - `data/archive.json` is the structured data source for migration or empty-library restore checks.
        - `preview/moments.md` is a human-readable preview.
        - `media/` contains media files that were present on this iPhone at export time.

        Privacy:
        - This archive is not encrypted.
        - It can contain private text, comments, summaries, reviews, check-ins, and media.
        - It does not contain AI provider API keys or Keychain credentials.
        - It does not contain private transcript text.

        Missing media files recorded in this export: \(manifest.missingMedia.count)
        """
    }
}

private struct LocalArchiveSnapshot {
    let exportedAt: Date
    let items: [TimelineItem]
    let tags: [TimelineTag]
    let tagAliases: [TimelineTagAlias]
    let checkInItems: [CheckInItem]
    let checkInEntries: [CheckInEntry]
    let checkInMedia: [CheckInMedia]
    let checkInAISummaries: [CheckInAISummary]
    let weeklyReviews: [ReviewPayload]
}

private struct LocalArchiveMediaFile {
    let sourceURL: URL
    let archivePath: String
}

private struct LocalArchiveManifest: Encodable {
    let version: Int
    let exportedAt: String
    let generator: String
    let counts: LocalArchiveCounts
    let privacy: LocalArchivePrivacy
    let missingMedia: [LocalArchiveMissingMedia]
}

private struct LocalArchiveCounts: Encodable {
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

private struct LocalArchivePrivacy: Encodable {
    let containsCredentials: Bool
    let containsProviderAPIKeys: Bool
    let containsPrivateTranscriptText: Bool
    let encrypted: Bool
    let note: String
}

private struct LocalArchiveMissingMedia: Encodable {
    let ownerType: String
    let ownerId: String
    let variant: String
    let reason: String
}

private struct LocalArchiveData: Encodable {
    let posts: [LocalArchivePostRecord]
    let tags: [TimelineTag]
    let tagAliases: [TimelineTagAlias]
    let checkInItems: [CheckInItem]
    let checkInEntries: [CheckInEntry]
    let checkInMedia: [LocalArchiveCheckInMediaRecord]
    let checkInAISummaries: [CheckInAISummary]
    let weeklyReviews: [ReviewPayload]
}

private struct LocalArchivePostRecord: Encodable {
    let post: TimelinePost
    let media: [LocalArchiveTimelineMediaRecord]
    let comments: [TimelineComment]
    let aiSummaries: [TimelineAISummary]
    let tags: [TimelineAssignedTag]

    init(item: TimelineItem) {
        post = item.post
        media = item.media.map(LocalArchiveTimelineMediaRecord.init(media:))
        comments = item.comments
        aiSummaries = item.aiSummaries
        tags = item.tags
    }
}

private struct LocalArchiveTimelineMediaRecord: Encodable {
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

    init(media: TimelineMedia) {
        id = media.id
        postId = media.postId
        kind = media.kind
        originalPreserved = media.originalPreserved
        uploadStatus = media.uploadStatus
        mimeType = media.mimeType
        durationSeconds = media.durationSeconds
        transcriptionStatus = media.transcriptionStatus
        transcriptionError = media.transcriptionError
        transcriptionUpdatedAt = media.transcriptionUpdatedAt
        transcriptLength = media.transcriptionText?.count
        sortOrder = media.sortOrder
        checksum = media.checksum
        createdAt = media.createdAt
        updatedAt = media.updatedAt
    }
}

private struct LocalArchiveCheckInMediaRecord: Encodable {
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

    init(media: CheckInMedia) {
        id = media.id
        entryId = media.entryId
        kind = media.kind
        uploadStatus = media.uploadStatus
        uploadError = media.uploadError
        mimeType = media.mimeType
        durationSeconds = media.durationSeconds
        transcriptionStatus = media.transcriptionStatus
        transcriptionError = media.transcriptionError
        transcriptionUpdatedAt = media.transcriptionUpdatedAt
        transcriptLength = media.transcriptionText?.count
        sortOrder = media.sortOrder
        checksum = media.checksum
        createdAt = media.createdAt
        updatedAt = media.updatedAt
        deletedAt = media.deletedAt
    }
}

private struct StoredZipWriter {
    private struct Entry {
        let path: String
        let crc32: UInt32
        let size: UInt32
        let localHeaderOffset: UInt32
    }

    private let handle: FileHandle
    private var entries: [Entry] = []
    private var offset: UInt32 = 0

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    mutating func addFile(path: String, data: Data) throws {
        let nameData = Data(path.utf8)
        let crc = CRC32.checksum(data)
        let size = UInt32(data.count)
        let localHeaderOffset = offset

        var header = Data()
        header.appendUInt32LE(0x04034b50)
        header.appendUInt16LE(20)
        header.appendUInt16LE(0)
        header.appendUInt16LE(0)
        header.appendUInt16LE(0)
        header.appendUInt16LE(0)
        header.appendUInt32LE(crc)
        header.appendUInt32LE(size)
        header.appendUInt32LE(size)
        header.appendUInt16LE(UInt16(nameData.count))
        header.appendUInt16LE(0)
        header.append(nameData)

        try write(header)
        try write(data)
        entries.append(Entry(path: path, crc32: crc, size: size, localHeaderOffset: localHeaderOffset))
    }

    mutating func finish() throws {
        let centralDirectoryOffset = offset
        var directory = Data()

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            directory.appendUInt32LE(0x02014b50)
            directory.appendUInt16LE(20)
            directory.appendUInt16LE(20)
            directory.appendUInt16LE(0)
            directory.appendUInt16LE(0)
            directory.appendUInt16LE(0)
            directory.appendUInt16LE(0)
            directory.appendUInt32LE(entry.crc32)
            directory.appendUInt32LE(entry.size)
            directory.appendUInt32LE(entry.size)
            directory.appendUInt16LE(UInt16(nameData.count))
            directory.appendUInt16LE(0)
            directory.appendUInt16LE(0)
            directory.appendUInt16LE(0)
            directory.appendUInt16LE(0)
            directory.appendUInt32LE(0)
            directory.appendUInt32LE(entry.localHeaderOffset)
            directory.append(nameData)
        }

        try write(directory)
        let centralDirectorySize = offset - centralDirectoryOffset

        var footer = Data()
        footer.appendUInt32LE(0x06054b50)
        footer.appendUInt16LE(0)
        footer.appendUInt16LE(0)
        footer.appendUInt16LE(UInt16(entries.count))
        footer.appendUInt16LE(UInt16(entries.count))
        footer.appendUInt32LE(centralDirectorySize)
        footer.appendUInt32LE(centralDirectoryOffset)
        footer.appendUInt16LE(0)
        try write(footer)
        try handle.close()
    }

    private mutating func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
        offset += UInt32(data.count)
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = (crc >> 1) ^ 0xedb88320
            } else {
                crc >>= 1
            }
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xff)]
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
