import SwiftUI
import AppKit

/// The full wordmark. The white artwork vanishes on a light window, so each
/// appearance gets its own file.
struct BrandLogo: View {
    @Environment(\.colorScheme) private var colorScheme

    private static let light = load("logo-light")
    private static let dark = load("logo-dark")

    /// Loads from the app bundle's own Resources. Deliberately not Bundle.module:
    /// SwiftPM's generated accessor looks beside the executable and otherwise
    /// falls back to an absolute .build path from the build machine, which
    /// crashes on any Mac that did not compile the app.
    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        if let image = colorScheme == .dark ? Self.dark : Self.light {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("PerformaWhisper")
        } else {
            // Running the bare binary without the resource bundle alongside it.
            Text("PerformaWhisper").font(.title.bold())
        }
    }
}
