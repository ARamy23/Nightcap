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

        Button("Quit Nightcap") {
            onQuit()
        }
        .keyboardShortcut("q")
    }
}
