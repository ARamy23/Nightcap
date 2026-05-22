import ComposableArchitecture
import Foundation
import SwiftUI

struct MenuContentView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        MenuStatusSection(
            assertionHeld: store.assertionHeld,
            activeAppCount: store.runningWatchedIDs.count,
            manualSession: store.manualSession
        )

        Divider()

        ManualSessionMenuSection(
            manualSession: store.manualSession,
            onStart: { duration in
                store.send(.manualSessionStarted(duration))
            },
            onStop: {
                store.send(.manualSessionStopped)
            }
        )

        Divider()

        WatchedAppsMenuSection(
            watchedApps: store.watchedApps,
            runningWatchedIDs: store.runningWatchedIDs,
            onObservationToggle: { id, isObserved in
                store.send(.observationToggled(id, isObserved))
            },
            onRemove: { id in
                store.send(.removeAppRequested(id))
            }
        )

        AddRunningAppMenu(
            candidates: store.runningAppCandidates,
            watchedBundleIDs: watchedBundleIDs,
            onAdd: { app in
                store.send(.addAppRequested(app))
            },
            onRefresh: {
                store.send(.runningAppCandidatesRefreshRequested)
            }
        )

        Button("Add App…") { presentAppPicker() }

        Divider()

        MenuActionsSection(
            launchAtLoginStatus: store.launchAtLoginStatus,
            onLaunchAtLoginToggle: { isEnabled in
                store.send(.launchAtLoginToggled(isEnabled))
            },
            onQuit: {
                store.send(.quitTapped)
            }
        )
    }

    private var watchedBundleIDs: Set<String> {
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
