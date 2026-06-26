import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleLexiBar = Self("toggleLexiBar", default: .init(.l, modifiers: [.control, .option]))
}

enum GlobalShortcut {
    @MainActor
    static func setup() {
        KeyboardShortcuts.onKeyUp(for: .toggleLexiBar) {
            FloatingPanelManager.shared.showWithGrabbedText()
        }
    }
}
