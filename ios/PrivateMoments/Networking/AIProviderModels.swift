import Foundation

enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case openAI
    case anthropic
    case gemini
    case deepSeek
    case qwen
    case kimi
    case customOpenAICompatible

    var id: String { rawValue }
}

struct AIProviderPreset: Identifiable, Equatable {
    let kind: AIProviderKind
    let displayName: String
    let defaultBaseURLString: String
    let defaultModel: String
    let supportsSpeechTranscription: Bool
    let supportsAudioInput: Bool

    var id: AIProviderKind { kind }

    static let defaultTextAnalysisPresets: [AIProviderPreset] = [
        AIProviderPreset(
            kind: .openAI,
            displayName: "OpenAI",
            defaultBaseURLString: "https://api.openai.com/v1",
            defaultModel: "gpt-4o-mini",
            supportsSpeechTranscription: true,
            supportsAudioInput: true
        ),
        AIProviderPreset(
            kind: .anthropic,
            displayName: "Anthropic",
            defaultBaseURLString: "https://api.anthropic.com",
            defaultModel: "claude-3-5-haiku-latest",
            supportsSpeechTranscription: false,
            supportsAudioInput: false
        ),
        AIProviderPreset(
            kind: .gemini,
            displayName: "Gemini",
            defaultBaseURLString: "https://generativelanguage.googleapis.com/v1beta/openai",
            defaultModel: "gemini-2.0-flash",
            supportsSpeechTranscription: false,
            supportsAudioInput: true
        ),
        AIProviderPreset(
            kind: .deepSeek,
            displayName: "DeepSeek",
            defaultBaseURLString: "https://api.deepseek.com",
            defaultModel: "deepseek-chat",
            supportsSpeechTranscription: false,
            supportsAudioInput: false
        ),
        AIProviderPreset(
            kind: .qwen,
            displayName: "Qwen",
            defaultBaseURLString: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            defaultModel: "qwen-plus",
            supportsSpeechTranscription: false,
            supportsAudioInput: false
        ),
        AIProviderPreset(
            kind: .kimi,
            displayName: "Kimi",
            defaultBaseURLString: "https://api.moonshot.cn/v1",
            defaultModel: "moonshot-v1-8k",
            supportsSpeechTranscription: false,
            supportsAudioInput: false
        ),
        AIProviderPreset(
            kind: .customOpenAICompatible,
            displayName: "Custom",
            defaultBaseURLString: "",
            defaultModel: "",
            supportsSpeechTranscription: false,
            supportsAudioInput: false
        )
    ]

    static func preset(for kind: AIProviderKind) -> AIProviderPreset {
        defaultTextAnalysisPresets.first { $0.kind == kind }
            ?? defaultTextAnalysisPresets[0]
    }
}

struct AIProviderProfile: Codable, Identifiable, Equatable {
    var id: String
    var kind: AIProviderKind
    var displayName: String
    var baseURLString: String
    var model: String
    var isEnabled: Bool
    var sortOrder: Int

    var preset: AIProviderPreset {
        AIProviderPreset.preset(for: kind)
    }

    var isConfiguredForRequests: Bool {
        isEnabled
            && !baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum AIProviderFailureCategory: String, Codable, Equatable {
    case transient
    case artifactGeneration
    case needsAttention
}

struct AIProviderFallbackRecord: Codable, Equatable {
    var transientFailures: Int
    var downUntil: Date?
    var needsAttention: Bool
    var lastError: String?
    var updatedAt: Date
}

struct AIProviderFallbackState: Codable, Equatable {
    private(set) var records: [String: AIProviderFallbackRecord] = [:]

    mutating func recordFailure(
        profileId: String,
        category: AIProviderFailureCategory,
        now: Date = Date(),
        message: String? = nil
    ) {
        var record = records[profileId] ?? AIProviderFallbackRecord(
            transientFailures: 0,
            downUntil: nil,
            needsAttention: false,
            lastError: nil,
            updatedAt: now
        )
        record.lastError = message
        record.updatedAt = now

        switch category {
        case .transient:
            record.transientFailures += 1
            record.needsAttention = false
            record.downUntil = now.addingTimeInterval(Self.cooldownSeconds(for: record.transientFailures))
        case .artifactGeneration:
            record.transientFailures = 0
            record.needsAttention = false
            record.downUntil = nil
        case .needsAttention:
            record.needsAttention = true
            record.downUntil = nil
        }

        records[profileId] = record
    }

    mutating func recordSuccess(profileId: String) {
        records.removeValue(forKey: profileId)
    }

    func isCoolingDown(profileId: String, now: Date = Date()) -> Bool {
        guard let downUntil = records[profileId]?.downUntil else {
            return false
        }

        return downUntil > now
    }

    func needsAttention(profileId: String) -> Bool {
        records[profileId]?.needsAttention == true
    }

    mutating func clearLegacyArtifactGenerationNeedsAttentionRecords(now: Date = Date()) -> Bool {
        var didChange = false
        for (profileId, record) in records where record.needsAttention && Self.isArtifactGenerationError(record.lastError) {
            var updated = record
            updated.transientFailures = 0
            updated.downUntil = nil
            updated.needsAttention = false
            updated.updatedAt = now
            records[profileId] = updated
            didChange = true
        }
        return didChange
    }

    private static func cooldownSeconds(for failures: Int) -> TimeInterval {
        switch failures {
        case ...1:
            return 120
        case 2:
            return 300
        case 3:
            return 900
        default:
            return 1_800
        }
    }

    private static func isArtifactGenerationError(_ message: String?) -> Bool {
        guard let message else {
            return false
        }
        return message == AITextAnalysisError.unsupportedResponse.localizedDescription
            || message.contains("response Ownlight could not read")
            || message.contains("response Private Moments could not read")
    }
}

enum AIProviderRouter {
    static func selectProfile(
        profiles: [AIProviderProfile],
        fallbackState: AIProviderFallbackState,
        now: Date = Date(),
        forceRetry: Bool = false
    ) -> AIProviderProfile? {
        profiles
            .filter { $0.isConfiguredForRequests && !fallbackState.needsAttention(profileId: $0.id) }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.displayName < rhs.displayName
                }

                return lhs.sortOrder < rhs.sortOrder
            }
            .first { forceRetry || !fallbackState.isCoolingDown(profileId: $0.id, now: now) }
    }
}
