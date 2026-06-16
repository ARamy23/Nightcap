import Dependencies
import DependenciesMacros
import Foundation
import StoreKit

@DependencyClient
struct ReviewPromptClient: Sendable {
    var requestIfAppropriate: @Sendable () -> Void
}

extension ReviewPromptClient: DependencyKey {
    static let liveValue: ReviewPromptClient = .init(
        requestIfAppropriate: {
            let defaults = UserDefaults.standard
            let key = "reviewPrompt.lastRequestDate"
            let now = Date()
            if let last = defaults.object(forKey: key) as? Date,
               now.timeIntervalSince(last) < 60 * 60 * 24 * 30 {
                return
            }
            defaults.set(now, forKey: key)
            SKStoreReviewController.requestReview()
        }
    )

    static let testValue = ReviewPromptClient(requestIfAppropriate: {})
}

extension DependencyValues {
    var reviewPromptClient: ReviewPromptClient {
        get { self[ReviewPromptClient.self] }
        set { self[ReviewPromptClient.self] = newValue }
    }
}
