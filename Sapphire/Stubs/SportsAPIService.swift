import Foundation

final class SportsAPIService {
    static let shared = SportsAPIService()
    private init() {}

    func bootstrapIfNeeded() {}

    func cachedLiveEvent(for teamOrLeague: String) -> LiveSportsEvent? { nil }

    func peekLatestCommentary(for event: LiveSportsEvent) -> SportsComment? { nil }
}
