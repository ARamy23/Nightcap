import AppKit
import ComposableArchitecture
import NightcapDomain
import SnapshotTesting
import SwiftUI
import Testing

@testable import NightcapUI

/// `MenuContentView` is the whole menu assembled from its sections, and it is the
/// only place that decides *which* state each section sees — for example that the
/// "add running app" list must know the already-watched bundle IDs so it can grey
/// them out. The per-section snapshots cannot catch a mis-wiring there; these can.
@MainActor
@Suite("Feature: How the assembled menu renders")
struct MenuContentSnapshotTests {
    /// `@Shared(.fileStorage)` would otherwise read and write the real Documents
    /// directory, letting one test's watched list leak into the next.
    private func makeStore(
        _ mutate: (inout AppFeature.State) -> Void
    ) -> StoreOf<AppFeature> {
        withDependencies {
            $0.defaultFileStorage = .inMemory
            $0.macStatePublisherClient.publish = { _ in }
        } operation: {
            var state = AppFeature.State()
            state.$watchedApps.withLock { $0 = [] }
            mutate(&state)
            return Store(initialState: state) { AppFeature() }
        }
    }

    private func snapshot(
        _ store: StoreOf<AppFeature>,
        height: CGFloat,
        _ name: String,
        fileID: StaticString = #fileID,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let hosting = NSHostingView(
            rootView: VStack(alignment: .leading, spacing: 8) {
                MenuContentView(store: store)
            }
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: height)
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

    @Test("Scenario 1: a fresh install with nothing watched")
    func emptyMenu() {
        let store = makeStore { _ in }
        snapshot(store, height: 260, "menu-empty")
    }

    @Test("Scenario 2: one watched app is running and holding the Mac awake")
    func holdingAwake() {
        let store = makeStore { state in
            state.$watchedApps.withLock {
                $0 = [WatchedApp(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty")]
            }
            state.runningWatchedIDs = ["com.mitchellh.ghostty"]
            state.assertionHeld = true
            state.launchAtLoginStatus = .enabled
        }
        snapshot(store, height: 300, "menu-holding-awake")
    }

    @Test("Scenario 3: watched apps exist but none are running, so sleep is allowed")
    func watchedButIdle() {
        let store = makeStore { state in
            state.$watchedApps.withLock {
                $0 = [
                    WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode"),
                    WatchedApp(bundleID: "us.zoom.xos", displayName: "zoom.us", isObserved: false),
                ]
            }
            state.assertionHeld = false
            state.launchAtLoginStatus = .disabled
        }
        snapshot(store, height: 320, "menu-watched-but-idle")
    }

    @Test("Scenario 4: launch at login is waiting on approval in System Settings")
    func awaitingLoginApproval() {
        let store = makeStore { state in
            state.launchAtLoginStatus = .requiresApproval
        }
        snapshot(store, height: 300, "menu-requires-approval")
    }

    @Test("Scenario 5: a running candidate already watched is offered but disabled")
    func candidateAlreadyWatched() {
        // Given Xcode is both a running candidate and already watched, while
        // Zoom is only a candidate.
        let store = makeStore { state in
            state.$watchedApps.withLock {
                $0 = [WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode")]
            }
            state.runningAppCandidates = [
                WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode"),
                WatchedApp(bundleID: "us.zoom.xos", displayName: "zoom.us"),
            ]
        }
        snapshot(store, height: 300, "menu-candidate-already-watched")
    }

    @Test("Scenario 6: the add-running menu is told which bundles are already watched")
    func passesWatchedBundleIDsThrough() {
        // This is the wiring the per-section snapshots cannot see: if
        // MenuContentView stopped passing watchedBundleIDs down, the menu would
        // happily offer to add an app that is already in the list.
        let store = makeStore { state in
            state.$watchedApps.withLock {
                $0 = [
                    WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode"),
                    WatchedApp(bundleID: "us.zoom.xos", displayName: "zoom.us"),
                ]
            }
        }
        let view = MenuContentView(store: store)
        #expect(view.watchedBundleIDs == ["com.apple.dt.Xcode", "us.zoom.xos"])
    }
}
