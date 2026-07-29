import NightcapDomain
import ComposableArchitecture
import Foundation
import SwiftUI

public struct MenuContentView: View {
    @Bindable public var store: StoreOf<AppFeature>

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public var body: some View {
        MenuStatusSection(
            assertionHeld: store.assertionHeld,
            activeAppCount: store.runningWatchedIDs.count
        )

        Divider()

        WatchedAppsMenuSection(
            watchedApps: store.watchedApps,
            runningWatchedIDs: store.runningWatchedIDs,
            onObservationToggle: setObservation,
            onRemove: removeApp
        )

        AddRunningAppMenu(
            candidates: store.runningAppCandidates,
            watchedBundleIDs: watchedBundleIDs,
            onAdd: addApp,
            onRefresh: refreshCandidates
        )

        Button("Add App…") { presentAppPicker() }

        Divider()

        MenuActionsSection(
            launchAtLoginStatus: store.launchAtLoginStatus,
            onLaunchAtLoginToggle: setLaunchAtLogin,
            onQuit: quit
        )
    }

    // Each of these is one menu item's intent. They are methods rather than
    // inline closures because the closures would live inside a `Menu`, which
    // SwiftUI leaves unevaluated until the menu opens — unreachable from a test.
    // As methods, a test can send them against a real store and assert the
    // resulting state, which is what actually matters: the right action reaches
    // the reducer for the right app.

    func setObservation(_ id: WatchedApp.ID, to isObserved: Bool) {
        store.send(.observationToggled(id, isObserved))
    }

    func removeApp(_ id: WatchedApp.ID) {
        store.send(.removeAppRequested(id))
    }

    func addApp(_ app: WatchedApp) {
        store.send(.addAppRequested(app))
    }

    func refreshCandidates() {
        store.send(.runningAppCandidatesRefreshRequested)
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        store.send(.launchAtLoginToggled(isEnabled))
    }

    func quit() {
        store.send(.quitTapped)
    }

    /// Internal rather than private so a test can pin the wiring: the add-running
    /// menu greys out already-watched apps only if this reaches it.
    var watchedBundleIDs: Set<String> {
        Set(store.watchedApps.map(\.bundleID))
    }

    private func presentAppPicker() {
        DispatchQueue.main.async {
            MenuAppPicker.present(existingApps: store.watchedApps) { app in
                store.send(.addAppRequested(app))
            }
        }
    }
}
