//
//  CaptchaProvider.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-18.
//

import SwiftUI
import CaptchaSolverInterface
import WebKit

internal class ConcreteCaptchaPresenter: CaptchaPresenting {
    public func loginView(onComplete: @escaping ([[String: Any]]) -> Void, onCancel: @escaping () -> Void) -> AnyView {
        AnyView(LoginWebView(onComplete: onComplete, onCancel: onCancel))
    }
}

@_cdecl("createCaptchaPresenter")
public func createCaptchaPresenter() -> UnsafeMutableRawPointer {
    let presenter = ConcreteCaptchaPresenter()
    return Unmanaged.passRetained(presenter).toOpaque()
}

internal struct LoginWebView: View {
    let onComplete: ([[String: Any]]) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack {
            Text("Complete Login").font(.title).padding()
            Text("Your credentials will be auto-filled. Please click 'Log In' and complete any required steps (like entering a 2FA code).")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal).padding(.bottom)

            LoginWebViewRepresentable(onComplete: onComplete)

            Button("Cancel", action: onCancel).padding()
        }
        .frame(width: 800, height: 700)
    }
}

private struct LoginWebViewRepresentable: NSViewRepresentable {
    let onComplete: ([[String: Any]]) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator

        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let spotifyRecords = records.filter { $0.displayName.contains("spotify.com") }
            if !spotifyRecords.isEmpty {
                print("[CaptchaSolver] Found old Spotify data. Clearing cache and cookies...")
                dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: spotifyRecords) {
                    print("[CaptchaSolver] Old data cleared. Loading fresh login page.")
                    self.loadLoginPage(in: webView)
                }
            } else {
                print("[CaptchaSolver] No old Spotify data found. Loading login page directly.")
                self.loadLoginPage(in: webView)
            }
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
    }

    private func loadLoginPage(in webView: WKWebView) {
        if let url = URL(string: "https://accounts.spotify.com/en/login") {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LoginWebViewRepresentable
        private var isCompleting = false

        init(_ parent: LoginWebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            print("[CaptchaSolver] Finished loading URL: \(url.absoluteString)")

            checkForSessionCookies()

        }

        private func checkForSessionCookies() {
            guard !isCompleting else { return }

            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let hasSessionCookie = cookies.contains { $0.name == "sp_dc" } && cookies.contains { $0.name == "sp_key" }

                if hasSessionCookie {
                    self.isCompleting = true
                    print("[CaptchaSolver] SUCCESS: Session cookies detected. Completing login.")

                    let cookieProperties = cookies.compactMap { cookie -> [String: Any]? in
                        guard let properties = cookie.properties else { return nil }
                        return Dictionary(uniqueKeysWithValues: properties.map { key, value in
                            (key.rawValue, value)
                        })
                    }

                    DispatchQueue.main.async {
                        self.parent.onComplete(cookieProperties)
                    }
                }
            }
        }
    }
}