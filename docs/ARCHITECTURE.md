# LexiBar 架构文档

## 技术栈
- **语言/框架**：Swift + SwiftUI + AppKit
- **项目类型**：Xcode macOS App
- **依赖**：
  - `KeyboardShortcuts`：全局快捷键注册。
  - `URLSession`：LLM API 调用（不引入 SDK，减少依赖）。

## 模块职责

| 文件 | 职责 |
|------|------|
| `LexiBarApp.swift` | App 入口，初始化菜单栏控制器和全局快捷键。 |
| `StatusBarController.swift` | 管理 `NSStatusItem`：图标、点击菜单、打开浮窗。 |
| `GlobalShortcut.swift` | 使用 `KeyboardShortcuts` 注册并监听快捷键事件。 |
| `TextGrabber.swift` | 模拟 Cmd+C，读取剪贴板文本，并恢复原剪贴板内容。 |
| `LLMService.swift` | 构造请求、发送 HTTP、流式解析 SSE 响应。 |
| `Prompts.swift` | 默认 Prompt 模板。 |
| `FloatingPanel.swift` | 浮窗 UI：输入框、结果区、复制/重新生成按钮。 |
| `SettingsView.swift` | 设置面板：API Key、Base URL、Model、Temperature、Prompt。 |

## 数据流

```
用户选中文本 → 按快捷键
                 ↓
       GlobalShortcut 触发
                 ↓
       TextGrabber 模拟 Cmd+C
                 ↓
       读取剪贴板文本
                 ↓
       FloatingPanel 显示文本
                 ↓
       用户点击解释 / 自动提交
                 ↓
       LLMService 构造请求并流式调用 API
                 ↓
       FloatingPanel 展示结果
```

## 权限说明
- **剪贴板读取**：无需特殊权限，使用 `NSPasteboard` 即可。
- **模拟键盘事件**：使用 `CGEvent` 模拟 Cmd+C，需要应用具备“输入监控”或“辅助功能”权限才能向其他 App 发送按键。MVP 中先尝试实现，若权限不足则提示用户手动复制粘贴。
- **网络访问**：调用 LLM API，需要网络权限（macOS 通常自动允许）。

## 目录结构

```
LexiBar/
├── docs/
│   ├── PRD.md
│   ├── ARCHITECTURE.md
│   └── API_INTEGRATION.md
├── LexiBar/
│   ├── LexiBarApp.swift
│   ├── StatusBarController.swift
│   ├── GlobalShortcut.swift
│   ├── TextGrabber.swift
│   ├── LLMService.swift
│   ├── Prompts.swift
│   ├── FloatingPanel.swift
│   ├── SettingsView.swift
│   └── Models/
│       └── Translation.swift
└── LexiBar.xcodeproj
```
