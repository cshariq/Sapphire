//
//  OnboardingView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-09.
//

import SwiftUI
import CaptchaSolverInterface
import AVKit

// MARK: - Main Onboarding View
struct OnboardingView: View {
    enum OnboardingStep {
        case welcome, permissions, helperInstallation, privacyPolicy, musicChoice, spotifySetup, batterySetup, corePreferences, lockScreenSetup, subscriptionOverview, finish
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
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                case .permissions:
                    PermissionsStepView(onContinue: { currentStep = .helperInstallation })
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))

                case .helperInstallation:
                    HelperInstallationStepView(onContinue: { currentStep = .privacyPolicy })
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))

                case .privacyPolicy:
                    PrivacyStepView(onContinue: { currentStep = .musicChoice })
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                case .musicChoice:
                    MusicChoiceStepView(onNext: {
                        if settings.settings.defaultMusicPlayer == .spotify {
                            currentStep = .spotifySetup
                        } else {
                            currentStep = .batterySetup
                        }
                    })
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                case .spotifySetup:
                    SpotifySetupStepView(
                        onNext: { currentStep = .batterySetup },
                        isLoading: $isPrivateApiLoading,
                        error: $privateApiError
                    )
                    .environmentObject(musicManager)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))

                case .batterySetup:
                    BatterySetupStepView(onNext: { currentStep = .corePreferences })
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))

                case .corePreferences:
                    CorePreferencesStepView(onNext: { currentStep = .lockScreenSetup })
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))

                case .lockScreenSetup:
                    LockScreenSetupStepView(onNext: { currentStep = .subscriptionOverview })
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))

                case .subscriptionOverview:
                    SubscriptionOverviewStepView(onNext: { currentStep = .finish })
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))

                case .finish:
                    FinishStepView(onComplete: onComplete)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.4), value: currentStep)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(width: 1200, height: 900)
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

private struct WelcomeStepView: View {
    var onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("Welcome to Sapphire")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text("A new way to experience your Mac's notch.\nLet's get you set up.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

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
            Text("Permissions")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .padding(.top, 40).padding(.bottom, 10)

            Text("Sapphire needs a few permissions for its core features.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 50)
                .padding(.bottom, 30)

            ScrollView {
                VStack(spacing: 25) {
                    PermissionSectionView(title: "Required", permissions: permissionsManager.requiredPermissions, manager: permissionsManager)
                    PermissionSectionView(title: "Recommended", permissions: permissionsManager.recommendedPermissions, description: "These permissions enable major features like widgets and live activities.", manager: permissionsManager)
                    PermissionSectionView(title: "Optional", permissions: permissionsManager.optionalPermissions, description: "These permissions enable minor or cosmetic features.", manager: permissionsManager)
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

private struct HelperInstallationStepView: View {
    @StateObject private var helperManager = HelperManager.shared
    var onContinue: () -> Void

    @State private var player: AVPlayer?
    @State private var playerObserver: Any?

    var body: some View {
        VStack(spacing: 0) {
            Text("Install Helper Service")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .padding(.top, 40).padding(.bottom, 10)

            Text("Sapphire uses a helper for advanced features like battery management and system integrations. This requires administrator approval to install.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 50)
                .padding(.bottom, 30)

            HStack(spacing: 15) {
                switch helperManager.status {
                case .enabled:
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green)
                    Text("Helper Installed Successfully")
                        .font(.headline)
                case .requiresApproval:
                    Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundColor(.yellow)
                    VStack(alignment: .leading) {
                        Text("Approval Required")
                            .font(.headline)
                        Text("Please enable in System Settings > Login Items.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                default:
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.red)
                    Text("Helper Not Installed")
                        .font(.headline)
                }

                Spacer()

                if helperManager.status != .enabled {
                    Button("Install") {
                        helperManager.installIfNeeded()
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                }
            }
            .padding()
            .background(.black.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .padding(.horizontal, 50)

            Spacer()

            OnboardingButton(title: "Continue", action: onContinue)
                .disabled(helperManager.status != .enabled)
                .animation(.easeInOut, value: helperManager.status)
        }
        .onAppear {
            helperManager.updateStatus()
//            setupPlayer()
        }
//        .onDisappear {
//            cleanupPlayer()
//        }
    }

    private func setupPlayer() {
//        guard let url = Bundle.main.url(forResource: "helper_install_demo", withExtension: "mp4") else {
//            print("Error: helper_install_demo.mp4 not found in app bundle.")
//            return
//        }

//        let newPlayer = AVPlayer(url: url)
//        newPlayer.isMuted = true
//        newPlayer.actionAtItemEnd = .none
//
//        playerObserver = NotificationCenter.default.addObserver(
//            forName: .AVPlayerItemDidPlayToEndTime,
//            object: newPlayer.currentItem,
//            queue: .main
//        ) { _ in
//            newPlayer.seek(to: .zero)
//            newPlayer.play()
//        }
//
//        self.player = newPlayer
//        self.player?.play()
        return
    }

    private func cleanupPlayer() {
        player?.pause()
        player = nil
        if let observer = playerObserver {
            NotificationCenter.default.removeObserver(observer)
            playerObserver = nil
        }
    }
}

private struct PrivacyStepView: View {
    var onContinue: () -> Void
    @State private var hasAgreed = false

    var body: some View {
        VStack(spacing: 15) {
            Spacer(minLength: 20)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.indigo)

            Text("Your Privacy Matters")
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text("We believe in transparency. Please review our data handling practices below.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 50)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PrivacySection(
                        title: "Data We Collect (Analytics)",
                        content: "To improve Sapphire, we collect completely anonymous, aggregated usage data. This helps us understand which features are popular, identify bugs, and make the app better for everyone."
                    )

                    PrivacySection(
                        title: "What This Includes:",
                        content: "• Feature usage frequency (e.g., how often a widget is used)\n• App version and macOS version\n• Anonymous crash reports"
                    )

                    PrivacySection(
                        title: "Data We NEVER Collect",
                        content: "We are committed to your privacy. We DO NOT automatically collect, store, or transmit any personal or sensitive information. This includes, but is not limited to:\n• Your name, email, or other personal identifiers\n• Screen contents or keyboard input\n• Application data from other apps"
                    )

                    PrivacySection(
                        title: "Data Storage & Third Parties",
                        content: "Anonymous data is processed by google for analytics. This data is always aggregated and cannot be used to identify you."
                    )
                }
                .padding(20)
                .padding(.vertical, 20)
                .background(.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white.opacity(0.1)))
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 60)
            .padding(.top, 20)

            Toggle(isOn: $hasAgreed) {
                Text("I have read and agree to the collection of anonymous usage data to help improve the app.")
                    .font(.callout)
            }
            .padding(.horizontal, 50)
            .padding(.top, 10)

            Spacer(minLength: 20)

            OnboardingButton(title: "Continue", action: onContinue)
                .disabled(!hasAgreed)
                .animation(.easeInOut, value: hasAgreed)
        }
    }

    private struct PrivacySection: View {
        let title: String, content: String
        var body: some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline).foregroundStyle(.primary); Text(content).font(.callout).foregroundStyle(.secondary).lineSpacing(4) } }
    }
}

private struct MusicChoiceStepView: View {
    @EnvironmentObject var settings: SettingsModel
    @State private var selection: DefaultMusicPlayer?
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Choose Your Music Service")
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text("Select your primary music player for the best integration.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            VStack(spacing: 15) {
                MusicServiceButton(title: "Apple Music", icon: "apple_logo", isSelected: selection == .appleMusic) {
                    selection = .appleMusic
                }
                MusicServiceButton(title: "Spotify", icon: "spotify_logo", isSelected: selection == .spotify) {
                    selection = .spotify
                }
            }
            .padding(50)

            Spacer()

            OnboardingButton(title: "Next", action: {
                if let finalSelection = selection {
                    settings.settings.defaultMusicPlayer = finalSelection
                    onNext()
                }
            })
            .disabled(selection == nil)
            .animation(.easeInOut, value: selection)
        }
        .onAppear {
            selection = settings.settings.defaultMusicPlayer
        }
    }
}

private struct SpotifySetupStepView: View {
    @EnvironmentObject var musicManager: MusicManager
    var onNext: () -> Void
    @Binding var isLoading: Bool
    @Binding var error: String?
    private func handlePrivateApiLogin() { error = nil; isLoading = true; musicManager.spotifyPrivateAPI.login() }
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Spotify Setup").font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Log in to enable enhanced features like liking tracks and skipping ads directly from the notch.").font(.title3).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
            VStack(alignment: .center, spacing: 15) {
                if musicManager.isPrivateAPIAuthenticated {
                    HStack(spacing: 10) { Image(systemName: "checkmark.circle.fill").font(.title).foregroundColor(.green); Text("Logged in successfully!").font(.headline) }
                } else {
                    Text("Private API Login").font(.headline)
                    Text("This method works for both Free and Premium users. Use at your own risk.").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    if isLoading {
                        VStack(spacing: 8) { ProgressView(); Text("Logging in...").font(.caption).foregroundColor(.secondary) }.frame(height: 40)
                    } else {
                        Button("Log In with Spotify", action: handlePrivateApiLogin).buttonStyle(.borderedProminent).tint(.green).controlSize(.large).frame(height: 40)
                    }
                    if let error = error { Text(error).font(.caption).foregroundColor(.red).padding(.top, 4) }
                }
            }.padding(25).background(.black.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1)).padding(50)
            Spacer()
            if musicManager.isPrivateAPIAuthenticated { OnboardingButton(title: "Continue", action: onNext) } else if !isLoading { Button("Skip for Now", action: onNext).buttonStyle(.plain).foregroundColor(.secondary).padding(.bottom, 50) } else { OnboardingButton(title: "Continue", action: {}).hidden().padding(.bottom, 50) }
        }
    }
}

private struct BatterySetupStepView: View {
    @EnvironmentObject var settings: SettingsModel
    var onNext: () -> Void

    private var chargeLimitBinding: Binding<Int> {
        Binding<Int>(
            get: { settings.settings.batteryChargeLimit },
            set: { settings.settings.batteryChargeLimit = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Intelligent Battery Management")
                .fontWeight(.bold)
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text("Protect your battery's health and extend its lifespan with these features.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 50)

            VStack(spacing: 15) {
                ModernOnboardingRow(iconName: "battery.100.bolt", iconColor: .green, title: "Set Charge Limit", description: "Prevent wear by stopping charging at a lower level. 80% is recommended.") {
                    Picker("", selection: chargeLimitBinding) {
                        Text("80%").tag(80)
                        Text("90%").tag(90)
                        Text("100%").tag(100)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }

                ModernOnboardingRow(iconName: "sailboat.fill", iconColor: .blue, title: "Enable Sailing Mode", description: "Reduces micro-charging cycles when the limit is reached.") {
                    Toggle("", isOn: $settings.settings.sailingModeEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                ModernOnboardingRow(iconName: "thermometer.medium", iconColor: .red, title: "Enable Heat Protection", description: "Pauses charging if the battery gets too hot.") {
                    Toggle("", isOn: $settings.settings.heatProtectionEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            .padding(50)

            Spacer()
            OnboardingButton(title: "Continue", action: onNext)
        }
    }
}

private struct CorePreferencesStepView: View {
    @EnvironmentObject var settings: SettingsModel
    var onNext: () -> Void
    private var showHudsBinding: Binding<Bool> { Binding(get: { settings.settings.enableVolumeHUD && settings.settings.enableBrightnessHUD }, set: { settings.settings.enableVolumeHUD = $0; settings.settings.enableBrightnessHUD = $0 }) }
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Quick Setup").font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Personalize your experience. You can change these any time in Settings.").font(.title3).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal, 50)
            VStack(spacing: 15) {
                ModernOnboardingRow(iconName: "sparkles.tv", iconColor: .cyan, title: "Show Custom HUDs", description: "Replace default volume & brightness indicators.") { Toggle("", isOn: showHudsBinding).labelsHidden().toggleStyle(.switch) }
                ModernOnboardingRow(iconName: "eye.fill", iconColor: .cyan, title: "Enable Eye Break Reminders", description: "Get reminded to look away from your screen periodically.") {
                    Toggle("", isOn: $settings.settings.eyeBreakLiveActivityEnabled).labelsHidden().toggleStyle(.switch)
                }
                ModernOnboardingRow(iconName: "thermometer.sun.fill", iconColor: .orange, title: "Temperature Unit", description: "Preferred unit for weather forecasts.") { Picker("", selection: $settings.settings.weatherUseCelsius) { Text("°C").tag(true); Text("°F").tag(false) }.pickerStyle(.segmented).labelsHidden().frame(width: 100) }
                ModernOnboardingRow(iconName: "bolt.horizontal.circle.fill", iconColor: .purple, title: "Launch at Login", description: "Start Sapphire automatically with your Mac.") { Toggle("", isOn: $settings.settings.launchAtLogin).labelsHidden().toggleStyle(.switch) }
            }.padding(50)
            Spacer()
            OnboardingButton(title: "Continue", action: onNext)
        }
    }
}

private struct LockScreenSetupStepView: View {
    @EnvironmentObject var settings: SettingsModel
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Lock Screen Features")
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text("Enhance your Mac's lock screen with live activities and widgets directly in the notch area.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 50)

            VStack(spacing: 15) {
                ModernOnboardingRow(iconName: "lock.display", iconColor: .red, title: "Enable on Lock Screen", description: "Show Sapphire's notch and features when your Mac is locked.") {
                    Toggle("", isOn: $settings.settings.lockScreenShowNotch).labelsHidden().toggleStyle(.switch)
                }

                VStack(spacing: 15) {
                    ModernOnboardingRow(iconName: "timer", iconColor: .cyan, title: "Show Live Activities", description: "Display timers, music, and more.") {
                        Toggle("", isOn: $settings.settings.lockScreenLiveActivityEnabled).labelsHidden().toggleStyle(.switch)
                    }

                    ModernOnboardingRow(iconName: "info.circle.fill", iconColor: .blue, title: "Show Info Widgets", description: "Display static info like weather or battery.") {
                        Toggle("", isOn: $settings.settings.lockScreenShowInfoWidget).labelsHidden().toggleStyle(.switch)
                    }
                }
                .disabled(!settings.settings.lockScreenShowNotch)
                .opacity(settings.settings.lockScreenShowNotch ? 1.0 : 0.5)
                .animation(.easeInOut, value: settings.settings.lockScreenShowNotch)
            }
            .padding(50)

            Spacer()
            OnboardingButton(title: "Continue", action: onNext)
        }
    }
}

private struct SubscriptionOverviewStepView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    var onNext: () -> Void

    @State private var showUpgradeSheet = false
    @State private var selectedCheckoutTier: SubscriptionTier = .basic

    private var currentTier: SubscriptionTier {
        subscriptionManager.activeTier
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Your Sapphire Plan")
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text("Link an account anytime in Settings to sync your subscription across devices.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 50)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.35), .indigo.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: subscriptionManager.isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.9))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(subscriptionManager.isSignedIn ? subscriptionManager.userDisplayName : "Guest Mode")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("Current plan: \(SubscriptionFeatureCatalog.tierDisplayName(currentTier))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, 50)

            HStack(alignment: .top, spacing: 14) {
                ForEach(SubscriptionFeatureCatalog.marketingTierHighlights(), id: \.tier) { highlight in
                    OnboardingPlanCard(
                        tier: highlight.tier,
                        perks: highlight.features,
                        isCurrent: highlight.tier == currentTier,
                        onUpgrade: onboardingTierRank(highlight.tier) > onboardingTierRank(currentTier)
                            ? { beginCheckout(for: highlight.tier) }
                            : nil
                    )
                }
            }
            .padding(.horizontal, 50)
            .frame(height: 390)

            if currentTier == .free {
                Text("Upgrade to Basic or higher for beta updates, Gemini Live, and more.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 50)

                Link("Upgrade on website instead", destination: URL(string: "https://cshariq.github.io/Sapphire-Website/")!)
                    .font(.caption)
                    .foregroundStyle(.purple)
            }

            Spacer()

            OnboardingButton(title: "Skip", action: onNext)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showUpgradeSheet, onDismiss: {
            Task { await subscriptionManager.bootstrap() }
        }) {
            NativePaymentSheetView(tier: selectedCheckoutTier, deviceCount: 1, isAddingOnly: false) {
                showUpgradeSheet = false
            }
            .frame(width: 820, height: 750)
        }
        .onAppear {
            Task { await subscriptionManager.bootstrap() }
        }
    }

    private func beginCheckout(for tier: SubscriptionTier) {
        selectedCheckoutTier = tier
        showUpgradeSheet = true
    }

    private func onboardingTierRank(_ tier: SubscriptionTier) -> Int {
        switch tier {
        case .free: return 0
        case .basic: return 1
        case .pro: return 2
        case .ultra: return 3
        }
    }
}

private struct OnboardingPlanCard: View {
    let tier: SubscriptionTier
    let perks: [String]
    let isCurrent: Bool
    var onUpgrade: (() -> Void)? = nil

    private var accent: Color {
        switch tier {
        case .basic: return Color(red: 0.35, green: 0.62, blue: 1.0)
        case .pro: return Color(red: 0.82, green: 0.45, blue: 0.98)
        case .ultra: return Color(red: 1.0, green: 0.58, blue: 0.22)
        default: return .gray
        }
    }

    private var tierIcon: String {
        switch tier {
        case .basic: return "sparkles"
        case .pro: return "bolt.fill"
        case .ultra: return "crown.fill"
        default: return "seal"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: tierIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(SubscriptionFeatureCatalog.tierDisplayName(tier))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        if isCurrent {
                            Text("CURRENT")
                                .font(.system(size: 8, weight: .black))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(accent.opacity(0.22), in: Capsule())
                                .foregroundStyle(accent)
                        }
                    }

                    Text(SubscriptionFeatureCatalog.marketingSubtitle(for: tier))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.45), accent.opacity(0.05)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(perks, id: \.self) { perk in
                    HStack(alignment: .top, spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(accent.opacity(0.14))
                                .frame(width: 18, height: 18)
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(accent)
                        }
                        .padding(.top, 1)

                        Text(perk)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 0)

            if let onUpgrade {
                Button(action: onUpgrade) {
                    Text("Get \(SubscriptionFeatureCatalog.tierDisplayName(tier))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .shadow(color: accent.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(isCurrent ? 0.14 : 0.06),
                                    Color.black.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            accent.opacity(isCurrent ? 0.75 : 0.28),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isCurrent ? 1.5 : 1
                )
        }
        .shadow(color: isCurrent ? accent.opacity(0.22) : Color.black.opacity(0.18), radius: isCurrent ? 16 : 8, y: 6)
    }
}

private struct FinishStepView: View {
    var onComplete: () -> Void
    @StateObject private var updateChecker = UpdateChecker.shared

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

            Text("You're All Set!")
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text("Version \(currentAppVersion)")
                .foregroundStyle(.secondary)

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
            OnboardingButton(title: "Explore Sapphire", action: onComplete)

            Text("© 2025 Shariq Charolia. All rights reserved.")
                .font(.caption).foregroundStyle(.tertiary).padding(.bottom, 20)
        }
        .onAppear {
            updateChecker.checkForUpdates()
        }
    }
}

private struct OnboardingUpdateStatusView: View {
    @ObservedObject var updateChecker: UpdateChecker
    var body: some View {
        Group {
            switch updateChecker.status {
            case .checking: HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking for updates...").foregroundStyle(.secondary) }
            case .upToDate: HStack(spacing: 8) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("You are up to date!").foregroundStyle(.secondary) }
            case .available(let version, _): VStack(spacing: 8) { Text("Version \(version) is available!").font(.headline); Link(destination: URL(string: "https://github.com/cshariq/Sapphire/releases")!) { Text("Download from GitHub") }.buttonStyle(.bordered).tint(.accentColor) }
            case .error(let message): HStack(spacing: 8) { Image(systemName: "xmark.octagon.fill").foregroundColor(.red); Text(message).foregroundStyle(.secondary).lineLimit(1) }
            default: EmptyView()
            }
        }.animation(.easeInOut, value: updateChecker.status).frame(minHeight: 40)
    }
}

private struct ModernOnboardingRow<Content: View>: View {
    let iconName: String, iconColor: Color, title: String, description: String
    let content: Content
    init(iconName: String, iconColor: Color, title: String, description: String, @ViewBuilder content: () -> Content) { self.iconName = iconName; self.iconColor = iconColor; self.title = title; self.description = description; self.content = content() }
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: iconName).font(.title.weight(.semibold)).foregroundColor(iconColor).frame(width: 44, height: 44).background(iconColor.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline.weight(.bold)); Text(description).font(.callout).foregroundColor(.secondary) }
            Spacer()
            content
        }.padding(16).background(.black.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

private struct OnboardingButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline.weight(.bold)).foregroundColor(isEnabled ? .black.opacity(0.8) : .gray).padding(.horizontal, 60).frame(height: 50)
                .background(LinearGradient(gradient: Gradient(colors: isEnabled ? [Color(red: 154/255, green: 249/255, blue: 165/255), Color(red: 174/255, green: 255/255, blue: 247/255)] : [.gray.opacity(0.5)]), startPoint: .leading, endPoint: .trailing))
                .clipShape(Capsule()).shadow(color: .white.opacity(isEnabled ? 0.3 : 0), radius: 10, y: 5)
        }.buttonStyle(.plain).scaleEffect(isEnabled ? 1.0 : 0.98).padding(.bottom, 50)
    }
}

private struct MusicServiceButton: View {
    let title: String, icon: String, isSelected: Bool
    let action: () -> Void
    @State private var isPressed = false
    @ViewBuilder private var iconView: some View { if icon == "music.note" { Image(systemName: icon).resizable().renderingMode(.template).foregroundColor(.white) } else { Image(icon).resizable().renderingMode(.original) } }
    var body: some View {
        HStack {
            iconView.aspectRatio(contentMode: .fit).frame(width: 28, height: 28)
            Text(title).font(.system(size: 18, weight: .bold, design: .rounded)); Spacer()
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.white).opacity(isSelected ? 1.0 : 0.0).scaleEffect(isSelected ? 1.0 : 0.5)
        }.padding(.horizontal, 20).frame(height: 65).background(ZStack { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.2)); RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1); if isSelected { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.indigo, lineWidth: 3).shadow(color: .indigo.opacity(0.5), radius: 8) } })
        .scaleEffect(isPressed ? 0.97 : 1.0).contentShape(Rectangle()).onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { action() } }
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in if !isPressed { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPressed = true } } }.onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPressed = false } }).animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

private struct PermissionSectionView: View {
    let title: String, permissions: [PermissionItem]
    var description: String? = nil
    @ObservedObject var manager: PermissionsManager
    var body: some View { if !permissions.isEmpty { VStack(alignment: .leading, spacing: 4) { Text(title).font(.title2.weight(.semibold)); if let description = description { Text(description).font(.caption).foregroundColor(.secondary).padding(.bottom, 8) }; VStack(spacing: 15) { ForEach(permissions) { permission in PermissionRowView(permission: permission, manager: manager) } } } } }
}

private struct PermissionRowView: View {
    let permission: PermissionItem
    @ObservedObject var manager: PermissionsManager
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: permission.iconName).font(.title2).frame(width: 40, height: 40).background(permission.iconColor.opacity(0.2)).clipShape(Circle()).foregroundColor(permission.iconColor)
            VStack(alignment: .leading, spacing: 2) { Text(permission.title).font(.headline); Text(permission.description).font(.subheadline).foregroundColor(.secondary) }
            Spacer()
            let status = manager.status(for: permission.type)
            switch status {
            case .granted: Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green)
            case .denied: Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.red)
            case .notRequested:
                Button(action: { manager.requestPermission(permission.type) }) {
                    Text("Request")
                        .fontWeight(.bold)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(Color.accentColor.gradient)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(color: .accentColor.opacity(0.4), radius: 5, y: 2)
            }
        }.padding().background(.black.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

private struct CustomWindowControls: View {
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .buttonStyle(TrafficLightButtonStyle(color: .red, isHovering: isHovering))

            Button(action: {}) {
                Image(systemName: "minus").font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .buttonStyle(TrafficLightButtonStyle(color: .yellow, isHovering: isHovering))

            Button(action: {}) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .buttonStyle(TrafficLightButtonStyle(color: .green, isHovering: isHovering))
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovering = hovering }
        }
    }
}
