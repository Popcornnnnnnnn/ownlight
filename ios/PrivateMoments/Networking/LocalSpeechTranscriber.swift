@preconcurrency import AVFoundation
import Foundation
import Speech

enum LocalSpeechTranscriptionError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case emptyTranscript
    case audioExportUnavailable
    case audioExportFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech recognition permission is required for on-device transcription."
        case .recognizerUnavailable:
            return "On-device speech recognition is unavailable for this language."
        case .emptyTranscript:
            return "No speech was detected."
        case .audioExportUnavailable:
            return "Could not extract audio from this video."
        case .audioExportFailed:
            return "Audio extraction failed."
        }
    }
}

enum SpeechTranscriptionLocaleRouter {
    private static let chineseLocaleIdentifier = "zh-CN"
    private static let englishLocaleIdentifier = "en-US"

    static func candidateLocaleIdentifiers(
        aiLanguageMode: AILanguageMode = AppSettings.aiLanguageMode,
        appLanguageMode: AppLanguageMode = AppSettings.appLanguageMode,
        currentLocale: Locale = .current
    ) -> [String] {
        var identifiers: [String] = []
        appendLocaleIdentifier(AppSettings.preferredSpeechTranscriptionLocaleIdentifier, to: &identifiers)
        appendLocaleIdentifier(
            defaultLocaleIdentifier(
                aiLanguageMode: aiLanguageMode,
                appLanguageMode: appLanguageMode,
                currentLocale: currentLocale
            ),
            to: &identifiers
        )

        if identifiers.first == chineseLocaleIdentifier {
            appendLocaleIdentifier(englishLocaleIdentifier, to: &identifiers)
        } else {
            appendLocaleIdentifier(chineseLocaleIdentifier, to: &identifiers)
        }

        appendLocaleIdentifier(localeIdentifier(for: currentLocale), to: &identifiers)
        return identifiers
    }

    static func transcribe(
        url: URL,
        aiLanguageMode: AILanguageMode = AppSettings.aiLanguageMode,
        appLanguageMode: AppLanguageMode = AppSettings.appLanguageMode,
        currentLocale: Locale = .current,
        attempt: (URL, Locale) async throws -> String
    ) async throws -> String {
        let candidates = candidateLocaleIdentifiers(
            aiLanguageMode: aiLanguageMode,
            appLanguageMode: appLanguageMode,
            currentLocale: currentLocale
        )
        var lastError: Error?

        for identifier in candidates {
            do {
                let transcript = try await attempt(url, Locale(identifier: identifier))
                AppSettings.preferredSpeechTranscriptionLocaleIdentifier = identifier
                return transcript
            } catch {
                lastError = error
                guard shouldTryNextLocale(after: error) else {
                    throw error
                }
            }
        }

        throw lastError ?? LocalSpeechTranscriptionError.emptyTranscript
    }

    private static func defaultLocaleIdentifier(
        aiLanguageMode: AILanguageMode,
        appLanguageMode: AppLanguageMode,
        currentLocale: Locale
    ) -> String {
        switch aiLanguageMode {
        case .chinese:
            return chineseLocaleIdentifier
        case .english:
            return englishLocaleIdentifier
        case .auto:
            switch appLanguageMode {
            case .simplifiedChinese:
                return chineseLocaleIdentifier
            case .english:
                return englishLocaleIdentifier
            case .system:
                return localeIdentifier(for: currentLocale) ?? englishLocaleIdentifier
            }
        }
    }

    private static func localeIdentifier(for locale: Locale) -> String? {
        let identifier = locale.identifier.lowercased()
        if identifier.hasPrefix("zh") {
            return chineseLocaleIdentifier
        }
        if identifier.hasPrefix("en") {
            return englishLocaleIdentifier
        }
        return nil
    }

    private static func normalizedSupportedLocaleIdentifier(_ identifier: String?) -> String? {
        guard let identifier else {
            return nil
        }

        let normalized = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        if normalized.hasPrefix("zh") {
            return chineseLocaleIdentifier
        }
        if normalized.hasPrefix("en") {
            return englishLocaleIdentifier
        }
        return nil
    }

    private static func appendLocaleIdentifier(_ identifier: String?, to identifiers: inout [String]) {
        guard let normalized = normalizedSupportedLocaleIdentifier(identifier),
              !identifiers.contains(normalized) else {
            return
        }
        identifiers.append(normalized)
    }

    private static func shouldTryNextLocale(after error: Error) -> Bool {
        guard let speechError = error as? LocalSpeechTranscriptionError else {
            return false
        }

        switch speechError {
        case .emptyTranscript, .recognizerUnavailable:
            return true
        case .permissionDenied, .audioExportUnavailable, .audioExportFailed:
            return false
        }
    }
}

enum LocalSpeechTranscriber {
    static func transcribe(
        url: URL,
        aiLanguageMode: AILanguageMode = AppSettings.aiLanguageMode,
        appLanguageMode: AppLanguageMode = AppSettings.appLanguageMode
    ) async throws -> String {
        try await SpeechTranscriptionLocaleRouter.transcribe(
            url: url,
            aiLanguageMode: aiLanguageMode,
            appLanguageMode: appLanguageMode
        ) { inputURL, locale in
            try await transcribeOnce(url: inputURL, locale: locale)
        }
    }

    private static func transcribeOnce(url: URL, locale: Locale) async throws -> String {
        let status = await requestAuthorization()
        guard status == .authorized else {
            throw LocalSpeechTranscriptionError.permissionDenied
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw LocalSpeechTranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true

        let transcript: String = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var didResume = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error, !didResume {
                    didResume = true
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal, !didResume else {
                    return
                }

                didResume = true
                continuation.resume(returning: result.bestTranscription.formattedString)
            }

            Task {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                if !didResume {
                    didResume = true
                    task.cancel()
                    continuation.resume(throwing: LocalSpeechTranscriptionError.emptyTranscript)
                }
            }
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LocalSpeechTranscriptionError.emptyTranscript
        }
        return trimmed
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

enum LocalAudioExtractor {
    static func audioURLForTranscription(media: TimelineMedia) async throws -> URL {
        let url = URL(fileURLWithPath: media.localCompressedPath)
        guard media.isVideo else {
            return url
        }

        let asset = AVURLAsset(url: url)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw LocalSpeechTranscriptionError.audioExportUnavailable
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("private-moments-\(media.id)-speech.m4a")
        try? FileManager.default.removeItem(at: outputURL)
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exportSession.error ?? LocalSpeechTranscriptionError.audioExportFailed)
                default:
                    continuation.resume(throwing: LocalSpeechTranscriptionError.audioExportFailed)
                }
            }
        }
        return outputURL
    }
}
