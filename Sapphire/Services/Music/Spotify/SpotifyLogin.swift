//
//  SpotifyLogin.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import SwiftUI
import WebKit
import AppKit

struct SpotifyLoginWebView: View {
    let onComplete: ([[String: Any]]) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack {
            Text("Complete Login").font(.title).padding()
            Text("Sign in to Spotify below. Old sessions are cleared first so a revoked login cannot auto-complete.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal).padding(.bottom)

            SpotifyLoginWebViewRepresentable(onComplete: onComplete)

            Button("Cancel", action: onCancel).padding()
        }
        .frame(width: 800, height: 700)
    }
}

private struct SpotifyLoginWebViewRepresentable: NSViewRepresentable {
    let onComplete: ([[String: Any]]) -> Void

    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.desktopUserAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        print("[SpotifyLogin] Clearing residual Spotify website data, then loading a fresh login.")
        Self.clearSharedSpotifyWebsiteData {
            context.coordinator.loadLoginPage(in: webView)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    static func clearSharedSpotifyWebsiteData(completion: @escaping () -> Void) {
        let store = WKWebsiteDataStore.default()
        store.httpCookieStore.getAllCookies { cookies in
            let group = DispatchGroup()
            for cookie in cookies where Self.isSpotifyCookie(cookie) {
                group.enter()
                store.httpCookieStore.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                    let spotifyRecords = records.filter {
                        $0.displayName.localizedCaseInsensitiveContains("spotify")
                    }
                    guard !spotifyRecords.isEmpty else {
                        completion()
                        return
                    }
                    store.removeData(
                        ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                        for: spotifyRecords
                    ) {
                        DispatchQueue.main.async { completion() }
                    }
                }
            }
        }
    }

    static func isSpotifyCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased()
        return domain.contains("spotify.com") || domain.contains("spotify.net")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: SpotifyLoginWebViewRepresentable
        private var isCompleting = false
        private var didPassLoginForm = false
        private var cookiePollTimer: Timer?
        private var popupWindows: [WKWebView: NSWindow] = [:]

        init(_ parent: SpotifyLoginWebViewRepresentable) {
            self.parent = parent
        }

        deinit {
            tearDown()
        }

        func tearDown() {
            cookiePollTimer?.invalidate()
            cookiePollTimer = nil
            for (_, window) in popupWindows {
                window.close()
            }
            popupWindows.removeAll()
        }

        func loadLoginPage(in webView: WKWebView) {
            guard let url = URL(string: "https://accounts.spotify.com/en/login?continue=https%3A%2F%2Fopen.spotify.com%2F") else { return }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            webView.load(request)
            startCookiePolling(for: webView)
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            if popupWindows[webView] != nil {
                print("[SpotifyLogin] Popup finished: \(url.absoluteString)")
                checkForFreshSessionCookies(in: webView)
                return
            }

            print("[SpotifyLogin] Finished loading URL: \(url.absoluteString)")

            if Self.looksLikeAuthenticatedDestination(url) {
                didPassLoginForm = true
                checkForFreshSessionCookies(in: webView)
            } else if Self.looksLikeLoginPage(url) {
                print("[SpotifyLogin] Login form visible; waiting for a real sign-in.")
            } else if url.host?.contains("spotify.com") == true {
                didPassLoginForm = true
                checkForFreshSessionCookies(in: webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(.allow)
        }

        // MARK: - WKUIDelegate (social login / captcha popups)

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.customUserAgent = SpotifyLoginWebViewRepresentable.desktopUserAgent
            popup.navigationDelegate = self
            popup.uiDelegate = self

            let width = CGFloat(windowFeatures.width?.doubleValue ?? 520)
            let height = CGFloat(windowFeatures.height?.doubleValue ?? 720)
            let rect = NSRect(x: 0, y: 0, width: max(width, 480), height: max(height, 640))

            let window = NSWindow(
                contentRect: rect,
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Spotify Login"
            window.contentView = popup
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)

            popupWindows[popup] = window
            print("[SpotifyLogin] Opened auth popup for \(navigationAction.request.url?.absoluteString ?? "unknown")")

            if let url = navigationAction.request.url {
                popup.load(navigationAction.request)
            }

            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            if let window = popupWindows.removeValue(forKey: webView) {
                window.close()
                print("[SpotifyLogin] Auth popup closed by page.")
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = "Spotify"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = "Spotify"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        // MARK: - Cookie harvest

        private func startCookiePolling(for webView: WKWebView) {
            cookiePollTimer?.invalidate()
            cookiePollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                guard self.didPassLoginForm
                        || Self.looksLikeAuthenticatedDestination(webView.url)
                        || !self.popupWindows.isEmpty else { return }
                self.checkForFreshSessionCookies(in: webView)
            }
        }

        private func checkForFreshSessionCookies(in webView: WKWebView) {
            guard !isCompleting else { return }

            let store = webView.configuration.websiteDataStore
            store.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let spotifyCookies = cookies.filter { SpotifyLoginWebViewRepresentable.isSpotifyCookie($0) }
                let hasDC = spotifyCookies.contains { $0.name == "sp_dc" }
                let hasKey = spotifyCookies.contains { $0.name == "sp_key" }
                let hasT = spotifyCookies.contains { $0.name == "sp_t" }

                guard hasDC, hasKey else { return }

                let url = webView.url
                let leftAccountsLogin = url.map { !Self.looksLikeLoginPage($0) } ?? false
                guard hasT || leftAccountsLogin || Self.looksLikeAuthenticatedDestination(url) else {
                    return
                }

                self.isCompleting = true
                self.cookiePollTimer?.invalidate()
                print("[SpotifyLogin] SUCCESS: Fresh session cookies detected. Completing login.")

                let cookieProperties = spotifyCookies.compactMap { cookie -> [String: Any]? in
                    guard let properties = cookie.properties else { return nil }
                    return Dictionary(uniqueKeysWithValues: properties.map { key, value in
                        (key.rawValue, value)
                    })
                }

                DispatchQueue.main.async {
                    self.tearDown()
                    self.parent.onComplete(cookieProperties)
                }
            }
        }

        private static func looksLikeLoginPage(_ url: URL?) -> Bool {
            guard let url, let host = url.host?.lowercased() else { return false }
            guard host.contains("accounts.spotify.com") else { return false }
            let path = url.path.lowercased()
            return path.contains("/login") || path.contains("/signin") || path == "/" || path.isEmpty
        }

        private static func looksLikeAuthenticatedDestination(_ url: URL?) -> Bool {
            guard let url, let host = url.host?.lowercased() else { return false }
            if host.contains("open.spotify.com") { return true }
            if host.contains("accounts.spotify.com") {
                let path = url.path.lowercased()
                return path.contains("/status") || path.contains("/login/ok") || path.contains("/oauth")
            }
            return false
        }
    }
}