#if !SAPPHIRE_FULL_BUILD
import Foundation

final class SportsAPIService {
    static let shared = SportsAPIService()
    private init() {}

    func bootstrapIfNeeded() {}

    func cachedLiveEvent(for teamOrLeague: String) -> LiveSportsEvent? { nil }

    func peekLatestCommentary(for event: LiveSportsEvent) -> SportsComment? { nil }

    func prefetchLiveScoreboards(for teams: [String]) async {}

    func fetchLiveEvent(for teamOrLeague: String, forceRefresh: Bool = false) async -> LiveSportsEvent? {
        nil
    }
}
#endif
