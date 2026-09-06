import AppKit
import Carbon.HIToolbox

/// Inserts text at the cursor of the frontmost app by pasting,
/// preserving whatever was on the clipboard.
@MainActor
enum TextInserter {

    /// How long the dictated text stays on the clipboard before the previous
    /// contents are put back. The paste is asynchronous in the target app and
    /// there is no completion signal, so this is a margin, not a guarantee —
    /// Electron apps (Slack, Notion, VS Code) are the slow case.
    private static let restoreDelay: Duration = .milliseconds(1200)

    private static var restoreTask: Task<Void, Never>?
    private static var savedItems: [NSPasteboardItem] = []

    static func insert(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Only snapshot when nothing is pending: during a burst of dictations the
        // clipboard holds the *previous* dictation, which must not be mistaken
        // for the user's own content.
        if restoreTask == nil { savedItems = snapshot(of: pasteboard) }
        restoreTask?.cancel()

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        sendCmdV()

        let items = savedItems
        restoreTask = Task { @MainActor in
            try? await Task.sleep(for: restoreDelay)
            guard !Task.isCancelled else { return }
            restore(items, to: pasteboard)
            restoreTask = nil
        }
    }

    /// Copies the current selection via Cmd+C and returns it (nil if nothing selected).
    /// Async so the caller never blocks the main thread waiting for the target app.
    static func copySelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        let before = pasteboard.changeCount

        sendKeystroke(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        let deadline = ContinuousClock.now + .milliseconds(500)
        while pasteboard.changeCount == before, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(30))
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
        // Always clear: when the clipboard started empty there is nothing to put
        // back, and leaving the dictated text sitting there leaks it.
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}
