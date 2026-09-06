import AppKit
import WhisperKit

// CLI test mode: transcribe a wav file end to end without launching the UI.
// Usage: PerformaWhisper --test-transcribe /path/audio.wav
if let idx = CommandLine.arguments.firstIndex(of: "--test-transcribe"),
   CommandLine.arguments.count > idx + 1 {
    let path = CommandLine.arguments[idx + 1]
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            print("Carregando modelo \(Preferences.shared.modelName)…")
            let config = WhisperKitConfig(model: Preferences.shared.modelName,
                                          verbose: false, prewarm: true, load: true, download: true)
            let kit = try await WhisperKit(config)
            print("Transcrevendo \(path)…")
            let results = try await kit.transcribe(audioPath: path,
                                                   decodeOptions: DecodingOptions(task: .transcribe))
            let raw = Transcriber.cleanWhisperArtifacts(results.map(\.text).joined(separator: " "))
            print("BRUTO: \(raw)")
            print("LIMPO (regras): \(AIFormatter.ruleBasedCleanup(raw))")
        } catch {
            print("ERRO: \(error)")
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    AppDelegate.applyActivationPolicy()
    app.run()
}
