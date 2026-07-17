import Foundation

enum AIArtifactFeature: String {
    case mediaSummary
    case checkInSummary
    case weeklyReview
}

struct AIArtifactGenerationRequest {
    var feature: AIArtifactFeature
    var title: String?
    var sourceText: String
    var languageMode: AILanguageMode
    var topicVocabulary: [String]
}

struct AIArtifactGenerationResult: Equatable {
    var documentTitle: String
    var oneLiner: String
    var summaryText: String
    var keyPoints: [String]
    var documentBlocks: [TimelineAISummaryBlock]
    var suggestedTags: [String]
    var suggestedAreaId: String? = nil
    var reviewContent: ReviewContentPayload?
    var tokenUsage: AITokenUsage? = nil
}

enum AITextAnalysisError: LocalizedError {
    case noConfiguredProvider
    case externalProcessingConsentRequired
    case missingAPIKey(String)
    case unsupportedResponse
    case provider(statusCode: Int, message: String)
    case invalidProviderURL

    var errorDescription: String? {
        switch self {
        case .noConfiguredProvider:
            return "No configured AI provider is available."
        case .externalProcessingConsentRequired:
            return "AI needs your permission before sending content to the provider you configured."
        case .missingAPIKey(let name):
            return "API key is missing for \(name)."
        case .unsupportedResponse:
            return "The AI provider returned a response Ownlight could not read. Check the Base URL, model, and response format."
        case .provider(_, let message):
            return message
        case .invalidProviderURL:
            return "Provider base URL is invalid."
        }
    }

    var failureCategory: AIProviderFailureCategory {
        switch self {
        case .provider(let statusCode, _):
            if statusCode == 408 || statusCode == 409 || statusCode == 425 || statusCode == 429 || statusCode >= 500 {
                return .transient
            }
            return .needsAttention
        case .unsupportedResponse:
            return .artifactGeneration
        case .externalProcessingConsentRequired, .invalidProviderURL, .missingAPIKey:
            return .needsAttention
        case .noConfiguredProvider:
            return .transient
        }
    }
}

struct AITextAnalysisClient {
    var urlSession: URLSession = .shared

    func generate(
        request: AIArtifactGenerationRequest,
        profile: AIProviderProfile,
        apiKey: String
    ) async throws -> AIArtifactGenerationResult {
        let prompt = Self.prompt(for: request)
        let generated: ProviderTextGenerationResult
        if profile.kind == .anthropic {
            generated = try await generateAnthropic(prompt: prompt, profile: profile, apiKey: apiKey)
        } else {
            generated = try await generateOpenAICompatible(prompt: prompt, profile: profile, apiKey: apiKey)
        }

        var result = try Self.decodeResult(from: generated.content, feature: request.feature)
        result.tokenUsage = generated.tokenUsage
        return result
    }

    func testConnection(profile: AIProviderProfile, apiKey: String) async throws {
        let prompt = """
        Return only valid JSON exactly matching this shape:
        { "ok": true }
        """
        let generated: ProviderTextGenerationResult
        if profile.kind == .anthropic {
            generated = try await generateAnthropic(prompt: prompt, profile: profile, apiKey: apiKey, maxTokens: 64)
        } else {
            generated = try await generateOpenAICompatible(prompt: prompt, profile: profile, apiKey: apiKey, maxTokens: 64)
        }

        let json = Self.extractJSONObject(from: generated.content)
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AIConnectionTestResponse.self, from: data),
              decoded.ok == true else {
            throw AITextAnalysisError.unsupportedResponse
        }
    }

    private func generateOpenAICompatible(
        prompt: String,
        profile: AIProviderProfile,
        apiKey: String,
        maxTokens: Int = 2_800
    ) async throws -> ProviderTextGenerationResult {
        let url = try endpoint(baseURLString: profile.baseURLString, path: "chat/completions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 60
        urlRequest.httpBody = try JSONEncoder().encode(OpenAICompatibleRequest(
            model: profile.model,
            messages: [
                .init(role: "system", content: "You generate private personal timeline artifacts. Return only valid JSON."),
                .init(role: "user", content: prompt)
            ],
            temperature: 0.2,
            maxTokens: maxTokens,
            responseFormat: .init(type: "json_object")
        ))

        let (data, response) = try await urlSession.data(for: urlRequest)
        try Self.validateHTTPResponse(data: data, response: response)
        let decoded: OpenAICompatibleResponse
        do {
            decoded = try JSONDecoder().decode(OpenAICompatibleResponse.self, from: data)
        } catch {
            throw AITextAnalysisError.unsupportedResponse
        }
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw AITextAnalysisError.unsupportedResponse
        }
        return ProviderTextGenerationResult(content: content, tokenUsage: decoded.usage?.tokenUsage)
    }

    private func generateAnthropic(
        prompt: String,
        profile: AIProviderProfile,
        apiKey: String,
        maxTokens: Int = 2_800
    ) async throws -> ProviderTextGenerationResult {
        let url = try endpoint(baseURLString: profile.baseURLString, path: "v1/messages")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.timeoutInterval = 60
        urlRequest.httpBody = try JSONEncoder().encode(AnthropicRequest(
            model: profile.model,
            maxTokens: maxTokens,
            system: "You generate private personal timeline artifacts. Return only valid JSON.",
            messages: [.init(role: "user", content: prompt)]
        ))

        let (data, response) = try await urlSession.data(for: urlRequest)
        try Self.validateHTTPResponse(data: data, response: response)
        let decoded: AnthropicResponse
        do {
            decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        } catch {
            throw AITextAnalysisError.unsupportedResponse
        }
        let content = decoded.content.compactMap(\.text).joined(separator: "\n")
        guard !content.isEmpty else {
            throw AITextAnalysisError.unsupportedResponse
        }
        return ProviderTextGenerationResult(content: content, tokenUsage: decoded.usage?.tokenUsage)
    }

    private func endpoint(baseURLString: String, path: String) throws -> URL {
        guard var components = URLComponents(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AITextAnalysisError.invalidProviderURL
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, path].filter { !$0.isEmpty }.joined(separator: "/"))
        guard let url = components.url else {
            throw AITextAnalysisError.invalidProviderURL
        }
        return url
    }

    static func decodeResult(from content: String, feature: AIArtifactFeature) throws -> AIArtifactGenerationResult {
        let json = extractJSONObject(from: content)
        guard let data = json.data(using: .utf8) else {
            throw AITextAnalysisError.unsupportedResponse
        }
        let decoded: AIArtifactResponse
        do {
            decoded = try JSONDecoder().decode(AIArtifactResponse.self, from: data)
        } catch {
            throw AITextAnalysisError.unsupportedResponse
        }
        let title = normalized(decoded.documentTitle ?? decoded.title) ?? "Untitled"
        let oneLiner = normalized(decoded.oneLiner) ?? normalized(decoded.summaryText) ?? title
        let summaryText = normalized(decoded.summaryText) ?? oneLiner
        let keyPoints = decoded.keyPoints ?? []
        let blocks = decoded.documentBlocks?.map(\.summaryBlock).filter { block in
            !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !block.items.isEmpty
        } ?? [
            TimelineAISummaryBlock(kind: "heading", level: 2, text: title, items: []),
            TimelineAISummaryBlock(kind: "paragraph", level: 0, text: summaryText, items: []),
            TimelineAISummaryBlock(kind: "bullets", level: 0, text: "", items: keyPoints)
        ]
        let reviewContent: ReviewContentPayload?
        if feature == .weeklyReview {
            reviewContent = ReviewContentPayload(
                title: title,
                subtitle: decoded.subtitle,
                bodyMarkdown: decoded.bodyMarkdown ?? summaryText,
                oneLiner: oneLiner,
                keywords: decoded.keywords,
                themes: decoded.themes,
                emotionalReflection: decoded.emotionalReflection,
                progressAndOpenLoops: decoded.progressAndOpenLoops,
                rhythm: decoded.rhythm,
                notableMoments: decoded.notableMoments,
                gentleSuggestions: decoded.gentleSuggestions,
                uncertainty: decoded.uncertainty
            )
        } else {
            reviewContent = nil
        }
        return AIArtifactGenerationResult(
            documentTitle: title,
            oneLiner: oneLiner,
            summaryText: summaryText,
            keyPoints: keyPoints,
            documentBlocks: blocks,
            suggestedTags: decoded.suggestedTags?.topics ?? [],
            suggestedAreaId: decoded.suggestedTags?.areaId,
            reviewContent: reviewContent
        )
    }

    private static func validateHTTPResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AITextAnalysisError.unsupportedResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let message = (try? JSONDecoder().decode(ProviderErrorResponse.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw AITextAnalysisError.provider(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private static func prompt(for request: AIArtifactGenerationRequest) -> String {
        let language = languageInstruction(for: request.languageMode)
        let vocabulary = request.topicVocabulary.isEmpty
            ? "No existing topic vocabulary."
            : "Prefer these existing topic tags when applicable: \(request.topicVocabulary.joined(separator: ", "))."
        let fixedAreas = "Fixed topic areas: 技术, 产品与设计, 学习与知识, 工作事务, 生活记录, 健康与运动, 情绪与关系. Use exactly one of these area names."
        let schema: String
        let qualityRules: String
        switch request.feature {
        case .mediaSummary, .checkInSummary:
            schema = """
            Return JSON with documentTitle, oneLiner, summaryText, keyPoints, documentBlocks, suggestedTags.
            documentBlocks items use { "kind": "heading|paragraph|bullets|numbered_list|ai_suggested", "level": 0|2, "text": string, "items": string[] }.
            suggestedTags must use { "area": string, "topics": string[] }. Do not return or infer primary tags.
            \(fixedAreas)
            Keep documentTitle within 40 characters.
            """
            qualityRules = """
            Coverage rules:
            - Prefer complete coverage over brevity; a longer result is better than dropping important user intent.
            - Do not omit concrete points, decisions, questions, problems, names, tools, dates, places, next actions, or tradeoffs that appear in Source.
            - Do not invent details, causes, emotions, or actions that are not grounded in Source.
            - If the transcript seems unreliable, empty, contradictory, or unrelated to the requested topic, say that uncertainty explicitly in the summary instead of fabricating a confident story.
            - Use as many documentBlocks as needed to preserve the important content. For dense input, create multiple headed sections with paragraphs and bullet lists.
            - Keep oneLiner short, but make summaryText and documentBlocks comprehensive enough for later review without reopening the audio.
            """
        case .weeklyReview:
            schema = """
            Return JSON with title, subtitle, oneLiner, bodyMarkdown, keyPoints, documentBlocks, suggestedTags, gentleSuggestions.
            bodyMarkdown should be a complete weekly review ready to publish as a Moment.
            suggestedTags must use { "area": string, "topics": string[] }. Do not return or infer primary tags.
            \(fixedAreas)
            """
            qualityRules = """
            Coverage rules:
            - Prefer complete coverage over brevity; include the meaningful themes, shifts, accomplishments, blockers, open loops, and concrete moments from Source.
            - Do not omit concrete points, decisions, questions, problems, names, tools, dates, places, next actions, or tradeoffs that appear in Source.
            - Do not invent details, causes, emotions, or actions that are not grounded in Source.
            - If the source evidence is thin or contradictory, say that uncertainty explicitly.
            - Use as many documentBlocks as needed to preserve the important content.
            """
        }
        return """
        \(schema)
        \(qualityRules)
        \(language)
        \(vocabulary)
        Title/context: \(request.title ?? "None")

        Source:
        \(request.sourceText)
        """
    }

    private static func languageInstruction(for mode: AILanguageMode) -> String {
        switch mode {
        case .auto:
            return """
            Infer the dominant language from Source and write every user-facing artifact field in that language.
            If the source is mostly Chinese, write natural Simplified Chinese even when English technical terms appear.
            If the source is mostly English, write natural English while preserving necessary Chinese names or terms.
            If the source is genuinely mixed, keep the output naturally mixed.
            documentTitle/title, oneLiner, summaryText/bodyMarkdown, keyPoints, documentBlocks text/items, suggestedTags, and gentleSuggestions must follow the same language decision.
            Do not choose English just because this prompt, JSON schema, or field names are English.
            """
        case .chinese:
            return """
            Write every user-facing artifact field in natural Simplified Chinese.
            documentTitle/title, oneLiner, summaryText/bodyMarkdown, keyPoints, documentBlocks text/items, suggestedTags, and gentleSuggestions must be Chinese.
            Preserve necessary English technical terms when they are part of the source.
            """
        case .english:
            return """
            Write every user-facing artifact field in natural English.
            documentTitle/title, oneLiner, summaryText/bodyMarkdown, keyPoints, documentBlocks text/items, suggestedTags, and gentleSuggestions must be English.
            Preserve necessary Chinese names or terms when they are part of the source.
            """
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func extractJSONObject(from content: String) -> String {
        var trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") else {
            return trimmed
        }
        return String(trimmed[start...end])
    }
}

private struct OpenAICompatibleRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case responseFormat = "response_format"
        case maxTokens = "max_tokens"
    }
}

private struct ProviderTextGenerationResult {
    let content: String
    let tokenUsage: AITokenUsage?
}

private struct OpenAICompatibleResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
    let usage: OpenAICompatibleUsage?
}

private struct OpenAICompatibleUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }

    var tokenUsage: AITokenUsage? {
        let input = promptTokens ?? inputTokens
        let output = completionTokens ?? outputTokens
        let usage = AITokenUsage(inputTokens: input, outputTokens: output, totalTokens: totalTokens)
        return usage.hasValues ? usage : nil
    }
}

private struct AnthropicRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let maxTokens: Int
    let system: String
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model, system, messages
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicResponse: Decodable {
    struct Content: Decodable {
        let type: String?
        let text: String?
    }

    let content: [Content]
    let usage: AnthropicUsage?
}

private struct AnthropicUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }

    var tokenUsage: AITokenUsage? {
        let usage = AITokenUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: nil
        )
        return usage.hasValues ? usage : nil
    }
}

private struct ProviderErrorResponse: Decodable {
    struct ErrorBody: Decodable {
        let message: String?
    }

    let error: ErrorBody?

    var message: String? {
        error?.message
    }
}

private struct AISuggestedTagPayload: Decodable {
    let areaId: String?
    let topics: [String]

    enum CodingKeys: String, CodingKey {
        case area
        case areaId
        case topics
        case tags
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let legacyTopics = try? container.decode([String].self) {
            areaId = nil
            topics = Self.cleanedTopics(legacyTopics)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let areaValue = container.decodeLooseStringIfPresent(.area)
            ?? container.decodeLooseStringIfPresent(.areaId)

        let decodedTopics: [String]
        if let stringTopics = try? container.decodeIfPresent([String].self, forKey: .topics) {
            decodedTopics = Self.cleanedTopics(stringTopics)
        } else if let objectTopics = try? container.decodeIfPresent([AISuggestedTopicPayload].self, forKey: .topics) {
            decodedTopics = Self.cleanedTopics(objectTopics.compactMap(\.name))
        } else if let stringTags = try? container.decodeIfPresent([String].self, forKey: .tags) {
            decodedTopics = Self.cleanedTopics(stringTags)
        } else if let objectTags = try? container.decodeIfPresent([AISuggestedTopicPayload].self, forKey: .tags) {
            decodedTopics = Self.cleanedTopics(objectTags.compactMap(\.name))
        } else {
            decodedTopics = []
        }

        topics = decodedTopics
        areaId = areaValue.map { TopicTagArea.fromProviderValue($0, topicName: decodedTopics.first).rawValue }
    }

    private static func cleanedTopics(_ rawTopics: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for rawTopic in rawTopics {
            let topic = rawTopic.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !topic.isEmpty, topic.count <= 40 else {
                continue
            }

            let normalized = LocalDatabase.normalizedTagName(topic)
            guard seen.insert(normalized).inserted else {
                continue
            }
            result.append(topic)
        }

        return result
    }
}

private struct AISuggestedTopicPayload: Decodable {
    let name: String?

    init(from decoder: Decoder) throws {
        name = try LooseStringValue(from: decoder).value
    }
}

private struct AIArtifactResponse: Decodable {
    let documentTitle: String?
    let title: String?
    let subtitle: String?
    let oneLiner: String?
    let summaryText: String?
    let bodyMarkdown: String?
    let keyPoints: [String]?
    let documentBlocks: [AISummaryDocumentBlockPayload]?
    let suggestedTags: AISuggestedTagPayload?
    let keywords: [ReviewKeywordPayload]?
    let themes: [ReviewThemePayload]?
    let emotionalReflection: ReviewEmotionalReflectionPayload?
    let progressAndOpenLoops: ReviewProgressPayload?
    let rhythm: ReviewRhythmPayload?
    let notableMoments: [ReviewNotableMomentPayload]?
    let gentleSuggestions: [String]?
    let uncertainty: [String]?

    enum CodingKeys: String, CodingKey {
        case documentTitle
        case title
        case subtitle
        case oneLiner
        case summaryText
        case bodyMarkdown
        case keyPoints
        case documentBlocks
        case suggestedTags
        case keywords
        case themes
        case emotionalReflection
        case progressAndOpenLoops
        case rhythm
        case notableMoments
        case gentleSuggestions
        case uncertainty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        documentTitle = container.decodeLooseStringIfPresent(.documentTitle)
        title = container.decodeLooseStringIfPresent(.title)
        subtitle = container.decodeLooseStringIfPresent(.subtitle)
        oneLiner = container.decodeLooseStringIfPresent(.oneLiner)
        summaryText = container.decodeLooseStringIfPresent(.summaryText)
        bodyMarkdown = container.decodeLooseStringIfPresent(.bodyMarkdown)
        keyPoints = container.decodeLooseStringArrayIfPresent(.keyPoints)
        if container.contains(.documentBlocks) {
            documentBlocks = try container.decodeIfPresent([AISummaryDocumentBlockPayload].self, forKey: .documentBlocks)
        } else {
            documentBlocks = nil
        }
        suggestedTags = (try? container.decodeIfPresent(AISuggestedTagPayload.self, forKey: .suggestedTags)) ?? nil
        keywords = (try? container.decodeIfPresent([ReviewKeywordPayload].self, forKey: .keywords)) ?? nil
        themes = (try? container.decodeIfPresent([ReviewThemePayload].self, forKey: .themes)) ?? nil
        emotionalReflection = (try? container.decodeIfPresent(ReviewEmotionalReflectionPayload.self, forKey: .emotionalReflection)) ?? nil
        progressAndOpenLoops = (try? container.decodeIfPresent(ReviewProgressPayload.self, forKey: .progressAndOpenLoops)) ?? nil
        rhythm = (try? container.decodeIfPresent(ReviewRhythmPayload.self, forKey: .rhythm)) ?? nil
        notableMoments = (try? container.decodeIfPresent([ReviewNotableMomentPayload].self, forKey: .notableMoments)) ?? nil
        gentleSuggestions = container.decodeLooseStringArrayIfPresent(.gentleSuggestions)
        uncertainty = container.decodeLooseStringArrayIfPresent(.uncertainty)
    }
}

private struct AISummaryDocumentBlockPayload: Decodable {
    let kind: String?
    let level: Int?
    let text: String?
    let items: [String]?

    enum CodingKeys: String, CodingKey {
        case kind, level, text, items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = container.decodeLooseStringIfPresent(.kind)
        text = container.decodeLooseStringIfPresent(.text)
        items = container.decodeLooseStringArrayIfPresent(.items)

        if let intLevel = try? container.decodeIfPresent(Int.self, forKey: .level) {
            level = intLevel
        } else if let stringLevel = container.decodeLooseStringIfPresent(.level) {
            level = Int(stringLevel.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            level = nil
        }
    }

    var summaryBlock: TimelineAISummaryBlock {
        let normalizedKind = normalized(kind) ?? "paragraph"
        let defaultLevel = normalizedKind == "heading" ? 2 : 0
        return TimelineAISummaryBlock(
            kind: normalizedKind,
            level: level ?? defaultLevel,
            text: normalized(text) ?? "",
            items: items ?? []
        )
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private struct LooseStringArray: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var decodedValues: [String] = []
            while !array.isAtEnd {
                let decoded = try array.decode(LooseStringValue.self)
                if let value = decoded.value {
                    decodedValues.append(value)
                }
            }
            values = decodedValues
            return
        }

        let singleValue = try LooseStringValue(from: decoder).value
        values = singleValue.map { [$0] } ?? []
    }
}

private struct LooseStringValue: Decodable {
    let value: String?

    enum CodingKeys: String, CodingKey {
        case text
        case label
        case name
        case title
        case value
        case body
        case summary
        case content
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer() {
            if singleValue.decodeNil() {
                value = nil
                return
            }
            if let stringValue = try? singleValue.decode(String.self) {
                value = Self.normalized(stringValue)
                return
            }
            if let intValue = try? singleValue.decode(Int.self) {
                value = "\(intValue)"
                return
            }
            if let doubleValue = try? singleValue.decode(Double.self) {
                value = "\(doubleValue)"
                return
            }
            if let boolValue = try? singleValue.decode(Bool.self) {
                value = boolValue ? "true" : "false"
                return
            }
        }

        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            for key in [CodingKeys.text, .label, .name, .title, .value, .body, .summary, .content] {
                if let nested = try? container.decodeIfPresent(LooseStringValue.self, forKey: key),
                   let nestedValue = nested.value {
                    value = nestedValue
                    return
                }
            }
        }

        value = nil
    }

    private static func normalized(_ rawValue: String?) -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private extension KeyedDecodingContainer {
    func decodeLooseStringIfPresent(_ key: Key) -> String? {
        guard let decoded = try? decodeIfPresent(LooseStringValue.self, forKey: key) else {
            return nil
        }
        return decoded.value
    }

    func decodeLooseStringArrayIfPresent(_ key: Key) -> [String]? {
        guard let decoded = try? decodeIfPresent(LooseStringArray.self, forKey: key) else {
            return nil
        }
        return decoded.values
    }
}

private struct AIConnectionTestResponse: Decodable {
    let ok: Bool
}
