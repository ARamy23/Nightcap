import NightcapDomain
import AppKit
import UniformTypeIdentifiers

/// Window-server plumbing only. Every decision this picker makes lives in
/// `MenuAppPickerLogic`, which is unit-tested; the modal calls below cannot be,
/// so there is deliberately no logic left here to test.
enum MenuAppPicker {
    static func present(existingApps: [WatchedApp], onSelect: (WatchedApp) -> Void) {
        NSApp.activate()

        let panel = makePanel()
        let response = panel.runModal()
        NSApp.setActivationPolicy(.accessory)

        guard response == .OK, let url = panel.url else { return }

        switch MenuAppPickerLogic.outcome(forPickedURL: url, existingApps: existingApps) {
        case let .unreadableBundle(title, message):
            presentAlert(title: title, message: message)
        case let .alreadyWatched(title, message):
            presentAlert(title: title, message: message)
        case let .select(app):
            onSelect(app)
        }
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

    private static func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
