import SwiftUI

struct MenuStatusSection: View {
    let assertionHeld: Bool
    let activeAppCount: Int
    let manualSession: AppFeature.ManualSession?

    var body: some View {
        if assertionHeld {
            Label("Keeping Mac Awake", systemImage: "cup.and.saucer.fill")
            Text(statusDetail)
                .foregroundStyle(.secondary)
        } else {
            Label("Idle", systemImage: "moon.zzz")
            Text("Sleep allowed")
                .foregroundStyle(.secondary)
        }
    }

    private var statusDetail: String {
        if let manualSession {
            return activeAppCount > 0
                ? "\(manualSession.statusText) - \(activeAppsLabel)"
                : manualSession.statusText
        }
        return activeAppsLabel
    }

    private var activeAppsLabel: String {
        activeAppCount == 1 ? "1 app active" : "\(activeAppCount) apps active"
    }
}
