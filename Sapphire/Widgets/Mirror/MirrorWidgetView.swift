//
//  MirrorWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-11
//

import SwiftUI

struct MirrorWidgetView: View {
    @Environment(\.navigationStack) var navigationStack
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var camera = MirrorCameraManager.shared

    var body: some View {
        ZStack {
            if camera.isLive {
                MirrorCameraPreviewView(
                    session: camera.session,
                    flipHorizontally: settings.settings.mirrorFlipHorizontally
                )
            } else {
                idleView
            }
        }
        .frame(width: 130, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if camera.isLive {
                if settings.settings.mirrorOpenOnClick {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        navigationStack.wrappedValue.append(.mirrorPlayer)
                    }
                }
            } else {
                camera.start()
            }
        }
        .contextMenu {
            if camera.isLive {
                Button("Stop Camera") { camera.stop() }
            } else if camera.isDenied {
                Button("Open Camera Privacy Settings") { camera.openSystemPrivacySettings() }
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 6) {
            Image(systemName: camera.isDenied ? "camera.slash" : "camera")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(camera.isDenied ? 0.4 : 0.6))
            Text(camera.isDenied ? "Camera Denied" : (camera.isError ? "Unavailable" : "Tap to Start"))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}