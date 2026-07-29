import ComposableArchitecture
import NightcapDomain
import SwiftUI

/// The companion screen, shared by iPhone and Watch. Platform differences are
/// handled by SwiftUI's own adaptation rather than by branching here.
public struct CompanionView: View {
    @Bindable public var store: StoreOf<CompanionFeature>

    public init(store: StoreOf<CompanionFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    MacStatusRow(
                        isAwakeHeld: store.macState.isAwakeHeld,
                        isWaiting: store.isWaitingForMac,
                        activeCount: store.macState.activeApps.count
                    )
                }

                if store.macState.shouldSuggestHotspot {
                    Section {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Your Mac lost its network")
                                Text("Turn on Personal Hotspot to keep it online.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "personalhotspot")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Your Mac lost its network. Turn on Personal Hotspot to keep it online.")
                    }
                }

                if let failureMessage = store.failureMessage {
                    Section {
                        Label(failureMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Watched Apps") {
                    if store.macState.watchedApps.isEmpty {
                        Text(store.isWaitingForMac ? "Waiting for your Mac…" : "No apps added")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.macState.watchedApps) { app in
                            WatchedAppRow(
                                app: app,
                                isRunning: store.macState.runningWatchedIDs.contains(app.bundleID),
                                onToggle: { isObserved in
                                    store.send(.observationToggled(app.bundleID, isObserved))
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Nightcap")
            .refreshable { store.send(.refreshRequested) }
        }
        .onAppear { store.send(.onAppear) }
        .onDisappear { store.send(.onDisappear) }
    }
}

struct MacStatusRow: View {
    let isAwakeHeld: Bool
    let isWaiting: Bool
    let activeCount: Int

    private var presentation: MacStatusPresentation {
        MacStatusPresentation(
            isAwakeHeld: isAwakeHeld,
            isWaiting: isWaiting,
            activeCount: activeCount
        )
    }

    var body: some View {
        HStack {
            Image(systemName: presentation.iconName)
                .font(.title2)
                .foregroundStyle(presentation.iconColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(presentation.title).font(.headline)
                Text(presentation.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

struct WatchedAppRow: View {
    let app: WatchedApp
    let isRunning: Bool
    let onToggle: (Bool) -> Void

    private var presentation: WatchedAppRowPresentation {
        WatchedAppRowPresentation(isObserved: app.isObserved, isRunning: isRunning)
    }

    var body: some View {
        HStack {
            Image(systemName: presentation.iconName)
                .foregroundStyle(presentation.iconColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(app.displayName)
                if !app.isObserved {
                    Text("Paused").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { app.isObserved }, set: onToggle))
                .labelsHidden()
                .accessibilityLabel("Watch \(app.displayName)")
        }
    }
}

#Preview {
    CompanionView(
        store: Store(initialState: CompanionFeature.State()) { CompanionFeature() }
    )
}
