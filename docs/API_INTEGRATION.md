# LexiBar API 集成文档

## 支持的 LLM 服务商
LexiBar 同时支持以下两种 API 格式，用户可在设置中选择：

1. **OpenAI 兼容格式**：OpenAI、Azure OpenAI、兼容 OpenAI 的第三方代理。
2. **Anthropic Messages API**：Claude 官方 API。

## OpenAI 兼容格式

### 请求
```http
POST {baseURL}/v1/chat/completions
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

## Anthropic Messages API

### 请求
```http
POST {baseURL}/v1/messages
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

## 安全
- API Key 存储在 macOS Keychain（MVP 优先实现，fallback 到 UserDefaults 时加密存储）。
- 所有请求使用 HTTPS。
