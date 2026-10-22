import Foundation

// Standalone integration tests for the public callback API. URLProtocol keeps
// requests in process; no API key, network access, or Xcode test target is needed.
private struct Fixture {
    var body: String
    var status = 200
    var contentType = "text/event-stream"
}

private struct RecordedRequest {
    let url: URL?
    let method: String?
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var fixtures: [String: Fixture] = [:]
    private static var recorded: [String: RecordedRequest] = [:]

    static func install(_ fixture: Fixture, path: String) {
        lock.lock()
        defer { lock.unlock() }
        fixtures[path] = fixture
    }

    static func request(path: String) -> RecordedRequest? {
        lock.lock()
        defer { lock.unlock() }
        return recorded[path]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "lexibar-test.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url!.path
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.lock.lock()
        let fixture = Self.fixtures[path]
        Self.recorded[path] = RecordedRequest(
            url: request.url,
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body
        )
        Self.lock.unlock()
        guard let fixture else {
            client?.urlProtocol(self, didFailWithError: TestFailure("Unexpected URL: \(path)"))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: fixture.status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": fixture.contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(fixture.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct StreamOutcome {
    var chunks: [String] = []
    var errors: [String] = []
    var completions = 0
    var timedOut = false
}

private final class Capture: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome = StreamOutcome()
    private var continuation: CheckedContinuation<StreamOutcome, Never>?

    init(_ continuation: CheckedContinuation<StreamOutcome, Never>) {
        self.continuation = continuation
    }

    func chunk(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        outcome.chunks.append(text)
    }

    func terminal(error: Error? = nil) {
        lock.lock()
        if let error { outcome.errors.append(error.localizedDescription) }
        else { outcome.completions += 1 }
        lock.unlock()
        // Observe accidental success callbacks after an error callback as well.
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(10)) {
            self.resolve()
        }
    }

    func resolve(timeout: Bool = false) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        if timeout { outcome.timedOut = true }
        let result = outcome
        lock.unlock()
        waiting?.resume(returning: result)
    }
}

private func json(_ object: Any, pretty: Bool = false) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object,
                                           options: pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func event(_ type: String, _ fields: [String: Any] = [:]) -> String {
    var payload = fields
    payload["type"] = type
    return "event: \(type)\ndata: \(json(payload))\n\n"
}

private func message(_ content: [[String: Any]]) -> [String: Any] {
    ["type": "message", "role": "assistant", "content": content]
}

private func text(_ value: String) -> [String: Any] {
    ["type": "output_text", "text": value]
}

private func response(_ output: [[String: Any]], status: String = "completed") -> [String: Any] {
    ["object": "response", "status": status, "output": output]
}

private struct Case {
    let name: String
    let provider: LLMProvider
    let fixture: Fixture
    let chunks: [String]
    var errorContains: String? = nil
}

@main
private struct LLMServiceRegressionTests {
    static func main() async {
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        URLProtocol.registerClass(MockURLProtocol.self)
        let completed = response([message([text("完整内容")])])
        let failed: [String: Any] = ["status": "failed", "error": ["message": "response failed"]]
        let incomplete: [String: Any] = ["status": "incomplete", "incomplete_details": ["reason": "max_output_tokens"]]
        let cases: [Case] = [
            Case(name: "Responses text/refusal deltas and completed deduplication", provider: .openAIResponses,
                 fixture: Fixture(body:
                    event("response.created", ["response": ["status": "in_progress"]]) +
                    event("response.reasoning_summary_text.delta", ["delta": "hidden reasoning"]) +
                    event("response.output_text.delta", ["delta": "你好"]) +
                    event("response.refusal.delta", ["delta": "，无法回答"]) +
                    event("response.output_text.done", ["text": "你好，无法回答"]) +
                    event("response.completed", ["response": response([message([text("你好，无法回答")])])])),
                 chunks: ["你好", "，无法回答"]),
            Case(name: "Responses completed event without deltas", provider: .openAIResponses,
                 fixture: Fixture(body: event("response.completed", ["response": completed])), chunks: ["完整内容"]),
            Case(name: "Responses multiline JSON and multiple output messages", provider: .openAIResponses,
                 fixture: Fixture(body: json(response([
                    ["type": "reasoning", "summary": [["text": "hidden"]]],
                    message([text("甲"), ["type": "refusal", "refusal": "乙"]]),
                    ["type": "function_call", "arguments": "hidden"],
                    message([text("丙"), text("丁")])
                 ]), pretty: true), contentType: "application/json"), chunks: ["甲乙丙丁"]),
            Case(name: "Responses single line JSON", provider: .openAIResponses,
                 fixture: Fixture(body: json(completed), contentType: "application/json"), chunks: ["完整内容"]),
            Case(name: "Responses refusal JSON", provider: .openAIResponses,
                 fixture: Fixture(body: json(response([message([["type": "refusal", "refusal": "无法回答"]])])),
                                  contentType: "application/json"), chunks: ["无法回答"]),
            Case(name: "Responses failed event", provider: .openAIResponses,
                 fixture: Fixture(body: event("response.failed", ["response": failed])),
                 chunks: [], errorContains: "response failed"),
            Case(name: "Responses incomplete event after a delta", provider: .openAIResponses,
                 fixture: Fixture(body: event("response.output_text.delta", ["delta": "部分内容"]) +
                    event("response.incomplete", ["response": incomplete])),
                 chunks: ["部分内容"], errorContains: "max_output_tokens"),
            Case(name: "Responses stream error", provider: .openAIResponses,
                 fixture: Fixture(body: event("error", ["message": "quota exceeded"])),
                 chunks: [], errorContains: "quota exceeded"),
            Case(name: "Responses failed JSON", provider: .openAIResponses,
                 fixture: Fixture(body: json(failed, pretty: true), contentType: "application/json"),
                 chunks: [], errorContains: "response failed"),
            Case(name: "Responses incomplete JSON", provider: .openAIResponses,
                 fixture: Fixture(body: json(incomplete), contentType: "application/json"),
                 chunks: [], errorContains: "max_output_tokens"),
            Case(name: "Responses HTTP error", provider: .openAIResponses,
                 fixture: Fixture(body: "denied", status: 401, contentType: "application/json"),
                 chunks: [], errorContains: "HTTP 401"),
            Case(name: "Responses unknown events are not successful output", provider: .openAIResponses,
                 fixture: Fixture(body: event("response.reasoning_summary_text.delta", ["delta": "hidden"]) +
                    event("response.completed", ["response": response([["type": "reasoning", "summary": []]])])),
                 chunks: [], errorContains: "解析"),
            Case(name: "Responses truncated stream after a delta", provider: .openAIResponses,
                 fixture: Fixture(body: event("response.output_text.delta", ["delta": "部分内容"])),
                 chunks: ["部分内容"], errorContains: "中断"),
            Case(name: "Responses data without optional space or final newline", provider: .openAIResponses,
                 fixture: Fixture(body: "data:\(json(["type": "response.output_text.delta", "delta": "紧凑流"]))\n\n" +
                    "data:\(json(["type": "response.completed", "response": completed]))"), chunks: ["紧凑流"]),
            Case(name: "Chat Completions stream compatibility", provider: .openAI,
                 fixture: Fixture(body: "data: \(json(["choices": [["delta": ["content": "旧接口"]]]]))\n\ndata: [DONE]\n\n"),
                 chunks: ["旧接口"]),
            Case(name: "Chat Completions multiline JSON fallback", provider: .openAI,
                 fixture: Fixture(body: json(["choices": [["message": ["content": "完整旧接口"]]]], pretty: true),
                                  contentType: "application/json"), chunks: ["完整旧接口"]),
            Case(name: "Anthropic stream compatibility", provider: .anthropic,
                 fixture: Fixture(body: event("content_block_delta", ["delta": ["type": "text_delta", "text": "Anthropic 内容"]]) +
                    event("message_stop")), chunks: ["Anthropic 内容"])
        ]

        var failures: [String] = []
        if LLMProvider.openAIResponses.rawValue != "OpenAI Responses" {
            failures.append("Responses provider must persist as OpenAI Responses")
        }
        for (index, test) in cases.enumerated() {
            do {
                try await run(test, index: index)
                print("PASS: \(test.name)")
            } catch {
                failures.append("\(test.name): \(error)")
                print("FAIL: \(test.name): \(error)")
            }
        }
        guard failures.isEmpty else {
            print("\n\(failures.count) regression(s) failed")
            exit(1)
        }
        print("\nAll \(cases.count) LLM regressions passed")
    }

    private static func run(_ test: Case, index: Int) async throws {
        let suffix: String
        switch test.provider {
        case .openAI: suffix = "chat/completions"
        case .openAIResponses: suffix = "responses"
        case .anthropic: suffix = "messages"
        }
        let basePath = "/case-\(index)/v1"
        let path = "\(basePath)/\(suffix)"
        MockURLProtocol.install(test.fixture, path: path)
        let settings = LLMSettings(provider: test.provider, apiKey: "test-placeholder-key",
                                   baseURL: "https://lexibar-test.invalid\(basePath)",
                                   model: "test-model", temperature: 0.25)
        let result = await withCheckedContinuation { continuation in
            let capture = Capture(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(5)) {
                capture.resolve(timeout: true)
            }
            LLMService.stream(settings: settings, input: "hello workplace",
                              onChunk: { capture.chunk($0) },
                              onError: { capture.terminal(error: $0) },
                              onComplete: { capture.terminal() })
        }
        try require(!result.timedOut, "stream timed out")
        try require(result.chunks == test.chunks, "chunks \(result.chunks) != \(test.chunks)")
        if let expected = test.errorContains {
            try require(result.errors.count == 1 && result.errors[0].contains(expected),
                        "expected error containing \(expected), got \(result.errors)")
            try require(result.completions == 0, "onComplete called after failure")
        } else {
            try require(result.errors.isEmpty, "unexpected errors: \(result.errors)")
            try require(result.completions == 1, "expected exactly one completion, got \(result.completions)")
        }
        guard let request = MockURLProtocol.request(path: path) else {
            throw TestFailure("expected request at \(path)")
        }
        try require(request.method == "POST", "expected POST")
        try require(request.header("Content-Type") == "application/json", "missing JSON Content-Type")
        let body = try JSONSerialization.jsonObject(with: request.body) as? [String: Any] ?? [:]
        try require(body["model"] as? String == "test-model", "wrong model")
        if test.provider == .openAIResponses {
            try require(body["temperature"] == nil, "Responses must omit unsupported temperature")
        } else {
            try require(body["temperature"] as? Double == 0.25, "wrong temperature")
        }
        try require(body["stream"] as? Bool == true, "stream must be true")
        if test.provider == .openAIResponses {
            try require(request.header("Authorization") == "Bearer test-placeholder-key", "missing bearer auth")
            try require(body["instructions"] as? String == Prompts.systemPrompt, "wrong instructions")
            let input = body["input"] as? [[String: Any]]
            try require(input?.count == 1, "Responses input must be a list containing one message")
            try require(input?.first?["role"] as? String == "user", "wrong Responses input role")
            let content = input?.first?["content"] as? [[String: String]]
            try require(content == [["type": "input_text", "text": Prompts.userPrompt(for: "hello workplace")]],
                        "wrong Responses input content")
        } else if test.provider == .openAI {
            try require(request.header("Authorization") == "Bearer test-placeholder-key", "missing bearer auth")
            let messages = body["messages"] as? [[String: String]]
            try require(messages == [["role": "system", "content": Prompts.systemPrompt],
                                     ["role": "user", "content": Prompts.userPrompt(for: "hello workplace")]], "wrong chat messages")
        } else {
            try require(request.header("x-api-key") == "test-placeholder-key", "missing Anthropic key")
            try require(request.header("anthropic-version") == "2023-06-01", "wrong Anthropic version")
            try require(body["system"] as? String == Prompts.systemPrompt, "wrong Anthropic system prompt")
            try require(body["max_tokens"] as? Int == 2048, "wrong Anthropic max_tokens")
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure(message) }
    }
}
