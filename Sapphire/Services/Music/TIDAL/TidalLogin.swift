//
//  TidalLogin.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-05.
//

import SwiftUI
import WebKit
import AppKit

struct TidalLoginWebView: View {
    let onComplete: () -> Void
    let onCancel: () -> Void

    private func cancelLogin() {
        MusicManager.shared.tidalAPI.cancelLogin()
        onCancel()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Log in to TIDAL").font(.headline)
                Spacer()
                Button("Cancel", action: cancelLogin)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            TidalLoginWebViewRepresentable(onComplete: onComplete, onCancel: cancelLogin)
        }
        .frame(width: 480, height: 720)
    }
}

private struct TidalLoginWebViewRepresentable: NSViewRepresentable {
    let onComplete: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let webView = AuthLoginWebView.makeWebView(delegate: context.coordinator)

        if let url = MusicManager.shared.tidalAPI.makeAuthorizeURL() {
            webView.load(URLRequest(url: url))
        } else {
            print("[TidalLogin] Missing Client ID/Secret; cannot build authorize URL.")
            DispatchQueue.main.async(execute: onCancel)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    final class Coordinator: AuthLoginCoordinator {
        private var isCompleting = false
        private let onComplete: () -> Void
        private let onCancel: () -> Void

        init(onComplete: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.onComplete = onComplete
            self.onCancel = onCancel
            super.init(serviceName: "TIDAL", logPrefix: "TidalLogin")
        }

        // MARK: - WKNavigationDelegate

        override func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               url.scheme?.lowercased() == "sapphire",
               url.host?.lowercased() == "callback" {
                if !isCompleting {
                    isCompleting = true
                    print("[TidalLogin] Intercepted redirect: \(url.absoluteString)")
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
                    let hasAuthorizationCode = components?.queryItems?.contains {
                        $0.name == "code" && $0.value?.isEmpty == false
                    } == true

                    if hasAuthorizationCode {
                        MusicManager.shared.tidalAPI.handleRedirect(url: url)
                        tearDown()
                        DispatchQueue.main.async(execute: onComplete)
                    } else {
                        MusicManager.shared.tidalAPI.cancelLogin()
                        tearDown()
                        DispatchQueue.main.async(execute: onCancel)
                    }
                }
                decisionHandler(.cancel)
                return
            }

            if let url = navigationAction.request.url,
               let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
               components.path.contains("/error") || components.queryItems?.contains(where: { $0.name == "error" }) == true {
                if !isCompleting {
                    isCompleting = true
                    print("[TidalLogin] OAuth error response; cancelling login.")
                    MusicManager.shared.tidalAPI.cancelLogin()
                    tearDown()
                    DispatchQueue.main.async(execute: onCancel)
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        override func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            guard nsError.code != 3072  && nsError.domain != WebKitErrorDomain else { return }
            print("[TidalLogin] Navigation failed: \(error.localizedDescription)")
        }
    }
}