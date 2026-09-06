import AppKit
import Carbon.HIToolbox

/// Global hold-to-talk hotkeys via a listen-only CGEventTap.
/// Requires Accessibility permission.
final class HotkeyManager {
    var onDictationDown: (() -> Void)?
    var onDictationUp: (() -> Void)?
    var onCommandDown: (() -> Void)?
    var onCommandUp: (() -> Void)?
    var onCancel: (() -> Void)?

    /// Set while a session is active so Esc can cancel it.
    var isSessionActive: (() -> Bool) = { false }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var dictationHeld = false
    private var commandHeld = false

    static func keyCode(for key: HoldKey) -> CGKeyCode {
        switch key {
        case .rightOption: return CGKeyCode(kVK_RightOption)
        case .rightCommand: return CGKeyCode(kVK_RightCommand)
        case .fn: return CGKeyCode(kVK_Function)
        case .controlOption: return 0 // combo: evaluated by flags, not key code
        }
    }

    static func flagMask(for key: HoldKey) -> CGEventFlags {
        switch key {
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .fn: return .maskSecondaryFn
        case .controlOption: return [.maskControl, .maskAlternate]
        }
    }

    /// Whether `key` is currently pressed according to this flagsChanged event.
    /// Returns nil when the event is unrelated to `key` (single keys react only
    /// to their own key code; combos are re-evaluated on every flags change).
    /// Modifiers we compare against, so caps lock and device-specific bits do not
    /// count as part of a combo.
    private static let trackedModifiers: CGEventFlags =
        [.maskControl, .maskAlternate, .maskCommand, .maskShift, .maskSecondaryFn]

    private static func pressedState(for key: HoldKey, event: CGEvent) -> Bool? {
        if key.isCombo {
            // Exact match: Control+Option must not fire when the user is pressing
            // Control+Option+Command or any other system shortcut built on top of it.
            return event.flags.intersection(trackedModifiers) == flagMask(for: key)
        }
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == Self.keyCode(for: key) else { return nil }
        return event.flags.contains(flagMask(for: key))
    }

    func start() {
        guard tap == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            manager.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        )
        guard let tap else {
            NSLog("WhisperFlow: falha ao criar event tap (sem permissão de Acessibilidade?)")
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // macOS disables taps that time out; re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        if type == .keyDown {
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == CGKeyCode(kVK_Escape) && isSessionActive() {
                DispatchQueue.main.async { self.onCancel?() }
            }
            return
        }

        guard type == .flagsChanged else { return }

        let dictKey = Preferences.shared.holdKey
        let cmdKey = Preferences.shared.commandModeKey

        if let pressed = Self.pressedState(for: dictKey, event: event), pressed != dictationHeld {
            dictationHeld = pressed
            DispatchQueue.main.async {
                pressed ? self.onDictationDown?() : self.onDictationUp?()
            }
        }
        if let pressed = Self.pressedState(for: cmdKey, event: event), pressed != commandHeld {
            commandHeld = pressed
            DispatchQueue.main.async {
                pressed ? self.onCommandDown?() : self.onCommandUp?()
            }
        }
    }
}
