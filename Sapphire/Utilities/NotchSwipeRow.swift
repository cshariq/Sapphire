//
//  NotchSwipeRow.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct NotchSwipeAction {
    let systemImage: String
    let tint: Color
    let handler: () -> Void
}

struct NotchSwipeRow<Content: View>: View {
    let leading: NotchSwipeAction?
    let trailing: NotchSwipeAction?
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var isSwipingHorizontally = false

    private let leadingThreshold: CGFloat = 72
    private let trailingThreshold: CGFloat = -72
    private let releaseAnimation = Animation.spring(response: 0.38, dampingFraction: 0.78)
    private let dragAnimation = Animation.interactiveSpring(response: 0.2, dampingFraction: 0.82, blendDuration: 0.08)

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if let leading {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(leading.tint)
                        .frame(width: max(0, offset))
                        .overlay(
                            Image(systemName: leading.systemImage)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(min(1, offset / 36))
                        )
                }
                Spacer(minLength: 0)
                if let trailing {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(trailing.tint)
                        .frame(width: max(0, -offset))
                        .overlay(
                            Image(systemName: trailing.systemImage)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(min(1, -offset / 36))
                        )
                }
            }

            content()
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { gesture in
                            if !isSwipingHorizontally {
                                let w = gesture.translation.width
                                let h = gesture.translation.height
                                if abs(w) > abs(h), abs(w) > 4 {
                                    isSwipingHorizontally = true
                                }
                            }
                            guard isSwipingHorizontally else { return }
                            var proposed = gesture.translation.width
                            if leading == nil { proposed = min(0, proposed) }
                            if trailing == nil { proposed = max(0, proposed) }
                            withAnimation(dragAnimation) { offset = proposed }
                        }
                        .onEnded { _ in
                            settle()
                        },
                    including: .subviews
                )
                #if os(macOS)
                .overlay(
                    NotchTrackpadSwipeCapture(
                        beginHorizontal: {
                            if !isSwipingHorizontally { isSwipingHorizontally = true }
                        },
                        changeHorizontal: { dx in
                            var proposed = offset - dx
                            if leading == nil { proposed = min(0, proposed) }
                            if trailing == nil { proposed = max(0, proposed) }
                            withAnimation(dragAnimation) { offset = proposed }
                        },
                        endHorizontal: {
                            settle()
                        }
                    )
                )
                #endif
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func settle() {
        defer { isSwipingHorizontally = false }
        if offset > leadingThreshold, let leading {
            leading.handler()
            withAnimation(releaseAnimation) { offset = 0 }
        } else if offset < trailingThreshold, let trailing {
            withAnimation(.easeIn(duration: 0.18)) { offset = -420 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                trailing.handler()
                offset = 0
            }
        } else {
            withAnimation(releaseAnimation) { offset = 0 }
        }
    }
}

#if os(macOS)
private struct NotchTrackpadSwipeCapture: NSViewRepresentable {
    let beginHorizontal: () -> Void
    let changeHorizontal: (CGFloat) -> Void
    let endHorizontal: () -> Void

    func makeNSView(context: Context) -> NSView {
        CaptureView(
            beginHorizontal: beginHorizontal,
            changeHorizontal: changeHorizontal,
            endHorizontal: endHorizontal
        )
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class CaptureView: NSView {
        let beginHorizontal: () -> Void
        let changeHorizontal: (CGFloat) -> Void
        let endHorizontal: () -> Void
        private var horizontalActive = false

        init(
            beginHorizontal: @escaping () -> Void,
            changeHorizontal: @escaping (CGFloat) -> Void,
            endHorizontal: @escaping () -> Void
        ) {
            self.beginHorizontal = beginHorizontal
            self.changeHorizontal = changeHorizontal
            self.endHorizontal = endHorizontal
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        required init?(coder: NSCoder) { nil }
        override var acceptsFirstResponder: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY

            if !horizontalActive {
                if abs(dx) > abs(dy), abs(dx) > 0.5 {
                    horizontalActive = true
                    beginHorizontal()
                } else {
                    nextResponder?.scrollWheel(with: event)
                    return
                }
            }

            if event.phase == .ended || event.momentumPhase == .ended || event.phase == .cancelled {
                horizontalActive = false
                endHorizontal()
                return
            }
            changeHorizontal(dx)
        }
    }
}
#endif

struct NotchCapsuleBackButtonContent: View {
    var body: some View {
        NotchCapsuleIconLabel(systemName: "chevron.left")
    }
}

struct NotchCapsuleIconLabel: View {
    let systemName: String
    var isActive: Bool = false
    var activeTint: Color = .white

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(isActive ? activeTint.opacity(0.95) : Color.white.opacity(0.92))
            .frame(width: 18, height: 18)
            .padding(4)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? activeTint.opacity(0.18) : Color.white.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isActive ? activeTint.opacity(0.35) : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
            )
    }
}

struct NotchCapsuleIconButton: View {
    let systemName: String
    var isActive: Bool = false
    var activeTint: Color = .white
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            NotchCapsuleIconLabel(
                systemName: systemName,
                isActive: isActive,
                activeTint: activeTint
            )
        }
        .buttonStyle(.plain)
        .help(help ?? "")
    }
}

@MainActor
final class NotchBackRouter {
    static let shared = NotchBackRouter()

    var intercept: (() -> Bool)?

    func handleBack() -> Bool {
        intercept?() ?? false
    }
}