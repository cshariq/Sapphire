//
//  NotchSearchField.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI
import AppKit

struct NotchSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil
    var autofocus: Bool = false

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onSubmit { onSubmit?() }
            .onChange(of: isFocused) { _, focused in
                guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
                if focused {
                    appDelegate.makeNotchWindowFocusable()
                } else {
                    appDelegate.revertNotchWindowFocus()
                }
            }
            .onAppear {
                if autofocus {
                    DispatchQueue.main.async {
                        isFocused = true
                    }
                }
            }
            .onDisappear {
                if isFocused {
                    isFocused = false
                    (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus()
                }
            }
    }
}

struct NotchKeyboardFocusModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
                if focused {
                    appDelegate.makeNotchWindowFocusable()
                } else {
                    appDelegate.revertNotchWindowFocus()
                }
            }
            .onDisappear {
                if isFocused {
                    isFocused = false
                    (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus()
                }
            }
    }
}

extension View {
    func notchKeyboardFocus() -> some View {
        modifier(NotchKeyboardFocusModifier())
    }
}