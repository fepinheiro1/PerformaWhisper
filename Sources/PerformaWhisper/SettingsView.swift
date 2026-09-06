import SwiftUI

struct SettingsView: View {
    var onModelChanged: () -> Void

    var body: some View {
        TabView {
            GeneralTab(onModelChanged: onModelChanged)
                .tabItem { Label("Geral", systemImage: "gearshape") }
            AITab()
                .tabItem { Label("IA", systemImage: "sparkles") }
            DictionaryTab()
                .tabItem { Label("Dicionário", systemImage: "character.book.closed") }
            SnippetsTab()
                .tabItem { Label("Snippets", systemImage: "text.badge.plus") }
            HistoryTab()
                .tabItem { Label("Histórico", systemImage: "clock") }
        }
        .frame(width: 560, height: 420)
    }
}

// MARK: - Geral

private struct GeneralTab: View {
    var onModelChanged: () -> Void
    @State private var holdKey = Preferences.shared.holdKey
    @State private var commandKey = Preferences.shared.commandModeKey
    @State private var model = Preferences.shared.modelName
    @State private var language = Preferences.shared.language
    @State private var playSounds = Preferences.shared.playSounds
    @State private var saveHistory = Preferences.shared.saveHistory
    @State private var showDockIcon = Preferences.shared.showDockIcon

    private let models: [(String, String)] = [
        ("tiny", "Tiny — mais rápido, menos preciso (~75 MB)"),
        ("base", "Base — rápido (~140 MB)"),
        ("small", "Small — equilíbrio recomendado (~460 MB)"),
        ("medium", "Medium — mais preciso, mais lento (~1,5 GB)"),
        ("large-v3_turbo", "Large v3 Turbo — máxima precisão (~1,6 GB)")
    ]

    private let languages: [(String, String)] = [
        ("auto", "Detectar automaticamente"),
        ("pt", "Português"), ("en", "Inglês"), ("es", "Espanhol"),
        ("fr", "Francês"), ("de", "Alemão"), ("it", "Italiano"), ("ja", "Japonês")
    ]

    var body: some View {
        Form {
            // Each picker hides the key the other one uses: the same key on both
            // modes silently disables Command Mode.
            Picker("Tecla de ditado:", selection: $holdKey) {
                ForEach(HoldKey.allCases.filter { $0 != commandKey }) { Text($0.label).tag($0) }
            }
            .onChange(of: holdKey) { v in Preferences.shared.holdKey = v }

            Picker("Tecla do Command Mode:", selection: $commandKey) {
                ForEach(HoldKey.allCases.filter { $0 != holdKey }) { Text($0.label).tag($0) }
            }
            .onChange(of: commandKey) { v in Preferences.shared.commandModeKey = v }

            Text("Segure a tecla, fale, e solte para inserir o texto. Esc cancela.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Picker("Modelo de voz:", selection: $model) {
                ForEach(models, id: \.0) { Text($0.1).tag($0.0) }
            }
            .onChange(of: model) { v in
                Preferences.shared.modelName = v
                onModelChanged()
            }

            Picker("Idioma:", selection: $language) {
                ForEach(languages, id: \.0) { Text($0.1).tag($0.0) }
            }
            .onChange(of: language) { v in Preferences.shared.language = v }

            Toggle("Sons de início/fim de ditado", isOn: $playSounds)
                .onChange(of: playSounds) { v in Preferences.shared.playSounds = v }

            Toggle("Salvar histórico de ditados", isOn: $saveHistory)
                .onChange(of: saveHistory) { v in Preferences.shared.saveHistory = v }

            Toggle("Mostrar ícone no Dock", isOn: $showDockIcon)
                .onChange(of: showDockIcon) { v in
                    Preferences.shared.showDockIcon = v
                    AppDelegate.applyActivationPolicy()
                }
                .help("Com o ícone no Dock o app também aparece no alternador de janelas (⌘Tab). Sem ele, fica só na barra de menus.")

            Text("O histórico fica em texto puro no seu Mac (Application Support). Desligue se for ditar informação sensível.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

// MARK: - IA

private struct AITab: View {
    @State private var key = Preferences.shared.openAIKey
    @State private var enabled = Preferences.shared.aiCleanupEnabled
    @State private var tone = Preferences.shared.tone
    @State private var model = Preferences.shared.openAIModel

    var body: some View {
        Form {
            Toggle("Limpeza com IA (remover vícios de fala, pontuação, tom)", isOn: $enabled)
                .onChange(of: enabled) { v in Preferences.shared.aiCleanupEnabled = v }

            SecureField("Chave da API OpenAI (sk-…):", text: $key)
                .onChange(of: key) { v in Preferences.shared.openAIKey = v }

            Text("Sem chave, o app usa uma limpeza básica por regras e o Command Mode fica indisponível. A transcrição de voz é sempre 100% local e offline.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Modelo de texto:", text: $model)
                    .onChange(of: model) { v in Preferences.shared.openAIModel = v }
                Button("Padrão") {
                    model = Preferences.defaultOpenAIModel
                    Preferences.shared.openAIModel = model
                }
                .disabled(model == Preferences.defaultOpenAIModel)
            }
            .help("Modelo da OpenAI usado para limpar o texto e para o Command Mode. Não afeta a transcrição, que é local.")

            Text("Se a OpenAI aposentar este modelo, cole aqui o id de um atual (a lista fica em platform.openai.com/docs/models). Isso não afeta a transcrição de voz.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Picker("Tom do texto:", selection: $tone) {
                ForEach(ToneStyle.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: tone) { v in Preferences.shared.tone = v }

            Text("No modo automático, o tom se adapta ao app ativo: casual no Slack/WhatsApp, formal no Mail, literal em editores de código.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

// MARK: - Dicionário

private struct DictionaryTab: View {
    @ObservedObject private var store = DataStore.shared
    @State private var newWord = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nomes, jargões e palavras incomuns que o reconhecimento costuma errar.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Nova palavra ou nome", text: $newWord)
                    .onSubmit(add)
                Button("Adicionar", action: add)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                ForEach(store.dictionaryWords, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button {
                            store.dictionaryWords.removeAll { $0 == word }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(24)
    }

    private func add() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !store.dictionaryWords.contains(word) else { return }
        store.dictionaryWords.append(word)
        newWord = ""
    }
}

// MARK: - Snippets

private struct SnippetsTab: View {
    @ObservedObject private var store = DataStore.shared
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diga a frase-gatilho durante o ditado e ela vira o texto expandido.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top) {
                VStack {
                    TextField("Frase falada (ex.: assinatura de email)", text: $trigger)
                    TextField("Texto expandido", text: $expansion, axis: .vertical)
                        .lineLimit(2...4)
                }
                Button("Adicionar") {
                    let t = trigger.trimmingCharacters(in: .whitespaces)
                    let e = expansion.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty, !e.isEmpty else { return }
                    store.snippets.append(Snippet(trigger: t, expansion: e))
                    trigger = ""; expansion = ""
                }
            }

            List {
                ForEach(store.snippets) { snippet in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("“\(snippet.trigger)”").fontWeight(.medium)
                            Text(snippet.expansion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button {
                            store.snippets.removeAll { $0.id == snippet.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(24)
    }
}

// MARK: - Histórico

private struct HistoryTab: View {
    @ObservedObject private var store = DataStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(store.history.count) ditados")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Limpar histórico") { store.history.removeAll() }
                    .disabled(store.history.isEmpty)
            }

            List {
                ForEach(store.history) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(entry.appName).fontWeight(.medium)
                            Spacer()
                            if entry.wordsPerMinute > 0 {
                                Text("\(entry.wordsPerMinute) wpm")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(entry.date, style: .relative)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(entry.finalText)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 3)
                    .contextMenu {
                        Button("Copiar") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.finalText, forType: .string)
                        }
                    }
                }
            }
        }
        .padding(24)
    }
}
