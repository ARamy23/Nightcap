import NightcapDomain
import SwiftUI

struct AddRunningAppMenu: View {
    let candidates: [WatchedApp]
    let watchedBundleIDs: Set<String>
    let onAdd: (WatchedApp) -> Void
    let onRefresh: () -> Void

    var body: some View {
        Menu("Add Running App") {
            candidateItems

            Divider()

            Button("Refresh Running Apps", action: refresh)
        }
    }

    /// See the note in `MenuContentView`: menu-content closures are not
    /// evaluated until the menu opens, so the intent is a callable method.
    func refresh() {
        onRefresh()
    }

    func add(_ app: WatchedApp) {
        onAdd(app)
    }

    @ViewBuilder
    private var candidateItems: some View {
        if candidates.isEmpty {
            Text("No running apps found")
                .foregroundStyle(.secondary)
        } else {
            ForEach(candidates) { app in
                RunningAppCandidateButton(
                    app: app,
                    isAlreadyWatched: watchedBundleIDs.contains(app.bundleID),
                    onAdd: add
                )
            }
        }
    }
}

private struct RunningAppCandidateButton: View {
    let app: WatchedApp
    let isAlreadyWatched: Bool
    let onAdd: (WatchedApp) -> Void

    private var presentation: RunningAppCandidatePresentation {
        RunningAppCandidatePresentation(isAlreadyWatched: isAlreadyWatched)
    }

    var body: some View {
        Button {
            onAdd(app)
        } label: {
            Label(app.displayName, systemImage: presentation.iconName)
        }
        .disabled(presentation.isDisabled)
    }
}

/// How a running-app candidate presents itself. Split out for the same reason as
/// `WatchedAppMenuStatus`: it sits inside a `Menu`, whose content SwiftUI does not
/// evaluate until the menu opens, so inline it would be untestable.
struct RunningAppCandidatePresentation {
    let isAlreadyWatched: Bool

    /// A tick reads as "already handled"; a plus as "you can add this".
    var iconName: String {
        isAlreadyWatched ? "checkmark" : "plus"
    }

    /// Shown rather than hidden when already watched, so the list does not
    /// reshuffle under the pointer — but not clickable, since adding twice is
    /// refused by the reducer anyway.
    var isDisabled: Bool {
        isAlreadyWatched
    }
}
