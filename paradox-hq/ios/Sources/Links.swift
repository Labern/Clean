import SwiftUI
import UIKit

/// The places the company lives, each a tap away in its app or on the web.
struct QuickLink: Identifiable {
    let title: String
    /// The company's mark as an app-icon tile (a `Logo-*` image set).
    let logo: String
    let web: URL
    /// The addresses that open the company's app, tried in order. An https one is
    /// only ever a path the app has claimed: most apps refuse their site's bare
    /// home address, which is what made "App" fail for Stripe and Claude.
    var app: [URL] = []

    var id: String { title }
    var opensApp: Bool { !app.isEmpty }

    /// "paradoxica.co.uk/focus": host and path, without the www.
    var label: String {
        let host = web.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        let path = web.path()
        return path.isEmpty || path == "/" ? host : host + path
    }

    static let all: [QuickLink] = [
        QuickLink(title: "Home", logo: "IconPreview-main", web: url("https://paradoxica.co.uk")),
        QuickLink(title: "Focus", logo: "Logo-Focus", web: url("https://paradoxica.co.uk/focus")),
        QuickLink(title: "Google Workspace", logo: "Logo-Google", web: url("https://admin.google.com"),
                  app: [url("googlegmail://")]),
        QuickLink(title: "Stripe", logo: "Logo-Stripe", web: url("https://dashboard.stripe.com"),
                  app: [url("https://dashboard.stripe.com/dashboard")]),
        QuickLink(title: "GitHub", logo: "Logo-GitHub", web: url("https://github.com/Labern"),
                  app: [url("https://github.com/Labern"), url("github://")]),
        QuickLink(title: "Claude", logo: "Logo-Claude", web: url("https://claude.ai"),
                  app: [url("https://claude.ai/new"), url("claude://")]),
        QuickLink(title: "Tesla", logo: "Logo-Tesla", web: url("https://www.tesla.com/teslaaccount"),
                  app: [url("https://www.tesla.com/1/app/home"), url("tesla://")]),
    ]

    private static func url(_ string: String) -> URL { URL(string: string)! }
}

/// One link: its name and where it goes, with App and Web side by side.
struct QuickLinkRow: View {
    let link: QuickLink
    @Environment(\.openURL) private var openURL
    @State private var missing = false

    var body: some View {
        HStack(spacing: 12) {
            LogoTile(name: link.logo)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                    .foregroundStyle(Ink.body)
                    .lineLimit(1)
                Text(missing ? "Couldn't open the app" : link.label)
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
        open(link.app[...])
    }

    /// Tries each address in turn and only gives up after the last one.
    private func open(_ routes: ArraySlice<URL>) {
        guard let route = routes.first else {
            withAnimation(.snappy) { missing = true }
            Task {
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.snappy) { missing = false }
            }
            return
        }
        // A web address must open the app or nothing: never fall through to Safari.
        let web = route.scheme == "https"
        UIApplication.shared.open(route, options: web ? [.universalLinksOnly: true] : [:]) { opened in
            Task { @MainActor in
                if !opened { open(routes.dropFirst()) }
            }
        }
    }
}
