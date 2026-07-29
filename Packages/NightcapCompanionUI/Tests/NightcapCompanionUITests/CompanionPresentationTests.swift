import NightcapDomain
import Testing

@testable import NightcapCompanionUI

/// What the companion screen tells you about your Mac. This wording is the whole
/// product on the phone and the watch — it is the only channel saying whether the
/// Mac is awake — so each branch is pinned rather than left to one snapshot.
@Suite("Feature: What the companion says about the Mac")
struct MacStatusPresentationTests {
    private func presentation(
        awake: Bool = false,
        waiting: Bool = false,
        active: Int = 0
    ) -> MacStatusPresentation {
        MacStatusPresentation(isAwakeHeld: awake, isWaiting: waiting, activeCount: active)
    }

    @Test("Scenario 1: before any status arrives, the app admits it doesn't know")
    func waitingForFirstStatus() {
        // Given no status has been received yet
        let status = presentation(waiting: true)

        // Then it says so, rather than guessing "Idle" — which would be a claim
        // about the Mac that nothing has actually told us.
        #expect(status.title == "Waiting for your Mac")
        #expect(status.subtitle == "No status received yet")
        #expect(status.iconName == "questionmark.circle")
    }

    @Test("Scenario 2: waiting outranks a stale awake flag")
    func waitingOutranksAwake() {
        // Given we are waiting, but the state happens to carry isAwakeHeld
        let status = presentation(awake: true, waiting: true, active: 3)

        // Then waiting still wins — a stale flag must not be reported as current
        #expect(status.title == "Waiting for your Mac")
        #expect(status.iconName == "questionmark.circle")
    }

    @Test("Scenario 3: the Mac is being kept awake by exactly one app")
    func awakeWithOneApp() {
        let status = presentation(awake: true, active: 1)

        #expect(status.title == "Keeping Mac Awake")
        #expect(status.subtitle == "1 app active")
        #expect(status.iconName == "cup.and.saucer.fill")
    }

    @Test("Scenario 4: several apps are keeping the Mac awake", arguments: [0, 2, 7])
    func awakeWithSeveralApps(count: Int) {
        let status = presentation(awake: true, active: count)

        // Plural everywhere except exactly one — the singular is the special case
        #expect(status.subtitle == "\(count) apps active")
    }

    @Test("Scenario 5: nothing is holding the Mac awake, so sleep is allowed")
    func idle() {
        let status = presentation(awake: false, active: 0)

        #expect(status.title == "Idle")
        #expect(status.subtitle == "Sleep allowed")
        #expect(status.iconName == "moon.zzz")
    }

    @Test("Scenario 6: an idle Mac says sleep is allowed even if apps are running")
    func idleIgnoresActiveCount() {
        // Given the Mac is not holding an assertion, but apps are running
        let status = presentation(awake: false, active: 4)

        // Then the count is not mentioned: without an assertion those apps are
        // not keeping anything awake, so "4 apps active" would mislead.
        #expect(status.subtitle == "Sleep allowed")
    }

    @Test("Scenario 7: VoiceOver reads the row as one sentence")
    func accessibilityLabelCombinesTitleAndSubtitle() {
        let status = presentation(awake: true, active: 1)

        #expect(status.accessibilityLabel == "Keeping Mac Awake. 1 app active")
    }
}

/// How each watched app's row reads on the companion screen.
@Suite("Feature: How a watched app reads on the companion")
struct WatchedAppRowPresentationTests {
    @Test("Scenario 1: a running, observed app shows as filled")
    func runningAndObserved() {
        let row = WatchedAppRowPresentation(isObserved: true, isRunning: true)
        #expect(row.iconName == "circle.fill")
    }

    @Test("Scenario 2: an observed app that isn't running shows as hollow")
    func observedNotRunning() {
        let row = WatchedAppRowPresentation(isObserved: true, isRunning: false)
        #expect(row.iconName == "circle")
    }

    @Test(
        "Scenario 3: a paused app reads as paused whether or not it is running",
        arguments: [true, false]
    )
    func pausedRegardlessOfRunning(isRunning: Bool) {
        // A paused app's running-ness is not acted on, so showing it would imply
        // Nightcap is doing something about it when it is not.
        let row = WatchedAppRowPresentation(isObserved: false, isRunning: isRunning)
        #expect(row.iconName == "pause.circle")
    }
}
