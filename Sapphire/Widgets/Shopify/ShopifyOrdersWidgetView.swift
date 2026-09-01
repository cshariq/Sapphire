//
//  ShopifyOrdersWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-31

import SwiftUI

struct ShopifyOrdersWidgetView: View {
    @Environment(\.navigationStack) private var navigationStack
    @StateObject private var shopify = ShopifyService.shared

    private var latestOrder: ShopifyOrder? { shopify.orders.first }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bag.fill")
                .font(.system(size: 20))
                .foregroundStyle(.green)

            if let order = latestOrder {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Shopify")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(order.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(order.currency) \(order.totalPrice)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text((order.financialStatus ?? "pending").capitalized)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            } else {
                Text(shopify.isConfigured ? "No orders" : "Set up Shopify")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 150, minHeight: 32)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                navigationStack.wrappedValue.append(.shopifyOrders)
            }
        }
        .task {
            if shopify.isConfigured && shopify.orders.isEmpty {
                await shopify.refresh()
            }
        }
    }
}