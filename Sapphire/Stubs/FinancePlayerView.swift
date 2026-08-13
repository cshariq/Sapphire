import SwiftUI

struct FinancePlayerView: View {
    @Binding var navigationStack: [NotchWidgetMode]

    init(navigationStack: Binding<[NotchWidgetMode]>) {
        _navigationStack = navigationStack
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "dollarsign.circle.fill").font(.system(size: 22))
            Text("Finance").font(.headline)
        }
        .frame(width: 320)
    }
}
