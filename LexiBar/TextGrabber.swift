import AppKit

enum TextGrabber {
    static func grabSelectedText(completion: @escaping (String) -> Void) {
        let pasteboard = NSPasteboard.general
        let backup = pasteboard.string(forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .privateState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let text = pasteboard.string(forType: .string) ?? ""
                if let backup = backup {
                    pasteboard.clearContents()
                    pasteboard.setString(backup, forType: .string)
                }
                completion(text)
            }
        }
    }
}
