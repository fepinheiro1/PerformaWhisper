import SwiftUI

struct AboutView: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Versão \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 18) {
            BrandLogo()
                .frame(width: 300, height: 36)

            VStack(spacing: 4) {
                Text("Ditado por voz local e privado para macOS")
                    .font(.callout)
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 6) {
                Text("Criado por")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Fernando Pinheiro")
                    .font(.title3.weight(.semibold))
            }

            HStack(spacing: 18) {
                ContactLink(label: "LinkedIn", systemImage: "person.crop.square",
                            url: "https://www.linkedin.com/in/fernando-pinheiro-45155341/")
                ContactLink(label: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right",
                            url: "https://github.com/fepinheiro1/")
                ContactLink(label: "E-mail", systemImage: "envelope",
                            url: "mailto:fepinheiro1@gmail.com")
            }

            Text("A transcrição roda 100% no seu Mac. Seu áudio nunca sai da máquina.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 420)
    }
}

private struct ContactLink: View {
    let label: String
    let systemImage: String
    let url: String

    var body: some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                VStack(spacing: 4) {
                    Image(systemName: systemImage).font(.system(size: 16))
                    Text(label).font(.caption)
                }
                .frame(width: 76)
            }
            .buttonStyle(.plain)
            .help(url)
        }
    }
}
