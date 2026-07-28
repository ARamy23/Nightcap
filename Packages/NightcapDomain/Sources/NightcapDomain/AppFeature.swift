import ComposableArchitecture
import Foundation
import Sharing

@Reducer
public struct AppFeature {
    @ObservableState
    public struct State: Equatable {
        @Shared(.fileStorage(.documentsDirectory.appending(component: "watched-apps.json")))
        public var watchedApps: [WatchedApp] = [.ghostty]
        public var runningWatchedIDs: Set<String> = []
        public var runningAppCandidates: [WatchedApp] = []
        public var launchAtLoginStatus: LaunchAtLoginStatus = .unknown
        public var assertionHeld = false

        public init() {}
    }

    public enum Action {
        case onAppear
        case lifecycleEvent(AppLifecycleClient.Event)
        case reconcile
        case runningAppCandidatesRefreshRequested
        case addAppRequested(WatchedApp)
        case removeAppRequested(WatchedApp.ID)
        case observationToggled(WatchedApp.ID, Bool)
        case launchAtLoginToggled(Bool)
        case launchAtLoginStatusUpdated(LaunchAtLoginStatus)
        case quitTapped
    }

    private enum CancelID { case lifecycle, launchAtLogin }

    @Dependency(\.appLifecycleClient) var lifecycle
    @Dependency(\.powerAssertionClient) var assertion
    @Dependency(\.launchAtLoginClient) var launchAtLogin
    @Dependency(\.appQuitterClient) var quitter
    @Dependency(\.reviewPromptClient) var reviewPrompt

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.launchAtLoginStatus = launchAtLogin.status()
                reconcileRunning(&state)
                refreshRunningAppCandidates(&state)
                return .run { send in
                    for await event in lifecycle.events() {
                        await send(.lifecycleEvent(event))
                    }
                }
                .cancellable(id: CancelID.lifecycle, cancelInFlight: true)

            case let .lifecycleEvent(.launched(id)):
                refreshRunningAppCandidates(&state)
                guard state.watchedApps.contains(where: { $0.bundleID == id && $0.isObserved }) else { return .none }
                state.runningWatchedIDs.insert(id)
                syncAssertion(&state)
                return .none

            case let .lifecycleEvent(.terminated(id)):
                refreshRunningAppCandidates(&state)
                guard state.runningWatchedIDs.contains(id) else { return .none }
                if !lifecycle.runningBundleIDs().contains(id) {
                    state.runningWatchedIDs.remove(id)
                    syncAssertion(&state)
                }
                return .none

            case .lifecycleEvent(.wake), .reconcile:
                reconcileRunning(&state)
                refreshRunningAppCandidates(&state)
                return .none

            case .runningAppCandidatesRefreshRequested:
                refreshRunningAppCandidates(&state)
                return .none

            case let .addAppRequested(app):
                guard !state.watchedApps.contains(where: { $0.bundleID == app.bundleID }) else { return .none }
                state.$watchedApps.withLock { $0.append(app) }
                if lifecycle.runningBundleIDs().contains(app.bundleID) {
                    state.runningWatchedIDs.insert(app.bundleID)
                    syncAssertion(&state)
                }
                return .run { _ in
                    reviewPrompt.requestIfAppropriate()
                }

            case let .removeAppRequested(id):
                state.$watchedApps.withLock { $0.removeAll { $0.bundleID == id } }
                if state.runningWatchedIDs.remove(id) != nil {
                    syncAssertion(&state)
                }
                return .none

            case let .observationToggled(id, isObserved):
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

            case let .launchAtLoginToggled(enable):
                let previous = state.launchAtLoginStatus
                state.launchAtLoginStatus = enable ? .enabled : .disabled
                return .run { send in
                    do {
                        try launchAtLogin.setEnabled(enable)
                        let actual = launchAtLogin.status()
                        let resolved: LaunchAtLoginStatus
                        switch actual {
                        case .enabled, .disabled, .requiresApproval:
                            resolved = actual
                        case .unknown, .error:
                            resolved = enable ? .enabled : .disabled
                        }
                        await send(.launchAtLoginStatusUpdated(resolved))
                    } catch {
                        await send(.launchAtLoginStatusUpdated(previous))
                    }
                }
                .cancellable(id: CancelID.launchAtLogin, cancelInFlight: true)

            case let .launchAtLoginStatusUpdated(status):
                state.launchAtLoginStatus = status
                return .none

            case .quitTapped:
                assertion.release()
                state.assertionHeld = false
                quitter.quit()
                return .none
            }
        }
    }

    private func reconcileRunning(_ state: inout State) {
        state.runningWatchedIDs = lifecycle.runningBundleIDs().intersection(observedIDs(in: state))
        syncAssertion(&state)
    }

    private func observedIDs(in state: State) -> Set<String> {
        Set(state.watchedApps.filter(\.isObserved).map(\.bundleID))
    }

    private func refreshRunningAppCandidates(_ state: inout State) {
        state.runningAppCandidates = lifecycle.runningApps()
    }

    private func syncAssertion(_ state: inout State) {
        if state.runningWatchedIDs.isEmpty {
            assertion.release()
            state.assertionHeld = false
        } else {
            let names = state.watchedApps
                .filter { state.runningWatchedIDs.contains($0.bundleID) }
                .map(\.displayName)
                .joined(separator: ", ")
            state.assertionHeld = assertion.acquire("Nightcap: \(names)")
        }
    }
}
