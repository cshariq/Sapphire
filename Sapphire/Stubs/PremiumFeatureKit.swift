//
//  PremiumFeatureKit.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

#if !SAPPHIRE_FULL_BUILD
import Combine
import SwiftUI

enum PremiumGate {
    static func hasAccess(_ feature: AppFeature) -> Bool {
        SubscriptionAccess.hasAccess(to: feature)
    }

    static func isActive(_ feature: AppFeature?, enabled: Bool) -> Bool {
        enabled && (feature.map(hasAccess) ?? true)
    }

    static var accessChanges: AnyPublisher<Void, Never> {
        NotificationCenter.default.publisher(for: .subscriptionEntitlementsDidChange)
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    @discardableResult
    static func require(_ feature: AppFeature, message: String? = nil) -> Bool {
        FeatureGate.shared.require(feature, message: message ?? premiumDefaultMessage(for: feature))
    }
}

struct PremiumFeatureView<Content: View>: View {
    let feature: AppFeature
    let content: Content

    init(feature: AppFeature, message: String? = nil, @ViewBuilder content: () -> Content) {
        self.feature = feature
        self.content = content()
    }

    var body: some View {
        content.disabled(true).opacity(0.45)
    }
}

extension View {
    func premiumFeature(_ feature: AppFeature, message: String? = nil) -> some View {
        PremiumFeatureView(feature: feature, message: message) { self }
    }
}

func premiumDefaultMessage(for feature: AppFeature) -> String {
    let tier = SubscriptionFeatureCatalog.minimumTier(for: feature)
    return "This feature requires Sapphire \(SubscriptionFeatureCatalog.tierDisplayName(tier))."
}

extension SettingsModel {
    func premiumChanges(_ feature: AppFeature, _ enabled: @escaping (Settings) -> Bool) -> AnyPublisher<Bool, Never> {
        $settings
            .map(enabled)
            .removeDuplicates()
            .combineLatest(PremiumGate.accessChanges.prepend(()))
            .map { isOn, _ in isOn && PremiumGate.hasAccess(feature) }
            .removeDuplicates()
            .dropFirst()
            .eraseToAnyPublisher()
    }

    func isPremiumActive(_ feature: AppFeature, _ enabled: (Settings) -> Bool) -> Bool {
        PremiumGate.isActive(feature, enabled: enabled(settings))
    }
}

extension WidgetType {
    var requiredPremiumFeature: AppFeature? {
        switch self {
        case .sports: .sportsWidget
        case .finance: .financeWidget
        case .battery: .batteryWidget
        case .storage: .storageWidgets
        default: nil
        }
    }

    var isPremiumLocked: Bool {
        requiredPremiumFeature.map { !PremiumGate.hasAccess($0) } ?? false
    }
}

extension LiveActivityType {
    var requiredPremiumFeature: AppFeature? {
        switch self {
        case .sports: .liveSports
        case .finance: .financeLiveActivity
        default: nil
        }
    }

    var isPremiumLocked: Bool {
        requiredPremiumFeature.map { !PremiumGate.hasAccess($0) } ?? false
    }
}
#endif