import AppKit

/// Orchestrates the whole flow:
/// hotkey down → record → hotkey up → transcribe → AI cleanup → insert at cursor.
@MainActor
final class DictationController {
    enum Mode { case dictation, command }

    enum PillState: Equatable {
        case hidden
        case downloadingModel(Double)
        case loadingModel
        case modelReady
        case recording(isCommand: Bool)
        case processing
        case success
        case error(String)
    }

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let hotkeys = HotkeyManager()
    private let pill = FloatingPillController()

    private var mode: Mode = .dictation
    private var isActive = false
    private var recordingStart: Date?
    private var selectionTask: Task<String?, Never>?

    var transcriberState: Transcriber.State { transcriberStateCache }
    private var transcriberStateCache: Transcriber.State = .idle
    var onTranscriberState: ((Transcriber.State) -> Void)?

    func start() {
        transcriber.onStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.transcriberStateCache = state
                self.onTranscriberState?(state)
                switch state {
                case .downloading(let progress):
                    self.pill.show(.downloadingModel(progress))
                case .loading:
                    self.pill.show(.loadingModel)
                case .ready:
                    self.pill.show(.modelReady)
                    self.pill.hideAfter(1.6)
                case .failed(let msg):
                    self.pill.show(.error("Falha no modelo: \(msg)"))
                    self.pill.hideAfter(4)
                case .idle:
                    break
                }
            }
        }
        transcriber.loadModel()

        recorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.pill.updateLevel(level) }
        }

        hotkeys.isSessionActive = { [weak self] in self?.isActive ?? false }
        hotkeys.onDictationDown = { [weak self] in self?.beginSession(mode: .dictation) }
        hotkeys.onDictationUp = { [weak self] in self?.endSession() }
        hotkeys.onCommandDown = { [weak self] in self?.beginSession(mode: .command) }
        hotkeys.onCommandUp = { [weak self] in self?.endSession() }
        hotkeys.onCancel = { [weak self] in self?.cancelSession() }
        hotkeys.start()
    }

    func reloadModel() {
        transcriber.reloadModel()
    }

    // MARK: - Session lifecycle

    private func beginSession(mode: Mode) {
        guard !isActive else { return }
        guard transcriber.isReady else {
            pill.show(.error("Modelo ainda carregando…"))
            pill.hideAfter(2)
            return
        }
        self.mode = mode
        isActive = true
        recordingStart = Date()
        selectionTask?.cancel()
        selectionTask = nil

        do {
            try recorder.start()
            if Preferences.shared.playSounds { NSSound(named: "Pop")?.play() }
            pill.show(.recording(isCommand: mode == .command))

            if mode == .command {
                // Grab the selection while the user speaks: copying waits on the
                // target app, and doing that inline would freeze the UI.
                selectionTask = Task { @MainActor in await TextInserter.copySelection() }
            }
        } catch {
            isActive = false
            pill.show(.error(error.localizedDescription))
            pill.hideAfter(3)
        }
    }

    private func endSession() {
        guard isActive else { return }
        isActive = false
        let samples = recorder.stop()
        let duration = recordingStart.map { Date().timeIntervalSince($0) } ?? 0

        let pendingSelection = selectionTask
        selectionTask = nil

        // Ignore accidental taps (< 0.3 s of audio).
        guard samples.count > Int(AudioRecorder.targetSampleRate * 0.3) else {
            pendingSelection?.cancel()
            pill.hide()
            return
        }

        pill.show(.processing)
        let mode = self.mode
        let context = ActiveAppContext.current()

        Task {
            do {
                let raw = try await transcriber.transcribe(samples: samples)
                guard !raw.isEmpty else {
                    pill.show(.error("Não entendi — tente de novo"))
                    pill.hideAfter(2)
                    return
                }

                let final: String
                switch mode {
                case .dictation:
                    final = await AIFormatter.cleanup(raw, context: context)
                case .command:
                    let selected = await pendingSelection?.value
                    guard let selected, !selected.isEmpty else {
                        pill.show(.error("Selecione um texto antes de usar o Command Mode"))
                        pill.hideAfter(3)
                        return
                    }
                    final = try await AIFormatter.applyCommand(instruction: raw, to: selected)
                }

                guard !final.isEmpty else {
                    pill.show(.error("Nada para inserir"))
                    pill.hideAfter(2)
                    return
                }

                TextInserter.insert(final)
                if Preferences.shared.playSounds { NSSound(named: "Glass")?.play() }
                pill.show(.success)
                pill.hideAfter(1.0)

                if Preferences.shared.saveHistory {
                    DataStore.shared.addHistory(HistoryEntry(
                        date: Date(),
                        appName: context.appName,
                        rawText: raw,
                        finalText: final,
                        durationSeconds: duration
                    ))
                }
            } catch {
                pill.show(.error(error.localizedDescription))
                pill.hideAfter(4)
            }
        }
    }

    private func cancelSession() {
        guard isActive else { return }
        isActive = false
        selectionTask?.cancel()
        selectionTask = nil
        recorder.cancel()
        if Preferences.shared.playSounds { NSSound(named: "Bottle")?.play() }
        pill.hide()
    }
}
