import AuthenticationServices
import SwiftUI
import WebKit

/// The game in a WKWebView, nothing else: the page is the site itself, so it is always the
/// version the servers speak.
///
/// Google and Discord refuse to sign in inside a web view, and Apple's sign in works better
/// outside it, so those pages open in an ASWebAuthenticationSession (the system browser
/// sheet). The master (api-game...) is told `?app=1` and, when the sign in is done, sends
/// the browser to rysteria://oauth#oauth_code=...; the session hands that address back and
/// the code is given to the page, which exchanges it like on the website.
struct WebScreen: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = "RysteriaApp"
        // the default store is persistent: the login (localStorage) stays
        configuration.websiteDataStore = .default()

        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.isOpaque = false
        web.backgroundColor = .black
        context.coordinator.web = web
        web.load(URLRequest(url: Coordinator.gameURL))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, ASWebAuthenticationPresentationContextProviding {
        static let gameURL = URL(string: Bundle.main.object(forInfoDictionaryKey: "GameURL") as? String
                                 ?? "https://game.parshwa.blog/")!
        static let apiHost = Bundle.main.object(forInfoDictionaryKey: "ApiHost") as? String
            ?? "api-game.parshwa.blog"
        private let signInHosts: Set<String> = ["accounts.google.com", "appleid.apple.com", "discord.com", "www.discord.com"]

        weak var web: WKWebView?
        private var session: ASWebAuthenticationSession?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, let host = url.host else {
                decisionHandler(.allow)
                return
            }
            let gameHost = Self.gameURL.host ?? ""
            if host == Self.apiHost, url.path.hasPrefix("/oauth/"), url.path.hasSuffix("/start") {
                // the page asked to sign in with a provider: do it in the browser sheet
                var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: "app", value: "1")]
                signIn(with: parts.url!)
                decisionHandler(.cancel)
            } else if signInHosts.contains(host) {
                signIn(with: url)
                decisionHandler(.cancel)
            } else if host == gameHost || host == Self.apiHost || host.hasSuffix("." + gameHost)
                        || url.scheme == "about" || url.scheme == "blob" {
                decisionHandler(.allow)
            } else if navigationAction.navigationType == .linkActivated {
                // any other site opens outside the game
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        private func signIn(with url: URL) {
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "rysteria") { [weak self] callback, _ in
                guard let self = self, let callback = callback else { return }
                // rysteria://oauth#oauth_code=... -> the game page with the same fragment
                var game = Self.gameURL.absoluteString
                if let fragment = callback.fragment, !fragment.isEmpty { game += "#" + fragment }
                if let target = URL(string: game) { self.web?.load(URLRequest(url: target)) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
                .first ?? ASPresentationAnchor()
        }
    }
}
