import AppKit

/// Detects the frontmost app to adapt tone — the privacy-friendly version of
/// Wispr Flow's context awareness (no screenshots, only the app name).
struct ActiveAppContext {
    let appName: String
    let bundleID: String

    static func current() -> ActiveAppContext {
        let app = NSWorkspace.shared.frontmostApplication
        return ActiveAppContext(
            appName: app?.localizedName ?? "desconhecido",
            bundleID: app?.bundleIdentifier ?? ""
        )
    }

    /// Suggested tone for the app when tone preference is .auto.
    var suggestedTone: ToneStyle {
        let id = bundleID.lowercased()
        let casual = ["slack", "whatsapp", "telegram", "discord", "messages", "imessage", "signal"]
        let formal = ["mail", "outlook", "gmail", "word", "pages", "docs"]
        let code = ["vscode", "xcode", "cursor", "jetbrains", "terminal", "iterm", "sublime", "zed"]

        if casual.contains(where: { id.contains($0) }) { return .casual }
        if formal.contains(where: { id.contains($0) }) { return .formal }
        if code.contains(where: { id.contains($0) }) { return .neutral }
        return .neutral
    }

    var isCodeEditor: Bool {
        let id = bundleID.lowercased()
        return ["vscode", "xcode", "cursor", "jetbrains", "iterm", "terminal", "sublime", "zed"]
            .contains(where: { id.contains($0) })
    }
}
