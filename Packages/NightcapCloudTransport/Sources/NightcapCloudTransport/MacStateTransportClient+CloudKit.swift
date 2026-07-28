import CloudKit
import Dependencies
import Foundation
import NightcapDomain

extension MacStateTransportClient {
    /// The companion-side transport backed by the user's private CloudKit
    /// database. Not the default: `liveValue` remains the stub until an app
    /// build actually ships the iCloud entitlement.
    public static func cloudKit(
        store: CloudKitMacStateStore = CloudKitMacStateStore(),
        pollInterval: Duration = .seconds(30)
    ) -> MacStateTransportClient {
        MacStateTransportClient(
            states: {
                AsyncStream { continuation in
                    let task = Task {
                        // Push keeps this fresh; the poll is a floor so a missed
                        // notification cannot leave the companion showing a stale
                        // Mac forever.
                        try? await store.subscribeToChanges()
                        while !Task.isCancelled {
                            if let state = try? await store.fetch() {
                                continuation.yield(state)
                            }
                            try? await Task.sleep(for: pollInterval)
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            setObservation: { bundleID, isObserved in
                try await store.requestObservation(bundleID: bundleID, isObserved: isObserved)
            },
            refresh: {
                _ = try await store.fetch()
            }
        )
    }
}
