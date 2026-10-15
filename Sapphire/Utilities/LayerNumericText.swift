//
//  LayerNumericText.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07

import AppKit
import SwiftUI

struct LayerNumericText: NSViewRepresentable {
    let text: String
    let font: NSFont
    let color: NSColor
    var duration: CFTimeInterval = 0.3

    func makeNSView(context: Context) -> LayerNumericTextView {
        let view = LayerNumericTextView()
        view.update(text: text, font: font, color: color, duration: duration, animated: false)
        return view
    }

    func updateNSView(_ nsView: LayerNumericTextView, context: Context) {
        let animated = !context.transaction.disablesAnimations
        nsView.update(text: text, font: font, color: color, duration: duration, animated: animated)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LayerNumericTextView, context: Context) -> CGSize? {
        LayerNumericTextView.size(of: text, font: font)
    }
}

extension LayerNumericText {
    func textBaseline() -> some View {
        alignmentGuide(.lastTextBaseline) { dimensions in
            dimensions.height + font.descender
        }
        .alignmentGuide(.firstTextBaseline) { dimensions in
            dimensions.height + font.descender
        }
    }
}

final class LayerNumericTextView: NSView {
    private struct Slot {
        let character: Character
        let layer: CATextLayer
    }

    private var slots: [Slot] = []
    private var text = ""
    private var font = NSFont.systemFont(ofSize: 13)
    private var color = NSColor.white

    private static let blurName = "numericBlur"
    private static let maxBlurRadius: CGFloat = 3

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshContentsScale()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshContentsScale()
    }

    private func refreshContentsScale() {
        guard let scale = window?.backingScaleFactor, scale > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for slot in slots where slot.layer.contentsScale != scale { slot.layer.contentsScale = scale }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        positionSlots()
        CATransaction.commit()
    }

    private struct SizeKey: Hashable {
        let text: String
        let fontName: String
        let pointSize: CGFloat
    }

    private static var sizeCache: [SizeKey: CGSize] = [:]

    static func size(of text: String, font: NSFont) -> CGSize {
        let key = SizeKey(text: text, fontName: font.fontName, pointSize: font.pointSize)
        if let cached = sizeCache[key] { return cached }
        let width = attributed(text, font: font, color: .white).size().width
        let size = CGSize(width: ceil(width), height: ceil(font.ascender - font.descender + font.leading))
        if sizeCache.count > 512 { sizeCache.removeAll(keepingCapacity: true) }
        sizeCache[key] = size
        return size
    }

    private static func attributed(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }

    func update(text newText: String, font newFont: NSFont, color newColor: NSColor, duration: CFTimeInterval, animated: Bool) {
        let styleChanged = newFont != font || newColor != color
        font = newFont
        color = newColor
        guard newText != text || styleChanged || slots.isEmpty else { return }

        let oldText = text
        let oldSlots = slots
        text = newText
        let newCharacters = Array(newText)
        let shouldAnimate = animated && window != nil && !oldSlots.isEmpty
        let keepsUnchanged = !styleChanged && oldSlots.count == newCharacters.count

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var next: [Slot] = []
        var entering: [CALayer] = []
        for (index, character) in newCharacters.enumerated() {
            if keepsUnchanged, oldSlots[index].character == character {
                next.append(oldSlots[index])
            } else {
                let layer = makeLayer(for: character)
                self.layer?.addSublayer(layer)
                next.append(Slot(character: character, layer: layer))
                entering.append(layer)
            }
        }
        let kept = Set(next.map { ObjectIdentifier($0.layer) })
        let leaving = oldSlots.map(\.layer).filter { !kept.contains(ObjectIdentifier($0)) }
        slots = next
        positionSlots()

        if shouldAnimate {
            let down: CGFloat = (layer?.contentsAreFlipped() ?? true) ? 1 : -1
            let shift = keepsUnchanged ? font.pointSize * 0.6 * Self.direction(from: oldText, to: newText) * down : 0
            entering.forEach { animate($0, in: true, offset: shift, duration: duration) }
            leaving.forEach { animate($0, in: false, offset: -shift, duration: duration) }
            CATransaction.setCompletionBlock {
                leaving.forEach { $0.removeFromSuperlayer() }
                entering.forEach { $0.filters = nil }
            }
        } else {
            leaving.forEach { $0.removeFromSuperlayer() }
        }
        CATransaction.commit()
        invalidateIntrinsicContentSize()
    }

    private static func direction(from old: String, to new: String) -> CGFloat {
        guard let a = Double(old.filter { $0.isNumber || $0 == "." || $0 == "-" }),
              let b = Double(new.filter { $0.isNumber || $0 == "." || $0 == "-" }) else { return 1 }
        return b >= a ? 1 : -1
    }

    private func makeLayer(for character: Character) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = Self.attributed(String(character), font: font, color: color)
        layer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer.isWrapped = false
        layer.truncationMode = .none
        layer.alignmentMode = .left
        layer.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "transform": NSNull()]
        return layer
    }

    private func positionSlots() {
        let line = CTLineCreateWithAttributedString(Self.attributed(text, font: font, color: color))
        let height = Self.size(of: text, font: font).height
        var utf16Start = 0
        for slot in slots {
            let utf16End = utf16Start + String(slot.character).utf16.count
            let x0 = CTLineGetOffsetForStringIndex(line, utf16Start, nil)
            let x1 = CTLineGetOffsetForStringIndex(line, utf16End, nil)
            let frame = CGRect(x: x0, y: 0, width: max(1, x1 - x0) + 2, height: height)
            if slot.layer.frame != frame { slot.layer.frame = frame }
            utf16Start = utf16End
        }
    }

    private func blurFilter(radius: CGFloat) -> CIFilter? {
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.name = Self.blurName
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        return filter
    }

    private func animate(_ layer: CALayer, in entering: Bool, offset: CGFloat, duration: CFTimeInterval) {
        let move = CABasicAnimation(keyPath: "transform.translation.y")
        move.fromValue = entering ? offset : 0
        move.toValue = entering ? 0 : offset
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = entering ? 0 : 1
        fade.toValue = entering ? 1 : 0
        var animations: [CAAnimation] = [move, fade]
        if let blur = blurFilter(radius: 0) {
            layer.filters = [blur]
            let radius = CABasicAnimation(keyPath: "filters.\(Self.blurName).inputRadius")
            radius.fromValue = entering ? Self.maxBlurRadius : 0
            radius.toValue = entering ? 0 : Self.maxBlurRadius
            animations.append(radius)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if !entering {
            layer.opacity = 0
        }
        layer.add(group, forKey: entering ? "numericIn" : "numericOut")
    }
}