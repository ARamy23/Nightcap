import ComposableArchitecture
import Foundation

extension AppFeature {
    func handleOnAppear(state: inout State) -> Effect<Action> {
        state.launchAtLoginStatus = launchAtLogin.status()
        reconcileRunning(&state)
        refreshRunningAppCandidates(&state)

        return .run { send in
            for await event in lifecycle.events() {
                await send(.lifecycleEvent(event))
            }
        }
        .cancellable(id: CancelID.lifecycle, cancelInFlight: true)
    }

    func handleLifecycleEvent(
        _ event: AppLifecycleClient.Event,
        state: inout State
    ) -> Effect<Action> {
        switch event {
        case let .launched(id):
            return handleLaunchedApp(id, state: &state)

        case let .terminated(id):
            return handleTerminatedApp(id, state: &state)

        case .wake:
            return handleReconcile(state: &state)
        }
    }

    func handleReconcile(state: inout State) -> Effect<Action> {
        reconcileRunning(&state)
        refreshRunningAppCandidates(&state)
        return .none
    }

    func handleRunningAppCandidatesRefreshRequested(state: inout State) -> Effect<Action> {
        refreshRunningAppCandidates(&state)
        return .none
    }

    private func handleLaunchedApp(_ id: String, state: inout State) -> Effect<Action> {
        refreshRunningAppCandidates(&state)
        guard state.watchedApps.contains(where: { $0.bundleID == id && $0.isObserved }) else {
            return .none
        }
        state.runningWatchedIDs.insert(id)
        syncAssertion(&state)
        return .none
    }

    private func handleTerminatedApp(_ id: String, state: inout State) -> Effect<Action> {
        refreshRunningAppCandidates(&state)
        guard state.runningWatchedIDs.contains(id) else { return .none }
        if !lifecycle.runningBundleIDs().contains(id) {
            state.runningWatchedIDs.remove(id)
            syncAssertion(&state)
        }
        return .none
    }

    func reconcileRunning(_ state: inout State) {
        state.runningWatchedIDs = lifecycle.runningBundleIDs().intersection(observedIDs(in: state))
        syncAssertion(&state)
    }

    func refreshRunningAppCandidates(_ state: inout State) {
        state.runningAppCandidates = lifecycle.runningApps()
    }
}
