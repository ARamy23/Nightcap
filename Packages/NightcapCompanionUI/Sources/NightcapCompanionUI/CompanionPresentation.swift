import NightcapDomain
import SwiftUI

/// What the status row at the top of the companion screen says about the Mac.
///
/// Split out of the view so it can be tested directly: the wording here is the
/// whole point of the companion app — it is the only thing telling you whether
/// your Mac is awake — and it branches three ways that a snapshot pins only one
/// of at a time.
struct MacStatusPresentation {
    let isAwakeHeld: Bool
    let isWaiting: Bool
    let activeCount: Int

    /// "Waiting" outranks the awake/idle split: before the first status arrives
    /// we do not know which it is, and claiming "Idle" would be a guess.
    var iconName: String {
        if isWaiting { return "questionmark.circle" }
        return isAwakeHeld ? "cup.and.saucer.fill" : "moon.zzz"
    }

    var iconColor: Color {
        if isWaiting { return .secondary }
        return isAwakeHeld ? .green : .secondary
    }

    var title: String {
        if isWaiting { return "Waiting for your Mac" }
        return isAwakeHeld ? "Keeping Mac Awake" : "Idle"
    }

    var subtitle: String {
        if isWaiting { return "No status received yet" }
        guard isAwakeHeld else { return "Sleep allowed" }
        return activeCount == 1 ? "1 app active" : "\(activeCount) apps active"
    }

    /// VoiceOver reads the row as one phrase rather than announcing the icon.
    var accessibilityLabel: String {
        "\(title). \(subtitle)"
    }
}

/// How one watched app's row presents itself on the companion screen.
struct WatchedAppRowPresentation {
    let isObserved: Bool
    let isRunning: Bool

    /// A paused app reads as paused whether or not it happens to be running —
    /// its running-ness is not acted on while paused, so showing it would lie.
    var iconName: String {
        guard isObserved else { return "pause.circle" }
        return isRunning ? "circle.fill" : "circle"
    }

    var iconColor: Color {
        guard isObserved else { return .secondary }
        return isRunning ? .green : .secondary
    }
}
