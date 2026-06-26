# LexiBar 产品需求文档

## 一句话描述
LexiBar 是一个 macOS 菜单栏小工具，帮用户把领导、同事说的中英文夹杂“黑话”快速翻译成人话。

## 目标用户
- 工作中经常遇到中英文夹杂、英文缩写、行业黑话的职场人。
- 典型场景：海归领导在 Slack/微信/邮件里说了一句 "We need to align on the Q3 OKR and make sure everyone is on the same page."，用户不知道 OKR、align、on the same page 是什么意思。

## 核心场景
1. 用户在任意 App（Slack、微信、浏览器、邮件等）选中一句话。
2. 按下快捷键，LexiBar 浮窗出现。
3. LexiBar 自动填入选中的句子并调用 LLM。
4. LLM 返回：
   - 整句话的通俗总结。
   - 逐个解释其中的英文单词/缩写/黑话。
5. 用户可以复制结果、重新生成或手动输入新句子。

## 功能清单

### MVP 功能
- [ ] 菜单栏图标常驻，点击可打开主窗口/设置/退出。
- [ ] 全局快捷键呼出浮窗。
- [ ] 自动抓取当前选中的文本。
- [ ] 调用 LLM 解释文本。
- [ ] 结果展示：总结 + 逐项解释。
- [ ] 复制结果到剪贴板。
- [ ] 设置面板：配置 API Key、Base URL、Model、Temperature、Prompt。
- [ ] 支持 OpenAI 和 Anthropic 两种 API 格式。

### 后续可扩展
- [ ] 历史记录。
- [ ] 自定义 Prompt 模板。
- [ ] 划词后右键菜单直接调用。
- [ ] Accessibility API 直接读取选中文本（替代 Cmd+C）。

## 非功能需求
- **简单**：安装即用，配置最少。
- **轻量**：原生 macOS 应用，内存占用低。
- **快速**：快捷键后 1 秒内出现浮窗，LLM 流式输出结果。
- **安全**：API Key 仅存储在本地 Keychain（MVP 可先用 UserDefaults 加密/Keychain 后续优化）。
- **隐私**：文本仅发送至用户自己配置的 LLM 服务端。
