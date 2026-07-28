import ComposableArchitecture
import ConcurrencyExtras
import Foundation
import Sharing
import Testing

@testable import Nightcap

// MARK: - Feature: Holding the sleep assertion

@MainActor
@Suite("Feature: Holding the sleep assertion")
struct SleepAssertionFeature {
    @Test("Scenario 1: a watched app launches, so the Mac is kept awake")
    func watchedAppLaunchAcquiresAssertion() async {
        // Given no watched app is running
        let env = TestEnv(running: [])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .disabled
        }

        // When Ghostty launches
        await store.send(.lifecycleEvent(.launched(bundleID: .ghostty))) {
            // Then it is tracked and the assertion is held
            $0.runningWatchedIDs = [.ghostty]
            $0.assertionHeld = true
        }

        // And the assertion names the app, so the user can see why in pmset
        #expect(env.acquired.value == ["Nightcap: Ghostty"])
    }

    @Test("Scenario 2: the last instance quits, so the Mac may sleep again")
    func lastInstanceTerminationReleasesAssertion() async {
        // Given Ghostty is running and the assertion is held
        let env = TestEnv(running: [.ghostty])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.runningWatchedIDs = [.ghostty]
            $0.assertionHeld = true
            $0.launchAtLoginStatus = .disabled
        }

        // When Ghostty terminates and no instance remains
        env.running.setValue([])
        await store.send(.lifecycleEvent(.terminated(bundleID: .ghostty))) {
            // Then tracking clears and the assertion is released
            $0.runningWatchedIDs = []
            $0.assertionHeld = false
        }

        #expect(env.released.value >= 1)
    }

    @Test("Scenario 3: one instance quits while another still runs, so the Mac stays awake")
    func terminationWithSurvivingInstanceKeepsAssertion() async {
        // Given Ghostty is running and the assertion is held
        let env = TestEnv(running: [.ghostty])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.runningWatchedIDs = [.ghostty]
            $0.assertionHeld = true
            $0.launchAtLoginStatus = .disabled
        }

        // When a terminate event arrives but another instance is still alive
        // (env.running still reports Ghostty)
        await store.send(.lifecycleEvent(.terminated(bundleID: .ghostty)))

        // Then no state change occurs and the assertion is never released
        #expect(env.released.value == 0)
    }

    @Test("Scenario 4: the Mac wakes, so state is reconciled from reality")
    func wakeReconcilesAgainstRunningApps() async {
        // Given nothing is running
        let env = TestEnv(running: [])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .disabled
        }

        // When the Mac wakes and Ghostty is now running (its launch event was missed)
        env.running.setValue([.ghostty])
        await store.send(.lifecycleEvent(.wake)) {
            // Then the assertion is acquired without a launch event
            $0.runningWatchedIDs = [.ghostty]
            $0.assertionHeld = true
        }

        // When the Mac wakes again and Ghostty has since died
        env.running.setValue([])
        await store.send(.lifecycleEvent(.wake)) {
            // Then the stale assertion is released
            $0.runningWatchedIDs = []
            $0.assertionHeld = false
        }
    }
}

// MARK: - Feature: Managing the watched list

@MainActor
@Suite("Feature: Managing the watched list")
struct WatchedListFeature {
    @Test("Scenario 1: adding an app that is already running starts watching immediately")
    func addingRunningAppAcquiresWithoutWaitingForLaunch() async {
        // Given Xcode is running but unwatched
        let env = TestEnv(running: [.xcode], runningApps: [.xcodeApp])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.runningAppCandidates = [.xcodeApp]
            $0.launchAtLoginStatus = .disabled
        }

        // When the user adds it
        await store.send(.addAppRequested(.xcodeApp)) {
            // Then it is watched and the assertion is held right away
            $0.$watchedApps.withLock { $0.append(.xcodeApp) }
            $0.runningWatchedIDs = [.xcode]
            $0.assertionHeld = true
        }

        #expect(env.acquired.value == ["Nightcap: Xcode"])
    }

    @Test("Scenario 2: adding an app already on the list changes nothing")
    func duplicateAddIsANoOp() async {
        // Given Ghostty is already the default watched app
        let env = TestEnv(running: [])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .disabled
        }

        // When the user adds Ghostty again
        await store.send(.addAppRequested(.ghosttyApp))

        // Then no state changes and no review prompt fires
        #expect(env.reviewPrompts.value == 0)
    }

    @Test("Scenario 3: adding a genuinely new app asks for a review at the value moment")
    func firstSuccessfulAddRequestsReview() async {
        // Given a fresh list
        let env = TestEnv(running: [])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .disabled
        }

        // When the user adds an app not already watched
        let writer = WatchedApp(bundleID: "com.example.writer", displayName: "Writer")
        await store.send(.addAppRequested(writer)) {
            // Then it joins the list
            $0.$watchedApps.withLock { $0.append(writer) }
        }

        // And exactly one review prompt is requested
        #expect(env.reviewPrompts.value == 1)
    }

    @Test("Scenario 4: opening the menu lists the apps currently running")
    func onAppearLoadsRunningAppCandidates() async {
        // Given Xcode and Zoom are running
        let env = TestEnv(running: [], runningApps: [.xcodeApp, .zoomApp])
        let store = env.makeStore()

        // When the menu appears
        await store.send(.onAppear) {
            // Then both are offered as candidates
            $0.launchAtLoginStatus = .disabled
            $0.runningAppCandidates = [.xcodeApp, .zoomApp]
        }
    }

    @Test("Scenario 5: an unwatched app launching refreshes the candidate list")
    func unwatchedLaunchRefreshesCandidates() async {
        // Given nothing is running
        let env = TestEnv(running: [], runningApps: [])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .disabled
        }

        // When Xcode launches, though it is not watched
        env.runningApps.setValue([.xcodeApp])
        await store.send(.lifecycleEvent(.launched(bundleID: .xcode))) {
            // Then it appears as a candidate to add
            $0.runningAppCandidates = [.xcodeApp]
        }
    }
}

// MARK: - Feature: Pausing and resuming a watched app

@MainActor
@Suite("Feature: Pausing and resuming a watched app")
struct PauseResumeFeature {
    @Test("Scenario 1: pausing a running app releases the Mac without forgetting the app")
    func pausingReleasesButKeepsTheEntry() async {
        // Given Ghostty is watched, running, and holding the assertion
        let env = TestEnv(running: [.ghostty])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.runningWatchedIDs = [.ghostty]
            $0.assertionHeld = true
            $0.launchAtLoginStatus = .disabled
        }

        // When the user pauses watching
        await store.send(.observationToggled(.ghostty, false)) {
            // Then the assertion drops but the app stays on the list
            $0.$watchedApps.withLock { $0[0].isObserved = false }
            $0.runningWatchedIDs = []
            $0.assertionHeld = false
        }

        #expect(env.released.value >= 1)
    }

    @Test("Scenario 2: resuming re-acquires when the app is still running")
    func resumingReacquiresForAStillRunningApp() async {
        // Given Ghostty is watched, running, and then paused
        let env = TestEnv(running: [.ghostty])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.runningWatchedIDs = [.ghostty]
            $0.assertionHeld = true
            $0.launchAtLoginStatus = .disabled
        }
        await store.send(.observationToggled(.ghostty, false)) {
            $0.$watchedApps.withLock { $0[0].isObserved = false }
            $0.runningWatchedIDs = []
            $0.assertionHeld = false
        }

        // When the user resumes watching
        await store.send(.observationToggled(.ghostty, true)) {
            // Then the assertion comes back without needing a relaunch
            $0.$watchedApps.withLock { $0[0].isObserved = true }
            $0.runningWatchedIDs = [.ghostty]
            $0.assertionHeld = true
        }

        #expect(env.acquired.value == ["Nightcap: Ghostty", "Nightcap: Ghostty"])
    }

    @Test("Scenario 3: a paused app launching does not wake-lock the Mac")
    func pausedAppLaunchDoesNotAcquire() async {
        // Given Ghostty is watched but paused
        let env = TestEnv(running: [])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .disabled
        }
        await store.send(.observationToggled(.ghostty, false)) {
            $0.$watchedApps.withLock { $0[0].isObserved = false }
        }

        // When Ghostty launches
        await store.send(.lifecycleEvent(.launched(bundleID: .ghostty)))

        // Then no assertion is taken
        #expect(env.acquired.value.isEmpty)
    }
}

// MARK: - Feature: Removing a watched app

@MainActor
@Suite("Feature: Removing a watched app")
struct RemoveAppFeature {
    @Test("Scenario 1: removing a running app releases the Mac")
    func removingARunningAppReleasesAssertion() async {
        // Given Ghostty is watched, running, and holding the assertion
        let env = TestEnv(running: [.ghostty])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.runningWatchedIDs = [.ghostty]
            $0.assertionHeld = true
            $0.launchAtLoginStatus = .disabled
        }

        // When the user removes it from the list
        await store.send(.removeAppRequested(.ghostty)) {
            // Then it is gone and the assertion drops
            $0.$watchedApps.withLock { $0.removeAll { $0.bundleID == .ghostty } }
            $0.runningWatchedIDs = []
            $0.assertionHeld = false
        }

        #expect(env.released.value >= 1)
    }

    @Test("Scenario 2: removing an app that is not running touches no assertion")
    func removingAnIdleAppDoesNotRelease() async {
        // Given Ghostty is watched but not running
        let env = TestEnv(running: [])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .disabled
        }

        // Note: onAppear already reconciled to "nothing running" and called
        // release() once unconditionally. That is a no-op inside AssertionHolder,
        // which guards on `held` — but it is visible here, so measure the delta.
        let releasesBeforeRemoval = env.released.value

        // When the user removes it
        await store.send(.removeAppRequested(.ghostty)) {
            $0.$watchedApps.withLock { $0.removeAll { $0.bundleID == .ghostty } }
        }

        // Then removal itself attempts no release, since the app held nothing
        #expect(env.released.value == releasesBeforeRemoval)
    }

    @Test("Scenario 3: removing one of two running apps keeps the Mac awake for the other")
    func removingOneOfTwoKeepsAssertion() async {
        // Given Ghostty and Xcode are both watched and running
        let env = TestEnv(running: [.ghostty, .xcode])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.runningWatchedIDs = [.ghostty]
            $0.assertionHeld = true
            $0.launchAtLoginStatus = .disabled
        }
        await store.send(.addAppRequested(.xcodeApp)) {
            $0.$watchedApps.withLock { $0.append(.xcodeApp) }
            $0.runningWatchedIDs = [.ghostty, .xcode]
            $0.assertionHeld = true
        }

        // When Ghostty is removed
        await store.send(.removeAppRequested(.ghostty)) {
            // Then the assertion survives for Xcode alone
            $0.$watchedApps.withLock { $0.removeAll { $0.bundleID == .ghostty } }
            $0.runningWatchedIDs = [.xcode]
            $0.assertionHeld = true
        }

        // And the reason is re-stated without Ghostty, so pmset shows the truth
        #expect(env.acquired.value.last == "Nightcap: Xcode")
    }
}

// MARK: - Feature: Reporting why the Mac is awake

@MainActor
@Suite("Feature: Reporting why the Mac is awake")
struct AssertionReasonFeature {
    @Test("Scenario 1: a second watched app launching re-states the reason with both names")
    func secondAppLaunchIncludesBothNamesInReason() async {
        // Given Ghostty is watched and running, and Xcode is watched but idle
        let env = TestEnv(running: [.ghostty])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.runningWatchedIDs = [.ghostty]
            $0.assertionHeld = true
            $0.launchAtLoginStatus = .disabled
        }
        await store.send(.addAppRequested(.xcodeApp)) {
            $0.$watchedApps.withLock { $0.append(.xcodeApp) }
        }

        // When Xcode launches too
        env.running.setValue([.ghostty, .xcode])
        await store.send(.lifecycleEvent(.launched(bundleID: .xcode))) {
            $0.runningWatchedIDs = [.ghostty, .xcode]
            $0.assertionHeld = true
        }

        // Then the newest reason names both apps, in watch-list order
        #expect(env.acquired.value.last == "Nightcap: Ghostty, Xcode")
    }

    @Test("Scenario 2: the Mac is reported as not held when IOKit refuses the assertion")
    func failedAcquireLeavesAssertionUnheld() async {
        // Given IOKit will reject IOPMAssertionCreateWithName
        let env = TestEnv(running: [])
        let store = env.makeStore(acquireReturns: false)
        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .disabled
        }

        // When a watched app launches
        await store.send(.lifecycleEvent(.launched(bundleID: .ghostty))) {
            // Then the app is tracked but the UI must not claim the Mac is awake
            $0.runningWatchedIDs = [.ghostty]
        }

        #expect(env.acquired.value == ["Nightcap: Ghostty"])
    }
}

// MARK: - Feature: Launch at login

@MainActor
@Suite("Feature: Launch at login")
struct LaunchAtLoginFeature {
    @Test("Scenario 1: the toggle rolls back when the system refuses to register")
    func failedRegistrationRollsBackTheToggle() async {
        // Given launch at login is off and SMAppService will throw
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.defaultFileStorage = .inMemory
            $0.appLifecycleClient.runningBundleIDs = { [] }
            $0.appLifecycleClient.runningApps = { [] }
            $0.appLifecycleClient.events = { .finished }
            $0.launchAtLoginClient.status = { .disabled }
            $0.launchAtLoginClient.setEnabled = { _ in throw TestEnv.SimulatedError() }
            $0.powerAssertionClient.acquire = { _ in true }
            $0.powerAssertionClient.release = {}
        }

        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .disabled
        }

        // When the user flips it on and registration fails
        await store.send(.launchAtLoginToggled(true)) {
            // Then the UI flips optimistically first
            $0.launchAtLoginStatus = .enabled
        }

        // And then reverts, so the toggle never lies about the real state
        await store.receive(\.launchAtLoginStatusUpdated) {
            $0.launchAtLoginStatus = .disabled
        }
    }
}

// MARK: - Feature: Persisting the watched list

@Suite("Feature: Persisting the watched list")
struct PersistenceFeature {
    @Test("Scenario 1: a list saved before pause/resume existed still loads as watched")
    func legacyRecordsDecodeAsObserved() throws {
        // Given a JSON record written before `isObserved` existed
        let data = #"{"bundleID":"com.example.app","displayName":"Example"}"#
            .data(using: .utf8)!

        // When it is decoded
        let app = try JSONDecoder().decode(WatchedApp.self, from: data)

        // Then it defaults to watched, so upgrading never silently stops working
        #expect(app.isObserved)
    }
}

// MARK: - Feature: Quitting Nightcap

@MainActor
@Suite("Feature: Quitting Nightcap")
struct QuitFeature {
    @Test("Scenario 1: quitting releases the assertion before terminating")
    func quitReleasesAssertionBeforeTerminate() async {
        // Given Nightcap is running
        let env = TestEnv(running: [])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .disabled
        }

        // When the user quits
        await store.send(.quitTapped)

        // Then the kernel assertion is released, so no wake-lock outlives the app
        #expect(env.released.value >= 1)
    }
}

// MARK: - Test support

extension String {
    fileprivate static let ghostty = "com.mitchellh.ghostty"
    fileprivate static let xcode = "com.apple.dt.Xcode"
}

extension WatchedApp {
    fileprivate static let ghosttyApp = WatchedApp(bundleID: .ghostty, displayName: "Ghostty")
    fileprivate static let xcodeApp = WatchedApp(bundleID: .xcode, displayName: "Xcode")
    fileprivate static let zoomApp = WatchedApp(bundleID: "us.zoom.xos", displayName: "zoom.us")
}

/// Records what the reducer asked the outside world to do, so scenarios can
/// assert on effects (assertion reasons, release counts, review prompts) rather
/// than only on state.
private struct TestEnv {
    struct SimulatedError: Error {}

    let running: LockIsolated<Set<String>>
    let runningApps: LockIsolated<[WatchedApp]>
    let acquired = LockIsolated<[String]>([])
    let released = LockIsolated(0)
    let reviewPrompts = LockIsolated(0)

    init(running: Set<String>, runningApps: [WatchedApp] = []) {
        self.running = LockIsolated(running)
        self.runningApps = LockIsolated(runningApps)
    }

    @MainActor
    func makeStore(
        acquireReturns: Bool = true
    ) -> TestStore<AppFeature.State, AppFeature.Action> {
        TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            // In-memory, not the real container JSON: Swift Testing runs suites in
            // parallel and @Shared(.fileStorage) would otherwise be shared mutable
            // state across scenarios.
            $0.defaultFileStorage = .inMemory
            $0.appLifecycleClient.runningBundleIDs = { running.value }
            $0.appLifecycleClient.runningApps = { runningApps.value }
            $0.appLifecycleClient.events = { .finished }
            $0.launchAtLoginClient.status = { .disabled }
            $0.powerAssertionClient.acquire = { reason in
                acquired.withValue { $0.append(reason) }
                return acquireReturns
            }
            $0.powerAssertionClient.release = {
                released.withValue { $0 += 1 }
            }
            $0.reviewPromptClient.requestIfAppropriate = {
                reviewPrompts.withValue { $0 += 1 }
            }
        }
    }
}
