import ComposableArchitecture
import NightcapCompanionUI
import NightcapDomain
import SwiftUI

#if NIGHTCAP_CLOUDKIT
import NightcapCloudTransport
#endif

@main
struct NightcapPhoneApp: App {
    @State private var store = Store(initialState: CompanionFeature.State()) {
        CompanionFeature()
    }

    init() {
        // Without this the transport keeps its stub liveValue and the app shows
        // canned sample apps that look convincingly like a real Mac. The flag is
        // set only by the CloudKit overlay, which is also the only build carrying
        // the container entitlement this needs.
        #if NIGHTCAP_CLOUDKIT
        prepareDependencies {
            $0.macStateTransportClient = .cloudKit()
            $0.hotspotNotifierClient = .userNotifications
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            CompanionView(store: store)
        }
    }
}
