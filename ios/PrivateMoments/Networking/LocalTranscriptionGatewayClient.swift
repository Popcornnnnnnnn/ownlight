import Foundation

struct LocalTranscriptionGatewayHealth: Decodable, Equatable {
    var ok: Bool?
    var service: String?
    var provider: String?
    var engine: String?
    var status: String
    var model: String
    var concurrency: Int?
}

struct LocalTranscriptionGatewaySegment: Codable, Equatable {
    var start: Double?
    var end: Double?
    var text: String
}

struct LocalTranscriptionGatewayTranscript: Decodable, Equatable {
    var text: String
    var language: String?
    var segments: [LocalTranscriptionGatewaySegment]
    var model: String?
    var provider: String?

    private enum CodingKeys: String, CodingKey {
        case text
        case language
        case segments
        case model
        case provider
    }

    init(
        text: String,
        language: String? = nil,
        segments: [LocalTranscriptionGatewaySegment] = [],
        model: String? = nil,
        provider: String? = nil
    ) {
        self.text = text
        self.language = language
        self.segments = segments
        self.model = model
        self.provider = provider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        segments = try container.decodeIfPresent([LocalTranscriptionGatewaySegment].self, forKey: .segments) ?? []
        model = try container.decodeIfPresent(String.self, forKey: .model)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
    }
}

struct LocalTranscriptionGatewayTranscriptionRequest {
    var audioURL: URL
    var media: TimelineMedia
    var gatewayURLString: String
    var model: String
    var token: String
}

enum LocalTranscriptionGatewayError: LocalizedError, Equatable {
    case invalidURL
    case missingToken
    case provider(statusCode: Int, message: String)
    case unsupportedResponse
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Local transcription gateway URL is invalid."
        case .missingToken:
            return "Local transcription gateway bearer token is missing."
        case .provider(_, let message):
            return message
        case .unsupportedResponse:
            return "The transcription provider returned a response Ownlight could not read. Check the Base URL, model, and response format."
        case .emptyTranscript:
            return "Local transcription gateway returned no speech text."
        }
    }
}

struct TranscriptionProviderConnectionInfo: Equatable {
    var model: String?
}

struct LocalTranscriptionGatewayClient {
    var urlSession: URLSession = .shared

    func testConnection(urlString: String, token: String) async throws -> LocalTranscriptionGatewayHealth {
        let url = try endpoint(baseURLString: urlString, pathSegments: ["health"])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(try normalizedToken(token))", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(data: data, response: response)
        return try JSONDecoder().decode(LocalTranscriptionGatewayHealth.self, from: data)
    }

    func testOpenAICompatibleConnection(urlString: String, token: String) async throws -> TranscriptionProviderConnectionInfo {
        let url = try endpoint(baseURLString: urlString, pathSegments: ["v1", "models"])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(try normalizedToken(token))", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(data: data, response: response)
        let models = try? JSONDecoder().decode(OpenAICompatibleModelsResponse.self, from: data)
        return TranscriptionProviderConnectionInfo(model: models?.data.first?.id)
    }

    func transcribe(
        audioURL: URL,
        urlString: String,
        token: String,
        model: String,
        language: String? = nil
    ) async throws -> LocalTranscriptionGatewayTranscript {
        let url = try endpoint(baseURLString: urlString, pathSegments: ["v1", "audio", "transcriptions"])
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestModel = normalizedModel.isEmpty ? LocalTranscriptionGatewaySettings.defaultModel : normalizedModel
        let boundary = "PrivateMomentsBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("Bearer \(try normalizedToken(token))", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try multipartBody(
            audioURL: audioURL,
            boundary: boundary,
            model: requestModel,
            language: language
        )
        let (data, response) = try await urlSession.upload(for: request, from: body)
        try validateHTTPResponse(data: data, response: response)
        let transcript: LocalTranscriptionGatewayTranscript
        do {
            transcript = try JSONDecoder().decode(LocalTranscriptionGatewayTranscript.self, from: data)
        } catch {
            throw LocalTranscriptionGatewayError.unsupportedResponse
        }
        guard !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalTranscriptionGatewayError.emptyTranscript
        }
        return transcript
    }

    private func endpoint(baseURLString: String, pathSegments: [String]) throws -> URL {
        guard var components = URLComponents(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw LocalTranscriptionGatewayError.invalidURL
        }

        let baseSegments = components.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        let normalizedSegments = mergedPathSegments(baseSegments: baseSegments, desiredSegments: pathSegments)
        components.path = "/" + normalizedSegments.joined(separator: "/")
        guard let url = components.url, let scheme = url.scheme, !scheme.isEmpty, url.host != nil else {
            throw LocalTranscriptionGatewayError.invalidURL
        }
        return url
    }

    private func mergedPathSegments(baseSegments: [String], desiredSegments: [String]) -> [String] {
        guard !desiredSegments.isEmpty else {
            return baseSegments
        }

        var normalizedBaseSegments = baseSegments
        if desiredSegments.first?.lowercased() == "v1",
           normalizedBaseSegments.last?.lowercased() == "health" {
            normalizedBaseSegments.removeLast()
        }

        if normalizedBaseSegments.suffix(desiredSegments.count).map({ $0.lowercased() })
            == desiredSegments.map({ $0.lowercased() }) {
            return normalizedBaseSegments
        }

        if desiredSegments.first?.lowercased() == "v1",
           normalizedBaseSegments.last?.lowercased() == "v1" {
            return normalizedBaseSegments + Array(desiredSegments.dropFirst())
        }

        if desiredSegments.count == 1,
           normalizedBaseSegments.last?.lowercased() == desiredSegments[0].lowercased() {
            return normalizedBaseSegments
        }

        return normalizedBaseSegments + desiredSegments
    }

    private func normalizedToken(_ token: String) throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LocalTranscriptionGatewayError.missingToken
        }
        return trimmed
    }

    private func validateHTTPResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalTranscriptionGatewayError.unsupportedResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = (try? JSONDecoder().decode(LocalTranscriptionGatewayErrorResponse.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw LocalTranscriptionGatewayError.provider(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func multipartBody(
        audioURL: URL,
        boundary: String,
        model: String,
        language: String?
    ) throws -> Data {
        var data = Data()
        data.appendMultipartField(name: "model", value: model, boundary: boundary)
        data.appendMultipartField(name: "response_format", value: "json", boundary: boundary)
        if let language = language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            data.appendMultipartField(name: "language", value: language, boundary: boundary)
        }
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n")
        data.append("Content-Type: \(mimeType(for: audioURL))\r\n\r\n")
        data.append(try Data(contentsOf: audioURL))
        data.append("\r\n--\(boundary)--\r\n")
        return data
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a", "mp4":
            return "audio/mp4"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "caf":
            return "audio/x-caf"
        default:
            return "application/octet-stream"
        }
    }
}

private struct LocalTranscriptionGatewayErrorResponse: Decodable {
    var error: String?
    var message: String?
}

private struct OpenAICompatibleModelsResponse: Decodable {
    struct Model: Decodable {
        var id: String
    }

    var data: [Model]
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }
}
