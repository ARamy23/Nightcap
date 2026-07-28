import Dependencies
import Foundation
import NightcapDomain
import StoreKit

extension ReviewPromptClient: DependencyKey {
    public static let liveValue: ReviewPromptClient = .init(
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
}
