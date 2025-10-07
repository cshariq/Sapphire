//
//  OnboardingView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-09.
//
//

import SwiftUI
import CaptchaSolverInterface

struct OnboardingView: View {
    enum OnboardingStep {
        case welcome, permissions, musicChoice, spotifySetup, corePreferences, finish
    }

    @State private var currentStep: OnboardingStep = .welcome
    var onComplete: () -> Void

    @EnvironmentObject var settings: SettingsModel
    @StateObject var musicManager = MusicManager.shared

    @StateObject var spotifyPrivateAPI = SpotifyPrivateAPIManager.shared
    @State private var isPrivateApiLoading = false
    @State private var privateApiError: String?

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.indigo.opacity(0.3), Color.black]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            CustomWindowControls()
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .zIndex(2)

            ZStack {
                switch currentStep {
                case .welcome:
                    WelcomeStepView(onGetStarted: { currentStep = .permissions })
                        .transition(.opacity)
                case .permissions:
                    PermissionsStepView(onContinue: { currentStep = .musicChoice })
                        .transition(.opacity)
                case .musicChoice:
                    MusicChoiceStepView(onNext: {
                        if settings.settings.mediaSource == .spotify {
                            currentStep = .spotifySetup
                        } else {
                            currentStep = .corePreferences
                        }
                    })
                    .transition(.opacity)
                case .spotifySetup:
                    SpotifySetupStepView(
                        onNext: { currentStep = .corePreferences },
                        isLoading: $isPrivateApiLoading,
                        error: $privateApiError
                    )
                    .environmentObject(musicManager)
                    .transition(.opacity)
                case .corePreferences:
                    CorePreferencesStepView(onNext: { currentStep = .finish })
                        .transition(.opacity)
                case .finish:
                    FinishStepView(onComplete: onComplete)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: currentStep)

        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .sheet(item: $spotifyPrivateAPI.loginChallenge) { _ in
            if let presenter = try? CaptchaLoader.shared.loadPresenter() {
                presenter.loginView(
                    onComplete: { cookieProperties in
                        spotifyPrivateAPI.completeLoginAfterWebViewSuccess(with: cookieProperties)
                        spotifyPrivateAPI.loginChallenge = nil
                        isPrivateApiLoading = false
                    },
                    onCancel: {
                        privateApiError = "Login was cancelled by the user."
                        spotifyPrivateAPI.loginChallenge = nil
                        isPrivateApiLoading = false
                    }
                )
            } else {
                VStack(spacing: 15) {
                    Text("Login Error").font(.largeTitle)
                    Text("Could not load the login solver component. Please try again later.").multilineTextAlignment(.center)
                    Button("Close") {
                        spotifyPrivateAPI.loginChallenge = nil
                        isPrivateApiLoading = false
                        privateApiError = "Failed to load login component."
                    }
                }
                .frame(width: 300, height: 200)
            }
        }
    }
}

// MARK: - Step Views

private struct WelcomeStepView: View {
    var onGetStarted: () -> Void

    @State private var isHoveringGetStarted = false

    private var buttonGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 249/255, green: 165/255, blue: 154/255),
                Color(red: 255/255, green: 197/255, blue: 158/255),
                Color(red: 255/255, green: 247/255, blue: 174/255)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("Welcome to Sapphire").font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
            Text("A new way to experience your Mac's notch.\nLet's get you set up.").font(.title3).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
            Spacer()

            OnboardingButton(title: "Get Started", action: onGetStarted)
        }
    }
}

private struct PermissionsStepView: View {
    @StateObject private var permissionsManager = PermissionsManager.shared
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Permissions").font(.largeTitle.weight(.bold)).padding(.top, 40).padding(.bottom, 10)
            Text("Sapphire needs a few permissions for its core features. Your data is never collected or sent anywhere.").font(.body).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal, 50).padding(.bottom, 30)

            ScrollView {
                VStack(spacing: 25) {
                    PermissionSectionView(title: "Required", permissions: permissionsManager.requiredPermissions, manager: permissionsManager)
                    PermissionSectionView(title: "Recommended", description: "These permissions enable major features like widgets and live activities.", permissions: permissionsManager.recommendedPermissions, manager: permissionsManager)
                    PermissionSectionView(title: "Optional", description: "These permissions enable minor or cosmetic features.", permissions: permissionsManager.optionalPermissions, manager: permissionsManager)
                }.padding(.horizontal, 50)
            }

            Spacer()

            OnboardingButton(title: "Continue", action: onContinue)
                .disabled(!permissionsManager.areAllRequiredPermissionsGranted)
                .animation(.easeInOut, value: permissionsManager.areAllRequiredPermissionsGranted)
        }
        .onAppear { permissionsManager.checkAllPermissions() }
    }
}

private struct MusicChoiceStepView: View {
    @EnvironmentObject var settings: SettingsModel
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Music Service").font(.largeTitle.weight(.bold))
            Text("What do you primarily use for music? This helps Sapphire integrate better with your controls.").font(.title3).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)

            VStack(spacing: 15) {
                MusicServiceButton(title: "Apple Music", icon: "apple_logo", isSelected: settings.settings.mediaSource == .appleMusic) {
                    settings.settings.mediaSource = .appleMusic
                    onNext()
                }
                MusicServiceButton(title: "Spotify", icon: "spotify_logo", isSelected: settings.settings.mediaSource == .spotify) {
                    settings.settings.mediaSource = .spotify
                    onNext()
                }
                MusicServiceButton(title: "Other / None", icon: "music.note", isSelected: settings.settings.mediaSource == .system) {
                    settings.settings.mediaSource = .system
                    onNext()
                }
            }
            .padding()

            Spacer()
        }
    }
}

private struct SpotifySetupStepView: View {
    @EnvironmentObject var musicManager: MusicManager
    var onNext: () -> Void
    @Binding var isLoading: Bool
    @Binding var error: String?

    private func handlePrivateApiLogin() {
        error = nil
        isLoading = true
        musicManager.spotifyPrivateAPI.login()
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Spotify Setup").font(.largeTitle.weight(.bold))
            Text("Log in to enable enhanced features like liking tracks and skipping ads directly from the notch.").font(.title3).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)

            VStack(alignment: .center, spacing: 15) {
                if musicManager.isPrivateAPIAuthenticated {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").font(.title).foregroundColor(.green)
                        Text("Logged in successfully!").font(.headline)
                    }
                } else {
                    Text("Private API Login").font(.headline)
                    Text("This method works for both Free and Premium users. Use at your own risk.").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)

                    if isLoading {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Logging in...").font(.caption).foregroundColor(.secondary)
                        }.frame(height: 40)
                    } else {
                        Button("Log In with Spotify", action: handlePrivateApiLogin)
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .frame(height: 40)
                    }

                    if let error = error {
                        Text(error).font(.caption).foregroundColor(.red).padding(.top, 4)
                    }
                }
            }
            .padding()
            .modifier(OnboardingContainerModifier())

            Spacer()

            if musicManager.isPrivateAPIAuthenticated {
                OnboardingButton(title: "Continue", action: onNext)
            } else if !isLoading {
                Button("Skip for Now", action: onNext)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 50)
            } else {
                OnboardingButton(title: "Continue", action: {}).hidden().padding(.bottom, 50)
            }
        }
    }
}

private struct CorePreferencesStepView: View {
    @EnvironmentObject var settings: SettingsModel
    var onNext: () -> Void

    private var showHudsBinding: Binding<Bool> {
        Binding(
            get: { settings.settings.enableVolumeHUD && settings.settings.enableBrightnessHUD },
            set: { newValue in
                settings.settings.enableVolumeHUD = newValue
                settings.settings.enableBrightnessHUD = newValue
            }
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Quick Setup").font(.largeTitle.weight(.bold))
            Text("A few final preferences to personalize your experience. You can change these any time in Settings.").font(.title3).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)

            VStack(spacing: 15) {
                ModernOnboardingRow(iconName: "sparkles.tv", iconColor: .cyan, title: "Show Custom HUDs", description: "Replace the default volume and brightness indicators.") {
                    Toggle("", isOn: showHudsBinding).labelsHidden()
                }

                ModernOnboardingRow(iconName: "thermometer.sun.fill", iconColor: .orange, title: "Temperature Unit", description: "Choose your preferred unit for weather forecasts.") {
                    Picker("", selection: $settings.settings.weatherUseCelsius) {
                        Text("°C").tag(true)
                        Text("°F").tag(false)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 100)
                }

                ModernOnboardingRow(iconName: "bolt.horizontal.circle.fill", iconColor: .purple, title: "Launch at Login", description: "Start Sapphire automatically when you log into your Mac.") {
                    Toggle("", isOn: $settings.settings.launchAtLogin).labelsHidden()
                }
            }
            .padding(50)

            Spacer()
            OnboardingButton(title: "Continue", action: onNext)
        }
    }
}

private struct FinishStepView: View {
    var onComplete: () -> Void
    @StateObject private var updateChecker = UpdateChecker()

    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
    }

    var body: some View {
        VStack(spacing: 15) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text("You're All Set!").font(.largeTitle.weight(.bold))

            Text("Version \(currentAppVersion)").foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Link(destination: URL(string: "https://cshariq.github.io/Sapphire-Website/")!) {
                    Image(systemName: "link").resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18).foregroundColor(.white).padding(6).background(Color.blue).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(PlainButtonStyle())

                Link(destination: URL(string: "https://github.com/cshariq/Sapphire")!) {
                    Image("github_logo").resizable().renderingMode(.template).aspectRatio(contentMode: .fit).frame(width: 18, height: 18).foregroundColor(.white).padding(6).background(Color.black).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(PlainButtonStyle())

                Link(destination: URL(string: "https://discord.gg/TdRjC2kNnU")!) {
                    Image("discord_logo").resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18).padding(6).background(Color(red: 0.35, green: 0.40, blue: 0.95)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(PlainButtonStyle())
            }

            OnboardingUpdateStatusView(updateChecker: updateChecker)
                .padding(.top)

            Spacer()
            OnboardingButton(title: "Finish Setup", action: onComplete)

            Text("© 2025 Shariq Charolia. All rights reserved.")
                .font(.caption).foregroundStyle(.tertiary).padding(.bottom, 20)
        }
        .onAppear {
            updateChecker.checkForUpdates()
        }
    }
}

// MARK: - Reusable Components

private struct OnboardingUpdateStatusView: View {
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        Group {
            switch updateChecker.status {
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking for updates...").foregroundStyle(.secondary)
                }
            case .upToDate:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("You are up to date!").foregroundStyle(.secondary)
                }
            case .available(let version, _):
                VStack(spacing: 8) {
                    Text("Version \(version) is available!").font(.headline)
                    Link(destination: URL(string: "https://github.com/cshariq/Sapphire/releases")!) {
                        Text("Download from GitHub")
                    }.buttonStyle(.bordered).tint(.accentColor)
                }
            case .error(let message):
                 HStack(spacing: 8) {
                    Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
                    Text(message).foregroundStyle(.secondary).lineLimit(1)
                }
            default: // Don't show downloading/installing states in onboarding for simplicity
                EmptyView()
            }
        }
        .animation(.easeInOut, value: updateChecker.status)
        .frame(minHeight: 40)
    }
}

private struct ModernOnboardingRow<Content: View>: View {
    let iconName: String
    let iconColor: Color
    let title: String
    let description: String
    let content: Content

    init(iconName: String, iconColor: Color, title: String, description: String, @ViewBuilder content: () -> Content) {
        self.iconName = iconName
        self.iconColor = iconColor
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: iconName)
                .font(.title2.weight(.semibold))
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline.weight(.bold))
                Text(description).font(.callout).foregroundColor(.secondary)
            }
            Spacer()
            content
        }
        .padding(16)
        .background(.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

private struct OnboardingButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline).fontWeight(.semibold)
                .foregroundColor(isEnabled ? .black.opacity(0.8) : .gray)
                .padding(.horizontal, 60).padding(.vertical, 12)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: isEnabled ? [Color(red: 154/255, green: 249/255, blue: 165/255), Color(red: 174/255, green: 255/255, blue: 247/255)] : [.gray.opacity(0.5)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 50)
    }
}

private struct MusicServiceButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @ViewBuilder
    private var iconView: some View {
        if icon == "music.note" {
            Image(systemName: icon)
                .resizable()
                .renderingMode(.template)
                .foregroundColor(.white)
        } else {
            Image(icon)
                .resizable()
                .renderingMode(.original)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                iconView
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                Text(title).font(.headline)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                }
            }
            .padding()
            .modifier(OnboardingContainerModifier(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingContainerModifier: ViewModifier {
    var isSelected: Bool = false
    func body(content: Content) -> some View {
        content
            .background(.black.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(isSelected ? Color.accentColor : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1))
            .padding(.horizontal, 50)
    }
}

private struct PermissionSectionView: View {
    let title: String
    var description: String? = nil
    let permissions: [PermissionItem]
    @ObservedObject var manager: PermissionsManager

    var body: some View {
        if !permissions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.semibold))
                if let description = description {
                    Text(description).font(.caption).foregroundColor(.secondary).padding(.bottom, 8)
                }
                VStack(spacing: 15) {
                    ForEach(permissions) { permission in PermissionRowView(permission: permission, manager: manager) }
                }
            }
        }
    }
}

private struct PermissionRowView: View {
    let permission: PermissionItem
    @ObservedObject var manager: PermissionsManager

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: permission.iconName).font(.title2).frame(width: 40, height: 40).background(permission.iconColor.opacity(0.2)).clipShape(Circle()).foregroundColor(permission.iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(.headline)
                Text(permission.description).font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            let status = manager.status(for: permission.type)
            switch status {
            case .granted: Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green)
            case .denied: Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.red)
            case .notRequested: Button("Request") { manager.requestPermission(permission.type) }.buttonStyle(.bordered).tint(.accentColor)
            }
        }
        .padding().background(.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

private struct CustomWindowControls: View {
    @Environment(\.window) private var window: NSWindow?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { window?.close() }) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold, design: .rounded)) }.buttonStyle(TrafficLightButtonStyle(color: .red, isHovering: isHovering))
            Button(action: { window?.miniaturize(nil) }) { Image(systemName: "minus").font(.system(size: 9, weight: .bold, design: .rounded)) }.buttonStyle(TrafficLightButtonStyle(color: .yellow, isHovering: isHovering))
            Button(action: { window?.zoom(nil) }) { Image(systemName: "plus").font(.system(size: 9, weight: .bold, design: .rounded)) }.buttonStyle(TrafficLightButtonStyle(color: .green, isHovering: isHovering))
        }
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.1)) { isHovering = hovering } }
    }
}