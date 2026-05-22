import AppKit
import UniformTypeIdentifiers

enum MenuAppPicker {
    static func present(existingApps: [WatchedApp], onSelect: (WatchedApp) -> Void) {
        NSApp.activate()

        let panel = makePanel()
        let response = panel.runModal()
        NSApp.setActivationPolicy(.accessory)

        guard response == .OK, let url = panel.url else { return }
        guard let selectedApp = makeWatchedApp(from: url) else {
            presentAlert(
                title: "Couldn't read app info",
                message: "That file isn't a recognizable app bundle. Try picking another."
            )
            return
        }

        if let existingApp = existingApp(matching: selectedApp, in: existingApps) {
            presentAlert(
                title: "Already in your list",
                message: alreadyWatchedMessage(for: existingApp)
            )
            return
        }

        onSelect(selectedApp)
    }

    private static func makePanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Watch"
        panel.message = "Pick an app to keep your Mac awake while it's running."
        return panel
    }

    private static func makeWatchedApp(from url: URL) -> WatchedApp? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
            return nil
        }

        let displayName = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return WatchedApp(bundleID: bundleID, displayName: displayName)
    }

    private static func existingApp(
        matching selectedApp: WatchedApp,
        in existingApps: [WatchedApp]
    ) -> WatchedApp? {
        existingApps.first { $0.bundleID == selectedApp.bundleID }
    }

    private static func alreadyWatchedMessage(for app: WatchedApp) -> String {
        app.isObserved
            ? "\(app.displayName) is already being watched."
            : "\(app.displayName) is already in your list. Choose Resume Watching from its menu to watch it again."
    }

    private static func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
