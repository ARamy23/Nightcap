import ComposableArchitecture
import Foundation
import Sharing

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.fileStorage(.documentsDirectory.appending(component: "watched-apps.json")))
        var watchedApps: [WatchedApp] = []
        var runningWatchedIDs: Set<String> = []
        var runningAppCandidates: [WatchedApp] = []
        var launchAtLoginStatus: LaunchAtLoginStatus = .unknown
        var manualSession: ManualSession?
        var assertionHeld = false
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

    enum CancelID { case lifecycle, launchAtLogin, manualSession }

    @Dependency(\.appLifecycleClient) var lifecycle
    @Dependency(\.powerAssertionClient) var assertion
    @Dependency(\.launchAtLoginClient) var launchAtLogin
    @Dependency(\.appQuitterClient) var quitter
    @Dependency(\.continuousClock) var clock

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return handleOnAppear(state: &state)

            case let .lifecycleEvent(event):
                return handleLifecycleEvent(event, state: &state)

            case .reconcile:
                return handleReconcile(state: &state)

            case .runningAppCandidatesRefreshRequested:
                return handleRunningAppCandidatesRefreshRequested(state: &state)

            case let .addAppRequested(app):
                return handleAddAppRequested(app, state: &state)

            case let .removeAppRequested(id):
                return handleRemoveAppRequested(id, state: &state)

            case let .observationToggled(id, isObserved):
                return handleObservationToggled(id, isObserved: isObserved, state: &state)

            case let .manualSessionStarted(duration):
                return handleManualSessionStarted(duration, state: &state)

            case .manualSessionStopped:
                return handleManualSessionStopped(state: &state)

            case .manualSessionExpired:
                return handleManualSessionExpired(state: &state)

            case let .launchAtLoginToggled(enable):
                return handleLaunchAtLoginToggled(enable, state: &state)

            case let .launchAtLoginStatusUpdated(status):
                state.launchAtLoginStatus = status
                return .none

            case .quitTapped:
                return handleQuitTapped(state: &state)
            }
        }
    }
}
