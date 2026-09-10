import Foundation

/// Estado do motor de transcrição, comum às duas implementações.
enum TranscriberState: Equatable {
    case idle
    case downloading(Double)   // 0...1
    case loading
    case ready
    case failed(String)
}

enum WhisperText {
    /// Remove artefatos do Whisper: tokens especiais e anotações alucinadas.
    static func cleanArtifacts(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[[^\]]{0,40}\]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Modelos oferecidos na interface. Em x86_64 a lista é menor: o whisper.cpp
/// embutido pelo SwiftWhisper é anterior ao large-v3-turbo.
enum VoiceModel {
    static let all: [(id: String, label: String)] = {
        var models: [(String, String)] = [
            ("tiny", "Tiny — mais rápido, menos preciso (~75 MB)"),
            ("base", "Base — rápido (~140 MB)"),
            ("small", "Small — equilíbrio recomendado (~460 MB)"),
            ("medium", "Medium — mais preciso, mais lento (~1,5 GB)")
        ]
        #if arch(arm64)
        models.append(("large-v3_turbo", "Large v3 Turbo — máxima precisão (~1,6 GB)"))
        #endif
        return models
    }()

    /// Preferências antigas podem apontar para um modelo que a arquitetura atual
    /// não oferece; nesse caso cai no padrão em vez de falhar ao carregar.
    static func resolved(_ stored: String) -> String {
        all.contains { $0.id == stored } ? stored : "small"
    }
}
