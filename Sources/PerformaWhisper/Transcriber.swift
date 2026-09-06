import Foundation
import WhisperKit

/// Wraps WhisperKit: downloads/loads the model once and transcribes sample buffers.
///
/// The model is loaded on a background task while `isReady` is read from the
/// main actor, so the mutable state is guarded by a lock.
final class Transcriber {
    enum State: Equatable {
        case idle
        case downloading(Double)   // 0...1
        case loading
        case ready
        case failed(String)
    }

    var onStateChange: ((State) -> Void)?

    private let lock = NSLock()
    private var _state: State = .idle
    private var _whisperKit: WhisperKit?
    private var _loadTask: Task<Void, Never>?
    private var _isLoading = false
    private var _lastProgressPercent = -1

    /// Synchronous so async callers never hold the lock across a suspension.
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var state: State { withLock { _state } }

    var isReady: Bool { withLock { _whisperKit != nil } }

    private func setState(_ new: State) {
        withLock { _state = new }
        // Notify outside the lock: the callback hops to the main actor and must
        // never re-enter while the lock is held.
        onStateChange?(new)
    }

    /// Loads (downloading if needed) the model in `Preferences.shared.modelName`.
    func loadModel() {
        // Claim the slot under the lock so two callers cannot both start a load.
        let shouldStart = withLock { () -> Bool in
            guard !_isLoading else { return false }
            _isLoading = true
            return true
        }
        guard shouldStart else { return }

        let model = Preferences.shared.modelName
        withLock { _lastProgressPercent = -1 }
        setState(.downloading(0))

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let config = await self.prepareConfig(for: model)
                let kit = try await WhisperKit(config)
                self.withLock { self._whisperKit = kit }
                self.setState(.ready)
            } catch {
                self.setState(.failed(error.localizedDescription))
            }
            self.withLock { self._isLoading = false }
        }

        withLock { _loadTask = task }
    }

    /// Downloads the model first so real progress can be reported, then points
    /// the config at the folder on disk. Falls back to letting WhisperKit resolve
    /// and fetch the model itself if the explicit download path fails.
    private func prepareConfig(for model: String) async -> WhisperKitConfig {
        do {
            let folder = try await WhisperKit.download(variant: model) { [weak self] progress in
                self?.reportDownload(progress.fractionCompleted)
            }
            setState(.loading)
            return WhisperKitConfig(model: model,
                                    modelFolder: folder.path,
                                    verbose: false,
                                    prewarm: true,
                                    load: true,
                                    download: false)
        } catch {
            NSLog("PerformaWhisper: download explícito falhou (\(error.localizedDescription)); deixando o WhisperKit resolver")
            setState(.loading)
            return WhisperKitConfig(model: model,
                                    verbose: false,
                                    prewarm: true,
                                    load: true,
                                    download: true)
        }
    }

    /// Throttled to whole percent so a chatty progress callback does not flood
    /// the main actor with UI updates.
    private func reportDownload(_ fraction: Double) {
        let percent = Int(fraction * 100)
        let shouldReport = withLock { () -> Bool in
            guard percent != _lastProgressPercent else { return false }
            _lastProgressPercent = percent
            return true
        }
        guard shouldReport else { return }
        setState(.downloading(fraction))
    }

    /// Unloads the current model and loads a new one (after a settings change).
    func reloadModel() {
        let previous = withLock { () -> Task<Void, Never>? in
            let task = _loadTask
            _loadTask = nil
            _whisperKit = nil
            _isLoading = false
            return task
        }
        previous?.cancel()
        loadModel()
    }

    /// Transcribes 16 kHz mono samples. Returns the raw transcript.
    func transcribe(samples: [Float]) async throws -> String {
        guard let kit = withLock({ _whisperKit }) else {
            throw NSError(domain: "PerformaWhisper", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Modelo ainda não carregado"])
        }
        // Whisper needs at least ~1s of audio to behave; pad short clips with silence.
        var audio = samples
        let minSamples = Int(AudioRecorder.targetSampleRate * 1.2)
        if audio.count < minSamples {
            audio.append(contentsOf: [Float](repeating: 0, count: minSamples - audio.count))
        }

        let lang = Preferences.shared.language
        let options = DecodingOptions(
            task: .transcribe,
            language: lang == "auto" ? nil : lang,
            temperature: 0,
            usePrefillPrompt: lang != "auto",
            detectLanguage: lang == "auto",
            chunkingStrategy: .vad
        )
        let results = try await kit.transcribe(audioArray: audio, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
        return Self.cleanWhisperArtifacts(text)
    }

    /// Removes Whisper artifacts like special tokens and hallucinated tags.
    static func cleanWhisperArtifacts(_ text: String) -> String {
        var t = text
        // Remove <|...|> tokens and [MUSIC]/(applause)-style annotations.
        t = t.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[[^\]]{0,40}\]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
