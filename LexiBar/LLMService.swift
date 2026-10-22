import Foundation

enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case openAI = "OpenAI"
    case openAIResponses = "OpenAI Responses"
    case anthropic = "Anthropic"

    var id: String { rawValue }
}

struct LLMSettings {
    var provider: LLMProvider
    var apiKey: String
    var baseURL: String
    var model: String
    var temperature: Double
}

enum LLMError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)
    case streamParseError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 API 地址"
        case .invalidResponse: return "API 返回异常"
        case .apiError(let message): return message
        case .streamParseError: return "解析流式响应失败"
        }
    }
}

final class LLMService {
    static func stream(
        settings: LLMSettings,
        input: String,
        onChunk: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void,
        onComplete: @escaping () -> Void
    ) {
        guard let url = URL(string: settings.baseURL) else {
            onError(LLMError.invalidURL)
            return
        }

        var request: URLRequest
        switch settings.provider {
        case .openAI, .openAIResponses:
            request = openAIRequest(url: url, settings: settings, input: input)
        case .anthropic:
            request = anthropicRequest(url: url, settings: settings, input: input)
        }

        Task {
            do {
                print("[LexiBar] LLM request: \(request.url?.absoluteString ?? "nil")")
                print("[LexiBar] provider: \(settings.provider), model: \(settings.model)")
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw LLMError.invalidResponse
                }
                if httpResponse.statusCode >= 400 {
                    let data = try await bytes.reduce(into: Data()) { data, byte in data.append(byte) }
                    let body = String(data: data, encoding: .utf8) ?? ""
                    let message = body.isEmpty ? "HTTP \(httpResponse.statusCode)" : "HTTP \(httpResponse.statusCode): \(body)"
                    throw LLMError.apiError(message)
                }

                var buffer = ""
                var parsedAnyChunk = false
                var firstRawLine = ""
                var lineCount = 0
                var nonStreamingBody = ""
                var receivedSSE = false
                var responseCompleted = false
                for try await line in bytes.lines {
                    lineCount += 1
                    if firstRawLine.isEmpty && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        firstRawLine = line
                    }
                    print("[LexiBar] raw line #\(lineCount): \(line)")

                    if line.hasPrefix("data:") || line.hasPrefix("event:") {
                        receivedSSE = true
                        nonStreamingBody = ""
                    } else if !receivedSSE, settings.provider != .anthropic {
                        nonStreamingBody.append(line + "\n")
                    }

                    switch settings.provider {
                    case .openAI:
                        if let chunk = parseOpenAILine(line) {
                            parsedAnyChunk = true
                            onChunk(chunk)
                        }
                    case .openAIResponses:
                        if let event = try parseResponsesLine(line) {
                            switch event {
                            case .delta(let text):
                                if !text.isEmpty {
                                    parsedAnyChunk = true
                                    onChunk(text)
                                }
                            case .completed(let text):
                                responseCompleted = true
                                if !parsedAnyChunk, let text = text {
                                    parsedAnyChunk = true
                                    onChunk(text)
                                }
                            }
                        }
                    case .anthropic:
                        if line.hasPrefix("event: ") && !buffer.isEmpty {
                            if let chunk = parseAnthropicEvent(buffer) {
                                parsedAnyChunk = true
                                onChunk(chunk)
                            }
                            buffer = ""
                        }
                        buffer.append(line + "\n")
                        if line.isEmpty {
                            if let chunk = parseAnthropicEvent(buffer) {
                                parsedAnyChunk = true
                                onChunk(chunk)
                            }
                            buffer = ""
                        }
                    }
                }

                if !buffer.isEmpty, settings.provider == .anthropic {
                    if let chunk = parseAnthropicEvent(buffer) {
                        parsedAnyChunk = true
                        onChunk(chunk)
                    }
                    buffer = ""
                }

                if settings.provider == .openAIResponses, receivedSSE, !responseCompleted {
                    throw LLMError.apiError("响应在完成前中断")
                }

                if !parsedAnyChunk {
                    print("[LexiBar] warning: no chunk parsed across \(lineCount) lines")
                    print("[LexiBar] first raw line: \(firstRawLine)")

                    if settings.provider != .anthropic, !receivedSSE,
                       let fallback = try parseOpenAINonStreaming(nonStreamingBody, provider: settings.provider) {
                        print("[LexiBar] fallback to non-streaming parse")
                        onChunk(fallback)
                    } else {
                        throw LLMError.streamParseError
                    }
                }

                print("[LexiBar] LLM stream complete")
                onComplete()
            } catch {
                print("[LexiBar] LLM error: \(error)")
                onError(error)
            }
        }
    }

    private static func openAIRequest(url: URL, settings: LLMSettings, input: String) -> URLRequest {
        let isResponses = settings.provider == .openAIResponses
        let endpoint = isResponses ? "responses" : "chat/completions"
        var request = URLRequest(url: url.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": settings.model,
            "stream": true
        ]
        if isResponses {
            body["instructions"] = Prompts.systemPrompt
            body["input"] = [
                [
                    "role": "user",
                    "content": [["type": "input_text", "text": Prompts.userPrompt(for: input)]]
                ]
            ]
        } else {
            body["temperature"] = settings.temperature
            body["messages"] = [
                ["role": "system", "content": Prompts.systemPrompt],
                ["role": "user", "content": Prompts.userPrompt(for: input)]
            ]
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func anthropicRequest(url: URL, settings: LLMSettings, input: String) -> URLRequest {
        var request = URLRequest(url: url.appendingPathComponent("/messages"))
        request.httpMethod = "POST"
        request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": settings.model,
            "max_tokens": 2048,
            "temperature": settings.temperature,
            "stream": true,
            "system": Prompts.systemPrompt,
            "messages": [
                ["role": "user", "content": Prompts.userPrompt(for: input)]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func parseOpenAILine(_ line: String) -> String? {
        guard let object = parseSSEData(line) else { return nil }
        guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else { return nil }
        guard let delta = first["delta"] as? [String: Any], let content = delta["content"] as? String else { return nil }
        return content
    }

    private enum ResponsesEvent {
        case delta(String)
        case completed(String?)
    }

    private static func parseSSEData(_ line: String) -> [String: Any]? {
        guard line.hasPrefix("data:") else { return nil }
        let json = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func parseResponsesLine(_ line: String) throws -> ResponsesEvent? {
        guard let object = parseSSEData(line) else { return nil }
        if let error = responsesError(in: object) {
            throw error
        }
        switch object["type"] as? String {
        case "response.output_text.delta", "response.refusal.delta":
            guard let text = object["delta"] as? String else { return nil }
            return .delta(text)
        case "response.completed":
            guard let response = object["response"] as? [String: Any] else {
                throw LLMError.invalidResponse
            }
            return .completed(responsesText(in: response))
        default:
            return nil
        }
    }

    private static func responsesError(in object: [String: Any]) -> LLMError? {
        let response = object["response"] as? [String: Any] ?? object
        if let error = response["error"] as? [String: Any] {
            return .apiError(error["message"] as? String ?? error["code"] as? String ?? "API 返回错误")
        }
        if object["type"] as? String == "error" {
            return .apiError(object["message"] as? String ?? "API 返回错误")
        }
        let type = object["type"] as? String
        let status = response["status"] as? String
        if type == "response.failed" || status == "failed" {
            return .apiError("生成响应失败")
        }
        if type == "response.incomplete" || status == "incomplete" {
            let details = response["incomplete_details"] as? [String: Any]
            let reason = details?["reason"] as? String ?? "未知原因"
            return .apiError("响应未完成：\(reason)")
        }
        return nil
    }

    private static func responsesText(in object: [String: Any]) -> String? {
        guard let output = object["output"] as? [[String: Any]] else { return nil }
        let text = output.compactMap { item -> String? in
            guard item["type"] as? String == "message",
                  let content = item["content"] as? [[String: Any]] else { return nil }
            return content.compactMap { part -> String? in
                switch part["type"] as? String {
                case "output_text": return part["text"] as? String
                case "refusal": return part["refusal"] as? String
                default: return nil
                }
            }.joined()
        }.joined()
        return text.isEmpty ? nil : text
    }

    private static func parseAnthropicEvent(_ event: String) -> String? {
        var eventType: String?
        var data = ""
        for line in event.split(separator: "\n") {
            if line.hasPrefix("event: ") {
                eventType = String(line.dropFirst("event: ".count))
            } else if line.hasPrefix("data: ") {
                data = String(line.dropFirst("data: ".count))
            }
        }
        guard eventType == "content_block_delta" else { return nil }
        guard let dataData = data.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: dataData) as? [String: Any],
              let delta = object["delta"] as? [String: Any],
              let text = delta["text"] as? String else { return nil }
        return text
    }

    private static func parseOpenAINonStreaming(_ body: String, provider: LLMProvider) throws -> String? {
        guard let data = body.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = responsesError(in: object) {
            throw error
        }
        if provider == .openAIResponses {
            return responsesText(in: object)
        }
        guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else { return nil }
        guard let message = first["message"] as? [String: Any], let content = message["content"] as? String else { return nil }
        return content
    }
}
