import SwiftUI
import KeyboardShortcuts

final class SettingsStore {
    static let shared = SettingsStore()

    @AppStorage("llmProvider") var providerRaw = LLMProvider.openAI.rawValue
    @AppStorage("llmAPIKey") var apiKey = ""
    @AppStorage("llmBaseURL") var baseURL = "https://api.openai.com/v1"
    @AppStorage("llmModel") var model = "gpt-4o-mini"
    @AppStorage("llmTemperature") var temperature = 0.7

    var llmSettings: LLMSettings {
        LLMSettings(
            provider: LLMProvider(rawValue: providerRaw) ?? .openAI,
            apiKey: apiKey,
            baseURL: baseURL,
            model: model,
            temperature: temperature
        )
    }
}

struct SettingsView: View {
    @AppStorage("llmProvider") var providerRaw = LLMProvider.openAI.rawValue
    @AppStorage("llmAPIKey") var apiKey = ""
    @AppStorage("llmBaseURL") var baseURL = "https://api.openai.com/v1"
    @AppStorage("llmModel") var model = "gpt-4o-mini"
    @AppStorage("llmTemperature") var temperature = 0.7

    var body: some View {
        Form {
            Section("快捷键") {
                KeyboardShortcuts.Recorder("触发 LexiBar", name: .toggleLexiBar)
            }

            Section("模型") {
                Picker("API 格式", selection: $providerRaw) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider.rawValue)
                    }
                }

                TextField("API 地址", text: $baseURL)
                    .help("填写基础地址，例如 https://api.openai.com/v1；请求路径会按 API 格式自动追加。")
                TextField("模型", text: $model)
            }

            Section("密钥") {
                SecureField("API Key", text: $apiKey)
            }

            Section("参数") {
                Slider(value: $temperature, in: 0...2, step: 0.1) {
                    Text("Temperature: \(temperature, specifier: "%.1f")")
                }
                .disabled(providerRaw == LLMProvider.openAIResponses.rawValue)
                if providerRaw == LLMProvider.openAIResponses.rawValue {
                    Text("Responses 使用模型默认采样参数，不发送 Temperature。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
