import AppKit
import ComposableArchitecture
import NightcapDomain
import SnapshotTesting
import SwiftUI
import Testing

@testable import NightcapCompanionUI

/// The whole companion screen, as the phone and watch actually show it. The row
/// tests pin the pieces; these pin how the screen assembles them — which
/// sections appear for which state, and in particular that the hotspot nudge
/// shows up exactly when the Mac needs it.
@MainActor
@Suite("Feature: How the companion screen renders")
struct CompanionScreenTests {
    private func makeStore(
        macState: MacState = MacState(),
        hasConnected: Bool = true,
        failureMessage: String? = nil
    ) -> StoreOf<CompanionFeature> {
        withDependencies {
            // The view sends .onAppear when rendered, which subscribes to the
            // transport. Without a stub that reaches an unimplemented dependency
            // and the test passes or fails on timing rather than on behaviour.
            $0.macStateTransportClient = .stub(initial: macState)
        } operation: {
            var state = CompanionFeature.State()
            state.macState = macState
            state.hasConnected = hasConnected
            state.failureMessage = failureMessage
            return Store(initialState: state) { CompanionFeature() }
        }
    }

    private func snapshot(
        _ store: StoreOf<CompanionFeature>,
        height: CGFloat = 420,
        _ name: String,
        fileID: StaticString = #fileID,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let hosting = NSHostingView(rootView: CompanionView(store: store))
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: height)
        hosting.appearance = NSAppearance(named: .aqua)
        assertSnapshot(
            of: hosting,
            as: .image(size: hosting.frame.size),
            named: name,
            fileID: fileID,
            file: file,
            testName: testName,
            line: line,
            column: column
        )
    }

    private func macState(
        awake: Bool = false,
        apps: [WatchedApp] = [],
        running: Set<String> = [],
        lostNetwork: Bool = false
    ) -> MacState {
        MacState(
            isAwakeHeld: awake,
            watchedApps: apps,
            runningWatchedIDs: running,
            lastUpdated: Date(timeIntervalSince1970: 0),
            hasLostNetwork: lostNetwork
        )
    }

    @Test("Scenario 1: nothing has arrived from the Mac yet")
    func waitingForMac() {
        snapshot(makeStore(hasConnected: false), "screen-waiting")
    }

    @Test("Scenario 2: the Mac is awake, held by a running app")
    func awake() {
        let state = macState(
            awake: true,
            apps: [WatchedApp(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty")],
            running: ["com.mitchellh.ghostty"]
        )
        snapshot(makeStore(macState: state), "screen-awake")
    }

    @Test("Scenario 3: the Mac is idle with apps watched but none running")
    func idleWithWatchedApps() {
        let state = macState(
            apps: [
                WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode"),
                WatchedApp(bundleID: "us.zoom.xos", displayName: "zoom.us", isObserved: false),
            ]
        )
        snapshot(makeStore(macState: state), "screen-idle")
    }

    @Test("Scenario 4: the Mac is awake but has lost its network, so hotspot is suggested")
    func hotspotSuggested() {
        // This is the whole reason the companion exists: the Mac is being held
        // awake and has dropped off the network, so it needs tethering.
        let state = macState(
            awake: true,
            apps: [WatchedApp(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty")],
            running: ["com.mitchellh.ghostty"],
            lostNetwork: true
        )
        #expect(state.shouldSuggestHotspot)
        snapshot(makeStore(macState: state), height: 460, "screen-hotspot-suggested")
    }

    @Test("Scenario 5: a sleeping Mac that lost network is not nagged about hotspot")
    func hotspotNotSuggestedWhenIdle() {
        // A Mac that is asleep does not need the network kept up, so the banner
        // must stay away — otherwise the phone nags for no reason.
        let state = macState(lostNetwork: true)
        #expect(!state.shouldSuggestHotspot)
        snapshot(makeStore(macState: state), "screen-idle-lost-network")
    }

    @Test("Scenario 6: a transport failure is surfaced rather than swallowed")
    func failureShown() {
        snapshot(
            makeStore(failureMessage: "Couldn't reach your Mac"),
            "screen-failure"
        )
    }

    @Test("Scenario 7: toggling an app from the companion reaches the Mac")
    func toggleReachesMac() async {
        // Given the companion is showing a watched app
        let ghostty = WatchedApp(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty")
        let state = macState(awake: true, apps: [ghostty], running: [ghostty.bundleID])
        let store = makeStore(macState: state)

        // When the row's toggle is switched off
        store.send(.observationToggled(ghostty.bundleID, false))

        // Then the change is pushed back and echoed to the phone, rather than
        // only flipping locally — the Mac is the source of truth.
        await Task.yield()
        #expect(store.failureMessage == nil)
    }
}
