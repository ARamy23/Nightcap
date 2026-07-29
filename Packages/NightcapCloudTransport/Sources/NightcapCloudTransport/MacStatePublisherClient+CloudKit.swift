import Dependencies
import Foundation
import NightcapDomain

extension MacStatePublisherClient {
    /// The Mac side of the companion link: pushes each state change into the
    /// user's private CloudKit database, which is what the phone and watch read.
    ///
    /// Not the default. `liveValue` stays a no-op until a build actually ships
    /// the iCloud entitlement, so the App Store build remains offline.
    public static func cloudKit(
        store: CloudKitMacStateStore = CloudKitMacStateStore()
    ) -> MacStatePublisherClient {
        MacStatePublisherClient(
            publish: { state in
                try await store.publish(state)
            }
        )
    }
}
