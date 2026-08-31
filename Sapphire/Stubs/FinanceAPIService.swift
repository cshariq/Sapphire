//
//  FinanceAPIService.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

import Foundation
import SwiftUI

struct FinanceQuote {
    let symbol: String
    let price: Double
    let change: Double
    let changePercent: Double
    let name: String
    let isAfterHours: Bool
}

final class FinanceAPIService {
    static let shared = FinanceAPIService()
    private init() {}

    func cachedQuote(symbol: String) -> FinanceQuote? { nil }

    func makePayload(symbol: String, index: Int, quote: FinanceQuote?) -> FinancePayload {
        FinancePayload(
            symbol: symbol,
            price: "$0.00",
            change: "0.00",
            changePercent: "0.00%",
            isPositive: true,
            name: symbol,
            isAfterHours: quote?.isAfterHours ?? false,
            closingPrice: nil
        )
    }
}

extension FinanceAPIService {
    func fetchQuote(symbol: String) async -> FinanceQuote? { nil }
}

enum FinanceLiveActivityView {
    @ViewBuilder static func left(for payload: FinancePayload) -> some View { EmptyView() }
    @ViewBuilder static func right(for payload: FinancePayload) -> some View { EmptyView() }
}