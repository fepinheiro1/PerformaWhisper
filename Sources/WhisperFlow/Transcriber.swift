import Foundation
import WhisperKit

/// Wraps WhisperKit: downloads/loads the model once and transcribes sample buffers.
final class Transcriber {
    enum State: Equatable {
        case idle
        case downloading(Double)   // 0...1
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((State) -> Void)?

    private var whisperKit: WhisperKit?
    private var loadTask: Task<Void, Never>?

    var isReady: Bool { whisperKit != nil }

    /// Loads (downloading if needed) the model in `Preferences.shared.modelName`.
    func loadModel() {
        guard loadTask == nil else { return }
        let model = Preferences.shared.modelName
        state = .downloading(0)
        loadTask = Task { [weak self] in
            do {
                let config = WhisperKitConfig(
                    model: model,
                    verbose: false,
                    prewarm: true,
                    load: true,
                    download: true
                )
                let kit = try await WhisperKit(config)
                self?.whisperKit = kit
                self?.state = .ready
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
            self?.loadTask = nil
        }
    }

    /// Unloads the current model and loads a new one (after a settings change).
    func reloadModel() {
        loadTask?.cancel()
        loadTask = nil
        whisperKit = nil
        loadModel()
    }

    /// Transcribes 16 kHz mono samples. Returns the raw transcript.
    func transcribe(samples: [Float]) async throws -> String {
        guard let kit = whisperKit else {
            throw NSError(domain: "WhisperFlow", code: 2,
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
