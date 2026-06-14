//
//  SportsFinanceSettingsViews.swift
//  Sapphire
//

import SwiftUI

// MARK: - Shared Settings Chrome

private struct SettingsHeroHeader: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.35), tint.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String?
    var compactContent: Bool
    @ViewBuilder let content: Content

    init(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String? = nil,
        compactContent: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.compactContent = compactContent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, subtitle == nil ? 6 : 8)

            content
                .padding(.bottom, compactContent ? 4 : 12)
        }
        .modifier(SettingsContainerModifier())
    }
}

private struct CompactToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

private struct SettingsSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

private struct SettingsChip: View {
    let title: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSelected ? tint.opacity(0.28) : Color.white.opacity(0.07))
                .overlay(
                    Capsule()
                        .stroke(isSelected ? tint.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct FavoriteRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

private struct SettingsEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.7))
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal)
    }
}

// MARK: - Sports Settings

struct SportsSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var sportsAPI = SportsAPIService.shared
    @State private var searchText = ""
    @State private var leagueSearchText = ""
    @State private var selectedSport: SportCategory = .all

    enum SportCategory: String, CaseIterable {
        case all = "All"
        case football = "Football"
        case basketball = "Basketball"
        case baseball = "Baseball"
        case hockey = "Hockey"
        case soccer = "Soccer"
    }

    private var filteredLeagues: [String] {
        let query = leagueSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let leagues = query.isEmpty ? sportsAPI.popularLeagues() : sportsAPI.searchCatalog(query: query, limit: 40).map(\.name)

        guard selectedSport != .all else { return leagues }

        return leagues.filter { league in
            let lower = league.lowercased()
            switch selectedSport {
            case .all: return true
            case .football: return lower.contains("nfl") || lower.contains("football")
            case .basketball: return lower.contains("nba") || lower.contains("basketball")
            case .baseball: return lower.contains("mlb") || lower.contains("baseball")
            case .hockey: return lower.contains("nhl") || lower.contains("hockey")
            case .soccer: return lower.contains("soccer") || lower.contains("fifa") || lower.contains("premier")
            }
        }
    }

    private var filteredCatalog: [SportsTeamEntry] {
        sportsAPI.searchCatalog(query: searchText, limit: 75)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsHeroHeader(
                    icon: "sportscourt.fill",
                    tint: .orange,
                    title: "Sports",
                    subtitle: "Live scores, play-by-play, and team tracking in the notch."
                )

                SettingsSectionCard(
                    icon: "rectangle.inset.filled.and.person.filled",
                    tint: .orange,
                    title: "Notch & Widget",
                    subtitle: "Control how sports appear in the expanded notch.",
                    compactContent: true
                ) {
                    CompactToggleRow(
                        title: "Sports Widget",
                        description: "Show live scores in the widgets row.",
                        isOn: $settings.settings.sportsWidgetEnabled
                    )
                    Divider().padding(.leading, 20)
                    CompactToggleRow(
                        title: "Open Details on Click",
                        description: "Tap the widget to open the full scores and commentary view.",
                        isOn: $settings.settings.sportsOpenOnClick
                    )
                    Divider().padding(.leading, 20)
                    CompactToggleRow(
                        title: "Prefer Team Logos",
                        description: "Use team logos instead of abbreviated names.",
                        isOn: $settings.settings.sportsPreferLogo
                    )
                }

                SettingsSectionCard(
                    icon: "dot.radiowaves.left.and.right",
                    tint: .orange,
                    title: "Live Activity",
                    subtitle: "Real-time game updates below the notch.",
                    compactContent: true
                ) {
                    CompactToggleRow(
                        title: "Sports Live Activity",
                        description: "Keep score and game clock visible while you work.",
                        isOn: $settings.settings.sportsLiveActivityEnabled
                    )

                    if settings.settings.sportsLiveActivityEnabled {
                        Divider().padding(.leading, 20)
                        CompactToggleRow(
                            title: "Show Commentary in Live Activity",
                            description: "Scroll play-by-play updates under the score, similar to synced lyrics.",
                            isOn: $settings.settings.sportsCommentaryInLiveActivity
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: settings.settings.sportsLiveActivityEnabled)

                SettingsSectionCard(
                    icon: "trophy.fill",
                    tint: .orange,
                    title: "Discover Leagues",
                    subtitle: "\(sportsAPI.discoveredLeagueCount)+ leagues via ESPN and SportScore."
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SportCategory.allCases, id: \.self) { category in
                                SettingsChip(
                                    title: category.rawValue,
                                    isSelected: selectedSport == category,
                                    tint: .orange
                                ) {
                                    selectedSport = category
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                    }

                    SettingsSearchField(
                        placeholder: "Search leagues (NFL, NBA, FIFA, IPL…)",
                        text: $leagueSearchText
                    )

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(filteredLeagues, id: \.self) { league in
                                let isFollowing = settings.settings.sportsFavoriteTeams.contains(league)
                                Button {
                                    addTeam(league)
                                } label: {
                                    HStack(spacing: 5) {
                                        if isFollowing {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption2)
                                        }
                                        Text(league)
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(isFollowing ? Color.orange.opacity(0.25) : Color.white.opacity(0.07))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }
                }

                SettingsSectionCard(
                    icon: "person.3.fill",
                    tint: .orange,
                    title: "Add Teams",
                    subtitle: "Search the catalog or add a custom team name."
                ) {
                    SettingsSearchField(
                        placeholder: "Search teams (Lakers, Chiefs, Arsenal…)",
                        text: $searchText
                    )

                    if !filteredCatalog.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(filteredCatalog, id: \.self) { entry in
                                Button {
                                    addTeam(entry.name)
                                    searchText = ""
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.name)
                                                .foregroundStyle(.primary)
                                            Text(entry.league)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if entry != filteredCatalog.last {
                                    Divider().padding(.leading, 20)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            addTeam(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
                            searchText = ""
                        } label: {
                            HStack {
                                Text("Add \"\(searchText)\"")
                                    .foregroundStyle(.blue)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                            }
                            .padding()
                            .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                    }
                }

                SettingsSectionCard(
                    icon: "star.fill",
                    tint: .orange,
                    title: "Your Feed",
                    subtitle: "\(settings.settings.sportsFavoriteTeams.count) team\(settings.settings.sportsFavoriteTeams.count == 1 ? "" : "s") in rotation."
                ) {
                    if settings.settings.sportsFavoriteTeams.isEmpty {
                        SettingsEmptyState(
                            icon: "sportscourt",
                            title: "No favorites yet",
                            message: "Follow a league or add a team above to populate your sports feed."
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(settings.settings.sportsFavoriteTeams.indices, id: \.self) { index in
                                FavoriteRow(
                                    icon: "sportscourt.fill",
                                    tint: .orange,
                                    title: settings.settings.sportsFavoriteTeams[index],
                                    subtitle: index == settings.settings.sportsFavoriteTeamIndex ? "Primary feed" : nil
                                ) {
                                    settings.settings.sportsFavoriteTeams.remove(at: index)
                                    settings.settings.normalizedSportsFavoriteTeamIndex()
                                }

                                if index != settings.settings.sportsFavoriteTeams.count - 1 {
                                    Divider().padding(.leading, 56)
                                }
                            }
                        }
                    }
                }
            }
            .padding(25)
        }
        .onAppear {
            sportsAPI.bootstrapIfNeeded()
        }
    }

    private func addTeam(_ team: String) {
        if !settings.settings.sportsFavoriteTeams.contains(team) {
            settings.settings.sportsFavoriteTeams.append(team)
            settings.settings.normalizedSportsFavoriteTeamIndex()
        }
    }
}

// MARK: - Finance Settings

struct FinanceSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var financeAPI = FinanceAPIService.shared
    @State private var searchText = ""
    @State private var selectedCategory: FinanceCategory = .all
    @State private var searchResults: [FinanceSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    enum FinanceCategory: String, CaseIterable {
        case all = "All"
        case stocks = "Stocks"
        case crypto = "Crypto"
        case etf = "ETFs"
    }

    private var displayedResults: [FinanceSearchResult] {
        switch selectedCategory {
        case .all:
            return searchResults
        case .stocks:
            return searchResults.filter { $0.categoryLabel == "Stock" }
        case .crypto:
            return searchResults.filter { $0.categoryLabel == "Crypto" }
        case .etf:
            return searchResults.filter { $0.categoryLabel == "ETF" }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsHeroHeader(
                    icon: "chart.line.uptrend.xyaxis",
                    tint: .green,
                    title: "Finance",
                    subtitle: "Track holdings, cost basis, and live market data in the notch."
                )

                SettingsSectionCard(
                    icon: "rectangle.inset.filled.and.person.filled",
                    tint: .green,
                    title: "Notch & Widget",
                    subtitle: "Control how finance data appears in the expanded notch.",
                    compactContent: true
                ) {
                    CompactToggleRow(
                        title: "Finance Widget",
                        description: "Show ticker prices in the widgets row.",
                        isOn: $settings.settings.financeWidgetEnabled
                    )
                    Divider().padding(.leading, 20)
                    CompactToggleRow(
                        title: "Open Details on Click",
                        description: "Tap the widget to open charts and portfolio stats.",
                        isOn: $settings.settings.financeOpenOnClick
                    )
                }

                SettingsSectionCard(
                    icon: "dot.radiowaves.left.and.right",
                    tint: .green,
                    title: "Live Activity",
                    subtitle: "Keep your active symbol visible below the notch.",
                    compactContent: true
                ) {
                    CompactToggleRow(
                        title: "Finance Live Activity",
                        description: "Display price and daily change while markets are open.",
                        isOn: $settings.settings.financeLiveActivityEnabled
                    )
                }

                SettingsSectionCard(
                    icon: "plus.magnifyingglass",
                    tint: .green,
                    title: "Watchlist",
                    subtitle: "Track up to 3 symbols. Search by company or ticker via Yahoo Finance."
                ) {
                    HStack(spacing: 10) {
                        ForEach(FinanceCategory.allCases, id: \.self) { category in
                            SettingsChip(
                                title: category.rawValue,
                                isSelected: selectedCategory == category,
                                tint: .green
                            ) {
                                selectedCategory = category
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                    SettingsSearchField(
                        placeholder: "Search Apple, Tesla, Bitcoin…",
                        text: $searchText
                    )
                    .onChange(of: searchText) { _, newValue in
                        scheduleSymbolSearch(for: newValue)
                    }

                    if isSearching {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Searching Yahoo Finance…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }

                    if !displayedResults.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(displayedResults) { result in
                                Button {
                                    addStock(result.symbol)
                                    searchText = ""
                                    searchResults = []
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: symbolIcon(for: result.symbol, type: result.quoteType))
                                            .foregroundStyle(.green)
                                            .frame(width: 22)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(result.symbol)
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                            Text(result.name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Text(result.categoryLabel)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.white.opacity(0.06))
                                            .clipShape(Capsule())

                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(settings.settings.financeFavoriteSymbols.contains(result.symbol))

                                if result.id != displayedResults.last?.id {
                                    Divider().padding(.leading, 50)
                                }
                            }
                        }
                        .padding(.bottom, 4)
                    } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSearching {
                        SettingsEmptyState(
                            icon: "magnifyingglass",
                            title: "No matches",
                            message: "Try a company name (e.g. NVIDIA) or ticker symbol (e.g. NVDA)."
                        )
                        .padding(.bottom, 4)
                    }
                }

                if !settings.settings.financeFavoriteSymbols.isEmpty {
                    SettingsSectionCard(
                        icon: "chart.pie.fill",
                        tint: .green,
                        title: "Portfolio",
                        subtitle: "Amount invested and start date stay on this device."
                    ) {
                        InfoContainer(
                            text: "Start dates help calculate how long you've held each position. All portfolio data is stored locally.",
                            iconName: "lock.shield.fill",
                            color: .blue
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                        ForEach(settings.settings.financeFavoriteSymbols, id: \.self) { symbol in
                            FinancePortfolioDataRow(symbol: symbol)
                        }
                        .padding(.bottom, 4)
                    }
                }

                SettingsSectionCard(
                    icon: "list.bullet.rectangle",
                    tint: .green,
                    title: "Tracked Symbols",
                    subtitle: "\(settings.settings.financeFavoriteSymbols.count) symbol\(settings.settings.financeFavoriteSymbols.count == 1 ? "" : "s") tracked."
                ) {
                    if settings.settings.financeFavoriteSymbols.isEmpty {
                        SettingsEmptyState(
                            icon: "chart.bar.doc.horizontal",
                            title: "No symbols tracked",
                            message: "Add stocks or crypto from the watchlist section above."
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(settings.settings.financeFavoriteSymbols.indices, id: \.self) { index in
                                let symbol = settings.settings.financeFavoriteSymbols[index]
                                FavoriteRow(
                                    icon: symbolIcon(for: symbol),
                                    tint: .green,
                                    title: symbol,
                                    subtitle: financeAPI.cachedQuote(symbol: symbol)?.name
                                        ?? SportsFinanceContentProvider.syntheticCompanyName(for: symbol)
                                ) {
                                    removeSymbol(symbol, at: index)
                                }

                                if index != settings.settings.financeFavoriteSymbols.count - 1 {
                                    Divider().padding(.leading, 56)
                                }
                            }
                        }
                    }
                }
            }
            .padding(25)
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private func scheduleSymbolSearch(for query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let results = await financeAPI.searchSymbols(query: trimmed)
            guard !Task.isCancelled else { return }
            searchResults = results
            isSearching = false
        }
    }

    private func addStock(_ stock: String) {
        let symbol = stock.uppercased()
        if !settings.settings.financeFavoriteSymbols.contains(symbol) {
            settings.settings.financeFavoriteSymbols.append(symbol)
            settings.settings.financeInvestmentStartDates[symbol] = Date()
            settings.settings.normalizedFinanceFavoriteSymbolIndex()
            Task { _ = await financeAPI.fetchQuote(symbol: symbol) }
        }
    }

    private func removeSymbol(_ symbol: String, at index: Int) {
        settings.settings.financeFavoriteSymbols.remove(at: index)
        settings.settings.financeShares.removeValue(forKey: symbol)
        settings.settings.financeInvested.removeValue(forKey: symbol)
        settings.settings.financeInvestmentStartDates.removeValue(forKey: symbol)
        settings.settings.normalizedFinanceFavoriteSymbolIndex()
    }

    private func symbolIcon(for symbol: String, type: String? = nil) -> String {
        let quoteType = type?.lowercased() ?? ""
        if quoteType.contains("crypto") || ["BTC", "ETH", "DOGE", "SOL", "BNB", "XRP"].contains(symbol) {
            return "bitcoinsign.circle.fill"
        } else if quoteType == "etf" || ["SPY", "QQQ", "VOO", "VTI"].contains(symbol) {
            return "chart.pie.fill"
        } else {
            return "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Portfolio Row

struct FinancePortfolioDataRow: View {
    let symbol: String
    @EnvironmentObject var settings: SettingsModel

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private var investedBinding: Binding<Double> {
        Binding(
            get: { settings.settings.financeInvested[symbol] ?? 0.0 },
            set: { settings.settings.financeInvested[symbol] = $0 }
        )
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { settings.settings.financeInvestmentStartDates[symbol] ?? Date() },
            set: { settings.settings.financeInvestmentStartDates[symbol] = $0 }
        )
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    private var startDateTextBinding: Binding<String> {
        Binding(
            get: { Self.isoDateFormatter.string(from: startDateBinding.wrappedValue) },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = Self.isoDateFormatter.date(from: trimmed) {
                    startDateBinding.wrappedValue = min(parsed, Date())
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(symbol)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                if let label = SportsFinanceContentProvider.holdingPeriodLabel(for: symbol, settings: settings.settings) {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }

            portfolioField(title: "Amount Invested", value: investedBinding, formatter: Self.currencyFormatter)

            VStack(alignment: .leading, spacing: 8) {
                Text("Investment Start Date")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("2026-08-31", text: startDateTextBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func portfolioField(title: String, value: Binding<Double>, formatter: NumberFormatter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("0", value: value, formatter: formatter)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
    }
}
