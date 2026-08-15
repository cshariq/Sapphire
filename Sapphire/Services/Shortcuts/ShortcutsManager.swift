//
//  ShortcutsManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11
//

import Foundation
import AppKit
import SwiftUI

@MainActor
class ShortcutsManager {
    static let shared = ShortcutsManager()

    private init() {}

    func runShortcut(id: String) {
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", id]

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    print("[ShortcutsManager] Successfully ran shortcut with ID '\(id)'.")
                } else {
                    print("[ShortcutsManager] Error running shortcut with ID '\(id)'. Process terminated with status \(process.terminationStatus).")
                }
            } catch {
                print("[ShortcutsManager] Failed to run process for shortcut ID '\(id)': \(error)")
            }
        }
    }

    func getIcon(for shortcutInfo: ShortcutInfo) -> NSImage {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()

        let nsColor = shortcutInfo.backgroundColor != nil ? NSColor(shortcutInfo.backgroundColor!.color) : color(for: shortcutInfo.name)
        nsColor.setFill()
        let path = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 64, height: 64), xRadius: 12, yRadius: 12)
        path.fill()

        let symbolName = shortcutInfo.systemImageName ?? findSymbol(for: shortcutInfo.name)

        if let finalSymbolName = symbolName,
           let symbolImage = NSImage(systemSymbolName: finalSymbolName, accessibilityDescription: nil) {

            let iconTintColor = shortcutInfo.iconColor != nil ? NSColor(shortcutInfo.iconColor!.color) : NSColor.white
            let config = NSImage.SymbolConfiguration(paletteColors: [iconTintColor])
                .applying(.init(pointSize: 25, weight: .black, scale: .large))

            let configuredImage = symbolImage.withSymbolConfiguration(config) ?? symbolImage

            let size = configuredImage.size
            let point = NSPoint(x: (64 - size.width) / 2, y: (64 - size.height) / 2)

            configuredImage.draw(at: point, from: CGRect.zero, operation: .sourceOver, fraction: 1.0)

        } else {
            let initials = getInitials(from: shortcutInfo.name)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 28, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let string = NSAttributedString(string: initials, attributes: attributes)
            let size = string.size()
            let point = NSPoint(x: (64 - size.width) / 2, y: (64 - size.height) / 2)
            string.draw(at: point)
        }

        image.unlockFocus()
        return image
    }

    private func getInitials(from name: String) -> String {
        let words = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let firstLetters = words.compactMap { $0.first }
        return String(firstLetters.prefix(2)).uppercased()
    }

    private func color(for name: String) -> NSColor {
        var hash: Int = 0
        for char in name.unicodeScalars {
            hash = Int(char.value) &+ (hash << 5) &- hash
        }
        let hue = CGFloat(abs(hash % 256)) / 256.0
        return NSColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1.0)
    }

    private func findSymbol(for name: String) -> String? {
        let lowercasedName = name.lowercased()

        let keywordMap: [String: String] = [
            // MARK: - Interface & General
            "home": "house.fill", "main": "house.fill", "dashboard": "house.fill",
            "settings": "gearshape.fill", "options": "gearshape.fill", "preferences": "slider.horizontal.3", "config": "gearshape.2.fill",
            "adjust": "slider.horizontal.3", "controls": "slider.horizontal.3",
            "menu": "line.3.horizontal", "list": "list.bullet", "grid": "square.grid.2x2.fill",
            "sidebar": "sidebar.left", "panel": "pano.fill",
            "search": "magnifyingglass", "find": "magnifyingglass", "lookup": "magnifyingglass", "explore": "magnifyingglass",
            "filter": "line.3.horizontal.decrease.circle.fill", "refine": "line.3.horizontal.decrease.circle.fill",
            "sort": "arrow.up.arrow.down", "arrange": "arrow.up.arrow.down",
            "add": "plus.circle.fill", "new": "plus.circle.fill", "create": "plus.square.fill", "plus": "plus",
            "remove": "minus.circle.fill", "subtract": "minus.circle.fill", "minus": "minus",
            "edit": "pencil", "modify": "pencil", "change": "pencil", "update": "pencil", "write": "square.and.pencil", "compose": "square.and.pencil",
            "save": "square.and.arrow.down.fill",
            "delete": "trash.fill", "trash": "trash.fill", "discard": "trash.fill", "remove item": "trash.fill", "bin": "trash.fill",
            "cancel": "xmark.circle.fill", "close": "xmark.circle.fill", "exit": "xmark.circle.fill", "dismiss": "xmark",
            "lock": "lock.fill", "secure": "lock.shield.fill", "unlock": "lock.open.fill",
            "key": "key.fill", "password": "key.fill",
            "info": "info.circle.fill", "about": "info.circle.fill", "details": "info.circle.fill",
            "help": "questionmark.circle.fill", "question": "questionmark.circle.fill", "support": "questionmark.circle.fill",
            "share": "square.and.arrow.up", "export": "square.and.arrow.up.fill",
            "import": "square.and.arrow.down",
            "action": "ellipsis.circle.fill", "more": "ellipsis",
            "power": "power", "shutdown": "power", "restart": "arrow.counterclockwise", "reboot": "power.circle.fill",
            "refresh": "arrow.clockwise", "reload": "arrow.clockwise",
            "undo": "arrow.uturn.backward", "redo": "arrow.uturn.forward",
            "app": "square.fill.on.square.fill", "window": "macwindow",
            "shortcut": "square.grid.3x1.folder.badge.plus",
            "view": "eye.fill", "show": "eye.fill", "visible": "eye.fill",
            "hide": "eye.slash.fill", "hidden": "eye.slash.fill",
            "history": "clock.arrow.circlepath", "versions": "square.stack.3d.down.right.fill",
            "widget": "square.dashed.inset.filled",
            "notification": "bell.fill", "alert": "bell.fill", "bell": "bell.fill",
            "toggle": "switch.2", "switch": "switch.2",
            "zoom in": "plus.magnifyingglass", "zoom out": "minus.magnifyingglass",
            "expand": "arrow.up.left.and.arrow.down.right", "fullscreen": "arrow.up.left.and.arrow.down.right",
            "collapse": "arrow.down.right.and.arrow.up.left", "exit fullscreen": "arrow.down.right.and.arrow.up.left",
            "launch": "rocket.fill",
            "tools": "wrench.and.screwdriver.fill", "build": "hammer.fill", "hammer": "hammer.fill", "wrench": "wrench.fill",
            "design": "ruler.fill", "ruler": "ruler.fill",
            "palette": "paintpalette.fill", "color": "eyedropper.halffull",
            "crop": "crop", "rotate": "rotate.right.fill", "flip": "arrow.left.and.right.righttriangle.left.righttriangle.right.fill",
            "layer": "square.3.layers.3d.down.right", "layers": "square.stack.3d.up.fill",
            "wand": "wand.and.rays", "magic": "wand.and.stars",

            // MARK: - Status & Symbols
            "check": "checkmark.circle.fill", "checkmark": "checkmark", "success": "checkmark.seal.fill",
            "done": "checkmark.seal.fill", "complete": "checkmark.circle.fill", "ok": "checkmark", "yes": "checkmark",
            "verified": "checkmark.shield.fill", "approved": "checkmark.seal.fill",
            "error": "xmark.octagon.fill", "failure": "xmark.octagon.fill", "wrong": "xmark.circle.fill", "no": "xmark",
            "denied": "nosign", "prohibited": "hand.raised.slash.fill",
            "warning": "exclamationmark.triangle.fill", "important": "exclamationmark.bubble.fill",
            "favorite": "star.fill", "star": "star.fill", "rate": "star.fill",
            "like": "heart.fill", "love": "heart.fill", "heart": "heart.fill",
            "flag": "flag.fill", "report": "flag.fill",
            "tag": "tag.fill", "label": "tag.fill",
            "bookmark": "bookmark.fill",
            "pin": "pin.fill",
            "loading": "hourglass", "pending": "hourglass", "waiting": "hourglass",
            "progress": "chart.bar.fill",
            "idea": "lightbulb.fill", "tip": "lightbulb.fill", "hint": "lightbulb.fill",
            "fire": "flame.fill", "trend": "chart.line.uptrend.xyaxis", "popular": "flame.fill",
            "growth": "arrow.up.right", "decline": "arrow.down.right",
            "blocked": "hand.raised.fill", "spam": "exclamationmark.bubble.fill",
            "puzzle": "puzzlepiece.extension.fill",
            "happy": "face.smiling", "sad": "face.dashed", "neutral": "face.smiling.inverse", "angry": "exclamationmark.bubble.fill",
            "confused": "questionmark.app.dashed",

            // MARK: - Text & Editing
            "text": "textformat", "font": "textformat.size", "type": "textformat.size", "typography": "textformat.size",
            "bold": "bold", "italic": "italic", "underline": "underline", "strikethrough": "strikethrough",
            "paragraph": "paragraphsign",
            "align left": "text.alignleft", "left align": "text.alignleft",
            "align center": "text.aligncenter", "center align": "text.aligncenter",
            "align right": "text.alignright", "right align": "text.alignright",
            "justify": "text.justify",
            "bullet list": "list.bullet", "numbered list": "list.number", "checklist": "checklist",
            "indent": "increase.indent", "outdent": "decrease.indent",
            "quote": "text.quote",
            "highlighter": "highlighter",
            "spellcheck": "textformat.abc.dottedunderline",
            "find text": "text.magnifyingglass", "replace": "arrow.left.arrow.right.square.fill",
            "cut": "scissors",
            "cursor": "cursorarrow", "keyboard": "keyboard",
            "command": "command", "option": "option", "shift": "shift.fill", "caps lock": "capslock.fill",

            // MARK: - Communication
            "message": "message.fill", "chat": "bubble.left.and.bubble.right.fill", "comment": "text.bubble.fill",
            "email": "envelope.fill", "mail": "envelope.fill",
            "phone": "phone.fill", "call": "phone.fill",
            "contact": "person.crop.circle.fill",
            "person": "person.fill", "user": "person.fill", "account": "person.circle.fill", "profile": "person.text.rectangle.fill",
            "people": "person.2.fill", "users": "person.3.fill",
            "group": "person.3.fill", "team": "person.3.fill", "community": "person.3.sequence.fill",
            "video call": "video.fill", "conference": "video.badge.plus",
            "inbox": "tray.fill",
            "send": "paperplane.fill",
            "reply": "arrowshape.turn.up.left.fill", "reply all": "arrowshape.turn.up.left.2.fill",
            "forward mail": "arrowshape.turn.up.right.fill",
            "broadcast": "antenna.radiowaves.left.and.right",
            "voicemail": "mic.circle.fill",

            // MARK: - Media & Audio
            "play": "play.fill", "start playing": "play.fill", "resume": "play.fill", "begin": "play.fill",
            "playing": "waveform", "now playing": "waveform",
            "pause": "pause.fill", "hold": "pause.fill",
            "stop": "stop.fill", "end": "stop.fill",
            "record": "record.circle.fill",
            "forward": "forward.fill", "fast forward": "forward.fill", "seek forward": "forward.fill",
            "backward": "backward.fill", "rewind": "backward.fill", "seek backward": "backward.fill",
            "skip": "forward.end.fill", "next": "forward.end.fill", "skip forward": "forward.end.fill",
            "previous": "backward.end.fill", "last": "backward.end.fill", "skip backward": "backward.end.fill",
            "shuffle": "shuffle", "random": "shuffle",
            "repeat": "repeat", "loop": "repeat", "repeat one": "repeat.1",
            "music": "music.note", "song": "music.note",
            "album": "opticaldisc", "artist": "music.mic",
            "playlist": "music.note.list", "queue": "music.note.list",
            "mic": "mic.fill", "microphone": "mic.fill",
            "volume": "speaker.wave.2.fill", "volume up": "speaker.wave.3.fill", "volume down": "speaker.wave.1.fill",
            "mute": "speaker.slash.fill",
            "photo": "photo.fill", "image": "photo.fill", "picture": "photo.fill",
            "gallery": "photo.on.rectangle.angled",
            "camera": "camera.fill", "take picture": "camera.fill",
            "screenshot": "camera.viewfinder", "capture": "camera.viewfinder",
            "video": "video.fill", "movie": "film.fill",
            "live": "video.badge.plus",
            "airplay": "airplayvideo", "cast": "airplayvideo", "stream": "airplayvideo",
            "headphones": "headphones", "earpods": "earpods",
            "podcast": "waveform.circle.fill",
            "audiobook": "books.vertical.fill",
            "captions": "captions.bubble.fill", "subtitles": "captions.bubble.fill",
            "speed": "gauge.high",

            // MARK: - Files & Documents
            "file": "doc.fill", "files": "doc.on.doc.fill",
            "document": "doc.text.fill", "documents": "doc.richtext.fill",
            "folder": "folder.fill", "directory": "folder.fill", "category": "folder.fill",
            "copy": "doc.on.doc.fill", "duplicate": "plus.square.on.square",
            "paste": "doc.on.clipboard.fill", "clipboard": "list.clipboard.fill",
            "archive": "archivebox.fill", "zip": "archivebox.fill", "compress": "archivebox.fill",
            "unarchive": "archivebox.circle.fill", "extract": "archivebox.circle.fill",
            "add folder": "folder.badge.plus", "remove folder": "folder.badge.minus", "new folder": "folder.badge.plus",
            "paperclip": "paperclip", "attachment": "paperclip",
            "link": "link", "url": "link",
            "print": "printer.fill",
            "draft": "pencil.line",
            "scan": "doc.viewfinder.fill",
            "page": "doc.fill",
            "combine": "arrow.down.app.fill", "merge": "arrow.triangle.merge", "split": "arrow.triangle.split.2x2.fill",

            // MARK: - Connectivity & Devices
            "network": "network", "wifi": "wifi", "bluetooth": "wave.3.right.circle.fill",
            "cellular": "cellularbars", "data": "chart.pie.fill", "signal": "antenna.radiowaves.left.and.right",
            "hotspot": "personalhotspot", "iphone": "iphone", "ipad": "ipad", "mac": "desktopcomputer",
            "laptop": "laptopcomputer", "watch": "applewatch", "tv": "tv.fill", "display": "display",
            "printer": "printer.fill", "scanner": "scanner.fill", "server": "server.rack",
            "cpu": "cpu.fill", "memory": "memorychip.fill", "disk": "opticaldiscdrive.fill", "drive": "externaldrive.fill",
            "cloud": "cloud.fill", "upload": "cloud.arrow.up.fill", "download": "cloud.arrow.down.fill",
            "mouse": "magicmouse.fill", "keyboard device": "keyboard.fill",

            // MARK: - Health & Fitness
            "activity": "figure.walk", "steps": "figure.walk.circle.fill", "run": "figure.run",
            "heartbeat": "waveform.path.ecg.rectangle.fill", "pulse": "waveform.path",
            "medical": "cross.case.fill", "hospital": "cross.fill", "pills": "pills.fill", "medicine": "pills.fill",
            "brain": "brain.head.profile", "lungs": "lungs.fill", "dna": "atom",
            "bandage": "bandage.fill", "stethoscope": "stethoscope",

            // MARK: - Commerce & Finance
            "cart": "cart.fill", "bag": "bag.fill", "buy": "cart.badge.plus", "sell": "tag.fill",
            "shop": "storefront.fill", "store": "storefront.fill",
            "credit card": "creditcard.fill", "payment": "creditcard.fill",
            "wallet": "wallet.pass.fill",
            "money": "dollarsign.circle.fill", "dollar": "dollarsign.circle.fill", "euro": "eurosign.circle.fill", "yen": "yensign.circle.fill",
            "gift": "gift.fill", "receipt": "receipt.fill", "invoice": "list.bullet.rectangle.portrait.fill",
            "barcode": "barcode.viewfinder", "qrcode": "qrcode.viewfinder",
            "price": "tag.fill", "sale": "percent", "discount": "percent",
            "delivery": "shippingbox.fill", "shipping": "shippingbox.fill",

            // MARK: - Location & Navigation
            "map": "map.fill", "location": "location.circle.fill", "navigate": "location.north.line.fill",
            "globe": "globe", "compass": "safari.fill", "direction": "arrow.triangle.turn.up.right.diamond.fill",
            "route": "road.lanes", "car": "car.fill", "vehicle": "car.fill", "bus": "bus.fill",
            "train": "tram.fill", "subway": "tram.circle.fill", "plane": "airplane", "flight": "airplane",
            "bicycle": "bicycle", "walk": "figure.walk", "ferry": "ferry.fill", "scooter": "scooter",

            // MARK: - Gaming
            "game": "gamecontroller.fill", "controller": "gamecontroller.fill", "joystick": "dpad.fill",
            "dice": "dice.fill", "chance": "dice.fill", "trophy": "trophy.fill", "award": "trophy.fill",
            "achievement": "medal.fill", "medal": "medal.fill", "winner": "crown.fill", "crown": "crown.fill",

            // MARK: - Numbers
            "0": "0.circle.fill", "1": "1.circle.fill", "2": "2.circle.fill",
            "3": "3.circle.fill", "4": "4.circle.fill", "5": "5.circle.fill",
            "6": "6.circle.fill", "7": "7.circle.fill", "8": "8.circle.fill",
            "9": "9.circle.fill", "number": "number.circle.fill",

            // MARK: - Punctuation & Symbols
            "at": "at", "ampersand": "textformat.alt", "asterisk": "asterisk", "hash": "number", "hashtag": "number",

            "share photo": "square.and.arrow.up",
            "share file": "square.and.arrow.up",
            "share document": "square.and.arrow.up",
            "share text": "square.and.arrow.up",
            "add person": "person.badge.plus.fill",
            "remove person": "person.badge.minus.fill",
            "add user": "person.badge.plus.fill",
            "remove user": "person.badge.minus.fill",
            "add file": "doc.badge.plus",
            "remove file": "doc.badge.minus",
            "new message": "message.fill",
            "new email": "envelope.fill"
        ]

        for (keyword, symbolName) in keywordMap {
            if lowercasedName.contains(keyword) {
                return symbolName
            }
        }

        return nil
    }
}