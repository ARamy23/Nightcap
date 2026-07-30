import ComposableArchitecture
import ConcurrencyExtras
import Foundation
import Sharing
import Testing

import NightcapDomain

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
            $0.networkPathClient.isSatisfied = { .finished }
            $0.networkPathClient.connection = { .finished }
            $0.macStatePublisherClient.publish = { _ in }
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
    /// Records the order effects fired, so ordering invariants can be asserted
    /// rather than just "both happened".
    let effectLog = LockIsolated<[String]>([])

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
            // Scenarios drive network changes explicitly rather than through a
            // live path monitor, and publishing to companions is off by default.
            $0.networkPathClient.isSatisfied = { .finished }
            $0.networkPathClient.connection = { .finished }
            $0.macStatePublisherClient.publish = { _ in }
            $0.powerAssertionClient.acquire = { reason in
                acquired.withValue { $0.append(reason) }
                return acquireReturns
            }
            $0.powerAssertionClient.release = {
                released.withValue { $0 += 1 }
                effectLog.withValue { $0.append("release") }
            }
            $0.appQuitterClient.quit = {
                effectLog.withValue { $0.append("quit") }
            }
            $0.reviewPromptClient.requestIfAppropriate = {
                reviewPrompts.withValue { $0 += 1 }
            }
        }
    }
}

// MARK: - Feature: Watching the Mac from a companion app

@MainActor
@Suite("Feature: Watching the Mac from a companion app")
struct CompanionFeatureTests {
    @Test("Scenario 1: the app opens and shows the Mac's current state")
    func openingSubscribesAndReceivesState() async {
        // Given a Mac holding the assertion for Ghostty
        let store = TestStore(initialState: CompanionFeature.State()) {
            CompanionFeature()
        } withDependencies: {
            $0.macStateTransportClient = .stub(initial: .preview)
            $0.hotspotNotifierClient = .noop
        }

        // When the companion appears
        await store.send(.onAppear)

        // Then the first snapshot arrives and the app stops saying "waiting"
        await store.receive(\.macStateReceived) {
            $0.macState = .preview
            $0.hasConnected = true
        }
        #expect(store.state.isWaitingForMac == false)
        #expect(store.state.macState.activeApps.map(\.displayName) == ["Ghostty"])

        await store.send(.onDisappear)
    }

    @Test("Scenario 2: before any snapshot arrives the app does not claim the Mac is idle")
    func waitingStateIsDistinctFromIdle() {
        // Given a companion that has heard nothing yet
        let state = CompanionFeature.State()

        // Then it reports waiting, not "asleep"
        #expect(state.isWaitingForMac)
        #expect(state.macState.isAwakeHeld == false)
    }

    @Test("Scenario 3: pausing an app from the phone releases the Mac")
    func pausingFromCompanionUpdatesMacState() async {
        // Given a Mac kept awake by Ghostty
        let store = TestStore(initialState: CompanionFeature.State()) {
            CompanionFeature()
        } withDependencies: {
            $0.macStateTransportClient = .stub(initial: .preview)
            $0.hotspotNotifierClient = .noop
        }
        await store.send(.onAppear)
        await store.receive(\.macStateReceived) {
            $0.macState = .preview
            $0.hasConnected = true
        }

        // When the user pauses Ghostty from the companion
        await store.send(.observationToggled("com.mitchellh.ghostty", false))

        // Then the Mac reports itself no longer held
        await store.receive(\.macStateReceived) {
            $0.macState.watchedApps[0].isObserved = false
            $0.macState.runningWatchedIDs = []
            $0.macState.isAwakeHeld = false
        }

        await store.send(.onDisappear)
    }

    @Test("Scenario 4: a transport failure surfaces a message instead of failing silently")
    func transportFailureSurfacesMessage() async {
        // Given a Mac that cannot be reached
        struct Unreachable: Error {}
        let store = TestStore(initialState: CompanionFeature.State()) {
            CompanionFeature()
        } withDependencies: {
            $0.macStateTransportClient.states = { .finished }
            $0.macStateTransportClient.setObservation = { _, _ in throw Unreachable() }
        }

        // When the user toggles an app
        await store.send(.observationToggled("com.mitchellh.ghostty", false))

        // Then the failure is shown rather than swallowed
        await store.receive(\.failed) {
            $0.failureMessage = "Couldn't reach your Mac."
        }
    }
}

// MARK: - Feature: Noticing the Mac has lost its network

@MainActor
@Suite("Feature: Noticing the Mac has lost its network")
struct NetworkLossFeature {
    @Test("Scenario 1: losing the network while keeping the Mac awake is worth reporting")
    func networkLossWhileHeldSuggestsHotspot() async {
        // Given Ghostty is running and the Mac is being kept awake
        let env = TestEnv(running: [.ghostty])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.runningWatchedIDs = [.ghostty]
            $0.assertionHeld = true
            $0.launchAtLoginStatus = .disabled
        }

        // When the network path drops
        await store.send(.networkPathChanged(isSatisfied: false)) {
            $0.hasLostNetwork = true
        }

        // Then companions are told to suggest a hotspot
        #expect(store.state.macState.shouldSuggestHotspot)
    }

    @Test("Scenario 2: losing the network while idle is not worth nagging about")
    func networkLossWhileIdleIsQuiet() async {
        // Given nothing is being kept awake
        let env = TestEnv(running: [])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .disabled
        }

        // When the network path drops
        await store.send(.networkPathChanged(isSatisfied: false)) {
            $0.hasLostNetwork = true
        }

        // Then no hotspot suggestion is made, because a sleeping Mac being
        // offline is not interesting
        #expect(store.state.macState.shouldSuggestHotspot == false)
    }

    @Test("Scenario 3: repeated identical path reports do not churn")
    func duplicatePathReportsAreIgnored() async {
        // Given the network is already up
        let env = TestEnv(running: [])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .disabled
        }

        // When the monitor reports "satisfied" again, as NWPathMonitor does
        // on every interface change
        await store.send(.networkPathChanged(isSatisfied: true))

        // Then nothing changes and no publish is triggered
        #expect(store.state.hasLostNetwork == false)
    }

    @Test("Scenario 4: regaining the network clears the suggestion")
    func regainingNetworkClearsSuggestion() async {
        // Given the Mac is awake and offline
        let env = TestEnv(running: [.ghostty])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.runningWatchedIDs = [.ghostty]
            $0.assertionHeld = true
            $0.launchAtLoginStatus = .disabled
        }
        await store.send(.networkPathChanged(isSatisfied: false)) {
            $0.hasLostNetwork = true
        }

        // When the network comes back
        await store.send(.networkPathChanged(isSatisfied: true)) {
            $0.hasLostNetwork = false
        }

        // Then the hotspot suggestion goes away
        #expect(store.state.macState.shouldSuggestHotspot == false)
    }
}

// MARK: - Feature: What the companion sees about the network

@Suite("Feature: What the companion sees about the network")
struct MacStateNetworkTests {
    @Test("Scenario 1: a snapshot written before this feature existed decodes safely")
    func legacySnapshotDecodes() throws {
        // Given a MacState published by an older Mac, with no hasLostNetwork
        let json = """
        {"isAwakeHeld":true,"watchedApps":[],"runningWatchedIDs":[],"lastUpdated":0}
        """.data(using: .utf8)!

        // When a newer companion decodes it
        let state = try JSONDecoder().decode(MacState.self, from: json)

        // Then it defaults to "network fine" rather than showing a false alarm
        #expect(state.hasLostNetwork == false)
        #expect(state.shouldSuggestHotspot == false)
    }
}

// MARK: - Feature: Carrying Mac state to companions over iCloud

@Suite("Feature: Carrying Mac state to companions over iCloud")
struct MacStateRecordCodingTests {
    @Test("Scenario 1: a published snapshot survives the round trip intact")
    func payloadRoundTripsWithoutLoss() throws {
        // Given a Mac being kept awake by one of two watched apps, and offline
        var original = MacState.preview
        original.hasLostNetwork = true

        // When it is encoded for CloudKit and read back by a companion
        let encoded = try MacStateRecordCoding.encode(original)
        let decoded = try MacStateRecordCoding.decode(payload: encoded.payload)

        // Then nothing the companion renders was lost in transit
        #expect(decoded == original)
        #expect(decoded.watchedApps.count == 3)
        #expect(decoded.runningWatchedIDs == original.runningWatchedIDs)
        #expect(decoded.hasLostNetwork)
        #expect(encoded.lastUpdated == original.lastUpdated)
    }

    @Test("Scenario 2: a stale local copy re-applies onto the server's record")
    func conflictReappliesOntoServerRecord() {
        // Given a save was rejected because our copy of the record was stale,
        // and CloudKit handed back the server's version
        // When the conflict is resolved
        let resolution = MacStateRecordCoding.resolveConflict(hasServerRecord: true)

        // Then the update is re-applied rather than dropped, because the Mac is
        // the only writer and there is no competing edit to preserve
        #expect(resolution == .reapplyOntoServerRecord)
    }

    @Test("Scenario 3: a conflict with no server record surfaces the failure")
    func conflictWithoutServerRecordPropagates() {
        // Given a conflict arrived with nothing to re-apply onto
        // When the conflict is resolved
        let resolution = MacStateRecordCoding.resolveConflict(hasServerRecord: false)

        // Then the error is propagated rather than silently swallowed
        #expect(resolution == .propagateFailure)
    }

    @Test("Scenario 4: a companion opening before the Mac ever published sees no state")
    func absentPayloadMeansMacNeverPublished() throws {
        // Given the record carries no payload, as when the Mac app has never run
        // When the fetch result is interpreted
        let outcome = try MacStateRecordCoding.interpretFetch(payload: nil)

        // Then this is reported as "no Mac has published", not as an error and
        // not as an idle Mac
        #expect(outcome == .noMacHasPublished)
    }

    @Test("Scenario 5: a present payload is decoded into the Mac's state")
    func presentPayloadDecodes() throws {
        // Given a payload written by a Mac
        let payload = try MacStateRecordCoding.encode(.preview).payload

        // When the fetch result is interpreted
        let outcome = try MacStateRecordCoding.interpretFetch(payload: payload)

        // Then the companion receives that exact state
        #expect(outcome == .state(.preview))
    }

    @Test("Scenario 6: a corrupt payload fails loudly rather than showing a wrong Mac")
    func corruptPayloadThrows() {
        // Given a payload that is not a MacState
        let garbage = Data("not json".utf8)

        // When a companion tries to read it
        // Then it throws, rather than silently rendering a default state that
        // would claim the Mac is idle
        #expect(throws: (any Error).self) {
            try MacStateRecordCoding.decode(payload: garbage)
        }
    }
}

// MARK: - Feature: Not leaking the assertion (mutation-hunting scenarios)

@MainActor
@Suite("Feature: Not leaking the sleep assertion")
struct AssertionLeakFeature {
    @Test("Scenario 1: resuming an app that has since quit does not wake-lock the Mac")
    func resumingAnAppThatIsNoLongerRunningDoesNotAcquire() async {
        // Given Ghostty is watched and paused, and has since quit
        let env = TestEnv(running: [])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .disabled
        }
        await store.send(.observationToggled(.ghostty, false)) {
            $0.$watchedApps.withLock { $0[0].isObserved = false }
        }

        // When the user resumes watching it from the menu or a companion
        await store.send(.observationToggled(.ghostty, true)) {
            $0.$watchedApps.withLock { $0[0].isObserved = true }
        }

        // Then nothing is tracked and no assertion is taken, because the app is
        // not running. Re-acquiring here would keep the Mac awake indefinitely.
        #expect(store.state.runningWatchedIDs.isEmpty)
        #expect(store.state.assertionHeld == false)
        #expect(env.acquired.value.isEmpty)
    }

    @Test("Scenario 2: quitting while the Mac is held releases and reports it released")
    func quittingWhileHeldReleasesAndClearsState() async {
        // Given Ghostty is running and the Mac is actually being kept awake
        let env = TestEnv(running: [.ghostty])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.runningWatchedIDs = [.ghostty]
            $0.assertionHeld = true
            $0.launchAtLoginStatus = .disabled
        }
        let releasesBeforeQuit = env.released.value

        // When the user quits
        await store.send(.quitTapped) {
            // Then the app stops claiming the Mac is held
            $0.assertionHeld = false
        }

        // And the kernel assertion is released, so no wake-lock outlives the app
        #expect(env.released.value == releasesBeforeQuit + 1)
    }

    @Test("Scenario 3: the assertion is released before the app is told to terminate")
    func releaseHappensBeforeTerminate() async {
        // Given the Mac is being kept awake, and we record the order of effects
        let env = TestEnv(running: [.ghostty])
        let store = env.makeStore()
        await store.send(.onAppear) {
            $0.runningWatchedIDs = [.ghostty]
            $0.assertionHeld = true
            $0.launchAtLoginStatus = .disabled
        }
        env.effectLog.setValue([])

        // When the user quits
        await store.send(.quitTapped) {
            $0.assertionHeld = false
        }

        // Then release runs first. If termination began first, the process could
        // die holding a kernel assertion and the Mac would never sleep again.
        #expect(env.effectLog.value == ["release", "quit"])
    }
}

// MARK: - Feature: Reporting launch-at-login honestly

@MainActor
@Suite("Feature: Reporting launch-at-login honestly")
struct LaunchAtLoginReportingFeature {
    @Test("Scenario 1: an approval requirement is surfaced rather than shown as enabled")
    func requiresApprovalIsReportedAsSuch() async {
        // Given the system will register the login item but require approval
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.defaultFileStorage = .inMemory
            $0.appLifecycleClient.runningBundleIDs = { [] }
            $0.appLifecycleClient.runningApps = { [] }
            $0.appLifecycleClient.events = { .finished }
            $0.launchAtLoginClient.status = { .requiresApproval }
            $0.launchAtLoginClient.setEnabled = { _ in }
            $0.networkPathClient.isSatisfied = { .finished }
            $0.networkPathClient.connection = { .finished }
            $0.macStatePublisherClient.publish = { _ in }
            $0.powerAssertionClient.acquire = { _ in true }
            $0.powerAssertionClient.release = {}
        }

        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .requiresApproval
        }

        // When the user turns it on
        await store.send(.launchAtLoginToggled(true)) {
            $0.launchAtLoginStatus = .enabled
        }

        // Then the real status wins, so the UI can prompt for approval instead
        // of claiming the toggle succeeded
        await store.receive(\.launchAtLoginStatusUpdated) {
            $0.launchAtLoginStatus = .requiresApproval
        }
        #expect(store.state.launchAtLoginStatus.isOn == false)
    }

    @Test("Scenario 2: an unreadable status falls back to what the user asked for")
    func unknownStatusFallsBackToTheRequestedValue() async {
        // Given registration succeeds but the system reports an unusable status
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.defaultFileStorage = .inMemory
            $0.appLifecycleClient.runningBundleIDs = { [] }
            $0.appLifecycleClient.runningApps = { [] }
            $0.appLifecycleClient.events = { .finished }
            $0.launchAtLoginClient.status = { .error("Login item not found in bundle.") }
            $0.launchAtLoginClient.setEnabled = { _ in }
            $0.networkPathClient.isSatisfied = { .finished }
            $0.networkPathClient.connection = { .finished }
            $0.macStatePublisherClient.publish = { _ in }
            $0.powerAssertionClient.acquire = { _ in true }
            $0.powerAssertionClient.release = {}
        }

        await store.send(.onAppear) {
            $0.launchAtLoginStatus = .error("Login item not found in bundle.")
        }

        // When the user turns it on
        await store.send(.launchAtLoginToggled(true)) {
            $0.launchAtLoginStatus = .enabled
        }

        // Then the toggle reflects the request rather than reverting to an error.
        // No state change: the optimistic value already equals the resolved one,
        // which is the point — the user does not see it flicker back.
        await store.receive(\.launchAtLoginStatusUpdated)
        #expect(store.state.launchAtLoginStatus == .enabled)
        #expect(store.state.launchAtLoginStatus.isOn)
    }
}

@Suite("Feature: Launch-at-login status meaning")
struct LaunchAtLoginStatusTests {
    @Test("Scenario 1: only 'enabled' counts as on")
    func onlyEnabledIsOn() {
        // Given every status the system can report
        // Then exactly one of them means the toggle should look on
        #expect(LaunchAtLoginStatus.enabled.isOn)
        #expect(LaunchAtLoginStatus.disabled.isOn == false)
        #expect(LaunchAtLoginStatus.unknown.isOn == false)
        // requiresApproval is the trap: registered, but not actually active yet
        #expect(LaunchAtLoginStatus.requiresApproval.isOn == false)
        #expect(LaunchAtLoginStatus.error("boom").isOn == false)
    }
}

// MARK: - Feature: Clearing a stale failure banner

@MainActor
@Suite("Feature: Clearing a stale failure banner")
struct FailureBannerFeature {
    @Test("Scenario 1: a fresh snapshot clears a previous failure message")
    func newStateClearsFailureMessage() async {
        // Given the companion failed to reach the Mac and is showing a banner
        struct Unreachable: Error {}
        let store = TestStore(initialState: CompanionFeature.State()) {
            CompanionFeature()
        } withDependencies: {
            $0.macStateTransportClient.states = { .finished }
            $0.macStateTransportClient.setObservation = { _, _ in throw Unreachable() }
        }
        await store.send(.observationToggled("com.mitchellh.ghostty", false))
        await store.receive(\.failed) {
            $0.failureMessage = "Couldn't reach your Mac."
        }

        // When the Mac is reachable again and sends a snapshot
        await store.send(.macStateReceived(.preview)) {
            // Then the stale banner goes away rather than lingering forever
            $0.macState = .preview
            $0.hasConnected = true
            $0.failureMessage = nil
        }
    }
}

// MARK: - Feature: Deciding when a hotspot is worth suggesting

@Suite("Feature: Deciding when a hotspot is worth suggesting")
struct HotspotSuggestionTests {
    @Test(
        "Scenario 1: only an awake-and-offline Mac is worth a hotspot nudge",
        arguments: [
            (awake: true, offline: true, expected: true),
            (awake: true, offline: false, expected: false),
            (awake: false, offline: true, expected: false),
            (awake: false, offline: false, expected: false),
        ]
    )
    func hotspotIsSuggestedOnlyWhenAwakeAndOffline(
        combination: (awake: Bool, offline: Bool, expected: Bool)
    ) {
        // Given a Mac in one of the four awake/offline combinations
        var state = MacState.preview
        state.isAwakeHeld = combination.awake
        state.hasLostNetwork = combination.offline

        // Then a hotspot is suggested only when work is being kept alive AND the
        // network is gone. A sleeping Mac losing Wi-Fi is not worth a nudge, and
        // an online Mac never is.
        #expect(state.shouldSuggestHotspot == combination.expected)
    }

    @Test("Scenario 2: an offline Mac still reports which apps are keeping it awake")
    func offlineStateStillReportsActiveApps() {
        // Given a Mac kept awake by Ghostty that has dropped off the network
        var state = MacState.preview
        state.hasLostNetwork = true

        // Then the companion can still name what is holding it, so the nudge has
        // context rather than being a bare warning
        #expect(state.shouldSuggestHotspot)
        #expect(state.activeApps.map(\.displayName) == ["Ghostty"])
    }
}

/// When the Mac tells the companions anything at all.
///
/// This suite exists because publishing was once wired to a single reducer case
/// — the network change — so adding an app, pausing one, or an app launching
/// never reached the phone. The companions showed whatever the Mac was doing
/// when they connected and then froze, which looks exactly like a transport
/// fault. Every scenario below fails against that version.
@MainActor
@Suite("Feature: Telling the companions when something changes")
struct PublishingToCompanionsTests {
    private func makeStore(
        running: Set<String> = [],
        published: LockIsolated<[MacState]>
    ) -> TestStore<AppFeature.State, AppFeature.Action> {
        TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.defaultFileStorage = .inMemory
            $0.appLifecycleClient.runningBundleIDs = { running }
            $0.appLifecycleClient.runningApps = { [] }
            $0.appLifecycleClient.events = { .finished }
            $0.launchAtLoginClient.status = { .disabled }
            $0.networkPathClient.isSatisfied = { .finished }
            $0.networkPathClient.connection = { .finished }
            $0.powerAssertionClient.acquire = { _ in true }
            $0.powerAssertionClient.release = {}
            $0.reviewPromptClient.requestIfAppropriate = {}
            $0.macStatePublisherClient.publish = { state in
                published.withValue { $0.append(state) }
            }
        }
    }

    @Test("Scenario 1: adding an app tells the companions about it")
    func addingAnAppPublishes() async {
        // Given a Mac with nothing watched
        let published = LockIsolated<[MacState]>([])
        let store = makeStore(published: published)
        store.exhaustivity = .off
        await store.send(.onAppear)
        published.withValue { $0.removeAll() }

        // When an app is added
        let xcode = WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode")
        await store.send(.addAppRequested(xcode))
        await store.finish()

        // Then the companions are told, and the new app is in what they receive
        // (alongside the default watched app the app ships with)
        #expect(published.value.count >= 1)
        #expect(published.value.last?.watchedApps.contains { $0.bundleID == xcode.bundleID } == true)
    }

    @Test("Scenario 2: pausing an app tells the companions it is paused")
    func pausingPublishes() async {
        // Given one watched app
        let published = LockIsolated<[MacState]>([])
        let store = makeStore(published: published)
        store.exhaustivity = .off
        let xcode = WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode")
        await store.send(.addAppRequested(xcode))
        published.withValue { $0.removeAll() }

        // When it is paused
        await store.send(.observationToggled(xcode.id, false))
        await store.finish()

        // Then the phone learns it is paused, rather than continuing to show it
        // as actively watched
        let sent = published.value.last?.watchedApps.first { $0.bundleID == xcode.bundleID }
        #expect(sent?.isObserved == false)
    }

    @Test("Scenario 3: an app launching tells the companions the Mac is now held awake")
    func launchPublishesAwakeState() async {
        // Given a watched app that is not yet running. It must not be running at
        // add time, or the add itself would publish the awake state and this
        // scenario would pass without the launch ever being observed.
        let published = LockIsolated<[MacState]>([])
        let store = makeStore(published: published)
        store.exhaustivity = .off
        let xcode = WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode")
        await store.send(.addAppRequested(xcode))
        published.withValue { $0.removeAll() }

        // When it launches
        await store.send(.lifecycleEvent(.launched(bundleID: "com.apple.dt.Xcode")))
        await store.finish()

        // Then the companions are told the Mac is being kept awake — the single
        // most important thing they display
        #expect(published.value.last?.isAwakeHeld == true)
        #expect(published.value.last?.runningWatchedIDs == ["com.apple.dt.Xcode"])
    }

    @Test("Scenario 4: losing the network still publishes, so hotspot can be suggested")
    func networkLossPublishes() async {
        let published = LockIsolated<[MacState]>([])
        let store = makeStore(published: published)
        store.exhaustivity = .off
        await store.send(.onAppear)
        published.withValue { $0.removeAll() }

        await store.send(.networkPathChanged(isSatisfied: false))
        await store.finish()

        #expect(published.value.last?.hasLostNetwork == true)
    }

    @Test("Scenario 5: a change that the companions cannot see is not published")
    func unrenderedChangeDoesNotPublish() async {
        // Given a running Mac
        let published = LockIsolated<[MacState]>([])
        let store = makeStore(published: published)
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.finish()
        published.withValue { $0.removeAll() }

        // When something changes that no companion renders — the candidate list
        // for the Mac's own "Add Running App" menu
        await store.send(.runningAppCandidatesRefreshRequested)
        await store.finish()

        // Then nothing is sent. Publishing on every action would burn the
        // CloudKit quota on updates no one can see.
        #expect(published.value.isEmpty)
    }
}

/// Which connection the Mac is on, and what that means for the hotspot nudge.
@Suite("Feature: Knowing how the Mac is connected")
struct NetworkConnectionTests {
    @Test("Scenario 1: a hotspot is worth suggesting unless already tethered")
    func benefitsUnlessAlreadyTethered() {
        #expect(NetworkConnection.none.wouldBenefitFromHotspot)
        #expect(!NetworkConnection.hotspot.wouldBenefitFromHotspot)
        // .other means "unknown", which must not suppress the nudge: an older
        // Mac never reports a type, and swallowing the warning for those users
        // is worse than an occasional redundant one.
        #expect(NetworkConnection.other.wouldBenefitFromHotspot)
    }

    @Test("Scenario 2: a Mac already on a hotspot is not told to turn one on")
    func alreadyTetheredIsNotNagged() {
        // This is the whole reason the connection type is tracked: on a hotspot
        // the Mac has no network of its own, so the old boolean would have
        // nagged the user to enable the hotspot they were already using.
        #expect(!NetworkConnection.hotspot.wouldBenefitFromHotspot)
        #expect(NetworkConnection.hotspot.isConnected)
    }

    @Test("Scenario 3: only .none counts as disconnected", arguments: [
        NetworkConnection.wifi, .wired, .hotspot, .other,
    ])
    func everythingElseIsConnected(connection: NetworkConnection) {
        #expect(connection.isConnected)
    }

    @Test("Scenario 4: an awake Mac on a hotspot is not nagged")
    func awakeOnHotspotIsNotNagged() {
        let state = MacState(
            isAwakeHeld: true,
            lastUpdated: .distantPast,
            hasLostNetwork: true,
            connection: .hotspot
        )
        #expect(!state.shouldSuggestHotspot)
    }

    @Test("Scenario 5: an awake Mac with no network at all is nagged")
    func awakeAndOfflineIsNagged() {
        let state = MacState(
            isAwakeHeld: true,
            lastUpdated: .distantPast,
            hasLostNetwork: true,
            connection: .none
        )
        #expect(state.shouldSuggestHotspot)
    }

    @Test("Scenario 6: an older Mac that sends no connection still works")
    func olderMacWithoutConnectionField() throws {
        // Older Macs send hasLostNetwork and no connection. Decoding must not
        // silently report them as connected-and-fine, or the nudge disappears
        // for exactly the users who have not updated.
        let json = """
        {
          "isAwakeHeld": true,
          "watchedApps": [],
          "runningWatchedIDs": [],
          "lastUpdated": 0,
          "hasLostNetwork": true
        }
        """
        let decoded = try JSONDecoder().decode(MacState.self, from: Data(json.utf8))
        #expect(decoded.connection == .none)
        #expect(decoded.shouldSuggestHotspot)
    }

    @Test("Scenario 7b: an older, online Mac decodes as connected")
    func olderMacOnline() throws {
        let json = """
        {
          "isAwakeHeld": true,
          "watchedApps": [],
          "runningWatchedIDs": [],
          "lastUpdated": 0,
          "hasLostNetwork": false
        }
        """
        let decoded = try JSONDecoder().decode(MacState.self, from: Data(json.utf8))
        #expect(decoded.connection == .other)
        #expect(!decoded.shouldSuggestHotspot)
    }
}

/// Telling the user on their phone, when the app is not open.
@MainActor
@Suite("Feature: Alerting the phone when the Mac drops offline")
struct HotspotNotificationTests {
    private func offlineState(awake: Bool = true) -> MacState {
        MacState(
            isAwakeHeld: awake,
            watchedApps: [WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode")],
            runningWatchedIDs: awake ? ["com.apple.dt.Xcode"] : [],
            lastUpdated: Date(timeIntervalSince1970: 0),
            hasLostNetwork: true,
            connection: .none
        )
    }

    private func onlineState() -> MacState {
        MacState(
            isAwakeHeld: true,
            watchedApps: [WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode")],
            runningWatchedIDs: ["com.apple.dt.Xcode"],
            lastUpdated: Date(timeIntervalSince1970: 0),
            hasLostNetwork: false,
            connection: .wifi
        )
    }

    private func makeStore(
        notified: LockIsolated<[String]>
    ) -> TestStore<CompanionFeature.State, CompanionFeature.Action> {
        TestStore(initialState: CompanionFeature.State()) {
            CompanionFeature()
        } withDependencies: {
            $0.macStateTransportClient = .stub()
            $0.hotspotNotifierClient = .noop
            $0.hotspotNotifierClient.notify = { title, _ in
                notified.withValue { $0.append(title) }
            }
        }
    }

    @Test("Scenario 1: the phone is told when the Mac drops offline")
    func notifiesOnGoingOffline() async {
        let notified = LockIsolated<[String]>([])
        let store = makeStore(notified: notified)
        store.exhaustivity = .off

        await store.send(.macStateReceived(offlineState()))
        await store.finish()

        #expect(notified.value == ["Your Mac lost its network"])
    }

    @Test("Scenario 2: repeated polls of the same offline state notify only once")
    func doesNotRenotifyOnEveryPoll() async {
        // The transport re-delivers the same snapshot every 30 seconds. Level
        // triggering here would mean a notification twice a minute for as long
        // as the Mac stayed offline.
        let notified = LockIsolated<[String]>([])
        let store = makeStore(notified: notified)
        store.exhaustivity = .off

        await store.send(.macStateReceived(offlineState()))
        await store.send(.macStateReceived(offlineState()))
        await store.send(.macStateReceived(offlineState()))
        await store.finish()

        #expect(notified.value.count == 1)
    }

    @Test("Scenario 3: coming back online and dropping again notifies again")
    func renotifiesAfterRecovery() async {
        let notified = LockIsolated<[String]>([])
        let store = makeStore(notified: notified)
        store.exhaustivity = .off

        await store.send(.macStateReceived(offlineState()))
        await store.send(.macStateReceived(onlineState()))
        await store.send(.macStateReceived(offlineState()))
        await store.finish()

        #expect(notified.value.count == 2)
    }

    @Test("Scenario 4: a Mac that is merely asleep does not notify")
    func sleepingMacDoesNotNotify() async {
        let notified = LockIsolated<[String]>([])
        let store = makeStore(notified: notified)
        store.exhaustivity = .off

        await store.send(.macStateReceived(offlineState(awake: false)))
        await store.finish()

        #expect(notified.value.isEmpty)
    }

    @Test("Scenario 5: a Mac already on a hotspot does not notify")
    func hotspotMacDoesNotNotify() async {
        let notified = LockIsolated<[String]>([])
        let store = makeStore(notified: notified)
        store.exhaustivity = .off

        var tethered = offlineState()
        tethered.connection = .hotspot
        await store.send(.macStateReceived(tethered))
        await store.finish()

        #expect(notified.value.isEmpty)
    }
}
