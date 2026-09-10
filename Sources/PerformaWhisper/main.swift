import AppKit

// Modo de teste por linha de comando: transcreve um arquivo de ponta a ponta sem
// abrir a interface. Usa o mesmo motor que o app usaria nesta arquitetura, então
// serve para verificar Apple Silicon e Intel com o mesmo comando.
// Uso: PerformaWhisper --test-transcribe /caminho/audio.wav
if let idx = CommandLine.arguments.firstIndex(of: "--test-transcribe"),
   CommandLine.arguments.count > idx + 1 {
    let path = CommandLine.arguments[idx + 1]

    /// O SwiftWhisper entrega os resultados por `DispatchQueue.main.async`, então
    /// a main thread não pode ficar bloqueada esperando: em vez de um semáforo,
    /// o runloop principal segue rodando até o trabalho terminar.
    final class Done: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set() { lock.lock(); value = true; lock.unlock() }
    }
    let done = Done()

    Task.detached {
        let transcriber = Transcriber()
        var lastShown = -1
        transcriber.onStateChange = { state in
            switch state {
            case .downloading(let p):
                let step = Int(p * 100) / 5 * 5          // de 5 em 5%
                if step != lastShown { lastShown = step; print("Baixando modelo… \(step)%") }
            case .loading: print("Carregando modelo…")
            case .ready: print("Modelo pronto.")
            case .failed(let msg): print("ERRO: \(msg)")
            case .idle: break
            }
        }

        print("Motor: \(Transcriber.engineName) | modelo: \(VoiceModel.resolved(Preferences.shared.modelName))")
        transcriber.loadModel()

        while !transcriber.isReady {
            if case .failed = transcriber.state { done.set(); return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        do {
            print("Lendo \(path)…")
            let samples = try AudioRecorder.loadSamples(fromFile: path)
            print("Amostras: \(samples.count) (\(String(format: "%.1f", Double(samples.count) / AudioRecorder.targetSampleRate))s)")
            let raw = try await transcriber.transcribe(samples: samples)
            print("BRUTO: \(raw)")
            print("LIMPO (regras): \(AIFormatter.ruleBasedCleanup(raw))")
        } catch {
            print("ERRO: \(error.localizedDescription)")
        }
        done.set()
    }

    while !done.isSet {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    AppDelegate.applyActivationPolicy()
    app.run()
}
