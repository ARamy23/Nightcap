import NightcapDomain
import AppKit
import ServiceManagement
import SwiftUI

struct MenuActionsSection: View {
    let launchAtLoginStatus: LaunchAtLoginStatus
    let onLaunchAtLoginToggle: (Bool) -> Void
    let onQuit: () -> Void

    var body: some View {
        Toggle(
            "Launch at Login",
            isOn: Binding(
                get: { launchAtLoginStatus.isOn },
                set: onLaunchAtLoginToggle
            )
        )

        if case .requiresApproval = launchAtLoginStatus {
            Button("Approve in System Settings…") {
                SMAppService.openSystemSettingsLoginItems()
            }
        }

        Button("About Nightcap") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        }

        Divider()

        // Passed directly rather than wrapped in a closure: a wrapper body would
        // be an uncoverable region, and there is nothing for it to add.
        Button("Quit Nightcap", action: onQuit)
            .keyboardShortcut("q")
    }
}
