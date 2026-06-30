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
        case history
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
        let capturedInput = input
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
                    guard let self = self else { return }
                    self.isLoading = false
                    if !self.result.isEmpty {
                        HistoryStore.shared.add(HistoryRecord(
                            input: capturedInput,
                            result: self.result,
                            provider: settings.provider.rawValue,
                            model: settings.model
                        ))
                    }
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
                tabButton("历史", page: .history)
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

            switch viewModel.page {
            case .explain:
                ExplainPage(viewModel: viewModel)
            case .history:
                HistoryPage()
            case .settings:
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

struct HistoryPage: View {
    @ObservedObject private var store = HistoryStore.shared
    @State private var selectedID: HistoryRecord.ID?
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(store.records.count) 条记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(store.records.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()

            if store.records.isEmpty {
                Spacer()
                Text("暂无记录")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(selection: $selectedID) {
                    ForEach(store.records) { record in
                        HistoryRow(record: record)
                            .tag(record.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedID = record.id
                            }
                    }
                }
                .listStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog(
            "确定清空所有历史记录吗？此操作不可撤销。",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                store.clearAll()
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(item: Binding(
            get: { store.records.first { $0.id == selectedID } },
            set: { if $0 == nil { selectedID = nil } }
        )) { record in
            HistoryDetailSheet(record: record)
        }
    }
}

struct HistoryDetailSheet: View {
    let record: HistoryRecord
    @Environment(\.dismiss) private var dismiss

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("历史详情")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("时间")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(dateFormatter.string(from: record.timestamp))
                            .font(.system(size: 12))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("模型")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(record.provider) · \(record.model)")
                            .font(.system(size: 12))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("输入")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(record.input)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("结果")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(record.result)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 480, height: 520)
    }
}

struct HistoryRow: View {
    let record: HistoryRecord

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.input.prefix(60))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(dateFormatter.string(from: record.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(record.result.prefix(120))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}
