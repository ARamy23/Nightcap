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

            Button("Refresh Running Apps") {
                onRefresh()
            }
        }
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
                    onAdd: onAdd
                )
            }
        }
    }
}

private struct RunningAppCandidateButton: View {
    let app: WatchedApp
    let isAlreadyWatched: Bool
    let onAdd: (WatchedApp) -> Void

    var body: some View {
        Button {
            onAdd(app)
        } label: {
            Label(
                app.displayName,
                systemImage: isAlreadyWatched ? "checkmark" : "plus"
            )
        }
        .disabled(isAlreadyWatched)
    }
}
