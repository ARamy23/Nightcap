import ComposableArchitecture
import NightcapCompanionUI
import NightcapDomain
import SwiftUI

@main
struct NightcapWatchApp: App {
    @State private var store = Store(initialState: CompanionFeature.State()) {
        CompanionFeature()
    }

    var body: some Scene {
        WindowGroup {
            CompanionView(store: store)
        }
    }
}
