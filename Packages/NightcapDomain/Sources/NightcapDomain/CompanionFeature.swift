import ComposableArchitecture
import Foundation

/// Drives both the iPhone and the Watch app. Neither platform owns any logic of
/// its own: they differ only in how they render this state.
@Reducer
public struct CompanionFeature {
    @ObservableState
    public struct State: Equatable {
        public var macState: MacState = MacState()
        public var hasConnected = false
        public var failureMessage: String?

        public init() {}

        /// Nothing has arrived yet, so the UI should say so rather than claim the
        /// Mac is idle.
        public var isWaitingForMac: Bool { !hasConnected }
    }

    public enum Action {
        case onAppear
        case onDisappear
        case macStateReceived(MacState)
        case observationToggled(String, Bool)
        case refreshRequested
        case failed(String)
    }

    private enum CancelID { case states }

    @Dependency(\.macStateTransportClient) var transport

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    for await macState in transport.states() {
                        await send(.macStateReceived(macState))
                    }
                }
                .cancellable(id: CancelID.states, cancelInFlight: true)

            case .onDisappear:
                // Stop listening when the companion goes to the background, so a
                // watch app is not holding a stream open behind the user's back.
                return .cancel(id: CancelID.states)

            case let .macStateReceived(macState):
                state.macState = macState
                state.hasConnected = true
                state.failureMessage = nil
                return .none

            case let .observationToggled(bundleID, isObserved):
                return .run { send in
                    do {
                        try await transport.setObservation(bundleID, isObserved)
                    } catch {
                        await send(.failed("Couldn't reach your Mac."))
                    }
                }

            case .refreshRequested:
                return .run { send in
                    do {
                        try await transport.refresh()
                    } catch {
                        await send(.failed("Couldn't reach your Mac."))
                    }
                }

            case let .failed(message):
                state.failureMessage = message
                return .none
            }
        }
    }
}
