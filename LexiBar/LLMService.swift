import Foundation

enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case openAI = "OpenAI"
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
        case .openAI:
            request = openAIRequest(url: url, settings: settings, input: input)
        case .anthropic:
            request = anthropicRequest(url: url, settings: settings, input: input)
        }

        Task {
            do {
                NSLog("[LexiBar] LLM request: \(request.url?.absoluteString ?? "nil")")
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
                for try await line in bytes.lines {
                    switch settings.provider {
                    case .openAI:
                        if let chunk = parseOpenAILine(line) {
                            onChunk(chunk)
                        }
                    case .anthropic:
                        buffer.append(line + "\n")
                        if line.isEmpty {
                            if let chunk = parseAnthropicEvent(buffer) {
                                onChunk(chunk)
                            }
                            buffer = ""
                        }
                    }
                }
                NSLog("[LexiBar] LLM stream complete")
                onComplete()
            } catch {
                NSLog("[LexiBar] LLM error: \(error)")
                onError(error)
            }
        }
    }

    private static func openAIRequest(url: URL, settings: LLMSettings, input: String) -> URLRequest {
        var request = URLRequest(url: url.appendingPathComponent("/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": settings.model,
            "temperature": settings.temperature,
            "stream": true,
            "messages": [
                ["role": "system", "content": Prompts.systemPrompt],
                ["role": "user", "content": Prompts.userPrompt(for: input)]
            ]
        ]
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
        let prefix = "data: "
        guard line.hasPrefix(prefix) else { return nil }
        let json = String(line.dropFirst(prefix.count))
        guard json != "[DONE]" else { return nil }
        guard let data = json.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else { return nil }
        guard let delta = first["delta"] as? [String: Any], let content = delta["content"] as? String else { return nil }
        return content
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
}
