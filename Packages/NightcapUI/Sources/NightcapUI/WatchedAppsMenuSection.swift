import NightcapDomain
import SwiftUI

struct WatchedAppsMenuSection: View {
    let watchedApps: [WatchedApp]
    let runningWatchedIDs: Set<String>
    let onObservationToggle: (WatchedApp.ID, Bool) -> Void
    let onRemove: (WatchedApp.ID) -> Void

    var body: some View {
        if watchedApps.isEmpty {
            Text("No apps added")
                .foregroundStyle(.secondary)
        } else {
            ForEach(watchedApps) { app in
                WatchedAppMenu(
                    app: app,
                    isRunning: runningWatchedIDs.contains(app.bundleID),
                    onObservationToggle: { setObservation(app, to: $0) },
                    onRemove: { remove(app) }
                )
            }
        }
    }

    // Named rather than inline closures so tests can invoke the intent directly:
    // the bodies below sit inside a `Menu`, which SwiftUI does not evaluate until
    // the menu is opened, so an inline closure here is unreachable from a test.

    func setObservation(_ app: WatchedApp, to isObserved: Bool) {
        onObservationToggle(app.id, isObserved)
    }

    func remove(_ app: WatchedApp) {
        onRemove(app.id)
    }
}

private struct WatchedAppMenu: View {
    let app: WatchedApp
    let isRunning: Bool
    let onObservationToggle: (Bool) -> Void
    let onRemove: () -> Void

    var body: some View {
        Menu {
            Button(app.isObserved ? "Pause Watching" : "Resume Watching") {
                onObservationToggle(!app.isObserved)
            }

            Button("Remove from List", role: .destructive) {
                onRemove()
            }
        } label: {
            WatchedAppMenuLabel(
                app: app,
                status: WatchedAppMenuStatus(isObserved: app.isObserved, isRunning: isRunning)
            )
        }
    }
}

private struct WatchedAppMenuLabel: View {
    let app: WatchedApp
    let status: WatchedAppMenuStatus

    var body: some View {
        HStack {
            Image(systemName: status.iconName)
                .foregroundStyle(status.color)
            Text(app.displayName)
            if !app.isObserved {
                Text("Paused")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WatchedAppMenuStatus {
    let isObserved: Bool
    let isRunning: Bool

    var iconName: String {
        guard isObserved else { return "pause.circle" }
        return isRunning ? "circle.fill" : "circle"
    }

    var color: Color {
        guard isObserved else { return .secondary }
        return isRunning ? .green : .secondary
    }
}
