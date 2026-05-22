import ComposableArchitecture
import Foundation

extension AppFeature {
    func handleAddAppRequested(
        _ app: WatchedApp,
        state: inout State
    ) -> Effect<Action> {
        if !state.watchedApps.contains(where: { $0.bundleID == app.bundleID }) {
            state.$watchedApps.withLock { $0.append(app) }
        }
        if lifecycle.runningBundleIDs().contains(app.bundleID) {
            state.runningWatchedIDs.insert(app.bundleID)
            syncAssertion(&state)
        }
        return .none
    }

    func handleRemoveAppRequested(
        _ id: WatchedApp.ID,
        state: inout State
    ) -> Effect<Action> {
        state.$watchedApps.withLock { $0.removeAll { $0.bundleID == id } }
        if state.runningWatchedIDs.remove(id) != nil {
            syncAssertion(&state)
        }
        return .none
    }

    func handleObservationToggled(
        _ id: WatchedApp.ID,
        isObserved: Bool,
        state: inout State
    ) -> Effect<Action> {
        state.$watchedApps.withLock { apps in
            guard let index = apps.firstIndex(where: { $0.bundleID == id }) else { return }
            apps[index].isObserved = isObserved
        }

        if isObserved {
            if lifecycle.runningBundleIDs().contains(id) {
                state.runningWatchedIDs.insert(id)
            }
        } else {
            state.runningWatchedIDs.remove(id)
        }
        syncAssertion(&state)
        return .none
    }

    func observedIDs(in state: State) -> Set<String> {
        Set(state.watchedApps.filter(\.isObserved).map(\.bundleID))
    }
}
