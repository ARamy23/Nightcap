import Foundation
import NightcapDomain
import Testing

@testable import NightcapUI

/// The picker's decisions: what a picked file turns into, and what happens when
/// the user picks something already in their list. The modal panel and alert
/// around these are pure AppKit plumbing and are not covered here — they block
/// on a window server.
@Suite("Feature: Choosing an app from the file picker")
struct MenuAppPickerLogicTests {
    /// A real bundle on every Mac, so this needs no fixture.
    private let systemAppURL = URL(fileURLWithPath: "/System/Applications/Calculator.app")

    @Test("Scenario 1: picking a real app bundle yields an app to watch")
    func picksRealBundle() throws {
        // Given the user picked a genuine app bundle
        // When the picker reads it
        let app = try #require(MenuAppPickerLogic.makeWatchedApp(from: systemAppURL))

        // Then it carries the bundle's own identifier and a .app-free name
        #expect(app.bundleID == "com.apple.calculator")
        #expect(app.displayName == "Calculator")
        #expect(app.isObserved)
    }

    @Test("Scenario 2: picking something that isn't a bundle reads as unreadable")
    func rejectsNonBundle() throws {
        // Given a file that is not an app bundle
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nightcap-not-an-app-\(UUID().uuidString).txt")
        try Data("not a bundle".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // When the picker reads it
        // Then nothing can be built from it
        #expect(MenuAppPickerLogic.makeWatchedApp(from: url) == nil)

        // And the user is told why rather than silently getting nothing
        let outcome = MenuAppPickerLogic.outcome(forPickedURL: url, existingApps: [])
        guard case let .unreadableBundle(title, message) = outcome else {
            Issue.record("Expected .unreadableBundle, got \(outcome)")
            return
        }
        #expect(title == "Couldn't read app info")
        #expect(message.contains("isn't a recognizable app bundle"))
    }

    @Test("Scenario 3: a brand-new app is selected for watching")
    func selectsNewApp() {
        // Given a watched list that does not contain Calculator
        let existing = [WatchedApp(bundleID: "com.apple.dt.Xcode", displayName: "Xcode")]

        // When Calculator is picked
        let outcome = MenuAppPickerLogic.outcome(forPickedURL: systemAppURL, existingApps: existing)

        // Then it is handed back to be added
        guard case let .select(app) = outcome else {
            Issue.record("Expected .select, got \(outcome)")
            return
        }
        #expect(app.bundleID == "com.apple.calculator")
    }

    @Test("Scenario 4: re-picking an already-watched app is refused, not duplicated")
    func refusesDuplicate() {
        // Given Calculator is already being watched
        let existing = [WatchedApp(bundleID: "com.apple.calculator", displayName: "Calculator")]

        // When the user picks it again
        let outcome = MenuAppPickerLogic.outcome(forPickedURL: systemAppURL, existingApps: existing)

        // Then it is refused rather than added a second time
        guard case let .alreadyWatched(title, message) = outcome else {
            Issue.record("Expected .alreadyWatched, got \(outcome)")
            return
        }
        #expect(title == "Already in your list")
        #expect(message == "Calculator is already being watched.")
    }

    @Test("Scenario 5: re-picking a paused app points at Resume Watching")
    func pausedDuplicatePointsAtResume() {
        // Given Calculator is in the list but paused
        let existing = [
            WatchedApp(bundleID: "com.apple.calculator", displayName: "Calculator", isObserved: false)
        ]

        // When the user picks it again
        let outcome = MenuAppPickerLogic.outcome(forPickedURL: systemAppURL, existingApps: existing)

        // Then the message tells them how to un-pause it, rather than claiming
        // it is already being watched — which would be a lie for a paused app.
        guard case let .alreadyWatched(_, message) = outcome else {
            Issue.record("Expected .alreadyWatched, got \(outcome)")
            return
        }
        #expect(message.contains("Resume Watching"))
        #expect(!message.contains("is already being watched."))
    }

    @Test(
        "Scenario 6: the already-watched wording follows the app's paused state",
        arguments: [true, false]
    )
    func messageFollowsObservationState(isObserved: Bool) {
        let app = WatchedApp(bundleID: "com.a.b", displayName: "Zoom", isObserved: isObserved)
        let message = MenuAppPickerLogic.alreadyWatchedMessage(for: app)

        #expect(message.hasPrefix("Zoom is already"))
        #expect(message.contains("Resume Watching") == !isObserved)
    }
}
