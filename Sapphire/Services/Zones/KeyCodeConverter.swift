//
//  KeyCodeConverter.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//

import AppKit
import Carbon.HIToolbox.Events
import CoreServices

let kVK_MissionControl: UInt16 = 160
let kVK_Launchpad: UInt16 = 131
let kVK_Dictation: UInt16 = 199

struct KeyboardShortcutHelper {
    static func description(for flags: NSEvent.ModifierFlags) -> String {
        var description = ""
        if flags.contains(.control) { description += "⌃" }
        if flags.contains(.option) { description += "⌥" }
        if flags.contains(.shift) { description += "⇧" }
        if flags.contains(.command) { description += "⌘" }
        return description
    }
}

struct KeyCodeTranslator {
    static let shared = KeyCodeTranslator()

    private let keyCodeToStringMap: [UInt16: String]
    private let stringToKeyCodeMap: [String: UInt16]

    private init() {
        var keyCodeMap: [UInt16: String] = [:]
        var stringMap: [String: UInt16] = [:]

        let specialKeys: [UInt16: String] = [
            UInt16(kVK_Space): "Space",
            UInt16(kVK_Return): "Enter",
            UInt16(kVK_Escape): "Escape",
            UInt16(kVK_Delete): "Delete",
            UInt16(kVK_Tab): "Tab",
            UInt16(kVK_LeftArrow): "←",
            UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑",
            UInt16(kVK_DownArrow): "↓",

            UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
            UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
            UInt16(kVK_F16): "F16", UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18",
            UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20",

            kVK_MissionControl: "Mission Control",
            kVK_Launchpad: "Launchpad",
            kVK_Dictation: "Dictation",
            UInt16(kVK_Function): "Globe / Fn"
        ]

        for (code, name) in specialKeys {
            keyCodeMap[code] = name
            stringMap[name.uppercased()] = code
        }

        self.keyCodeToStringMap = keyCodeMap
        self.stringToKeyCodeMap = stringMap
    }

    func string(for keyCode: UInt16, from event: NSEvent? = nil) -> String? {
        if let specialName = keyCodeToStringMap[keyCode] {
            return specialName
        }

        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer).takeUnretainedValue()
        let layout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        let maxChars = 4
        var actualChars = 0
        var chars = [UniChar](repeating: 0, count: maxChars)

        let status = UCKeyTranslate(layout,
                                    keyCode,
                                    UInt16(kUCKeyActionDown),
                                    0,
                                    UInt32(LMGetKbdType()),
                                    UInt32(kUCKeyTranslateNoDeadKeysBit),
                                    &deadKeyState,
                                    maxChars,
                                    &actualChars,
                                    &chars)

        if status == noErr && actualChars > 0 {
            return String(utf16CodeUnits: chars, count: actualChars).uppercased()
        }

        return nil
    }

    func keyCode(for keyString: String) -> UInt16? {
        if let specialKeyCode = stringToKeyCodeMap[keyString.uppercased()] {
            return specialKeyCode
        }
        return nil
    }
}