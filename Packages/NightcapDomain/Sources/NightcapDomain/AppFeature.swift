import ComposableArchitecture
import Foundation
import OSLog
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
        public var hasLostNetwork = false
        public var connection: NetworkConnection = .other

        /// Exactly the fields the companions render, and nothing else.
        ///
        /// Separate from `macState` because `macState.lastUpdated` is `Date()`,
        /// freshly computed on every read — comparing two `macState` values is
        /// therefore always unequal and useless as a change signal.
        var companionSnapshot: CompanionSnapshot {
            CompanionSnapshot(
                isAwakeHeld: assertionHeld,
                watchedApps: watchedApps,
                runningWatchedIDs: runningWatchedIDs,
                hasLostNetwork: hasLostNetwork,
                connection: connection
            )
        }

        /// What the companion apps see.
        public var macState: MacState {
            MacState(
                isAwakeHeld: assertionHeld,
                watchedApps: watchedApps,
                runningWatchedIDs: runningWatchedIDs,
                lastUpdated: Date(),
                hasLostNetwork: hasLostNetwork,
                connection: connection
            )
        }

        public init() {}
    }

    /// The companion-visible slice of state, used only to decide when to publish.
    struct CompanionSnapshot: Equatable {
        let isAwakeHeld: Bool
        let watchedApps: [WatchedApp]
        let runningWatchedIDs: Set<String>
        let hasLostNetwork: Bool
        let connection: NetworkConnection
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
        case networkPathChanged(isSatisfied: Bool)
        case connectionChanged(NetworkConnection)
        case quitTapped
    }

    private enum CancelID { case lifecycle, launchAtLogin, networkPath, connection }

    @Dependency(\.appLifecycleClient) var lifecycle
    @Dependency(\.powerAssertionClient) var assertion
    @Dependency(\.launchAtLoginClient) var launchAtLogin
    @Dependency(\.appQuitterClient) var quitter
    @Dependency(\.reviewPromptClient) var reviewPrompt
    @Dependency(\.networkPathClient) var networkPath
    @Dependency(\.macStatePublisherClient) var publisher

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.launchAtLoginStatus = launchAtLogin.status()
                reconcileRunning(&state)
                refreshRunningAppCandidates(&state)
                return .merge(
                    .run { send in
                        for await event in lifecycle.events() {
                            await send(.lifecycleEvent(event))
                        }
                    }
                    .cancellable(id: CancelID.lifecycle, cancelInFlight: true),
                    .run { send in
                        for await isSatisfied in networkPath.isSatisfied() {
                            await send(.networkPathChanged(isSatisfied: isSatisfied))
                        }
                    }
                    .cancellable(id: CancelID.networkPath, cancelInFlight: true),
                    .run { send in
                        for await connection in networkPath.connection() {
                            await send(.connectionChanged(connection))
                        }
                    }
                    .cancellable(id: CancelID.connection, cancelInFlight: true)
                )

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

            case let .networkPathChanged(isSatisfied):
                let hasLostNetwork = !isSatisfied
                guard hasLostNetwork != state.hasLostNetwork else { return .none }
                state.hasLostNetwork = hasLostNetwork
                return .none

            case let .connectionChanged(connection):
                guard connection != state.connection else { return .none }
                state.connection = connection
                // Kept in step so the two cannot disagree: whichever stream
                // reports first, the companions see a consistent picture.
                state.hasLostNetwork = !connection.isConnected
                return .none

            case .quitTapped:
                assertion.release()
                state.assertionHeld = false
                quitter.quit()
                return .none
            }
        }
        // Publishing hangs off the state itself rather than off individual cases.
        // It used to be wired to the network-change case alone, which meant
        // adding an app, pausing one, or an app launching never reached the
        // companions: they showed whatever the Mac happened to be doing at
        // launch until the network flapped. Anything that changes what they
        // render now publishes, and nothing has to remember to ask.
        .onChange(of: \.companionSnapshot) { _, _ in
            Reduce { state, _ in
                publishEffect(state)
            }
        }
    }

    /// Companions only learn about the Mac when it says something, so publish
    /// after anything they render changes.
    private func publishEffect(_ state: State) -> Effect<Action> {
        let macState = state.macState
        return .run { _ in
            do {
                try await publisher.publish(macState)
            } catch {
                // Deliberately not surfaced in the UI: a failed publish costs the
                // user nothing on the Mac itself, and the menu bar is not the
                // place to report it. But it must not vanish either — swallowing
                // it makes a completely broken companion link look identical to a
                // working one, from the outside and from the logs.
                Logger.publishing.error(
                    "Failed to publish Mac state to companions: \(error.localizedDescription, privacy: .public)"
                )
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
