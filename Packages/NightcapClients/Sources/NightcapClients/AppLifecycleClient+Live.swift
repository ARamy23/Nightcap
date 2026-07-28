import AppKit
import Dependencies
import NightcapDomain

extension AppLifecycleClient: DependencyKey {
    public static let liveValue: AppLifecycleClient = .init(
        runningBundleIDs: {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        },
        runningApps: {
            let ownBundleID = Bundle.main.bundleIdentifier
            let apps = NSWorkspace.shared.runningApplications.compactMap { app -> WatchedApp? in
                guard
                    app.activationPolicy == .regular,
                    let bundleID = app.bundleIdentifier,
                    bundleID != ownBundleID,
                    let displayName = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !displayName.isEmpty
                else { return nil }

                return WatchedApp(bundleID: bundleID, displayName: displayName)
            }

            return Dictionary(grouping: apps, by: \.bundleID)
                .compactMap { $0.value.first }
                .sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
        },
        events: {
            AsyncStream { continuation in
                let center = NSWorkspace.shared.notificationCenter
                let launchToken = center.addObserver(
                    forName: NSWorkspace.didLaunchApplicationNotification,
                    object: nil,
                    queue: .main
                ) { note in
                    guard
                        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                        let bundleID = app.bundleIdentifier
                    else { return }
                    continuation.yield(.launched(bundleID: bundleID))
                }
                let terminateToken = center.addObserver(
                    forName: NSWorkspace.didTerminateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { note in
                    guard
                        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                        let bundleID = app.bundleIdentifier
                    else { return }
                    continuation.yield(.terminated(bundleID: bundleID))
                }
                let wakeToken = center.addObserver(
                    forName: NSWorkspace.didWakeNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    continuation.yield(.wake)
                }
                continuation.onTermination = { _ in
                    center.removeObserver(launchToken)
                    center.removeObserver(terminateToken)
                    center.removeObserver(wakeToken)
                }
            }
        }
    )
}
