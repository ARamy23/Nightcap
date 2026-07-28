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
    /// The Mac is awake and doing work but has lost its network path, so the
    /// user probably wants to turn on their phone's hotspot.
    public var hasLostNetwork: Bool

    public init(
        isAwakeHeld: Bool = false,
        watchedApps: [WatchedApp] = [],
        runningWatchedIDs: Set<String> = [],
        lastUpdated: Date = .distantPast,
        hasLostNetwork: Bool = false
    ) {
        self.isAwakeHeld = isAwakeHeld
        self.watchedApps = watchedApps
        self.runningWatchedIDs = runningWatchedIDs
        self.lastUpdated = lastUpdated
        self.hasLostNetwork = hasLostNetwork
    }

    /// Only worth nagging about when the Mac is actually being kept awake for
    /// work; a sleeping Mac losing its network is not interesting.
    public var shouldSuggestHotspot: Bool { hasLostNetwork && isAwakeHeld }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isAwakeHeld = try container.decode(Bool.self, forKey: .isAwakeHeld)
        watchedApps = try container.decode([WatchedApp].self, forKey: .watchedApps)
        runningWatchedIDs = try container.decode(Set<String>.self, forKey: .runningWatchedIDs)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        // Older Macs will not send this field.
        hasLostNetwork = try container.decodeIfPresent(Bool.self, forKey: .hasLostNetwork) ?? false
    }

    public var activeApps: [WatchedApp] {
        watchedApps.filter { runningWatchedIDs.contains($0.bundleID) }
    }
}
