import AppKit
import SwiftUI
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private let controller = DictationController()
    private var stateMenuItem: NSMenuItem!
    private var accessibilityMenuItem: NSMenuItem!

    /// Applies the Dock-icon preference. `.regular` puts the app in the Dock and
    /// the app switcher; `.accessory` keeps it menu-bar only.
    static func applyActivationPolicy() {
        NSApp.setActivationPolicy(Preferences.shared.showDockIcon ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
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

    // MARK: - Menu delegate

    /// A permissão de acessibilidade pode ser revogada a qualquer momento, e o
    /// macOS a invalida sozinho quando a assinatura do app muda. Reavalia toda vez
    /// que o menu abre, em vez de confiar no estado do lançamento.
    func menuWillOpen(_ menu: NSMenu) {
        let trusted = AXIsProcessTrusted()
        accessibilityMenuItem.isHidden = trusted
        if !trusted {
            accessibilityMenuItem.title = "⚠️ Acessibilidade desativada — o atalho não funciona"
        }
    }

    // MARK: - Main menu

    /// With a Dock icon the app also gets a real menu bar. Without these items it
    /// would show an empty one, and ⌘C/⌘V would stop working in the text fields.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = NSMenuItem(title: "Sobre o PerformaWhisper", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Configurações…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Sair do PerformaWhisper",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Editar")
        editMenu.addItem(NSMenuItem(title: "Desfazer", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Refazer", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Recortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Selecionar Tudo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "PerformaWhisper")
        }

        let menu = NSMenu()
        menu.delegate = self
        stateMenuItem = NSMenuItem(title: "Carregando modelo…", action: nil, keyEquivalent: "")
        stateMenuItem.isEnabled = false
        menu.addItem(stateMenuItem)

        // Sem acessibilidade o atalho global não funciona. Clicar abre os Ajustes.
        accessibilityMenuItem = NSMenuItem(title: "",
                                           action: #selector(openAccessibilitySettings),
                                           keyEquivalent: "")
        accessibilityMenuItem.target = self
        accessibilityMenuItem.isHidden = true
        menu.addItem(accessibilityMenuItem)
        menu.addItem(.separator())

        let hint = NSMenuItem(title: "Segure \(Preferences.shared.holdKey.label.components(separatedBy: " (").first ?? "") para ditar",
                              action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "Sobre o PerformaWhisper", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let settingsItem = NSMenuItem(title: "Configurações…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        // Quit keeps a nil target on purpose: with an explicit target the menu
        // validates against an object that does not respond to terminate(_:) and
        // disables the item. Leaving it nil sends it up the responder chain to NSApp.
        menu.addItem(NSMenuItem(title: "Sair do PerformaWhisper",
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
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "PerformaWhisper — Configurações"
            window.styleMask = [.titled, .closable]
            // Depois de trocar o styleMask a janela mantém o frame antigo e a área
            // de conteúdo encolhe, truncando o texto. Redimensiona pelo conteúdo.
            window.setContentSize(hosting.view.fittingSize)
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openAbout() {
        if aboutWindow == nil {
            let hosting = NSHostingController(rootView: AboutView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Sobre o PerformaWhisper"
            window.styleMask = [.titled, .closable]
            window.setContentSize(hosting.view.fittingSize)
            window.isReleasedWhenClosed = false
            window.center()
            aboutWindow = window
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
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
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "PerformaWhisper"
        window.styleMask = [.titled, .closable]
        window.setContentSize(hosting.view.fittingSize)
        window.isReleasedWhenClosed = false
        onboardingWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
