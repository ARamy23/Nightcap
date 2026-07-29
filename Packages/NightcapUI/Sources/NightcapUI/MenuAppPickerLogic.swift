import Foundation
import NightcapDomain

/// The decisions `MenuAppPicker` makes once the user has picked a file.
///
/// These live apart from the picker itself because `NSOpenPanel.runModal()` and
/// `NSAlert.runModal()` block on a real window server: any test touching them
/// hangs. Reading a bundle and deciding what to do with it needs neither, so it
/// is testable — and it is where the behaviour actually lives.
enum MenuAppPickerLogic {
    /// What should happen after the user picks `url`.
    enum Outcome: Equatable {
        /// The file is not a readable app bundle.
        case unreadableBundle(title: String, message: String)
        /// The app is already in the watched list.
        case alreadyWatched(title: String, message: String)
        /// A new app to start watching.
        case select(WatchedApp)
    }

    static func outcome(forPickedURL url: URL, existingApps: [WatchedApp]) -> Outcome {
        guard let selectedApp = makeWatchedApp(from: url) else {
            return .unreadableBundle(
                title: "Couldn't read app info",
                message: "That file isn't a recognizable app bundle. Try picking another."
            )
        }

        if let existingApp = existingApps.first(where: { $0.bundleID == selectedApp.bundleID }) {
            return .alreadyWatched(
                title: "Already in your list",
                message: alreadyWatchedMessage(for: existingApp)
            )
        }

        return .select(selectedApp)
    }

    static func makeWatchedApp(from url: URL) -> WatchedApp? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
            return nil
        }

        let displayName = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return WatchedApp(bundleID: bundleID, displayName: displayName)
    }

    /// A paused app is still "in the list", so the nudge points at Resume
    /// Watching rather than implying the add failed.
    static func alreadyWatchedMessage(for app: WatchedApp) -> String {
        app.isObserved
            ? "\(app.displayName) is already being watched."
            : "\(app.displayName) is already in your list. Choose Resume Watching from its menu to watch it again."
    }
}
