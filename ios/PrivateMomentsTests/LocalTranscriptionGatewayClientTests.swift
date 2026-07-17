import XCTest
@testable import PrivateMoments

final class LocalTranscriptionGatewayClientTests: XCTestCase {
    override func tearDown() {
        LocalGatewayCaptureURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: "localTranscriptionGatewaySettings")
        try? KeychainStore.clearTranscriptionProviderAPIKey()
        super.tearDown()
    }

    func testHealthUsesBearerAuthorizedGatewayURL() async throws {
        LocalGatewayCaptureURLProtocol.responseStatusCode = 200
        LocalGatewayCaptureURLProtocol.responseBody = """
        {"ok":true,"service":"private-moments-transcription-gateway","provider":"local-gateway","engine":"mlx-whisper","status":"ready","model":"mlx-community/whisper-large-v3-turbo","concurrency":1}
        """.data(using: .utf8)!

        let client = makeClient()
        let health = try await client.testConnection(
            urlString: "https://gateway.example/base/",
            token: "gateway-token"
        )

        XCTAssertEqual(LocalGatewayCaptureURLProtocol.request?.url?.absoluteString, "https://gateway.example/base/health")
        XCTAssertEqual(LocalGatewayCaptureURLProtocol.request?.value(forHTTPHeaderField: "Authorization"), "Bearer gateway-token")
        XCTAssertEqual(health.status, "ready")
        XCTAssertEqual(health.model, "mlx-community/whisper-large-v3-turbo")
    }

    func testHealthURLCanBePastedWithoutDuplicatingPath() async throws {
        LocalGatewayCaptureURLProtocol.responseStatusCode = 200
        LocalGatewayCaptureURLProtocol.responseBody = """
        {"ok":true,"status":"ready","model":"mlx-community/whisper-large-v3-turbo"}
        """.data(using: .utf8)!

        let client = makeClient()
        _ = try await client.testConnection(
            urlString: "http://192.0.2.10:3322/health",
            token: "gateway-token"
        )

        XCTAssertEqual(LocalGatewayCaptureURLProtocol.request?.url?.absoluteString, "http://192.0.2.10:3322/health")
    }

    func testOpenAICompatibleConnectionUsesModelsEndpoint() async throws {
        LocalGatewayCaptureURLProtocol.responseStatusCode = 200
        LocalGatewayCaptureURLProtocol.responseBody = """
        {"object":"list","data":[{"id":"whisper-1","object":"model"}]}
        """.data(using: .utf8)!

        let client = makeClient()
        let info = try await client.testOpenAICompatibleConnection(
            urlString: "https://api.example.com/v1",
            token: "gateway-token"
        )

        XCTAssertEqual(info.model, "whisper-1")
        XCTAssertEqual(LocalGatewayCaptureURLProtocol.request?.url?.absoluteString, "https://api.example.com/v1/models")
        XCTAssertEqual(LocalGatewayCaptureURLProtocol.request?.value(forHTTPHeaderField: "Authorization"), "Bearer gateway-token")
    }

    func testOpenAICompatibleConnectionTreatsPastedHealthURLAsServiceRoot() async throws {
        LocalGatewayCaptureURLProtocol.responseStatusCode = 200
        LocalGatewayCaptureURLProtocol.responseBody = """
        {"object":"list","data":[{"id":"mlx-community/whisper-large-v3-turbo","object":"model"}]}
        """.data(using: .utf8)!

        let client = makeClient()
        _ = try await client.testOpenAICompatibleConnection(
            urlString: "http://192.0.2.10:3322/health",
            token: "gateway-token"
        )

        XCTAssertEqual(LocalGatewayCaptureURLProtocol.request?.url?.absoluteString, "http://192.0.2.10:3322/v1/models")
    }

    func testConnectionWorkflowSavesCurrentDraftAfterSuccessfulTest() async throws {
        AppSettings.localTranscriptionGatewaySettings = LocalTranscriptionGatewaySettings(
            urlString: "https://old.example",
            model: "old-model"
        )
        try KeychainStore.saveTranscriptionProviderAPIKey("old-key")
        LocalGatewayCaptureURLProtocol.responseStatusCode = 200
        LocalGatewayCaptureURLProtocol.responseBody = """
        {"object":"list","data":[{"id":"mlx-community/whisper-large-v3-turbo","object":"model"}]}
        """.data(using: .utf8)!

        let workflow = TranscriptionProviderConnectionWorkflow(client: makeClient())
        let info = try await workflow.testAndSave(
            mode: .customOpenAICompatible,
            settings: LocalTranscriptionGatewaySettings(
                urlString: "https://new.example",
                model: "mlx-community/whisper-large-v3-turbo"
            ),
            apiKey: "new-key"
        )

        XCTAssertEqual(info.model, "mlx-community/whisper-large-v3-turbo")
        XCTAssertEqual(LocalGatewayCaptureURLProtocol.request?.url?.absoluteString, "https://new.example/v1/models")
        XCTAssertEqual(LocalGatewayCaptureURLProtocol.request?.value(forHTTPHeaderField: "Authorization"), "Bearer new-key")
        XCTAssertEqual(AppSettings.localTranscriptionGatewaySettings.urlString, "https://new.example")
        XCTAssertEqual(AppSettings.localTranscriptionGatewaySettings.model, "mlx-community/whisper-large-v3-turbo")
        XCTAssertEqual(try KeychainStore.transcriptionProviderAPIKey(), "new-key")
    }

    func testTranscriptionUsesOpenAICompatibleMultipartRequest() async throws {
        LocalGatewayCaptureURLProtocol.responseStatusCode = 200
        LocalGatewayCaptureURLProtocol.responseBody = """
        {"text":"今天讨论本地转录网关。","language":"zh","segments":[{"start":0,"end":1.2,"text":"今天讨论本地转录网关。"}],"model":"mlx-community/whisper-turbo","provider":"local-gateway"}
        """.data(using: .utf8)!
        let audioURL = FileManager.default.temporaryDirectory
            .appending(path: "gateway-client-\(UUID().uuidString).m4a")
        try Data("audio-bytes".utf8).write(to: audioURL)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        let client = makeClient()
        let result = try await client.transcribe(
            audioURL: audioURL,
            urlString: "https://gateway.example",
            token: "gateway-token",
            model: "mlx-community/whisper-turbo",
            language: "zh"
        )

        XCTAssertEqual(result.text, "今天讨论本地转录网关。")
        XCTAssertEqual(result.language, "zh")
        XCTAssertEqual(result.segments.first?.text, "今天讨论本地转录网关。")
        XCTAssertEqual(LocalGatewayCaptureURLProtocol.request?.url?.absoluteString, "https://gateway.example/v1/audio/transcriptions")
        XCTAssertEqual(LocalGatewayCaptureURLProtocol.request?.httpMethod, "POST")
        XCTAssertEqual(LocalGatewayCaptureURLProtocol.request?.value(forHTTPHeaderField: "Authorization"), "Bearer gateway-token")
        let contentType = try XCTUnwrap(LocalGatewayCaptureURLProtocol.request?.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.contains("multipart/form-data; boundary="))

        let body = String(decoding: try XCTUnwrap(LocalGatewayCaptureURLProtocol.requestBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"\(audioURL.lastPathComponent)\""))
        XCTAssertTrue(body.contains("name=\"model\""))
        XCTAssertTrue(body.contains("mlx-community/whisper-turbo"))
        XCTAssertTrue(body.contains("name=\"language\""))
        XCTAssertTrue(body.contains("zh"))
        XCTAssertTrue(body.contains("name=\"response_format\""))
        XCTAssertTrue(body.contains("json"))
    }

    func testOpenAICompatibleV1BaseURLDoesNotDuplicateV1Path() async throws {
        LocalGatewayCaptureURLProtocol.responseStatusCode = 200
        LocalGatewayCaptureURLProtocol.responseBody = """
        {"text":"hello","segments":[],"model":"whisper-1","provider":"custom"}
        """.data(using: .utf8)!
        let audioURL = FileManager.default.temporaryDirectory
            .appending(path: "gateway-client-\(UUID().uuidString).m4a")
        try Data("audio-bytes".utf8).write(to: audioURL)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        let client = makeClient()
        _ = try await client.transcribe(
            audioURL: audioURL,
            urlString: "https://api.example.com/v1",
            token: "gateway-token",
            model: "whisper-1"
        )

        XCTAssertEqual(LocalGatewayCaptureURLProtocol.request?.url?.absoluteString, "https://api.example.com/v1/audio/transcriptions")
    }

    func testOpenAICompatibleJSONResponseOnlyRequiresText() async throws {
        LocalGatewayCaptureURLProtocol.responseStatusCode = 200
        LocalGatewayCaptureURLProtocol.responseBody = """
        {"text":"hello from standard whisper json"}
        """.data(using: .utf8)!
        let audioURL = FileManager.default.temporaryDirectory
            .appending(path: "gateway-client-\(UUID().uuidString).m4a")
        try Data("audio-bytes".utf8).write(to: audioURL)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        let client = makeClient()
        let transcript = try await client.transcribe(
            audioURL: audioURL,
            urlString: "https://api.example.com/v1",
            token: "gateway-token",
            model: "whisper-1"
        )

        XCTAssertEqual(transcript.text, "hello from standard whisper json")
        XCTAssertEqual(transcript.segments, [])
    }

    func testTranscriptionDecodeFailureIsReportedAsUnsupportedResponse() async throws {
        LocalGatewayCaptureURLProtocol.responseStatusCode = 200
        LocalGatewayCaptureURLProtocol.responseBody = """
        {"unexpected":"shape"}
        """.data(using: .utf8)!
        let audioURL = FileManager.default.temporaryDirectory
            .appending(path: "gateway-client-\(UUID().uuidString).m4a")
        try Data("audio-bytes".utf8).write(to: audioURL)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        let client = makeClient()

        do {
            _ = try await client.transcribe(
                audioURL: audioURL,
                urlString: "https://api.example.com/v1",
                token: "gateway-token",
                model: "whisper-1"
            )
            XCTFail("Expected unsupported response for malformed transcription response.")
        } catch let error as LocalTranscriptionGatewayError {
            XCTAssertEqual(error, .unsupportedResponse)
        }
    }

    private func makeClient() -> LocalTranscriptionGatewayClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LocalGatewayCaptureURLProtocol.self]
        return LocalTranscriptionGatewayClient(urlSession: URLSession(configuration: configuration))
    }
}

private final class LocalGatewayCaptureURLProtocol: URLProtocol {
    static var request: URLRequest?
    static var requestBody: Data?
    static var responseStatusCode = 200
    static var responseBody = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.request = request
        Self.requestBody = request.httpBody ?? Self.readBodyStream(from: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.responseStatusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        request = nil
        requestBody = nil
        responseStatusCode = 200
        responseBody = Data()
    }

    private static func readBodyStream(from request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer {
            stream.close()
        }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }

        return data
    }
}
