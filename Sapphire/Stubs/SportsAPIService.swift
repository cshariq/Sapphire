import Foundation
import SwiftUI

final class SportsAPIService {
    static let shared = SportsAPIService()
    private init() {}

    func bootstrapIfNeeded() {}

    func cachedLiveEvent(for teamOrLeague: String) -> LiveSportsEvent? { nil }

    func peekLatestCommentary(for event: LiveSportsEvent) -> SportsComment? { nil }
}

extension SportsAPIService {
    func prefetchLiveScoreboards(for teams: [String]) async {}
    func fetchLiveEvent(for team: String, forceRefresh: Bool = false) async -> LiveSportsEvent? { nil }
}

enum SportsLiveActivityView {
    @ViewBuilder static func left(for payload: SportsPayload, preferLogo: Bool) -> some View { EmptyView() }
    @ViewBuilder static func right(for payload: SportsPayload, preferLogo: Bool) -> some View { EmptyView() }
}
