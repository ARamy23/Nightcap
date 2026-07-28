import Foundation

/// A snapshot of what the Mac is doing, as seen by a companion app.
///
/// This is the whole contract between the Mac and the phone/watch. Keeping it a
/// plain value type means the companions can be built and tested against a stub
/// long before any real transport exists.
public struct MacState: Codable, Equatable, Sendable {
    public var isAwakeHeld: Bool
    public var watchedApps: [WatchedApp]
    public var runningWatchedIDs: Set<String>
    public var lastUpdated: Date

    public init(
        isAwakeHeld: Bool = false,
        watchedApps: [WatchedApp] = [],
        runningWatchedIDs: Set<String> = [],
        lastUpdated: Date = .distantPast
    ) {
        self.isAwakeHeld = isAwakeHeld
        self.watchedApps = watchedApps
        self.runningWatchedIDs = runningWatchedIDs
        self.lastUpdated = lastUpdated
    }

    public var activeApps: [WatchedApp] {
        watchedApps.filter { runningWatchedIDs.contains($0.bundleID) }
    }
}
