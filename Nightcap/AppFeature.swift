import AppKit
import ComposableArchitecture
import Foundation
import Sharing

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.fileStorage(.documentsDirectory.appending(component: "watched-apps.json")))
        var watchedApps: [WatchedApp] = [.ghostty]
        var runningWatchedIDs: Set<String> = []
        var runningAppCandidates: [WatchedApp] = []
        var launchAtLoginStatus: LaunchAtLoginStatus = .unknown
        var manualSession: ManualSession?
        var assertionHeld = false
    }

    enum ManualSession: Equatable {
        case finite(ManualSessionDuration)
        case indefinite

        var statusText: String {
            switch self {
            case let .finite(duration):
                "Manual: \(duration.title)"
            case .indefinite:
                "Manual: Until turned off"
            }
        }

        var assertionReason: String {
            switch self {
            case let .finite(duration):
                "Manual keep awake (\(duration.shortTitle))"
            case .indefinite:
                "Manual keep awake"
            }
        }
    }

    enum ManualSessionDuration: Equatable, CaseIterable {
        case minutes15
        case hour1
        case indefinite

        var title: String {
            switch self {
            case .minutes15:
                "15 min"
            case .hour1:
                "1 hour"
            case .indefinite:
                "Until turned off"
            }
        }

        var shortTitle: String {
            switch self {
            case .minutes15:
                "15 min"
            case .hour1:
                "1 hour"
            case .indefinite:
                "until turned off"
            }
        }

        var finiteDuration: Duration? {
            switch self {
            case .minutes15:
                .seconds(15 * 60)
            case .hour1:
                .seconds(60 * 60)
            case .indefinite:
                nil
            }
        }
    }

    enum Action {
        case onAppear
        case lifecycleEvent(AppLifecycleClient.Event)
        case reconcile
        case runningAppCandidatesRefreshRequested
        case addAppRequested(WatchedApp)
        case removeAppRequested(WatchedApp.ID)
        case observationToggled(WatchedApp.ID, Bool)
        case manualSessionStarted(ManualSessionDuration)
        case manualSessionStopped
        case manualSessionExpired
        case launchAtLoginToggled(Bool)
        case launchAtLoginStatusUpdated(LaunchAtLoginStatus)
        case quitTapped
    }

    private enum CancelID { case lifecycle, launchAtLogin, manualSession }

    @Dependency(\.appLifecycleClient) var lifecycle
    @Dependency(\.powerAssertionClient) var assertion
    @Dependency(\.launchAtLoginClient) var launchAtLogin
    @Dependency(\.appQuitterClient) var quitter
    @Dependency(\.continuousClock) var clock

    var body: some ReducerOf<Self> {
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
                if !state.watchedApps.contains(where: { $0.bundleID == app.bundleID }) {
                    state.$watchedApps.withLock { $0.append(app) }
                }
                if lifecycle.runningBundleIDs().contains(app.bundleID) {
                    state.runningWatchedIDs.insert(app.bundleID)
                    syncAssertion(&state)
                }
                return .none

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

            case let .manualSessionStarted(duration):
                if duration == .indefinite {
                    state.manualSession = .indefinite
                    syncAssertion(&state)
                    return .cancel(id: CancelID.manualSession)
                }

                state.manualSession = .finite(duration)
                syncAssertion(&state)
                guard let finiteDuration = duration.finiteDuration else { return .none }
                return .run { send in
                    try await clock.sleep(for: finiteDuration)
                    await send(.manualSessionExpired)
                }
                .cancellable(id: CancelID.manualSession, cancelInFlight: true)

            case .manualSessionStopped:
                state.manualSession = nil
                syncAssertion(&state)
                return .cancel(id: CancelID.manualSession)

            case .manualSessionExpired:
                state.manualSession = nil
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
                state.manualSession = nil
                state.assertionHeld = false
                quitter.quit()
                return .cancel(id: CancelID.manualSession)
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
        let reasons = assertionReasons(in: state)
        if reasons.isEmpty {
            assertion.release()
            state.assertionHeld = false
        } else {
            state.assertionHeld = assertion.acquire("Nightcap: \(reasons.joined(separator: ", "))")
        }
    }

    private func assertionReasons(in state: State) -> [String] {
        let appNames = state.watchedApps
            .filter { state.runningWatchedIDs.contains($0.bundleID) }
            .map(\.displayName)

        guard let manualSession = state.manualSession else { return appNames }
        return appNames + [manualSession.assertionReason]
    }
}
