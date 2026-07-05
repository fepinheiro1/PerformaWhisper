import AVFoundation
import Foundation

/// Records microphone input and delivers 16 kHz mono Float32 samples,
/// the format WhisperKit expects.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false

    /// Called on an internal thread with the current input level (0...1),
    /// for the floating pill waveform.
    var onLevel: ((Float) -> Void)?

    static let targetSampleRate: Double = 16000

    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() throws {
        guard !isRecording else { return }
        samples.removeAll()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "WhisperFlow", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Microfone indisponível"])
        }

        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: Self.targetSampleRate,
                                         channels: 1,
                                         interleaved: false)!
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, targetFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Stops recording and returns the captured samples.
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        lock.lock()
        defer { lock.unlock() }
        let result = samples
        samples.removeAll()
        return result
    }

    func cancel() {
        _ = stop()
    }

    private func process(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, let ch = out.floatChannelData else { return }

        let frames = Int(out.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: ch[0], count: frames))

        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()

        if !chunk.isEmpty {
            var peak: Float = 0
            for s in chunk { peak = max(peak, abs(s)) }
            onLevel?(min(1, peak * 3))
        }
    }
}
