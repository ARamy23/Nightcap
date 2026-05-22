import ComposableArchitecture
import Foundation

extension AppFeature {
    func handleManualSessionStarted(
        _ duration: ManualSessionDuration,
        state: inout State
    ) -> Effect<Action> {
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
    }

    func handleManualSessionStopped(state: inout State) -> Effect<Action> {
        state.manualSession = nil
        syncAssertion(&state)
        return .cancel(id: CancelID.manualSession)
    }

    func handleManualSessionExpired(state: inout State) -> Effect<Action> {
        state.manualSession = nil
        syncAssertion(&state)
        return .none
    }
}
