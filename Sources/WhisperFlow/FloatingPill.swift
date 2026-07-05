import AppKit
import SwiftUI

/// The pill that floats at the bottom-center of the screen while dictating,
/// mirroring Wispr Flow's recording indicator.
@MainActor
final class FloatingPillController {
    private var panel: NSPanel?
    private let model = PillModel()
    private var hideTimer: Timer?

    func show(_ state: DictationController.PillState) {
        hideTimer?.invalidate()
        model.state = state
        ensurePanel()
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func hide() {
        hideTimer?.invalidate()
        panel?.orderOut(nil)
        model.state = .hidden
    }

    func hideAfter(_ seconds: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func updateLevel(_ level: Float) {
        model.pushLevel(level)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 64),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: PillView(model: model))
        self.panel = panel
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
final class PillModel: ObservableObject {
    @Published var state: DictationController.PillState = .hidden
    @Published var levels: [Float] = Array(repeating: 0.05, count: 24)

    func pushLevel(_ level: Float) {
        levels.removeFirst()
        levels.append(max(0.05, level))
    }
}

struct PillView: View {
    @ObservedObject var model: PillModel

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: model.state)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .hidden:
            EmptyView()
        case .downloadingModel(let progress):
            ProgressView().controlSize(.small)
            Text(progress > 0
                 ? "Baixando modelo… \(Int(progress * 100))%"
                 : "Preparando modelo…")
                .font(.system(size: 13, weight: .medium))
        case .recording(let isCommand):
            Circle()
                .fill(isCommand ? Color.purple : Color.red)
                .frame(width: 9, height: 9)
            Waveform(levels: model.levels, color: isCommand ? .purple : .red)
                .frame(width: 120, height: 24)
            Text(isCommand ? "Comando…" : "Ouvindo…")
                .font(.system(size: 13, weight: .medium))
        case .processing:
            ProgressView().controlSize(.small)
            Text("Transcrevendo…")
                .font(.system(size: 13, weight: .medium))
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Inserido")
                .font(.system(size: 13, weight: .medium))
        case .error(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: 300)
        }
    }
}

struct Waveform: View {
    let levels: [Float]
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(levels.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(0.85))
                    .frame(width: 2.5, height: CGFloat(4 + levels[i] * 20))
            }
        }
        .animation(.linear(duration: 0.05), value: levels)
    }
}
