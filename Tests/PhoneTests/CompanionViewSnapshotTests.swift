import ComposableArchitecture
import SnapshotTesting
import SwiftUI
import Testing

@testable import NightcapCompanionUI
import Dependencies
import NightcapDomain

/// Snapshots pin the companion screen's layout for each state the user can
/// actually land in. They are recorded on a fixed device so a different
/// simulator does not silently rewrite them.
@MainActor
@Suite("Feature: How the companion screen looks")
struct CompanionViewSnapshotTests {
    private func view(_ macState: MacState, failure: String? = nil) -> some View {
        var state = CompanionFeature.State()
        state.macState = macState
        state.hasConnected = macState.lastUpdated != .distantPast
        state.failureMessage = failure
        // The view sends .onAppear, which subscribes to the transport. Without a
        // stub that hits the unimplemented test dependency and records an issue,
        // so these snapshots were passing only by timing luck.
        return CompanionView(
            store: Store(initialState: state) {
                CompanionFeature()
            } withDependencies: {
                $0.macStateTransportClient = .stub(initial: macState)
            }
        )
        .frame(width: 393, height: 852)
    }

    @Test("Scenario 1: the Mac is being kept awake")
    func keepingAwake() {
        assertSnapshot(of: view(.preview), as: .image(layout: .device(config: .iPhone13Pro)))
    }

    @Test("Scenario 2: the Mac is idle")
    func idle() {
        var macState = MacState.preview
        macState.isAwakeHeld = false
        macState.runningWatchedIDs = []
        assertSnapshot(of: view(macState), as: .image(layout: .device(config: .iPhone13Pro)))
    }

    @Test("Scenario 3: nothing has been heard from the Mac yet")
    func waitingForMac() {
        assertSnapshot(of: view(MacState()), as: .image(layout: .device(config: .iPhone13Pro)))
    }

    @Test("Scenario 4: the Mac could not be reached")
    func transportFailure() {
        assertSnapshot(
            of: view(.preview, failure: "Couldn't reach your Mac."),
            as: .image(layout: .device(config: .iPhone13Pro))
        )
    }
}
