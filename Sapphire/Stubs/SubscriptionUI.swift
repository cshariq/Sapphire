#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct BetaBlockerView: View {
    var onValidationComplete: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
            Text("Beta entitlement check unavailable")
                .font(.headline)
            Text("SubscriptionKit is stubbed in this fork.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Continue") {
                onValidationComplete()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(width: 420, height: 260)
    }
}

struct NativePaymentSheetView: View {
    var tier: SubscriptionTier
    var deviceCount: Int
    var isAddingOnly: Bool
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Upgrade unavailable")
                .font(.title2.bold())
            Text("Native checkout for \(SubscriptionFeatureCatalog.tierDisplayName(tier)) is stubbed in this fork (devices: \(deviceCount)).")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack {
                Spacer()
                Button("Close", action: onDismiss)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
