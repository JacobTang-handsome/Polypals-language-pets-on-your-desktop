import Foundation
import Testing
@testable import PolyPals

private final class ResponseURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var capturedRequest: URLRequest?
    nonisolated(unsafe) static var capturedBody: Data?
    nonisolated(unsafe) static var contentType = "application/json"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedRequest = request
        Self.capturedBody = request.httpBody ?? request.httpBodyStream.flatMap(Self.readAll)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": Self.contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(from stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

@Suite("Responses API contract", .serialized)
struct OpenAIResponsesClientTests {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResponseURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    @Test("DeepSeek uses its own key, endpoint, stateless body, and reasoning setting")
    func deepSeekContract() async throws {
        let keys = InMemoryAPIKeyStore()
        try keys.saveAPIKey("deepseek-test-key", for: .deepSeek)
        ResponseURLProtocolStub.statusCode = 200
        ResponseURLProtocolStub.contentType = "application/json"
        ResponseURLProtocolStub.responseData = Data("{\"output_text\":\"OK\"}".utf8)
        ResponseURLProtocolStub.capturedRequest = nil
        ResponseURLProtocolStub.capturedBody = nil
        let client = OpenAIResponsesClient(
            keyStore: keys,
            session: session(),
            configuration: .deepSeekDefault
        )
        let result = try await client.testConnection()
        #expect(result.provider == .deepSeek)
        let request = try #require(ResponseURLProtocolStub.capturedRequest)
        #expect(request.url?.absoluteString == "https://api.deepseek.com/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer deepseek-test-key")
        let data = try #require(ResponseURLProtocolStub.capturedBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["store"] as? Bool == false)
        #expect((body["reasoning"] as? [String: Any])?["effort"] as? String == "none")
    }

    @Test("Structured card request is private and fixed-endpoint")
    func cardRequestContract() async throws {
        let card: [String: Any] = [
            "petId": "sol", "type": "expression", "language": "es", "level": "B1",
            "estimatedSeconds": 45, "hook": "Un hallazgo", "targetText": "estar en las nubes",
            "prompt": "¿Qué significa?", "choices": ["distraído", "enfadado"],
            "answer": "distraído", "chineseHelp": "心不在焉", "sourceTitle": NSNull(),
            "sourceURL": NSNull(), "memoryKey": "es:estar-en-las-nubes"
        ]
        let cardData = try JSONSerialization.data(withJSONObject: card)
        let cardText = try #require(String(data: cardData, encoding: .utf8))
        ResponseURLProtocolStub.statusCode = 200
        ResponseURLProtocolStub.contentType = "application/json"
        ResponseURLProtocolStub.responseData = try JSONSerialization.data(withJSONObject: ["output_text": cardText])
        ResponseURLProtocolStub.capturedRequest = nil
        ResponseURLProtocolStub.capturedBody = nil

        let client = OpenAIResponsesClient(
            keyStore: InMemoryAPIKeyStore(key: "test-key-never-log"),
            session: session(),
            model: "gpt-5.6-terra"
        )
        let generated = try await client.generateCard(for: .definition(for: .sol), type: .expression, energy: .curious)
        #expect(generated.isValid)
        let request = try #require(ResponseURLProtocolStub.capturedRequest)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-never-log")
        let bodyData = try #require(ResponseURLProtocolStub.capturedBody)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(body["store"] as? Bool == false)
        #expect(body["previous_response_id"] == nil)
        #expect(body["conversation"] == nil)
        #expect((body["text"] as? [String: Any])?["format"] != nil)
    }

    @Test("Server body is never exposed in an error")
    func sanitizedServerError() async {
        ResponseURLProtocolStub.statusCode = 429
        ResponseURLProtocolStub.responseData = Data("secret-chat-body".utf8)
        let client = OpenAIResponsesClient(
            keyStore: InMemoryAPIKeyStore(key: "test-key"),
            session: session()
        )
        do {
            _ = try await client.generateCard(for: .definition(for: .sol), type: .expression, energy: .focused)
            Issue.record("Expected a rate-limit error")
        } catch {
            #expect(!error.localizedDescription.contains("secret-chat-body"))
            #expect(error.localizedDescription.contains("429"))
        }
    }

    @Test("Recorded SSE streams text without server-side state")
    func streamContract() async throws {
        ResponseURLProtocolStub.statusCode = 200
        ResponseURLProtocolStub.contentType = "text/event-stream"
        ResponseURLProtocolStub.capturedBody = nil
        ResponseURLProtocolStub.responseData = Data("""
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"Hola"}

        event: response.completed
        data: {"type":"response.completed"}

        data: [DONE]

        """.utf8)

        let client = OpenAIResponsesClient(
            keyStore: InMemoryAPIKeyStore(key: "stream-key"),
            session: session()
        )
        let request = ChatRequest(
            pet: .definition(for: .sol),
            correctionMode: .casual,
            energy: .tired,
            userText: "Cuéntame algo breve.",
            confirmedMemories: ["用户喜欢海边"],
            recentMessages: []
        )
        let stream = try await client.streamChat(request)
        var text = ""
        for try await event in stream {
            if case let .textDelta(delta) = event { text += delta }
        }
        #expect(text == "Hola")

        let bodyData = try #require(ResponseURLProtocolStub.capturedBody)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(body["store"] as? Bool == false)
        #expect(body["stream"] as? Bool == true)
        #expect(body["conversation"] == nil)
        #expect(body["previous_response_id"] == nil)
        #expect((body["input"] as? String)?.contains("用户喜欢海边") == true)
    }
}
