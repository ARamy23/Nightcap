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
        /// True once the Mac's last report is old enough that it has plainly
        /// stopped talking to us.
        public var hasLostContactWithMac = false

        public init() {}

        /// How long a silence means the Mac is gone rather than merely quiet.
        ///
        /// The transport polls every 30s and the Mac republishes on every change,
        /// so three minutes is several missed cycles — long enough not to fire on
        /// a hiccup, short enough to catch a closed lid before the user has
        /// wandered off.
        public static let contactTimeout: TimeInterval = 180

        /// Nothing has arrived yet, so the UI should say so rather than claim the
        /// Mac is idle.
        public var isWaitingForMac: Bool { !hasConnected }

        /// Whether the Mac's own report is older than the timeout.
        ///
        /// Judged from `lastUpdated` rather than from whether a fetch succeeded:
        /// a sleeping Mac leaves its last record sitting in CloudKit, so the
        /// fetch keeps succeeding and returning the same stale snapshot. Silence
        /// is the only signal a Mac that has gone away can send.
        public func hasLostContact(asOf now: Date) -> Bool {
            guard hasConnected else { return false }
            return now.timeIntervalSince(macState.lastUpdated) > Self.contactTimeout
        }
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
    @Dependency(\.hotspotNotifierClient) var notifier
    @Dependency(\.date.now) var now

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .merge(
                    .run { send in
                        for await macState in transport.states() {
                            await send(.macStateReceived(macState))
                        }
                    }
                    .cancellable(id: CancelID.states, cancelInFlight: true),
                    // Asked here rather than at launch so the prompt arrives
                    // with the screen that explains what it is for. Declining
                    // costs only the alert; the in-app banner still works.
                    .run { _ in _ = await notifier.requestAuthorization() }
                )

            case .onDisappear:
                // Stop listening when the companion goes to the background, so a
                // watch app is not holding a stream open behind the user's back.
                return .cancel(id: CancelID.states)

            case let .macStateReceived(macState):
                // Edge, not level: the transport re-delivers the same state on
                // every poll, so notifying on the value would fire every 30
                // seconds for as long as the Mac stayed offline.
                let shouldAlert = macState.shouldSuggestHotspot
                    && !state.macState.shouldSuggestHotspot
                let wasOutOfContact = state.hasLostContactWithMac
                state.macState = macState
                state.hasConnected = true
                state.failureMessage = nil
                state.hasLostContactWithMac = state.hasLostContact(asOf: now)

                // Contact loss outranks the hotspot nudge: if the Mac has gone
                // silent we do not actually know its network state, and the
                // snapshot we are holding may be minutes old.
                if state.hasLostContactWithMac, !wasOutOfContact {
                    return .run { _ in
                        await notifier.notify(
                            "Lost contact with your Mac",
                            "It hasn't reported in. It may have slept or dropped off the network."
                        )
                    }
                }

                guard shouldAlert, !state.hasLostContactWithMac else { return .none }
                return .run { _ in
                    await notifier.notify(
                        "Your Mac lost its network",
                        "Turn on Personal Hotspot to keep it online."
                    )
                }

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
