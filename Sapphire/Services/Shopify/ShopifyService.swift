//
//  ShopifyService.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-31

import Foundation

struct ShopifyOrder: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let createdAt: Date
    let totalPrice: String
    let currency: String
    let customerName: String?
    let financialStatus: String?
    let fulfillmentStatus: String?

    var customerDisplayName: String { customerName ?? "Guest customer" }
}

private struct ShopifyOrdersResponse: Decodable {
    let orders: [ShopifyOrder]
}

private struct ShopifyOrderCodingKeys: CodingKey {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

extension ShopifyOrder {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ShopifyOrderCodingKeys.self)
        id = try container.decode(Int64.self, forKey: .init(stringValue: "id")!)
        name = try container.decode(String.self, forKey: .init(stringValue: "name")!)
        totalPrice = try container.decode(String.self, forKey: .init(stringValue: "current_total_price")!)
        currency = try container.decode(String.self, forKey: .init(stringValue: "currency")!)
        financialStatus = try container.decodeIfPresent(String.self, forKey: .init(stringValue: "financial_status")!)
        fulfillmentStatus = try container.decodeIfPresent(String.self, forKey: .init(stringValue: "fulfillment_status")!)
        let dateString = try container.decode(String.self, forKey: .init(stringValue: "created_at")!)
        let formatter = ISO8601DateFormatter()
        createdAt = formatter.date(from: dateString) ?? .distantPast
        if let customer = try container.decodeIfPresent([String: String].self, forKey: .init(stringValue: "customer")!),
           let first = customer["first_name"], let last = customer["last_name"] {
            customerName = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        } else {
            customerName = nil
        }
    }
}

@MainActor
final class ShopifyService: ObservableObject {
    static let shared = ShopifyService()
    @Published private(set) var orders: [ShopifyOrder] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private init() {}

    var isConfigured: Bool {
        !APIKeyManager.shared.shopifyStoreDomain.isEmpty && !APIKeyManager.shared.shopifyAdminToken.isEmpty
    }

    func refresh() async {
        guard let url = ordersURL else {
            orders = []
            errorMessage = isConfigured ? "Enter a valid Shopify store domain." : nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        var request = URLRequest(url: url)
        request.setValue(APIKeyManager.shared.shopifyAdminToken, forHTTPHeaderField: "X-Shopify-Access-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoder = JSONDecoder()
            orders = try decoder.decode(ShopifyOrdersResponse.self, from: data).orders
            errorMessage = nil
        } catch {
            errorMessage = "Unable to load Shopify orders. Check the store domain and token."
        }
    }

    private var ordersURL: URL? {
        var domain = APIKeyManager.shared.shopifyStoreDomain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        domain = domain.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/").first.map(String.init) ?? domain
        guard !domain.isEmpty, !domain.contains(" ") else { return nil }
        return URL(string: "https://\(domain)/admin/api/2025-10/orders.json?status=any&limit=10&order=created_at%20desc")
    }
}