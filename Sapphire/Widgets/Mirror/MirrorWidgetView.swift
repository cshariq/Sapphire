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
                .transition(.opacity)
            } else {
                idleView
                    .transition(.opacity)
            }
        }
        .frame(width: 130, height: 100)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(MaterialChartPalette.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(
                    camera.isLive ? Color.green.opacity(0.4) : MaterialChartPalette.outline,
                    lineWidth: camera.isLive ? 1.2 : 1
                )
        )
        .overlay(alignment: .topTrailing) {
            if camera.isLive {
                stopButton
                    .padding(10)
            }
        }
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
        .animation(.easeInOut(duration: 0.25), value: camera.isLive)
    }

    private var stopButton: some View {
        Button {
            camera.stop()
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(
                    Circle().stroke(.white.opacity(0.18), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help("Stop camera")
    }

    private var idleView: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo.opacity(0.5), Color.purple.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)
                Circle()
                    .stroke(.white.opacity(0.22), lineWidth: 1)
                    .frame(width: 46, height: 46)
                Image(systemName: camera.isDenied ? "camera.slash" : "camera")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text(camera.isDenied ? "Camera Denied" : (camera.isError ? "Unavailable" : "Tap to Start"))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
        }
    }
}