import AppKit
import SwiftUI
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let controller = DictationController()
    private var stateMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        controller.onTranscriberState = { [weak self] state in
            self?.updateStateMenuItem(state)
        }

        if Preferences.shared.onboardingDone && AXIsProcessTrusted() {
            controller.start()
        } else {
            showOnboarding()
        }
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "WhisperFlow")
        }

        let menu = NSMenu()
        stateMenuItem = NSMenuItem(title: "Carregando modelo…", action: nil, keyEquivalent: "")
        stateMenuItem.isEnabled = false
        menu.addItem(stateMenuItem)
        menu.addItem(.separator())

        let hint = NSMenuItem(title: "Segure \(Preferences.shared.holdKey.label.components(separatedBy: " (").first ?? "") para ditar",
                              action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Configurações…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        // Quit keeps a nil target on purpose: with an explicit target the menu
        // validates against an object that does not respond to terminate(_:) and
        // disables the item. Leaving it nil sends it up the responder chain to NSApp.
        menu.addItem(NSMenuItem(title: "Sair do WhisperFlow",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func updateStateMenuItem(_ state: Transcriber.State) {
        switch state {
        case .idle: stateMenuItem.title = "Aguardando"
        case .downloading(let p):
            stateMenuItem.title = p > 0 ? "Baixando modelo… \(Int(p * 100))%" : "Preparando modelo…"
        case .loading: stateMenuItem.title = "Carregando modelo…"
        case .ready: stateMenuItem.title = "Pronto para ditar ✓"
        case .failed(let msg): stateMenuItem.title = "Erro: \(msg)"
        }
    }

    // MARK: - Windows

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(onModelChanged: { [weak self] in
                Task { @MainActor in self?.controller.reloadModel() }
            })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "WhisperFlow — Configurações"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOnboarding() {
        let view = OnboardingView(onDone: { [weak self] in
            Task { @MainActor in
                Preferences.shared.onboardingDone = true
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                self?.controller.start()
            }
        })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "WhisperFlow"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        onboardingWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
