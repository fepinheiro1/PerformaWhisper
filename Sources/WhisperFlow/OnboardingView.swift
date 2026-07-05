import SwiftUI
import AVFoundation
import ApplicationServices

struct OnboardingView: View {
    var onDone: () -> Void
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axGranted = AXIsProcessTrusted()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Bem-vindo ao WhisperFlow")
                .font(.title.bold())
            Text("Ditado por voz local e privado, em qualquer app.\nPrecisamos de duas permissões para funcionar:")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microfone",
                    detail: "Para capturar sua voz",
                    granted: micGranted,
                    action: {
                        AVCaptureDevice.requestAccess(for: .audio) { granted in
                            DispatchQueue.main.async { micGranted = granted }
                        }
                    }
                )
                PermissionRow(
                    icon: "accessibility",
                    title: "Acessibilidade",
                    detail: "Para detectar a tecla de atalho e inserir texto no cursor",
                    granted: axGranted,
                    action: {
                        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                        AXIsProcessTrustedWithOptions(opts)
                    }
                )
            }
            .padding(.horizontal)

            Text("Depois de conceder, segure ⌥ Option direita e fale. Solte para inserir o texto.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Começar a usar") { onDone() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!(micGranted && axGranted))
        }
        .padding(32)
        .frame(width: 460)
        .onReceive(timer) { _ in
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            axGranted = AXIsProcessTrusted()
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Permitir", action: action)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
