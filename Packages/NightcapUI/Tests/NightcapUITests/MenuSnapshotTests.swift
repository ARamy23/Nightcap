import AppKit
import ComposableArchitecture
import NightcapDomain
import SnapshotTesting
import SwiftUI
import Testing

@testable import NightcapUI

/// The menu bar is Nightcap's entire interface, and it branches on state the
/// reducer tests already pin: empty list, running app, paused app, launch-at-login
/// needing approval. Snapshots catch a regression in how those branches *render*,
/// which no reducer test can see.
///
/// These render through NSHostingView rather than a running app, so they need no
/// Xcode scheme and no simulator.
@MainActor
@Suite("Feature: How the menu bar renders")
struct MenuSnapshotTests {
    private func snapshot(
        _ view: some View,
        width: CGFloat = 320,
        height: CGFloat = 160,
        _ name: String,
        fileID: StaticString = #fileID,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let hosting = NSHostingView(rootView: VStack(alignment: .leading, spacing: 8) { view })
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

    @Test("Scenario 1: the Mac is being kept awake by one app")
    func statusKeepingAwake() {
        snapshot(
            MenuStatusSection(assertionHeld: true, activeAppCount: 1),
            height: 80,
            "keeping-awake-one-app"
        )
    }

    @Test("Scenario 2: several apps are keeping the Mac awake")
    func statusKeepingAwakeMultiple() {
        snapshot(
            MenuStatusSection(assertionHeld: true, activeAppCount: 3),
            height: 80,
            "keeping-awake-three-apps"
        )
    }

    @Test("Scenario 3: nothing is watched, so sleep is allowed")
    func statusIdle() {
        snapshot(
            MenuStatusSection(assertionHeld: false, activeAppCount: 0),
            height: 80,
            "idle"
        )
    }

    @Test("Scenario 4: the watched list is empty")
    func watchedListEmpty() {
        snapshot(
            WatchedAppsMenuSection(
                watchedApps: [],
                runningWatchedIDs: [],
                onObservationToggle: { _, _ in },
                onRemove: { _ in }
            ),
            height: 60,
            "watched-list-empty"
        )
    }

    @Test("Scenario 5: the list shows running, idle and paused apps distinctly")
    func watchedListMixedStates() {
        snapshot(
            WatchedAppsMenuSection(
                watchedApps: [
                    WatchedApp(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty"),
                    WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode"),
                    WatchedApp(bundleID: "us.zoom.xos", displayName: "zoom.us", isObserved: false),
                ],
                runningWatchedIDs: ["com.mitchellh.ghostty"],
                onObservationToggle: { _, _ in },
                onRemove: { _ in }
            ),
            height: 140,
            "watched-list-mixed"
        )
    }

    @Test("Scenario 6: no apps are running to add")
    func addRunningAppEmpty() {
        snapshot(
            AddRunningAppMenu(
                candidates: [],
                watchedBundleIDs: [],
                onAdd: { _ in },
                onRefresh: {}
            ),
            height: 60,
            "add-running-empty"
        )
    }

    @Test("Scenario 7: an already-watched candidate is offered but disabled")
    func addRunningAppWithAlreadyWatched() {
        snapshot(
            AddRunningAppMenu(
                candidates: [
                    WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode"),
                    WatchedApp(bundleID: "us.zoom.xos", displayName: "zoom.us"),
                ],
                watchedBundleIDs: ["com.apple.dt.Xcode"],
                onAdd: { _ in },
                onRefresh: {}
            ),
            height: 80,
            "add-running-with-watched"
        )
    }

    @Test("Scenario 8: launch at login needs approval in System Settings")
    func actionsRequiringApproval() {
        snapshot(
            MenuActionsSection(
                launchAtLoginStatus: .requiresApproval,
                onLaunchAtLoginToggle: { _ in },
                onQuit: {}
            ),
            height: 140,
            "actions-requires-approval"
        )
    }

    @Test("Scenario 9: launch at login is simply on")
    func actionsLaunchAtLoginEnabled() {
        snapshot(
            MenuActionsSection(
                launchAtLoginStatus: .enabled,
                onLaunchAtLoginToggle: { _ in },
                onQuit: {}
            ),
            height: 120,
            "actions-launch-at-login-on"
        )
    }
}
