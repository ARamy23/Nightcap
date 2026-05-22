import ComposableArchitecture
import Foundation

extension AppFeature {
    func handleManualSessionStarted(
        _ duration: ManualSessionDuration,
        state: inout State
    ) -> Effect<Action> {
        let revision = nextManualSessionRevision(&state)
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
            await send(.manualSessionExpired(revision))
        }
        .cancellable(id: CancelID.manualSession, cancelInFlight: true)
    }

    func handleManualSessionStopped(state: inout State) -> Effect<Action> {
        _ = nextManualSessionRevision(&state)
        state.manualSession = nil
        syncAssertion(&state)
        return .cancel(id: CancelID.manualSession)
    }

    func handleManualSessionExpired(
        _ revision: Int,
        state: inout State
    ) -> Effect<Action> {
        guard
            state.manualSessionRevision == revision,
            case .finite = state.manualSession
        else { return .none }

        _ = nextManualSessionRevision(&state)
        state.manualSession = nil
        syncAssertion(&state)
        return .none
    }

    private func nextManualSessionRevision(_ state: inout State) -> Int {
        state.manualSessionRevision += 1
        return state.manualSessionRevision
    }
}
