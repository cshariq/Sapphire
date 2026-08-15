//
//  RichTextEditor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI
import AppKit

final class RichTextViewBox: ObservableObject {
    weak var textView: NSTextView?
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    var textViewBox: RichTextViewBox
    var onEditingChanged: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if attributedText.length > 0 {
            textView.textStorage?.setAttributedString(attributedText)
        }

        scroll.documentView = textView
        context.coordinator.textView = textView
        textViewBox.textView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        textViewBox.textView = textView
        if !context.coordinator.isEditing,
           !textView.attributedString().isEqual(attributedText) {
            let selected = textView.selectedRanges
            textView.textStorage?.setAttributedString(attributedText)
            textView.selectedRanges = selected
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?
        var isEditing = false

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
            (NSApp.delegate as? AppDelegate)?.makeNotchWindowFocusable()
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            sync()
            (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus()
        }

        func textDidChange(_ notification: Notification) {
            sync()
            parent.onEditingChanged?()
        }

        private func sync() {
            guard let textView else { return }
            parent.attributedText = textView.attributedString()
        }
    }
}

struct RichTextToolbar: View {
    @ObservedObject var textViewBox: RichTextViewBox
    @Binding var attributedText: NSAttributedString
    @State private var selectedColor: Color = .primary

    var body: some View {
        HStack(spacing: 6) {
            formatButton("bold", tip: "Bold") { toggleTrait(.boldFontMask) }
            formatButton("italic", tip: "Italic") { toggleTrait(.italicFontMask) }
            formatButton("underline", tip: "Underline") { toggleUnderline() }
            formatButton("strikethrough", tip: "Strikethrough") { toggleStrikethrough() }
            Divider().frame(height: 16)
            ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 22)
                .onChange(of: selectedColor) { _, color in
                    applyColor(NSColor(color))
                }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func formatButton(_ systemName: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(MaterialChartPalette.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tip)
    }

    private var liveTextView: NSTextView? {
        textViewBox.textView ?? (NSApp.keyWindow?.firstResponder as? NSTextView)
    }

    private func toggleTrait(_ trait: NSFontTraitMask) {
        guard let textView = liveTextView else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else {
            let font = (textView.typingAttributes[.font] as? NSFont) ?? .systemFont(ofSize: 13)
            let manager = NSFontManager.shared
            let converted: NSFont
            if manager.traits(of: font).contains(trait) {
                converted = manager.convert(font, toNotHaveTrait: trait)
            } else {
                converted = manager.convert(font, toHaveTrait: trait)
            }
            textView.typingAttributes[.font] = converted
            return
        }
        textView.textStorage?.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? .systemFont(ofSize: 13)
            let manager = NSFontManager.shared
            let converted: NSFont
            if manager.traits(of: font).contains(trait) {
                converted = manager.convert(font, toNotHaveTrait: trait)
            } else {
                converted = manager.convert(font, toHaveTrait: trait)
            }
            textView.textStorage?.addAttribute(.font, value: converted, range: subrange)
        }
        attributedText = textView.attributedString()
    }

    private func toggleUnderline() {
        guard let textView = liveTextView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            let current = (textView.typingAttributes[.underlineStyle] as? Int) ?? 0
            textView.typingAttributes[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            return
        }
        let storage = textView.textStorage
        let current = storage?.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
        let next = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        storage?.addAttribute(.underlineStyle, value: next, range: range)
        attributedText = textView.attributedString()
    }

    private func toggleStrikethrough() {
        guard let textView = liveTextView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            let current = (textView.typingAttributes[.strikethroughStyle] as? Int) ?? 0
            textView.typingAttributes[.strikethroughStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            return
        }
        let storage = textView.textStorage
        let current = storage?.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
        let next = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        storage?.addAttribute(.strikethroughStyle, value: next, range: range)
        attributedText = textView.attributedString()
    }

    private func applyColor(_ color: NSColor) {
        guard let textView = liveTextView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            textView.typingAttributes[.foregroundColor] = color
            return
        }
        textView.textStorage?.addAttribute(.foregroundColor, value: color, range: range)
        attributedText = textView.attributedString()
    }
}