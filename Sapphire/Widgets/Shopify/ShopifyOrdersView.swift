//
//  ShopifyOrdersView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-31

import SwiftUI

struct ShopifyOrdersView: View {
    @Environment(\.navigationStack) private var navigationStack
    @StateObject private var shopify = ShopifyService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bag.fill")
                    .foregroundStyle(.green)
                Text("Shopify Orders")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await shopify.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(shopify.isLoading || !shopify.isConfigured)
            }

            if !shopify.isConfigured {
                Text("Connect Shopify in the Shopify section of Settings to view recent orders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if shopify.isLoading && shopify.orders.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error = shopify.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if shopify.orders.isEmpty {
                Text("No orders found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shopify.orders.prefix(5)) { order in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(order.name).font(.system(size: 13, weight: .semibold))
                            Text(order.customerDisplayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(order.currency) \(order.totalPrice)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                            Text((order.financialStatus ?? "unknown").capitalized)
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .padding()
        .task {
            if shopify.isConfigured { await shopify.refresh() }
        }
    }
}