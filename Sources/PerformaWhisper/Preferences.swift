import Foundation

enum HoldKey: String, CaseIterable, Identifiable, Codable {
    case rightOption
    case rightCommand
    case fn
    case controlOption

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rightOption: return "⌥ Option direita (segurar)"
        case .rightCommand: return "⌘ Command direita (segurar)"
        case .fn: return "🌐 Fn (segurar)"
        case .controlOption: return "⌃⌥ Control + Option (segurar)"
        }
    }

    /// Combo keys are evaluated by modifier flags instead of a single key code.
    var isCombo: Bool { self == .controlOption }
}

enum ToneStyle: String, CaseIterable, Identifiable, Codable {
    case auto
    case veryCasual
    case casual
    case neutral
    case formal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Automático (pelo app ativo)"
        case .veryCasual: return "Muito casual"
        case .casual: return "Casual"
        case .neutral: return "Neutro"
        case .formal: return "Formal"
        }
    }
}

final class Preferences {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    private init() {}

    var holdKey: HoldKey {
        get { HoldKey(rawValue: d.string(forKey: "holdKey") ?? "") ?? .controlOption }
        set { d.set(newValue.rawValue, forKey: "holdKey") }
    }

    var commandModeKey: HoldKey {
        get { HoldKey(rawValue: d.string(forKey: "commandModeKey") ?? "") ?? .rightCommand }
        set { d.set(newValue.rawValue, forKey: "commandModeKey") }
    }

    /// Whisper model variant (WhisperKit naming).
    var modelName: String {
        get { d.string(forKey: "modelName") ?? "small" }
        set { d.set(newValue, forKey: "modelName") }
    }

    /// "auto" or an ISO language code like "pt", "en".
    var language: String {
        get { d.string(forKey: "language") ?? "auto" }
        set { d.set(newValue, forKey: "language") }
    }

    // MARK: - OpenAI key (Keychain-backed)

    private static let openAIAccount = "openAIKey"
    private var cachedOpenAIKey: String?

    /// Stored in the Keychain. Values written by older builds lived in
    /// UserDefaults and are migrated on first read.
    var openAIKey: String {
        get {
            if let cachedOpenAIKey { return cachedOpenAIKey }

            if let legacy = d.string(forKey: Self.openAIAccount), !legacy.isEmpty {
                // Only drop the plaintext copy once the Keychain actually took it.
                if Keychain.write(legacy, account: Self.openAIAccount) {
                    d.removeObject(forKey: Self.openAIAccount)
                }
                cachedOpenAIKey = legacy
                return legacy
            }

            let value = Keychain.read(Self.openAIAccount) ?? ""
            cachedOpenAIKey = value
            return value
        }
        set {
            Keychain.write(newValue, account: Self.openAIAccount)
            cachedOpenAIKey = newValue
        }
    }

    /// Editable on purpose: OpenAI retires model ids, and a hardcoded one would
    /// silently take Command Mode down with it.
    static let defaultOpenAIModel = "gpt-4o-mini"

    var openAIModel: String {
        get {
            let stored = d.string(forKey: "openAIModel") ?? ""
            return stored.isEmpty ? Self.defaultOpenAIModel : stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            d.set(trimmed, forKey: "openAIModel")
        }
    }

    var aiCleanupEnabled: Bool {
        get { d.object(forKey: "aiCleanupEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "aiCleanupEnabled") }
    }

    var tone: ToneStyle {
        get { ToneStyle(rawValue: d.string(forKey: "tone") ?? "") ?? .auto }
        set { d.set(newValue.rawValue, forKey: "tone") }
    }

    var playSounds: Bool {
        get { d.object(forKey: "playSounds") as? Bool ?? true }
        set { d.set(newValue, forKey: "playSounds") }
    }

    /// Dictations are transcribed locally but the transcript is kept on disk in
    /// plain JSON, so it has to be possible to turn off.
    var saveHistory: Bool {
        get { d.object(forKey: "saveHistory") as? Bool ?? true }
        set { d.set(newValue, forKey: "saveHistory") }
    }

    var onboardingDone: Bool {
        get { d.bool(forKey: "onboardingDone") }
        set { d.set(newValue, forKey: "onboardingDone") }
    }
}
