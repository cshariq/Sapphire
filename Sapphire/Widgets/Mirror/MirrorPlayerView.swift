//
//  MirrorPlayerView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-11
//

import SwiftUI
import AVFoundation

struct MirrorPlayerView: View {
    @Environment(\.navigationStack) var navigationStack
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var camera = MirrorCameraManager.shared
    @State private var isFullscreen = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if camera.isLive {
                MirrorCameraPreviewView(
                    session: camera.session,
                    flipHorizontally: settings.settings.mirrorFlipHorizontally
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else {
                offlineState
            }
        }
        .frame(width: 560, height: 380)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .onAppear {
            if !camera.isLive {
                camera.start()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(camera.isLive ? .green : .secondary)
                Text("Mirror")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                if camera.isLive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .shadow(color: .green, radius: 3)
                }
            }

            Spacer(minLength: 8)

            if camera.isLive {
                Button {
                    settings.settings.mirrorFlipHorizontally.toggle()
                    camera.updateMirroring(flipHorizontally: settings.settings.mirrorFlipHorizontally)
                } label: {
                    Label("Flip", systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Flip horizontally")
            }

            Button {
                isFullscreen.toggle()
            } label: {
                Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(.black.opacity(0.25), in: Circle())
            .help("Toggle fullscreen")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var offlineState: some View {
        VStack(spacing: 16) {
            Image(systemName: camera.isDenied ? "camera.slash" : "camera")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            VStack(spacing: 4) {
                Text(camera.isDenied ? "Camera Access Denied" : (camera.isError ? "Camera Unavailable" : "Camera Off"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(offlineMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if camera.isDenied {
                Button("Open Privacy Settings") {
                    camera.openSystemPrivacySettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            } else if camera.isError {
                Button("Retry") {
                    camera.start()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var offlineMessage: String {
        if camera.isDenied {
            return "Grant camera access in System Settings → Privacy & Security → Camera to use Mirror."
        } else if camera.isError {
            return camera.errorMessage ?? "No suitable camera found or camera in use by another app."
        } else {
            return "Tap the compact widget to start the camera, then click again to expand."
        }
    }
}