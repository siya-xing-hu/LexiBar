import SwiftUI
import AppKit

@MainActor
final class FloatingPanelManager {
    static let shared = FloatingPanelManager()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let viewModel = FloatingPanelViewModel()

    func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "📖"
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: [.leftMouseUp])
        statusItem = item

        let pop = NSPopover()
        pop.contentSize = NSSize(width: 380, height: 500)
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(rootView: FloatingPanelView(viewModel: self.viewModel))
        popover = pop
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func show() {
        guard let button = statusItem?.button, let popover = popover else { return }
        viewModel.page = .explain
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func showWithGrabbedText() {
        let pasteboard = NSPasteboard.general
        let text = (pasteboard.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.input = text
        viewModel.errorMessage = nil
        viewModel.page = .explain
        show()
        if !text.isEmpty {
            viewModel.translate()
        } else {
            viewModel.errorMessage = "剪贴板为空。请先选中文字按 Cmd+C 复制，再触发 LexiBar。"
        }
    }
}

@MainActor
final class FloatingPanelViewModel: ObservableObject {
    @Published var input = ""
    @Published var result = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var page: Page = .explain

    enum Page {
        case explain
        case settings
    }

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
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                tabButton("解释", page: .explain)
                tabButton("设置", page: .settings)
                Spacer()
                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("退出")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()

            if viewModel.page == .explain {
                ExplainPage(viewModel: viewModel)
            } else {
                SettingsView()
            }
        }
        .frame(width: 380, height: 500)
    }

    private func tabButton(_ title: String, page: FloatingPanelViewModel.Page) -> some View {
        Button(title) {
            viewModel.page = page
        }
        .buttonStyle(.plain)
        .font(viewModel.page == page ? .system(size: 13, weight: .semibold) : .system(size: 13))
        .foregroundColor(viewModel.page == page ? .accentColor : .secondary)
    }
}

struct ExplainPage: View {
    @StateObject var viewModel: FloatingPanelViewModel

    var body: some View {
        VStack(spacing: 10) {
            TextField("输入一句话...", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            HStack {
                Button("解释") {
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
                .onChange(of: viewModel.result) { _ in
                    withAnimation {
                        proxy.scrollTo("result", anchor: .bottom)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
