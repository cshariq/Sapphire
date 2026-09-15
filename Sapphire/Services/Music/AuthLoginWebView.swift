//
//  AuthLoginWebView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import AppKit
import WebKit

enum AuthLoginWebView {
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    static func makeWebView(delegate: AuthLoginCoordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = desktopUserAgent
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }
}

class AuthLoginCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let serviceName: String
    private let logPrefix: String
    private(set) var popupWindows: [WKWebView: NSWindow] = [:]

    init(serviceName: String, logPrefix: String) {
        self.serviceName = serviceName
        self.logPrefix = logPrefix
    }

    deinit {
        closePopups()
    }

    func tearDown() {
        closePopups()
    }

    private func closePopups() {
        for (_, window) in popupWindows {
            window.close()
        }
        popupWindows.removeAll()
    }

    // MARK: - WKNavigationDelegate (overridden by subclasses)

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}

    // MARK: - WKUIDelegate (social login / captcha popups)

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.customUserAgent = AuthLoginWebView.desktopUserAgent
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
        window.title = "\(serviceName) Login"
        window.contentView = popup
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        popupWindows[popup] = window
        print("[\(logPrefix)] Opened auth popup for \(navigationAction.request.url?.absoluteString ?? "unknown")")

        popup.load(navigationAction.request)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let window = popupWindows.removeValue(forKey: webView) {
            window.close()
            print("[\(logPrefix)] Auth popup closed by page.")
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = serviceName
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
        alert.messageText = serviceName
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}