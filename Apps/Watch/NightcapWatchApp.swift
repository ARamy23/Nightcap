import ComposableArchitecture
import NightcapCompanionUI
import NightcapDomain
import SwiftUI

#if NIGHTCAP_CLOUDKIT
import NightcapCloudTransport
#endif

@main
struct NightcapWatchApp: App {
    @State private var store = Store(initialState: CompanionFeature.State()) {
        CompanionFeature()
    }

    init() {
        // See the note in NightcapPhoneApp: without this the watch shows canned
        // sample data rather than the Mac.
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
