//
//  LiquidGlassViewTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

import AppKit
import XCTest
@testable import Sapphire

final class LiquidGlassViewTests: XCTestCase {
    @MainActor
    func testChangingMaterialRebuildsNativeGlassRenderer() throws {
        try XCTSkipIf(!LiquidGlassView.isSystemGlassAvailable)

        let host = LiquidGlassHostView(
            frame: NSRect(x: 0, y: 0, width: 200, height: 80),
            backend: .automatic
        )

        configure(host, material: .frosted)
        let originalRenderer = try XCTUnwrap(host.subviews.first)
        XCTAssertFalse(originalRenderer is NSVisualEffectView)

        configure(host, material: .frosted)
        XCTAssertTrue(originalRenderer === host.subviews.first)

        configure(host, material: .clearGlass)
        XCTAssertFalse(originalRenderer === host.subviews.first)
    }

    @MainActor
    private func configure(
        _ host: LiquidGlassHostView,
        material: LiquidGlassMaterial
    ) {
        host.configure(
            material: material,
            cornerRadius: 18,
            tintColor: nil,
            blendingMode: .behindWindow,
            appearance: .dark,
            interaction: .normal,
            contentLensing: 1,
            scrim: 0,
            subdued: 0
        )
    }
}