import ComposableArchitecture
import NightcapDomain
import Testing

@testable import NightcapUI

/// What each menu item actually does. The reducer tests pin what an action does
/// once it arrives; these pin that the menu sends the *right* action for the
/// *right* app — the wiring between a click and the reducer, which snapshots
/// cannot see and reducer tests never exercise.
@MainActor
@Suite("Feature: What the menu items do")
struct MenuIntentTests {
    private func makeStore(
        _ mutate: (inout AppFeature.State) -> Void = { _ in }
    ) -> StoreOf<AppFeature> {
        withDependencies {
            $0.defaultFileStorage = .inMemory
            // These tests are about which action a menu item sends, not what the
            // OS then does, so the adapters are stubbed rather than asserted on.
            $0.appLifecycleClient.runningBundleIDs = { [] }
            $0.appLifecycleClient.runningApps = { [] }
            $0.appLifecycleClient.events = { .finished }
            $0.powerAssertionClient.acquire = { _ in true }
            $0.powerAssertionClient.release = {}
            $0.launchAtLoginClient.status = { .enabled }
            $0.launchAtLoginClient.setEnabled = { _ in }
        } operation: {
            var state = AppFeature.State()
            state.$watchedApps.withLock { $0 = [] }
            mutate(&state)
            return Store(initialState: state) { AppFeature() }
        }
    }

    @Test("Scenario 1: pausing an app stops it being observed")
    func pauseApp() {
        // Given two watched apps
        let ghostty = WatchedApp(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty")
        let xcode = WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode")
        let store = makeStore { $0.$watchedApps.withLock { $0 = [ghostty, xcode] } }
        let view = MenuContentView(store: store)

        // When Pause Watching is chosen on Ghostty
        view.setObservation(ghostty.id, to: false)

        // Then only Ghostty is paused — the id must not be misrouted
        #expect(store.watchedApps.first { $0.id == ghostty.id }?.isObserved == false)
        #expect(store.watchedApps.first { $0.id == xcode.id }?.isObserved == true)
    }

    @Test("Scenario 2: resuming an app makes it observed again")
    func resumeApp() {
        let zoom = WatchedApp(bundleID: "us.zoom.xos", displayName: "zoom.us", isObserved: false)
        let store = makeStore { $0.$watchedApps.withLock { $0 = [zoom] } }
        let view = MenuContentView(store: store)

        view.setObservation(zoom.id, to: true)

        #expect(store.watchedApps.first?.isObserved == true)
    }

    @Test("Scenario 3: removing an app drops it from the list, leaving the rest")
    func removeApp() {
        let ghostty = WatchedApp(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty")
        let xcode = WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode")
        let store = makeStore { $0.$watchedApps.withLock { $0 = [ghostty, xcode] } }
        let view = MenuContentView(store: store)

        view.removeApp(ghostty.id)

        #expect(store.watchedApps.map(\.bundleID) == ["com.apple.dt.Xcode"])
    }

    @Test("Scenario 4: adding a running app puts it in the watched list")
    func addApp() {
        let store = makeStore()
        let view = MenuContentView(store: store)
        let xcode = WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode")

        view.addApp(xcode)

        #expect(store.watchedApps.map(\.bundleID) == ["com.apple.dt.Xcode"])
    }

    @Test("Scenario 5: toggling launch at login is reflected in the status")
    func setLaunchAtLogin() {
        let store = makeStore { $0.launchAtLoginStatus = .disabled }
        let view = MenuContentView(store: store)

        view.setLaunchAtLogin(true)

        #expect(store.launchAtLoginStatus != .disabled)
    }

    @Test("Scenario 6: refreshing candidates is accepted without disturbing the list")
    func refreshCandidates() {
        let ghostty = WatchedApp(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty")
        let store = makeStore { $0.$watchedApps.withLock { $0 = [ghostty] } }
        let view = MenuContentView(store: store)

        view.refreshCandidates()

        #expect(store.watchedApps.map(\.bundleID) == ["com.mitchellh.ghostty"])
    }

    @Test("Scenario 7: the section forwards a toggle for the app it was shown for")
    func sectionForwardsToggle() {
        // Given the watched-apps section
        let ghostty = WatchedApp(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty")
        let toggled = LockIsolated<[(WatchedApp.ID, Bool)]>([])
        let removed = LockIsolated<[WatchedApp.ID]>([])
        let section = WatchedAppsMenuSection(
            watchedApps: [ghostty],
            runningWatchedIDs: [],
            onObservationToggle: { id, isObserved in toggled.withValue { $0.append((id, isObserved)) } },
            onRemove: { id in removed.withValue { $0.append(id) } }
        )

        // When the menu's items are chosen
        section.setObservation(ghostty, to: false)
        section.remove(ghostty)

        // Then the app's own id travels with each, not a positional index
        #expect(toggled.value.map(\.0) == [ghostty.id])
        #expect(toggled.value.map(\.1) == [false])
        #expect(removed.value == [ghostty.id])
    }

    @Test("Scenario 8: the add-running menu forwards the chosen app and refreshes")
    func addRunningMenuForwards() {
        let xcode = WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode")
        let added = LockIsolated<[WatchedApp]>([])
        let refreshes = LockIsolated(0)
        let menu = AddRunningAppMenu(
            candidates: [xcode],
            watchedBundleIDs: [],
            onAdd: { app in added.withValue { $0.append(app) } },
            onRefresh: { refreshes.withValue { $0 += 1 } }
        )

        menu.add(xcode)
        menu.refresh()

        #expect(added.value == [xcode])
        #expect(refreshes.value == 1)
    }

    @Test(
        "Scenario 9: an already-watched candidate reads as ticked and is not clickable",
        arguments: [true, false]
    )
    func candidatePresentation(isAlreadyWatched: Bool) {
        let presentation = RunningAppCandidatePresentation(isAlreadyWatched: isAlreadyWatched)

        // A tick means "already handled", a plus means "you can add this" — and
        // the two must agree with whether the row is clickable, or the menu shows
        // a plus on a row that does nothing.
        #expect(presentation.iconName == (isAlreadyWatched ? "checkmark" : "plus"))
        #expect(presentation.isDisabled == isAlreadyWatched)
    }
}
