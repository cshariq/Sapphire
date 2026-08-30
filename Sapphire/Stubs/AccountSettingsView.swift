#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct AccountSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connected accounts unavailable", systemImage: "person.crop.circle.badge.questionmark")
                .font(.headline)
            Text("Account linking lives in the private ConnectedAccounts package and is stubbed in this fork.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}
#endif
