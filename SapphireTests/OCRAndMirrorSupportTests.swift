//
//  OCRAndMirrorSupportTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07

import CoreGraphics
import XCTest
@testable import Sapphire

final class OCRScreenTextSupportTests: XCTestCase {

    // MARK: Hotkey

    func testExactModifierMatch() {
        let required: CGEventFlags = [.maskCommand, .maskShift]
        XCTAssertTrue(OCRScreenTextSupport.modifiersMatchExactly(eventFlags: [.maskCommand, .maskShift], required: required))
        XCTAssertFalse(OCRScreenTextSupport.modifiersMatchExactly(eventFlags: [.maskCommand, .maskShift, .maskAlternate], required: required))
        XCTAssertFalse(OCRScreenTextSupport.modifiersMatchExactly(eventFlags: [.maskCommand], required: required))
    }

    func testModifierMatchIgnoresCapsLockAndFunctionKeys() {
        let required: CGEventFlags = [.maskControl]
        XCTAssertTrue(OCRScreenTextSupport.modifiersMatchExactly(
            eventFlags: [.maskControl, .maskAlphaShift, .maskSecondaryFn, .maskNumericPad],
            required: required
        ))
    }

    // MARK: Geometry

    func testCaptureRectIsClampedToDisplayAndSnappedToPixels() {
        let rect = OCRScreenTextSupport.captureSourceRect(
            selectionInView: CGRect(x: 10.3, y: 20.7, width: 100.1, height: 50.2),
            displaySize: CGSize(width: 1512, height: 982),
            scale: 2
        )
        XCTAssertEqual(rect, CGRect(x: 10, y: 20.5, width: 100.5, height: 50.5))

        let clamped = OCRScreenTextSupport.captureSourceRect(
            selectionInView: CGRect(x: 1500, y: 970, width: 100, height: 100),
            displaySize: CGSize(width: 1512, height: 982),
            scale: 1
        )
        XCTAssertEqual(clamped, CGRect(x: 1500, y: 970, width: 12, height: 12))
    }

    func testTinyOrOffscreenSelectionIsRejected() {
        XCTAssertNil(OCRScreenTextSupport.captureSourceRect(
            selectionInView: CGRect(x: 0, y: 0, width: 1, height: 40),
            displaySize: CGSize(width: 800, height: 600),
            scale: 2
        ))
        XCTAssertNil(OCRScreenTextSupport.captureSourceRect(
            selectionInView: CGRect(x: 900, y: 0, width: 40, height: 40),
            displaySize: CGSize(width: 800, height: 600),
            scale: 2
        ))
    }

    func testPixelSizeUsesBackingScale() {
        let size = OCRScreenTextSupport.capturePixelSize(for: CGRect(x: 0, y: 0, width: 100.5, height: 40), scale: 2)
        XCTAssertEqual(size.width, 201)
        XCTAssertEqual(size.height, 80)
    }

    func testScreenUnderPointerOnSecondDisplay() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: 1512, y: -200, width: 2560, height: 1440),
        ]
        XCTAssertEqual(OCRScreenTextSupport.indexOfScreen(containing: CGPoint(x: 2000, y: 500), in: frames), 1)
        XCTAssertEqual(OCRScreenTextSupport.indexOfScreen(containing: CGPoint(x: 100, y: 100), in: frames), 0)
        XCTAssertEqual(OCRScreenTextSupport.indexOfScreen(containing: CGPoint(x: 1000, y: 1100), in: frames), 0)
        XCTAssertNil(OCRScreenTextSupport.indexOfScreen(containing: .zero, in: []))
    }

    // MARK: Recognition

    func testRecognitionLanguagesAreFilteredToSupported() {
        let supported = ["en-US", "fr-FR", "zh-Hans"]
        XCTAssertEqual(OCRScreenTextSupport.recognitionLanguages(preferred: "en-US", supported: supported), ["en-US"])
        XCTAssertEqual(OCRScreenTextSupport.recognitionLanguages(preferred: "fr", supported: supported), ["fr-FR"])
        XCTAssertEqual(OCRScreenTextSupport.recognitionLanguages(preferred: "ko-KR", supported: supported), [])
        XCTAssertEqual(OCRScreenTextSupport.recognitionLanguages(preferred: "", supported: supported), [])
    }

    func testLinesAreOrderedTopToBottomThenLeftToRight() {
        typealias Line = OCRScreenTextSupport.RecognizedLine
        let lines = [
            Line(text: "third", boundingBox: CGRect(x: 0.1, y: 0.10, width: 0.3, height: 0.05)),
            Line(text: "right", boundingBox: CGRect(x: 0.6, y: 0.81, width: 0.3, height: 0.05)),
            Line(text: "second", boundingBox: CGRect(x: 0.1, y: 0.50, width: 0.3, height: 0.05)),
            Line(text: "left", boundingBox: CGRect(x: 0.1, y: 0.80, width: 0.3, height: 0.05)),
        ]
        XCTAssertEqual(OCRScreenTextSupport.orderedText(lines), "left right\nsecond\nthird")
    }

    func testBarelyOverlappingLinesStaySeparateRows() {
        typealias Line = OCRScreenTextSupport.RecognizedLine
        let lines = [
            Line(text: "lower", boundingBox: CGRect(x: 0.0, y: 0.50, width: 0.3, height: 0.10)),
            Line(text: "upper", boundingBox: CGRect(x: 0.5, y: 0.58, width: 0.3, height: 0.10)),
        ]
        XCTAssertEqual(OCRScreenTextSupport.orderedText(lines), "upper\nlower")
    }

    func testEmptyLinesAreDropped() {
        typealias Line = OCRScreenTextSupport.RecognizedLine
        XCTAssertEqual(OCRScreenTextSupport.orderedText([]), "")
        XCTAssertEqual(OCRScreenTextSupport.orderedText([
            Line(text: "  ", boundingBox: CGRect(x: 0, y: 0.5, width: 0.1, height: 0.1)),
            Line(text: " hi ", boundingBox: CGRect(x: 0, y: 0.2, width: 0.1, height: 0.1)),
        ]), "hi")
    }

    // MARK: Barcodes

    func testOnlyWebLinksAreOfferedForOpening() {
        XCTAssertEqual(OCRScreenTextSupport.webURL(fromBarcodePayload: " https://example.com/a?b=1 ")?.absoluteString, "https://example.com/a?b=1")
        XCTAssertNotNil(OCRScreenTextSupport.webURL(fromBarcodePayload: "HTTP://example.com"))
        XCTAssertNil(OCRScreenTextSupport.webURL(fromBarcodePayload: "WIFI:S:home;T:WPA;P:secret;;"))
        XCTAssertNil(OCRScreenTextSupport.webURL(fromBarcodePayload: "file:///etc/passwd"))
        XCTAssertNil(OCRScreenTextSupport.webURL(fromBarcodePayload: "javascript:alert(1)"))
        XCTAssertNil(OCRScreenTextSupport.webURL(fromBarcodePayload: "https://"))
        XCTAssertNil(OCRScreenTextSupport.webURL(fromBarcodePayload: "see https://example.com"))
    }
}

final class MirrorCameraSelectionTests: XCTestCase {
    private let builtIn = MirrorCameraOption(id: "builtin", name: "FaceTime HD Camera", isBuiltIn: true, isFrontFacing: true)
    private let usb = MirrorCameraOption(id: "usb", name: "Logitech BRIO", isBuiltIn: false, isFrontFacing: false)
    private let phone = MirrorCameraOption(id: "phone", name: "iPhone Camera", isBuiltIn: false, isFrontFacing: false)

    func testRememberedCameraWinsWhenConnected() {
        XCTAssertEqual(
            MirrorCameraSelection.resolve(rememberedID: "usb", options: [builtIn, usb, phone], systemDefaultID: "phone"),
            "usb"
        )
    }

    func testMissingRememberedCameraFallsBackToBuiltIn() {
        XCTAssertEqual(
            MirrorCameraSelection.resolve(rememberedID: "usb", options: [phone, builtIn], systemDefaultID: "phone"),
            "builtin"
        )
    }

    func testWithoutBuiltInUsesSystemDefaultThenFirst() {
        XCTAssertEqual(MirrorCameraSelection.resolve(rememberedID: nil, options: [usb, phone], systemDefaultID: "phone"), "phone")
        XCTAssertEqual(MirrorCameraSelection.resolve(rememberedID: nil, options: [usb, phone], systemDefaultID: "gone"), "usb")
        XCTAssertNil(MirrorCameraSelection.resolve(rememberedID: "usb", options: [], systemDefaultID: nil))
    }

    func testHotPlugReconfiguresOnlyWhenTheChoiceChanges() {
        XCTAssertFalse(MirrorCameraSelection.shouldReconfigure(activeID: "usb", resolvedID: "usb"))
        XCTAssertTrue(MirrorCameraSelection.shouldReconfigure(activeID: "builtin", resolvedID: "usb"))
        XCTAssertTrue(MirrorCameraSelection.shouldReconfigure(activeID: "usb", resolvedID: nil))
    }
}