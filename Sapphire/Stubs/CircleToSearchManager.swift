#if !SAPPHIRE_FULL_BUILD
import Foundation

final class CircleToSearchManager {
    static let shared = CircleToSearchManager()
    private init() {}

    func endResultsPresentation() {}
}

extension Notification.Name {
    static let sapphireOpenCircleToSearch = Notification.Name("sapphireOpenCircleToSearch")
}
#endif
