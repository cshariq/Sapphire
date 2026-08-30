#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct FinanceWidgetView: View {
    var body: some View {
        Image(systemName: "dollarsign.circle.fill")
            .font(.system(size: 20))
            .foregroundStyle(.white)
    }
}

enum FinanceLiveActivityView {
    static func left(for payload: FinancePayload) -> some View {
        Image(systemName: "chart.line.uptrend.xyaxis")
            .font(.title3)
            .foregroundStyle(.white)
    }

    static func right(for payload: FinancePayload) -> some View {
        Text(payload.symbol)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }
}

struct FinanceSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Finance unavailable in this build", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
            Text("Finance settings are stubbed because the private Finance package is not included in this fork.")
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
