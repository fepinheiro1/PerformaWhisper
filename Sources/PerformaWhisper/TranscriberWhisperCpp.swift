#if !arch(arm64)
import Foundation
import SwiftWhisper

/// Motor de transcrição para Macs Intel.
///
/// O WhisperKit não serve aqui: em x86_64 ele estoura um buffer float16 e, passado
/// isso, a inferência do MelSpectrogram bate numa divisão por zero dentro do CoreML
/// da Apple. O whisper.cpp roda em CPU (GGML) e não toca no Espresso.
///
/// A API pública é idêntica à da implementação WhisperKit, para o resto do app não
/// saber qual motor está ativo.
final class Transcriber {
    typealias State = TranscriberState
    static let engineName = "whisper.cpp (GGML)"

    var onStateChange: ((State) -> Void)?

    private let lock = NSLock()
    private var _state: State = .idle
    private var _whisper: Whisper?
    private var _isLoading = false
    private var _lastProgressPercent = -1

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var state: State { withLock { _state } }
    var isReady: Bool { withLock { _whisper != nil } }

    private func setState(_ new: State) {
        withLock { _state = new }
        onStateChange?(new)
    }

    // MARK: - Carga do modelo

    func loadModel() {
        let shouldStart = withLock { () -> Bool in
            guard !_isLoading else { return false }
            _isLoading = true
            return true
        }
        guard shouldStart else { return }

        let variant = VoiceModel.resolved(Preferences.shared.modelName)
        withLock { _lastProgressPercent = -1 }
        setState(GGMLModelStore.isDownloaded(variant) ? .loading : .downloading(0))

        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await GGMLModelStore.ensureAvailable(variant) { [weak self] fraction in
                    self?.reportDownload(fraction)
                }
                self.setState(.loading)
                // O init do Whisper carrega o modelo de forma síncrona; fora da main
                // thread porque um `small` leva alguns segundos num Mac Intel.
                let whisper = Whisper(fromFileURL: url)
                whisper.params.language = Self.whisperLanguage(Preferences.shared.language)
                self.withLock { self._whisper = whisper }
                self.setState(.ready)
            } catch {
                self.setState(.failed(error.localizedDescription))
            }
            self.withLock { self._isLoading = false }
        }
    }

    func reloadModel() {
        withLock {
            _whisper = nil
            _isLoading = false
        }
        loadModel()
    }

    /// Limitado a percentuais inteiros para não inundar a main actor com updates.
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

    // MARK: - Transcrição

    func transcribe(samples: [Float]) async throws -> String {
        guard let whisper = withLock({ _whisper }) else {
            throw NSError(domain: "PerformaWhisper", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Modelo ainda não carregado"])
        }

        // O Whisper precisa de ~1s de áudio para se comportar; completa com silêncio.
        var audio = samples
        let minSamples = Int(AudioRecorder.targetSampleRate * 1.2)
        if audio.count < minSamples {
            audio.append(contentsOf: [Float](repeating: 0, count: minSamples - audio.count))
        }

        whisper.params.language = Self.whisperLanguage(Preferences.shared.language)
        let segments = try await whisper.transcribe(audioFrames: audio)
        let text = segments.map(\.text).joined(separator: " ")
        return WhisperText.cleanArtifacts(text)
    }

    static func cleanWhisperArtifacts(_ text: String) -> String {
        WhisperText.cleanArtifacts(text)
    }

    /// "auto" e códigos ISO das Preferências para o enum do SwiftWhisper.
    private static func whisperLanguage(_ code: String) -> WhisperLanguage {
        WhisperLanguage(rawValue: code) ?? .auto
    }
}
#endif
