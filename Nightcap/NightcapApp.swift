import ComposableArchitecture
import NightcapClients
import NightcapDomain
import NightcapUI
import SwiftUI

#if NIGHTCAP_CLOUDKIT
import NightcapCloudTransport
#endif

@main
struct NightcapApp: App {
    @State private var store: StoreOf<AppFeature>

    init() {
        // The publisher's liveValue is a no-op, so without this the Mac never
        // tells the companions anything and they sit on "Waiting for your Mac"
        // forever. Set only by the CloudKit overlay, which is the build carrying
        // the entitlement — the App Store build stays offline.
        #if NIGHTCAP_CLOUDKIT
        prepareDependencies {
            $0.macStatePublisherClient = .cloudKit()
        }
        #endif

        let store = Store(initialState: AppFeature.State()) { AppFeature() }
        store.send(.onAppear)
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            Image(systemName: store.assertionHeld
                  ? "cup.and.saucer.fill"
                  : "cup.and.saucer")
        }
        .menuBarExtraStyle(.menu)
    }
}
