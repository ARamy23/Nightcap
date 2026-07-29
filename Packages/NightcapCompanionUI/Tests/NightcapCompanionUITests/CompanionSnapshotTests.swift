import AppKit
import ComposableArchitecture
import NightcapDomain
import SnapshotTesting
import SwiftUI
import Testing

@testable import NightcapCompanionUI

/// Layout pins for the companion rows. The presentation tests fix the wording;
/// these fix that the wording actually reaches the screen in a readable shape —
/// a regression the string tests cannot see.
///
/// Rendered through NSHostingView on the host, so they need no simulator. The
/// full-device iOS snapshots live in the phone app's own test target.
@MainActor
@Suite("Feature: How the companion rows render")
struct CompanionSnapshotTests {
    private func snapshot(
        _ view: some View,
        width: CGFloat = 320,
        height: CGFloat = 80,
        _ name: String,
        fileID: StaticString = #fileID,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let hosting = NSHostingView(rootView: VStack(alignment: .leading) { view })
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
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

    @Test("Scenario 1: the Mac is awake, held by one app")
    func statusAwake() {
        snapshot(
            MacStatusRow(isAwakeHeld: true, isWaiting: false, activeCount: 1),
            "status-awake-one-app"
        )
    }

    @Test("Scenario 2: the Mac is idle")
    func statusIdle() {
        snapshot(
            MacStatusRow(isAwakeHeld: false, isWaiting: false, activeCount: 0),
            "status-idle"
        )
    }

    @Test("Scenario 3: no status has arrived from the Mac yet")
    func statusWaiting() {
        snapshot(
            MacStatusRow(isAwakeHeld: false, isWaiting: true, activeCount: 0),
            "status-waiting"
        )
    }

    @Test("Scenario 4: a running watched app")
    func rowRunning() {
        snapshot(
            WatchedAppRow(
                app: WatchedApp(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty"),
                isRunning: true,
                onToggle: { _ in }
            ),
            height: 60,
            "row-running"
        )
    }

    @Test("Scenario 5: a paused watched app is labelled Paused")
    func rowPaused() {
        snapshot(
            WatchedAppRow(
                app: WatchedApp(bundleID: "us.zoom.xos", displayName: "zoom.us", isObserved: false),
                isRunning: false,
                onToggle: { _ in }
            ),
            height: 60,
            "row-paused"
        )
    }
}
