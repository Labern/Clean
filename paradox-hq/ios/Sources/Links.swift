import SwiftUI
import UIKit

/// The places the company lives, each a tap away in its app or on the web.
struct QuickLink: Identifiable {
    let title: String
    let symbol: String
    let web: URL
    /// The app's own address, when it has one. Without one, the web address is
    /// tried as a universal link, which opens the app when it's installed.
    var app: URL? = nil
    var opensApp = true

    var id: String { title }

    /// "paradoxica.co.uk/focus": host and path, without the www.
    var label: String {
        let host = web.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        let path = web.path()
        return path.isEmpty || path == "/" ? host : host + path
    }

    static let all: [QuickLink] = [
        QuickLink(title: "Home", symbol: "house", web: URL(string: "https://paradoxica.co.uk")!, opensApp: false),
        QuickLink(title: "Focus", symbol: "scope", web: URL(string: "https://paradoxica.co.uk/focus")!, opensApp: false),
        QuickLink(title: "Google Workspace", symbol: "envelope", web: URL(string: "https://admin.google.com")!,
                  app: URL(string: "googlegmail://")),
        QuickLink(title: "Stripe", symbol: "creditcard", web: URL(string: "https://dashboard.stripe.com")!),
        QuickLink(title: "GitHub", symbol: "chevron.left.forwardslash.chevron.right",
                  web: URL(string: "https://github.com/Labern")!),
        QuickLink(title: "Claude", symbol: "sparkles", web: URL(string: "https://claude.ai")!),
        QuickLink(title: "Tesla", symbol: "car", web: URL(string: "https://www.tesla.com/teslaaccount")!,
                  app: URL(string: "tesla://")),
    ]
}

/// One link: its name and where it goes, with App and Web side by side.
struct QuickLinkRow: View {
    let link: QuickLink
    @Environment(\.openURL) private var openURL
    @State private var missing = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: link.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Ink.muted)
                .frame(width: 32, height: 32)
                .background(Ink.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                    .foregroundStyle(Ink.body)
                    .lineLimit(1)
                Text(missing ? "App not installed" : link.label)
                    .font(.caption)
                    .foregroundStyle(missing ? Ink.amber : Ink.muted)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            if link.opensApp {
                chip("App", primary: false, action: openApp)
            }
            chip("Web", primary: !link.opensApp) { openURL(link.web) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .sensoryFeedback(.warning, trigger: missing) { _, new in new }
    }

    private func chip(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primary ? Ink.buttonInk : Ink.body)
                .padding(.horizontal, 14)
                .frame(minWidth: 56, minHeight: 34)
                .background(primary ? Ink.button : Ink.surface2, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(link.title), \(title == "App" ? "open the app" : "open the website")")
    }

    private func openApp() {
        let target = link.app ?? link.web
        let options: [UIApplication.OpenExternalURLOptionsKey: Any] = link.app == nil ? [.universalLinksOnly: true] : [:]
        UIApplication.shared.open(target, options: options) { opened in
            Task { @MainActor in
                guard !opened else { return }
                withAnimation(.snappy) { missing = true }
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.snappy) { missing = false }
            }
        }
    }
}
