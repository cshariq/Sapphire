//
//  MirrorPlayerView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-11
//

import SwiftUI
import AVFoundation
import AppKit

struct MirrorPlayerView: View {
    @Environment(\.navigationStack) var navigationStack
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var camera = MirrorCameraManager.shared

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ZStack {
                if camera.isLive {
                    MirrorCameraPreviewView(
                        session: camera.session,
                        flipHorizontally: settings.settings.mirrorFlipHorizontally,
                        rotationAngle: camera.effectivePreviewRotationAngle,
                        sessionEpoch: camera.sessionEpoch
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                } else {
                    offlineState
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 560, height: 380)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.22), Color.black.opacity(0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(MaterialChartPalette.outlineStrong, lineWidth: 1)
        )
        .onAppear {
            if camera.isLive {
                camera.restartPreviewIfNeeded()
            } else {
                camera.start()
            }
        }
        .onDisappear {
            MirrorCameraManager.shared.teardown()
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(camera.isLive ? Color.green.opacity(0.2) : Color.white.opacity(0.08))
                        .frame(width: 30, height: 30)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(camera.isLive ? Color.green : Color.secondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mirror")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    if camera.isLive {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 5, height: 5)
                            Text("Live")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.red.opacity(0.9))
                        }
                    } else {
                        Text(camera.isDenied ? "No access" : (camera.isError ? "Unavailable" : "Camera off"))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            if camera.isLive {
                iconButton(systemName: "arrow.left.arrow.right", help: "Flip horizontally") {
                    settings.settings.mirrorFlipHorizontally.toggle()
                    camera.updateMirroring(flipHorizontally: settings.settings.mirrorFlipHorizontally)
                }

                iconButton(systemName: "rotate.right", help: "Rotate camera") {
                    settings.settings.mirrorRotationMode = settings.settings.mirrorRotationMode.next
                }

                stopButton
            }

            iconButton(systemName: "arrow.up.left.and.arrow.down.right", help: "Fullscreen") {
                MirrorFullscreenWindowController.shared.present()
            }

            closeButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func iconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.28), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var stopButton: some View {
        Button {
            camera.stop()
        } label: {
            Label("Stop", systemImage: "stop.fill")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.red.opacity(0.85), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Turn camera off")
    }

    private var closeButton: some View {
        Button {
            camera.stop()
            if navigationStack.wrappedValue.count > 1 {
                navigationStack.wrappedValue.removeLast()
            } else {
                navigationStack.wrappedValue = [.defaultWidgets]
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.28), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Close and stop camera")
    }

    private var offlineState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo.opacity(0.45), Color.purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 1)
                    .frame(width: 84, height: 84)
                Image(systemName: camera.isDenied ? "camera.slash" : "camera")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
            }

            VStack(spacing: 6) {
                Text(camera.isDenied ? "Camera Access Denied" : (camera.isError ? "Camera Unavailable" : "Camera Off"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(offlineMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button {
                    camera.start()
                } label: {
                    Label("Turn On Camera", systemImage: "camera.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(camera.isDenied ? Color.red : Color.indigo)
                .disabled(camera.isDenied)

                if camera.isDenied {
                    Button("Open Privacy Settings") {
                        camera.openSystemPrivacySettings()
                    }
                    .buttonStyle(.bordered)
                } else if camera.isError {
                    Button("Retry") {
                        camera.start()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var offlineMessage: String {
        if camera.isDenied {
            return "Grant camera access in System Settings → Privacy & Security → Camera to use Mirror."
        } else if camera.isError {
            return camera.errorMessage ?? "No suitable camera found or camera in use by another app."
        } else {
            return "The camera is off. Turn it on to start a live mirror."
        }
    }
}

struct MirrorFullscreenView: View {
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var camera = MirrorCameraManager.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.isLive {
                MirrorCameraPreviewView(
                    session: camera.session,
                    flipHorizontally: settings.settings.mirrorFlipHorizontally,
                    rotationAngle: camera.effectivePreviewRotationAngle,
                    sessionEpoch: camera.sessionEpoch
                )
                .ignoresSafeArea()
            }

            VStack {
                HStack(spacing: 10) {
                    if camera.isLive {
                        HStack(spacing: 5) {
                            Circle().fill(Color.red).frame(width: 7, height: 7)
                            Text("LIVE")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
                    }

                    Spacer()

                    if camera.isLive {
                        Button {
                            settings.settings.mirrorFlipHorizontally.toggle()
                            camera.updateMirroring(flipHorizontally: settings.settings.mirrorFlipHorizontally)
                        } label: {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Flip horizontally")

                        Button {
                            settings.settings.mirrorRotationMode = settings.settings.mirrorRotationMode.next
                        } label: {
                            Image(systemName: "rotate.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Rotate camera")

                        Button {
                            camera.stop()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.85), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Turn camera off")
                    }

                    Button {
                        MirrorFullscreenWindowController.shared.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Exit fullscreen")
                }
                .padding(16)

                Spacer()

                if !camera.isLive {
                    Text(camera.isDenied ? "Camera access denied" : "Camera off")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
final class MirrorFullscreenWindowController {
    static let shared = MirrorFullscreenWindowController()
    private var window: NSWindow?
    private var escapeMonitor: Any?

    private init() {}

    func present() {
        if let window, window.isVisible {
            window.orderFrontRegardless()
            return
        }

        guard let screen = NSScreen.main else { return }

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        let hosting = NSHostingView(
            rootView: MirrorFullscreenView()
                .environmentObject(SettingsModel.shared)
        )
        window.contentView = hosting

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.dismiss()
            return nil
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func dismiss(destroy: Bool = false) {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        window?.orderOut(nil)
        if destroy {
            window?.contentView = nil
            window = nil
        }
    }
}