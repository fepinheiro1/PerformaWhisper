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
    private var setupMenuItem: NSMenuItem!

    /// Applies the Dock-icon preference. `.regular` puts the app in the Dock and
    /// the app switcher; `.accessory` keeps it menu-bar only.
    static func applyActivationPolicy() {
        NSApp.setActivationPolicy(Preferences.shared.showDockIcon ? .regular : .accessory)
    }

    /// Em x86_64 o app usa o whisper.cpp em vez do WhisperKit, porque este último
    /// trava no CoreML em hardware Intel. O caminho novo foi verificado sob Rosetta,
    /// mas ainda não em um Mac Intel de verdade — daí o aviso, mostrado uma vez só.
    private func warnIfUnsupportedArchitecture() {
        #if arch(x86_64)
        guard !Preferences.shared.intelNoticeShown else { return }
        Preferences.shared.intelNoticeShown = true

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Suporte a Macs Intel em teste"
        alert.informativeText = """
        Neste Mac o PerformaWhisper usa um motor de transcrição diferente (whisper.cpp), \
        porque o motor usado nos Macs com chip Apple trava no hardware Intel.

        O caminho funciona, mas ainda não foi validado num Mac Intel real. Se algo falhar, \
        o relato ajuda a corrigir.

        A transcrição roda na CPU e é mais lenta: em Configurações → Geral, prefira o \
        modelo Base ou Tiny.
        """
        alert.addButton(withTitle: "Entendi")
        alert.addButton(withTitle: "Relatar um problema")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn,
           let url = URL(string: "https://github.com/fepinheiro1/PerformaWhisper/issues") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        warnIfUnsupportedArchitecture()
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
        let setupDone = Preferences.shared.onboardingDone
        setupMenuItem.isHidden = setupDone

        // Só faz sentido cobrar acessibilidade depois que a configuração terminou;
        // antes disso o aviso de configuração já cobre o caso.
        let trusted = AXIsProcessTrusted()
        accessibilityMenuItem.isHidden = trusted || !setupDone
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

        // Fechar a janela de boas-vindas sem concluir deixava o app vivo e inerte,
        // sem atalho e sem jeito de voltar. Este item é a saída.
        setupMenuItem = NSMenuItem(title: "⚠️ Configuração não concluída — abrir",
                                   action: #selector(resumeOnboarding),
                                   keyEquivalent: "")
        setupMenuItem.target = self
        setupMenuItem.isHidden = true
        menu.addItem(setupMenuItem)
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

    @objc private func resumeOnboarding() {
        showOnboarding()
    }

    private func showOnboarding() {
        // Reabrir traria uma segunda janela e vazaria a primeira.
        if let existing = onboardingWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
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
