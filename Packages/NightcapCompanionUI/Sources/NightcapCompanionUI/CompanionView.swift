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

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    private var iconName: String {
        if isWaiting { return "questionmark.circle" }
        return isAwakeHeld ? "cup.and.saucer.fill" : "moon.zzz"
    }

    private var iconColor: Color {
        if isWaiting { return .secondary }
        return isAwakeHeld ? .green : .secondary
    }

    private var title: String {
        if isWaiting { return "Waiting for your Mac" }
        return isAwakeHeld ? "Keeping Mac Awake" : "Idle"
    }

    private var subtitle: String {
        if isWaiting { return "No status received yet" }
        guard isAwakeHeld else { return "Sleep allowed" }
        return activeCount == 1 ? "1 app active" : "\(activeCount) apps active"
    }
}

struct WatchedAppRow: View {
    let app: WatchedApp
    let isRunning: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
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

    private var iconName: String {
        guard app.isObserved else { return "pause.circle" }
        return isRunning ? "circle.fill" : "circle"
    }

    private var iconColor: Color {
        guard app.isObserved else { return .secondary }
        return isRunning ? .green : .secondary
    }
}

#Preview {
    CompanionView(
        store: Store(initialState: CompanionFeature.State()) { CompanionFeature() }
    )
}
