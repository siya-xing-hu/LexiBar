import AppKit
import ApplicationServices

enum AccessibilityTextGrabber {
    static func grabSelectedText(completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let text = Self.grabSelectedTextSync()
            DispatchQueue.main.async {
                completion(text)
            }
        }
    }

    private static func grabSelectedTextSync() -> String? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            NSLog("[LexiBar] No frontmost application")
            return nil
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)

        var focusedElement: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusedResult == .success, let element = focusedElement else {
            NSLog("[LexiBar] Could not get focused element: \(focusedResult.rawValue)")
            return nil
        }

        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )

        guard textResult == .success, let text = selectedText as? String, !text.isEmpty else {
            NSLog("[LexiBar] Could not get selected text: \(textResult.rawValue)")
            return nil
        }

        return text
    }

    static func isTrusted() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
}
