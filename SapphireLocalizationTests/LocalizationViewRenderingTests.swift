// Production-view image artifacts for manual localization inspection.
// Successful capture does not establish clipping, wrapping, or layout acceptance.

import AppKit
import SwiftUI
import XCTest
@testable import Sapphire

final class LocalizationViewRenderingTests: XCTestCase {
    @MainActor
    func testSettingsSidebarProducesInspectionImage() throws {
        // SettingsView uses a 250-point sidebar. Constant bindings prevent actions
        // from changing settings; the public subscription stub has no startup work.
        let sidebar = SettingsSidebarView(
            selectedSection: .constant(.general),
            showAccountPane: .constant(false),
            onQuit: {}
        )
        try attachRender(sidebar, size: NSSize(width: 250, height: 900), name: "settings-sidebar")
    }

    @MainActor
    func testLongSettingsComponentsProduceInspectionImage() throws {
        // Labels are copied from their production SettingsPanes call sites.
        let sample = VStack(alignment: .leading, spacing: 20) {
            ToggleRow(
                title: "Show Other Activities Beside the Notch",
                description: "When more than one live activity is running, the ones after the first appear as small bubbles next to the notch, like the Dynamic Island. Click a bubble to open it.",
                isOn: .constant(true)
            )
            SettingsRowLabel(
                title: "Activities Beside the Notch",
                description: "The most bubbles that show at once. The first two sit on either side of the notch; more line up further out."
            )
            .padding(.horizontal, 16)
            ToggleRow(
                title: "Pause \"Now Playing\" while Locked",
                description: "Automatically pauses music or videos when the screen locks.",
                isOn: .constant(false)
            )
            InfoContainer(
                text: "Enabling stats will increase the app's cpu and power consumption.",
                iconName: "info.circle",
                color: .yellow
            )
            Spacer(minLength: 0)
        }
        .padding(20)
        try attachRender(sample, size: NSSize(width: 540, height: 620), name: "settings-components")
    }

    @MainActor
    private func attachRender<Content: View>(_ content: Content, size: NSSize, name: String) throws {
        let frame = NSRect(origin: .zero, size: size)
        let host = NSHostingView(rootView: content
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(.dark))
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = frame
        defer {
            window.contentView = nil
            window.close()
        }
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        host.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 0)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)

        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)-\(Int(size.width))x\(Int(size.height))-\(language)-\(Locale.current.identifier).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
