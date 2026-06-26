# LexiBar

macOS 菜单栏工具，选中文字 `Cmd+C` 复制后，按快捷键自动调用 LLM 解释。

## 使用

1. 选中文字，`Cmd+C` 复制。
2. 按快捷键 `⌃⌥L`，或点菜单栏 📖 图标。
3. 弹出浮窗自动解释，60 秒后自动关闭。

## 配置

首次运行后，点浮窗右上角 ⚙️ 图标填入 API Key、模型、Base URL。支持 OpenAI 和 Anthropic。

## 编译运行

```bash
./build.sh
open build/LexiBar.app
```

或用 Xcode：

```bash
xcodegen generate
open LexiBar.xcodeproj
```

## 项目结构

- `LexiBar/`：Swift 源码
- `docs/`：PRD、架构、API 集成文档
- `project.yml`：XcodeGen 配置
