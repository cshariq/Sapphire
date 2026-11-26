//
//  AppLanguageSettings.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-11-13
//

import AppKit
import SwiftUI

/// The language Sapphire shows its interface in.
///
/// macOS keeps a per-app language as the app's own `AppleLanguages` default — the value
/// System Settings ▸ General ▸ Language & Region ▸ Applications writes — and Foundation reads it
/// once at launch. Sapphire edits that same value, so both places stay in sync, and relaunches to
/// apply it. No copy is kept in `Settings`.
enum AppLanguage {
    private static let defaultsKey = "AppleLanguages"

    /// Localizations shipped in the app bundle, sorted by their own names.
    static let available: [String] = Bundle.main.localizations
        .filter { $0 != "Base" }
        .sorted { nativeName(for: $0).localizedStandardCompare(nativeName(for: $1)) == .orderedAscending }

    /// The language Sapphire chose at launch.
    static let running: String = Bundle.main.preferredLocalizations.first ?? "en"

    /// The app-specific language, or `nil` when Sapphire follows the Mac's language order.
    static var override: String? {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: bundleID)?[defaultsKey] as? [String],
              let first = languages.first else { return nil }
        return resolve([first])
    }

    static func setOverride(_ language: String?) {
        if let language {
            UserDefaults.standard.set([language], forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    /// The language Sapphire uses when it follows the Mac's language order.
    static var systemLanguage: String {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[defaultsKey] as? [String]
        return resolve(global ?? Locale.preferredLanguages) ?? "en"
    }

    /// The language a launch with `override` would pick.
    static func effectiveLanguage(override: String?) -> String {
        override ?? systemLanguage
    }

    /// The language's name in that language, e.g. "Deutsch".
    static func nativeName(for language: String) -> String {
        let locale = Locale(identifier: language)
        guard let name = locale.localizedString(forIdentifier: language) else { return language }
        return name.prefix(1).capitalized(with: locale) + name.dropFirst()
    }

    /// "Deutsch (German)": the native name, followed by the name in the current interface language
    /// when they differ, so someone who can't read the current language can still find their own.
    static func menuTitle(for language: String) -> String {
        let native = nativeName(for: language)
        guard let current = Locale.current.localizedString(forIdentifier: language),
              current.localizedCaseInsensitiveCompare(native) != .orderedSame else { return native }
        return "\(native) (\(current))"
    }

    private static func resolve(_ preferences: [String]) -> String? {
        Bundle.preferredLocalizations(from: available, forPreferences: preferences).first
    }
}

/// Language picker for the General pane.
struct AppLanguageSettingsCard: View {
    /// `nil` follows the Mac's language order.
    @State private var selection: String? = AppLanguage.override

    private var pendingLanguage: String? {
        let language = AppLanguage.effectiveLanguage(override: selection)
        return language == AppLanguage.running ? nil : language
    }

    var body: some View {
        SettingsCard(title: "Language") {
            HStack(alignment: .center, spacing: 12) {
                SettingsRowLabel(
                    title: "App Language",
                    description: "Sapphire follows your Mac's preferred languages unless you choose one here."
                )
                Spacer(minLength: 12)
                Picker("App Language", selection: $selection) {
                    Text("System Default (\(AppLanguage.nativeName(for: AppLanguage.systemLanguage)))")
                        .tag(String?.none)
                    Divider()
                    ForEach(AppLanguage.available, id: \.self) { language in
                        Text(verbatim: AppLanguage.menuTitle(for: language))
                            .tag(String?.some(language))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding()

            if let pendingLanguage {
                Divider().padding(.leading, 20)
                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Sapphire switches to \(AppLanguage.nativeName(for: pendingLanguage)) after it relaunches.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("Relaunch Now") {
                        HelperManager.relaunchApp()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .transition(.opacity)
            }
        }
        .animation(.default, value: pendingLanguage)
        .onChange(of: selection) { _, language in
            AppLanguage.setOverride(language)
        }
    }
}
