//
//  FaceIDViews.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import SwiftUI
import AVFoundation

private struct FaceIDPulseRing: NSViewRepresentable {
    let color: NSColor
    let lineWidth: CGFloat
    let endScale: CGFloat
    let duration: CFTimeInterval

    func makeNSView(context: Context) -> FaceIDPulseRingView {
        FaceIDPulseRingView()
    }

    func updateNSView(_ nsView: FaceIDPulseRingView, context: Context) {
        nsView.configure(
            color: color,
            lineWidth: lineWidth,
            endScale: endScale,
            duration: duration
        )
    }
}

private final class FaceIDPulseRingView: NSView {
    private static let animationKey = "faceIDPulse"
    private let ringLayer = CAShapeLayer()
    private var endScale: CGFloat = 1.05
    private var duration: CFTimeInterval = 1.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        ringLayer.fillColor = NSColor.clear.cgColor
        layer?.addSublayer(ringLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(color: NSColor, lineWidth: CGFloat, endScale: CGFloat, duration: CFTimeInterval) {
        let animationChanged = self.endScale != endScale || self.duration != duration
        self.endScale = endScale
        self.duration = duration

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.strokeColor = color.cgColor
        ringLayer.lineWidth = lineWidth
        CATransaction.commit()

        if animationChanged {
            ringLayer.removeAnimation(forKey: Self.animationKey)
        }
        if window != nil { startAnimationIfNeeded() }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.frame = bounds
        let inset = ringLayer.lineWidth / 2
        ringLayer.path = CGPath(
            ellipseIn: bounds.insetBy(dx: inset, dy: inset),
            transform: nil
        )
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            ringLayer.removeAnimation(forKey: Self.animationKey)
        } else {
            startAnimationIfNeeded()
        }
    }

    private func startAnimationIfNeeded() {
        guard ringLayer.animation(forKey: Self.animationKey) == nil else { return }

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = endScale

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1
        opacity.toValue = 0

        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = duration
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 60, preferred: 60)
        ringLayer.add(group, forKey: Self.animationKey)
    }
}

// MARK: - Camera Live View
struct CameraView: NSViewRepresentable {
    var cameraController: CameraController

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true

        let previewLayer = cameraController.makePreviewLayer()
        view.layer = previewLayer

        previewLayer.frame = view.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let previewLayer = nsView.layer as? AVCaptureVideoPreviewLayer {
            cameraController.applyMirroring(to: previewLayer)
            cameraController.applyRotation(to: previewLayer)
        }
    }
}

// MARK: - FaceID Registration View
struct FaceIDRegistrationView: View {
    @ObservedObject var cameraController: CameraController
    @Environment(\.presentationMode) var presentationMode

    let profileName: String
    @State private var displayedHoldProgress = 0.0

    private var isRegistered: Bool { cameraController.appState == .registeredAndIdle }
    private var registrationProgress: Double { cameraController.registrationProgress }
    private var instructionText: String { isRegistered ? "Registration Complete!" : cameraController.userInstruction }

    private var isAskExtended: Bool {
        if case .registering(let step) = cameraController.appState, step == .askExtended { return true }
        return false
    }

    private var overlayColor: Color {
        if case .registering(let step) = cameraController.appState {
            if step == .finalizing { return .purple }
            if step == .askExtended { return .orange }
            return .blue
        }
        return isRegistered ? .green : .blue
    }

    var body: some View {
        ZStack {
            RadialGradient(gradient: Gradient(colors: [Color(red: 0.1, green: 0.1, blue: 0.2), .black]), center: .center, startRadius: 50, endRadius: 400)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                HStack {
                    Text("Registering \(profileName)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    }.buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20).padding(.top, 20)

                Spacer()

                ZStack {
                    CameraView(cameraController: cameraController)
                        .frame(width: 300, height: 300)
                        .clipShape(Circle())
                        .blur(radius: isAskExtended ? 15 : 0)
                        .scaleEffect(isAskExtended ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.5), value: isAskExtended)

                    Circle()
                        .trim(from: 0, to: CGFloat(registrationProgress))
                        .stroke(overlayColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 300, height: 300)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.22), value: registrationProgress)

                    if !isRegistered && !isAskExtended {
                        Circle()
                            .stroke(Color.white.opacity(0.14), lineWidth: 6)
                            .frame(width: 276, height: 276)
                    }

                    if displayedHoldProgress > 0 && displayedHoldProgress < 1.0 && !isRegistered && !isAskExtended {
                        Circle()
                            .trim(from: 0, to: CGFloat(displayedHoldProgress))
                            .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 276, height: 276)
                            .rotationEffect(.degrees(-90))

                        VStack {
                            Spacer()
                            Text("Hold Still")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                                .clipShape(Capsule())
                                .padding(.bottom, 35)
                        }
                        .frame(width: 300, height: 300)
                    }

                    if !isRegistered && !isAskExtended {
                        FaceIDPulseRing(
                            color: NSColor(overlayColor.opacity(0.5)),
                            lineWidth: 8,
                            endScale: 1.05,
                            duration: 1.5
                        )
                            .frame(width: 300, height: 300)
                    }

                    if isAskExtended {
                        VStack(spacing: 14) {
                            Image(systemName: "faceid")
                                .font(.system(size: 42))
                                .foregroundStyle(.blue)

                            Text("Basic Setup Complete")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text("Capture more angles for better accuracy with glasses and varying lighting.")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)

                            HStack(spacing: 12) {
                                Button("Skip") {
                                    cameraController.skipExtendedRegistration()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)

                                Button("Continue") {
                                    cameraController.acceptExtendedRegistration()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                                .tint(.blue)
                            }
                            .padding(.top, 4)
                        }
                        .padding(20)
                        .frame(width: 260)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Color.black.opacity(0.15), radius: 10, y: 5)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.vertical, 30)

                Group {
                    if isRegistered {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50, weight: .bold))
                            .foregroundColor(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else if isAskExtended {
                        Color.clear
                    } else {
                        VStack(spacing: 16) {
                            if cameraController.isExtendedPhase {
                                HStack(spacing: 10) {
                                    poseIndicator(label: "Up", key: "up")
                                    poseIndicator(label: "Down", key: "down")
                                    poseIndicator(label: "Tilt L", key: "tiltLeft")
                                    poseIndicator(label: "Tilt R", key: "tiltRight")
                                }
                                HStack(spacing: 10) {
                                    poseIndicator(label: "Near", key: "closer")
                                    poseIndicator(label: "Far", key: "farther")
                                }
                            } else {
                                HStack(spacing: 10) {
                                    poseIndicator(label: "Front", key: "center")
                                    poseIndicator(label: "Left", key: "left")
                                    poseIndicator(label: "Right", key: "right")
                                }
                            }

                            Text(instructionText)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .frame(height: 50)
                                .transition(.opacity)
                        }
                    }
                }
                .frame(height: 150)
                Spacer()
            }
            .padding()
        }
        .onAppear {
            cameraController.startRegistration(forProfile: profileName)
        }
        .onDisappear { cameraController.cancelCurrentOperation() }
        .onChange(of: cameraController.holdProgress) { progress in
            withAnimation(.linear(duration: 0.12)) {
                displayedHoldProgress = min(max(progress, 0), 1)
            }
        }
        .onChange(of: cameraController.appState) { state in
            if case .registering(.scanning) = state { return }
            withAnimation(.easeOut(duration: 0.18)) {
                displayedHoldProgress = 0
            }
        }
        .onChange(of: isRegistered) { registered in
            if registered { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { presentationMode.wrappedValue.dismiss() } }
        }
    }

    @ViewBuilder
    private func poseIndicator(label: String, key: String) -> some View {
        let captured = cameraController.registrationPoseCaptured.contains(key)
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 2).frame(width: 28, height: 28)
                if captured { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(.green) }
            }
            Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundColor(captured ? .green : .white.opacity(0.7))
        }
        .frame(minWidth: 44)
    }
}

// MARK: - FaceID Unlock View Animation
struct FaceIDUnlockView: View {
    @State private var isUnlocked = false

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack {
                ZStack {
                    FaceIDPulseRing(
                        color: .systemGreen,
                        lineWidth: 4,
                        endScale: 1.2,
                        duration: 1
                    )
                    .frame(width: 96, height: 96)

                    Image(systemName: "faceid")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                        .scaleEffect(isUnlocked ? 1.2 : 1)
                        .rotationEffect(.degrees(isUnlocked ? 360 : 0))
                        .animation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0), value: isUnlocked)
                }

                if isUnlocked {
                    Text("Unlocked")
                        .font(.title)
                        .foregroundColor(.green)
                        .transition(.opacity)
                        .animation(.easeIn(duration: 0.5), value: isUnlocked)
                }
            }
        }
        .onTapGesture { withAnimation { isUnlocked.toggle() } }
    }
}