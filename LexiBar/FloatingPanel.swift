import SwiftUI
import AppKit

@MainActor
final class FloatingPanelManager {
    static let shared = FloatingPanelManager()
    private var panel: NSPanel?
    private var viewModel = FloatingPanelViewModel()
    private var autoCloseTimer: Timer?

    func show() {
        if panel == nil {
            createPanel()
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startAutoCloseTimer()
    }

    func showWithGrabbedText() {
        let pasteboard = NSPasteboard.general
        let text = (pasteboard.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.input = text
        viewModel.errorMessage = nil
        show()
        if !text.isEmpty {
            viewModel.translate()
        } else {
            viewModel.errorMessage = "剪贴板为空。请先选中文字按 Cmd+C 复制，再触发 LexiBar。"
        }
    }

    private func startAutoCloseTimer() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.panel?.orderOut(nil)
            }
        }
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "LexiBar"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.center()
        panel.contentView = NSHostingView(rootView: FloatingPanelView(viewModel: self.viewModel))
        self.panel = panel
    }
}

@MainActor
final class FloatingPanelViewModel: ObservableObject {
    @Published var input = ""
    @Published var result = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    func translate() {
        NSLog("[LexiBar] translate() called, input: \(input.prefix(50))")
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSLog("[LexiBar] input is empty, skipping")
            return
        }
        isLoading = true
        result = ""
        errorMessage = nil

        let settings = SettingsStore.shared.llmSettings
        NSLog("[LexiBar] settings: provider=\(settings.provider), baseURL=\(settings.baseURL), model=\(settings.model), apiKeyEmpty=\(settings.apiKey.isEmpty)")
        LLMService.stream(
            settings: settings,
            input: input,
            onChunk: { [weak self] chunk in
                DispatchQueue.main.async {
                    self?.result.append(chunk)
                }
            },
            onError: { [weak self] error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.errorMessage = error.localizedDescription
                }
            },
            onComplete: { [weak self] in
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
            }
        )
    }
}

struct FloatingPanelView: View {
    @StateObject var viewModel: FloatingPanelViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("LexiBar")
                    .font(.headline)
                Spacer()
                Button(action: {
                    SettingsWindowController.shared.show()
                }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("设置")

                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("退出")
            }

            TextField("输入一句话...", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            HStack {
                Button("解释") {
                    NSLog("[LexiBar] 解释 button clicked")
                    viewModel.translate()
                }
                .disabled(viewModel.isLoading)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.result)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("result")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: viewModel.result) { _ in
                    withAnimation {
                        proxy.scrollTo("result", anchor: .bottom)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}
