import Foundation

/// Baixa e guarda os modelos GGML usados pelo motor whisper.cpp.
///
/// O WhisperKit cuida do próprio download; o whisper.cpp recebe apenas um
/// caminho de arquivo, então esta parte é nossa.
final class GGMLModelStore: NSObject, URLSessionDownloadDelegate {

    enum StoreError: LocalizedError {
        case badResponse(Int)
        case moveFailed(String)

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "Falha ao baixar o modelo (HTTP \(code))"
            case .moveFailed(let why): return "Falha ao salvar o modelo: \(why)"
            }
        }
    }

    private static let repoBase = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base
            .appendingPathComponent("PerformaWhisper", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileName(for variant: String) -> String { "ggml-\(variant).bin" }

    static func localURL(for variant: String) -> URL {
        directory.appendingPathComponent(fileName(for: variant))
    }

    static func isDownloaded(_ variant: String) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: variant).path)
    }

    // MARK: - Download

    private var progressHandler: ((Double) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?

    /// Devolve o caminho local do modelo, baixando se ainda não existir.
    static func ensureAvailable(_ variant: String,
                                progress: @escaping (Double) -> Void) async throws -> URL {
        let local = localURL(for: variant)
        if FileManager.default.fileExists(atPath: local.path) { return local }
        return try await GGMLModelStore().download(variant: variant, to: local, progress: progress)
    }

    private func download(variant: String,
                          to destination: URL,
                          progress: @escaping (Double) -> Void) async throws -> URL {
        self.progressHandler = progress
        // Grava num arquivo temporário e só renomeia no fim: um download
        // interrompido não pode deixar um .bin pela metade que pareça completo.
        self.destination = destination.appendingPathExtension("partial")

        let url = URL(string: "\(Self.repoBase)/\(Self.fileName(for: variant))")!
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let partial: URL = try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            session.downloadTask(with: url).resume()
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            throw StoreError.moveFailed(error.localizedDescription)
        }
        return destination
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // O arquivo em `location` é apagado assim que este método retorna.
        guard let partial = destination else { return }
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            continuation?.resume(throwing: StoreError.badResponse(http.statusCode))
            continuation = nil
            return
        }
        do {
            if FileManager.default.fileExists(atPath: partial.path) {
                try FileManager.default.removeItem(at: partial)
            }
            try FileManager.default.moveItem(at: location, to: partial)
            continuation?.resume(returning: partial)
        } catch {
            continuation?.resume(throwing: StoreError.moveFailed(error.localizedDescription))
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }   // sucesso já resolvido em didFinishDownloadingTo
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
