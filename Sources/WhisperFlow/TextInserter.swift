import AppKit
import Carbon.HIToolbox

/// Inserts text at the cursor of the frontmost app by pasting,
/// preserving whatever was on the clipboard.
enum TextInserter {

    static func insert(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        sendCmdV()

        // Restore the clipboard after the paste lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            restore(saved, to: pasteboard)
        }
    }

    /// Copies the current selection via Cmd+C and returns it (nil if nothing selected).
    static func copySelection() -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        let before = pasteboard.changeCount

        sendKeystroke(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        // Wait briefly for the app to publish the copy.
        let deadline = Date().addingTimeInterval(0.5)
        while pasteboard.changeCount == before && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        let text = pasteboard.changeCount == before ? nil : pasteboard.string(forType: .string)
        restore(saved, to: pasteboard)
        return text
    }

    private static func sendCmdV() {
        sendKeystroke(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    private static func sendKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }
}
