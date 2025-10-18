//
//  FaceIDRegistrationView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-26
//

import SwiftUI

struct FaceIDRegistrationView: View {
    @ObservedObject var cameraController: CameraController
    @Environment(\.presentationMode) var presentationMode

    let profileName: String

    @State private var isPulsating = false

    private var isRegistered: Bool {
        cameraController.appState == .registeredAndIdle
    }

    private var registrationProgress: Double {
        cameraController.registrationProgress
    }

    private var instructionText: String {
        if isRegistered {
            return "Registration Complete!"
        }
        return cameraController.userInstruction
    }

    private var overlayColor: Color {
        if case .registering(let step) = cameraController.appState {
            return step == .finalizing ? .purple : .blue
        }
        return isRegistered ? .green : .blue
    }

    var body: some View {
        ZStack {
            RadialGradient(
                gradient: Gradient(colors: [Color(red: 0.1, green: 0.1, blue: 0.2), .black]),
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                HStack {
                    Text("Registering \(profileName)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .background(Color.clear)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer()

                ZStack {
                    CameraView(session: cameraController.captureSession)
                        .frame(width: 300, height: 300)
                        .clipShape(Circle())
                        .shadow(radius: 10)

                    Circle()
                        .trim(from: 0, to: CGFloat(registrationProgress))
                        .stroke(overlayColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 300, height: 300)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring().speed(0.5), value: registrationProgress)

                    if !isRegistered {
                        Circle()
                            .stroke(overlayColor.opacity(0.5), lineWidth: 8)
                            .frame(width: 300, height: 300)
                            .scaleEffect(isPulsating ? 1.05 : 1.0)
                            .opacity(isPulsating ? 0 : 1)
                            .animation(
                                .easeInOut(duration: 1.5).repeatForever(autoreverses: false),
                                value: isPulsating
                            )
                    }
                }
                .padding(.vertical, 30)

                Group {
                    if isRegistered {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50, weight: .bold))
                            .foregroundColor(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text(instructionText)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .frame(height: 100)

                Spacer()
            }
            .padding()
        }
        .onAppear {
            cameraController.startRegistration(forProfile: profileName)
            isPulsating = true
        }
        .onDisappear {
            cameraController.cancelCurrentOperation()
        }
        .onChange(of: isRegistered) { registered in
            if registered {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
}