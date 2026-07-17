import Foundation
import os

private let composerDraftLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "PrivateMoments",
    category: "ComposerDraft"
)

enum ComposerDraftStore {
    private static let textKey = "composer.draft.text"
    private static let occurredAtKey = "composer.draft.occurredAt"
    private static let updatedAtKey = "composer.draft.updatedAt"

    static func loadText() -> String {
        UserDefaults.standard.string(forKey: textKey) ?? ""
    }

    static func loadOccurredAt() -> Date {
        guard let value = UserDefaults.standard.string(forKey: occurredAtKey),
              let date = ISO8601DateFormatter().date(from: value) else {
            return Date()
        }

        return date
    }

    static func loadUpdatedAt() -> Date? {
        guard let value = UserDefaults.standard.string(forKey: updatedAtKey) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: value)
    }

    static func hasTextOrDateDraft() -> Bool {
        UserDefaults.standard.object(forKey: textKey) != nil ||
            UserDefaults.standard.object(forKey: occurredAtKey) != nil
    }

    static func save(text: String, occurredAt: Date, updatedAt: Date = Date()) {
        let previousLength = UserDefaults.standard.string(forKey: textKey)?.count ?? 0
        UserDefaults.standard.set(text, forKey: textKey)
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: occurredAt), forKey: occurredAtKey)
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: updatedAt), forKey: updatedAtKey)
        logTextLengthChange(previousLength: previousLength, nextLength: text.count)
    }

    static func clearTextAndDate() {
        let previousLength = UserDefaults.standard.string(forKey: textKey)?.count ?? 0
        UserDefaults.standard.removeObject(forKey: textKey)
        UserDefaults.standard.removeObject(forKey: occurredAtKey)
        UserDefaults.standard.removeObject(forKey: updatedAtKey)
        if previousLength > 0 {
            composerDraftLogger.debug(
                "composer_draft text_and_date_cleared previousTextLength=\(previousLength, privacy: .public)"
            )
        }
    }

    static func textAfterRecoveringTransientEmpty(currentText: String) -> String {
        guard currentText.isEmpty else {
            return currentText
        }

        let persistedText = loadText()
        guard !persistedText.isEmpty else {
            return currentText
        }

        composerDraftLogger.debug(
            "composer_draft restored transient empty text persistedTextLength=\(persistedText.count, privacy: .public)"
        )
        return persistedText
    }

    static func loadImages() -> [Data] {
        do {
            let directory = try draftMediaDirectory(create: false)
            let urls = try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "image" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            return urls.compactMap { try? Data(contentsOf: $0) }
        } catch {
            return []
        }
    }

    static func loadAudioDraftURLs(maxCount: Int = 9) -> [URL] {
        do {
            let urls = try FileManager.default
                .contentsOfDirectory(
                    at: try draftMediaDirectory(create: false),
                    includingPropertiesForKeys: [.contentModificationDateKey]
                )
                .filter { url in
                    url.lastPathComponent.hasPrefix("composer-audio-") && url.pathExtension == "m4a"
                }
                .sorted { lhs, rhs in
                    let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    if lhsDate == rhsDate {
                        return lhs.lastPathComponent < rhs.lastPathComponent
                    }
                    return lhsDate < rhsDate
                }

            return Array(urls.prefix(maxCount))
        } catch {
            return []
        }
    }

    static func hasMediaDrafts() -> Bool {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: try draftMediaDirectory(create: false),
                includingPropertiesForKeys: nil
            )
            return urls.contains { !$0.lastPathComponent.hasPrefix(".") }
        } catch {
            return false
        }
    }

    static func saveImages(_ imageData: [Data]) throws {
        let fileManager = FileManager.default
        let directory = try draftMediaDirectory(create: true)

        if fileManager.fileExists(atPath: directory.path) {
            let existingImages = try fileManager
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "image" }

            for imageURL in existingImages {
                try fileManager.removeItem(at: imageURL)
            }
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, data) in imageData.prefix(9).enumerated() {
            let filename = String(format: "%03d.image", index)
            try data.write(to: directory.appending(path: filename), options: [.atomic])
        }
    }

    static func clear() {
        let previousLength = UserDefaults.standard.string(forKey: textKey)?.count ?? 0
        UserDefaults.standard.removeObject(forKey: textKey)
        UserDefaults.standard.removeObject(forKey: occurredAtKey)
        UserDefaults.standard.removeObject(forKey: updatedAtKey)
        if previousLength > 0 {
            composerDraftLogger.debug(
                "composer_draft cleared previousTextLength=\(previousLength, privacy: .public)"
            )
        }

        if let directory = try? draftMediaDirectory(create: false) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func logTextLengthChange(previousLength: Int, nextLength: Int) {
        guard previousLength != nextLength else {
            return
        }

        let delta = abs(previousLength - nextLength)
        guard previousLength == 0 || nextLength == 0 || delta >= 20 else {
            return
        }

        composerDraftLogger.debug(
            "composer_draft saved previousTextLength=\(previousLength, privacy: .public) nextTextLength=\(nextLength, privacy: .public)"
        )
    }

    private static func draftMediaDirectory(create: Bool) throws -> URL {
        let directory = try AppDirectories.applicationSupportDirectory()
            .appending(path: "draft-media", directoryHint: .isDirectory)

        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }
}
