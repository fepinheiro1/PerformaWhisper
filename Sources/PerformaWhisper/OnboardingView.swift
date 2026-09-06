import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices

struct OnboardingView: View {
    var onDone: () -> Void
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axGranted = AXIsProcessTrusted()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            // Altura explícita: uma imagem redimensionável não tem altura mínima e
            // encolhe até sumir se a janela for menor que o conteúdo.
            BrandLogo()
                .frame(width: 300, height: 36)
                .padding(.bottom, 4)
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
                        // O prompt do sistema só aparece uma vez por app; depois disso
                        // o botão não faria nada visível. Abrir os Ajustes garante que
                        // sempre haja um próximo passo.
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }
            .padding(.horizontal)

            if !axGranted {
                // O macOS guarda a permissão junto com a assinatura do app. Como a
                // assinatura ad-hoc muda a cada build, reinstalar deixa a chave ligada
                // apontando para a versão antiga.
                Text("Já ligou a chave e continua aparecendo pendente? Acontece depois de reinstalar: selecione o PerformaWhisper na lista de Acessibilidade, remova com o botão “−” e ligue de novo.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Text("Depois de conceder, segure ⌃ Control + ⌥ Option e fale. Solte para inserir o texto.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Só o microfone bloqueia. A checagem de acessibilidade pode ficar presa
            // em "não concedida" mesmo com a chave ligada, e travar a pessoa nesta
            // tela para sempre é pior do que deixar entrar com o atalho inativo — a
            // barra de menus avisa quando falta a permissão.
            Button(axGranted ? "Começar a usar" : "Continuar mesmo assim") { onDone() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!micGranted)
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
