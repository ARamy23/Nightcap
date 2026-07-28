import Dependencies
import DependenciesMacros
import Foundation

/// How a companion app reads and influences the Mac.
///
/// Deliberately transport-agnostic. The live value today is a stub: shipping a
/// real transport means adding a network entitlement to a sandboxed App Store
/// app whose listing promises zero network calls, which is a separate decision.
@DependencyClient
public struct MacStateTransportClient: Sendable {
    /// A stream of Mac snapshots. Emits the current state immediately.
    public var states: @Sendable () -> AsyncStream<MacState> = { .finished }
    /// Ask the Mac to pause or resume watching an app.
    public var setObservation: @Sendable (_ bundleID: String, _ isObserved: Bool) async throws -> Void
    /// Ask the Mac for a fresh snapshot.
    public var refresh: @Sendable () async throws -> Void
}

extension MacStateTransportClient: TestDependencyKey {
    public static let testValue = MacStateTransportClient()

    /// An in-memory Mac that behaves plausibly, so the companion apps can be
    /// built and demoed end to end without a transport.
    public static func stub(initial: MacState = .preview) -> MacStateTransportClient {
        let box = StubBox(state: initial)
        return MacStateTransportClient(
            states: { box.stream() },
            setObservation: { bundleID, isObserved in
                box.setObservation(bundleID: bundleID, isObserved: isObserved)
            },
            refresh: { box.republish() }
        )
    }
}

extension MacStateTransportClient: DependencyKey {
    public static let liveValue = MacStateTransportClient.stub()
}

extension DependencyValues {
    public var macStateTransportClient: MacStateTransportClient {
        get { self[MacStateTransportClient.self] }
        set { self[MacStateTransportClient.self] = newValue }
    }
}

extension MacState {
    public static let preview = MacState(
        isAwakeHeld: true,
        watchedApps: [
            WatchedApp(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty"),
            WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode"),
            WatchedApp(bundleID: "us.zoom.xos", displayName: "zoom.us", isObserved: false),
        ],
        runningWatchedIDs: ["com.mitchellh.ghostty"],
        lastUpdated: Date(timeIntervalSince1970: 1_800_000_000)
    )
}

private final class StubBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state: MacState
    private var continuations: [UUID: AsyncStream<MacState>.Continuation] = [:]

    init(state: MacState) {
        self.state = state
    }

    func stream() -> AsyncStream<MacState> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            continuation.yield(state)
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.lock()
                continuations[id] = nil
                lock.unlock()
            }
        }
    }

    func setObservation(bundleID: String, isObserved: Bool) {
        lock.lock()
        if let index = state.watchedApps.firstIndex(where: { $0.bundleID == bundleID }) {
            state.watchedApps[index].isObserved = isObserved
            if isObserved {
                // The stub cannot know if the app is running, so treat a resume as
                // "running" only when it was already known to be running.
            } else {
                state.runningWatchedIDs.remove(bundleID)
            }
            state.isAwakeHeld = !state.runningWatchedIDs.isEmpty
        }
        let snapshot = state
        let targets = Array(continuations.values)
        lock.unlock()
        targets.forEach { $0.yield(snapshot) }
    }

    func republish() {
        lock.lock()
        let snapshot = state
        let targets = Array(continuations.values)
        lock.unlock()
        targets.forEach { $0.yield(snapshot) }
    }
}
