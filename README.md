# LexiBar

一个 macOS 菜单栏的黑话翻译器。

看不懂同事说的黑话、缩写、英文术语？选中那句话，按 `Cmd+L`，弹出浮窗直接给你翻译成人话。

## 怎么用

1. 选中那句看不懂的话。
2. `Cmd+C` 复制（或者不复制也行，会自动抓选中文字）。
3. 按 `Cmd+L`，浮窗自动弹出翻译。
4. 60 秒后自动关掉，不碍事。

## 配置

第一次用，点浮窗右上角 ⚙️ 进设置，填：

- API Key（支持 OpenAI / Anthropic）
- 模型名
- Base URL（默认 OpenAI）

快捷键也能在设置里改。

## 功能

- 全局快捷键唤起（默认 `Cmd+L`）
- 自动抓选中文字，不用手动粘贴
- 流式输出，边翻译边显示
- 历史记录，查过的都能翻回来
- 菜单栏常驻，不占 Dock

## 编译

```bash
./build.sh
open build/LexiBar.app
```

或 Xcode：

```bash
xcodegen generate
open LexiBar.xcodeproj
```

## 项目结构

- `LexiBar/`：Swift 源码
- `docs/`：PRD、架构、API 集成文档
- `project.yml`：XcodeGen 配置
