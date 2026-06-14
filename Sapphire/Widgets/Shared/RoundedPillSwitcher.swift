//
//  RoundedPillSwitcher.swift
//  Sapphire
//

import SwiftUI

struct RoundedPillSwitcher<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                Text(title(item))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(selection == item ? .white : .white.opacity(0.42))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(selection == item ? Color.white.opacity(0.2) : Color.clear)
                    )
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selection = item
                        }
                    }
            }
        }
        .background(Color.white.opacity(0.07))
        .clipShape(Capsule())
    }
}
