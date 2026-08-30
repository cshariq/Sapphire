#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct SportsWidgetView: View {
    var body: some View {
        Image(systemName: "sportscourt.fill")
            .font(.system(size: 20))
            .foregroundStyle(.white)
    }
}

enum SportsLiveActivityView {
    static func left(for payload: SportsPayload, preferLogo: Bool) -> some View {
        Image(systemName: "sportscourt.fill")
            .font(.title3)
            .foregroundStyle(.white)
    }

    static func right(for payload: SportsPayload, preferLogo: Bool) -> some View {
        Text("\(payload.awayScore)-\(payload.homeScore)")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }
}

struct SportsSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sports unavailable in this build", systemImage: "sportscourt.fill")
                .font(.headline)
            Text("Sports settings are stubbed because the private Sports package is not included in this fork.")
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
