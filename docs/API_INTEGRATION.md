# LexiBar API 集成文档

## 支持的 LLM 服务商
LexiBar 支持以下三种 API 格式，用户可在设置中选择：

1. **OpenAI 兼容格式**：使用 Chat Completions 的 OpenAI、Azure OpenAI、兼容 OpenAI 的第三方代理。
2. **OpenAI Responses**：使用 Responses API 的 OpenAI 或兼容服务。
3. **Anthropic Messages API**：Claude 官方 API。

Base URL 填 API 根路径，默认 OpenAI 为 `https://api.openai.com/v1`，应用会自动追加所选格式的端点。以下示例中的 `{baseURL}` 已包含 `/v1`，无需再重复添加。

## OpenAI 兼容格式

### 请求
```http
POST {baseURL}/chat/completions
Authorization: Bearer {apiKey}
Content-Type: application/json
```

```json
{
  "model": "gpt-4o-mini",
  "temperature": 0.7,
  "stream": true,
  "messages": [
    { "role": "system", "content": "{systemPrompt}" },
    { "role": "user", "content": "{inputText}" }
  ]
}
```

### 流式响应
返回 `text/event-stream`，每行以 `data: ` 开头：

```
data: {"choices":[{"delta":{"content":"hello"}}]}
```

## OpenAI Responses

在设置的 API 格式中选择 **OpenAI Responses**。默认 Base URL 为 `https://api.openai.com/v1`，应用自动追加 `/responses`。

### 请求
```http
POST {baseURL}/responses
Authorization: Bearer {apiKey}
Content-Type: application/json
```

```json
{
  "model": "gpt-4o-mini",
  "stream": true,
  "instructions": "{systemPrompt}",
  "input": [
    {
      "role": "user",
      "content": [
        { "type": "input_text", "text": "{inputText}" }
      ]
    }
  ]
}
```

`instructions` 传入系统提示词，`input` 使用消息数组，待翻译文本放入用户消息的 `input_text` 内容块，兼容要求 `input` 必须为列表的服务。模型名使用设置中的值。Responses 使用模型默认采样参数，不发送 `temperature`，以兼容不支持该参数的模型或服务；设置页中该滑块会停用，已保存的值仍用于其他 API 格式。

### 流式响应
返回 `text/event-stream`，通过 `response.output_text.delta` 事件追加文本：

```
event: response.output_text.delta
data: {"type":"response.output_text.delta","delta":"hello"}
```

以 `response.completed` 事件确认完成；完成前连接中断会提示错误。若已收到文本增量，完成事件中的全文不会重复追加；若未收到增量，则从完成事件的 `response.output` 提取文本。拒绝回答通过 `response.refusal.delta` 显示。

### 完整 JSON 响应
兼容服务直接返回完整 JSON 时，从 `output` 中的 `message` 项读取 `content`，拼接所有 `output_text` 项的 `text`：

```json
{
  "id": "resp_example",
  "status": "completed",
  "output": [
    {
      "type": "message",
      "role": "assistant",
      "content": [
        { "type": "output_text", "text": "hello", "annotations": [] }
      ]
    }
  ]
}
```

同样支持 `content` 中的 `refusal` 项，并忽略推理或工具调用项。协议参考 [OpenAI 官方迁移文档](https://developers.openai.com/api/docs/guides/migrate-to-responses)和[流式事件文档](https://developers.openai.com/api/reference/resources/responses/streaming-events)。

## Anthropic Messages API

### 请求
```http
POST {baseURL}/messages
x-api-key: {apiKey}
anthropic-version: 2023-06-01
Content-Type: application/json
```

```json
{
  "model": "claude-3-5-sonnet-20241022",
  "max_tokens": 2048,
  "temperature": 0.7,
  "stream": true,
  "system": "{systemPrompt}",
  "messages": [
    { "role": "user", "content": "{inputText}" }
  ]
}
```

### 流式响应
返回 `text/event-stream`，事件类型为 `content_block_delta`：

```
event: content_block_delta
data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hello"}}
```

## 默认 Prompt

```
你是一位耐心的职场翻译。请把下面这句话翻译成通俗易懂的中文，并按以下格式输出：

1. 整体意思：用一句话总结这句话想表达什么。
2. 重点解释：逐个列出句子中的英文单词、缩写或黑话，并说明含义。

句子：{{inputText}}
```

## 错误处理
- 网络错误：提示用户检查网络。
- 401/403：提示 API Key 无效或权限不足。
- 429：提示请求过于频繁。
- 其他 4xx/5xx：展示服务端返回的错误信息。
- Responses API 的流式错误事件或完整 JSON 错误：展示服务端返回的错误信息；响应不含可读取文本时提示错误。

## 安全
- API Key 存储在 macOS Keychain（MVP 优先实现，fallback 到 UserDefaults 时加密存储）。
- 默认使用 HTTPS。本地网络地址及 `host.docker.internal` 允许 HTTP，便于接入本机或 Docker 中的 API；其他域名仍使用系统默认的 ATS 保护。
