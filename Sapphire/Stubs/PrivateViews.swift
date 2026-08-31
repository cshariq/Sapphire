//
//  PrivateViews.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

#if !SAPPHIRE_FULL_BUILD
import SwiftUI

private struct UnavailableFeatureView: View {
    let name: String

    var body: some View {
        Text("\(name) is not included in this build.")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SportsSettingsView: View {
    var body: some View { UnavailableFeatureView(name: "Sports") }
}

struct FinanceSettingsView: View {
    var body: some View { UnavailableFeatureView(name: "Finance") }
}

struct AccountSettingsView: View {
    var body: some View { UnavailableFeatureView(name: "Account management") }
}

struct BetaBlockerView: View {
    var onValidationComplete: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Beta validation is not included in this build.")
                .foregroundColor(.secondary)
            Button("Continue", action: onValidationComplete)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NativePaymentSheetView: View {
    var tier: SubscriptionTier
    var deviceCount: Int
    var isAddingOnly: Bool
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Purchases are not included in this build.")
                .foregroundColor(.secondary)
            Button("Close", action: onDismiss)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum SubscriptionRevocationReason: String {
    case sessionExpired

    var alertMessage: String { "Your session has expired. Please sign in again." }
}

final class ScreenPerception {
    func captureAnnotatedScreen() async -> (NSImage?, [String]) { (nil, []) }
}
#endif