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
    ///
    /// Kept as a stored property rather than derived from `connection` so that a
    /// companion running against an older Mac — which sends this and not
    /// `connection` — still shows the right thing.
    public var hasLostNetwork: Bool

    /// How the Mac is reaching the internet.
    public var connection: NetworkConnection

    public init(
        isAwakeHeld: Bool = false,
        watchedApps: [WatchedApp] = [],
        runningWatchedIDs: Set<String> = [],
        lastUpdated: Date = .distantPast,
        hasLostNetwork: Bool = false,
        connection: NetworkConnection? = nil
    ) {
        self.isAwakeHeld = isAwakeHeld
        self.watchedApps = watchedApps
        self.runningWatchedIDs = runningWatchedIDs
        self.lastUpdated = lastUpdated
        self.hasLostNetwork = hasLostNetwork
        // Defaulted from `hasLostNetwork` rather than to a fixed case, so a
        // caller that only knows the old boolean still gets consistent
        // behaviour — the same resolution the decoder applies to older Macs.
        self.connection = connection ?? (hasLostNetwork ? .none : .other)
    }

    /// Only worth nagging about when the Mac is actually being kept awake for
    /// work; a sleeping Mac losing its network is not interesting.
    ///
    /// Suppressed when the Mac is already on a hotspot: it has no network *of
    /// its own*, but telling someone to enable the hotspot they are already
    /// using is the most annoying possible notification.
    public var shouldSuggestHotspot: Bool {
        guard isAwakeHeld, hasLostNetwork else { return false }
        return connection.wouldBenefitFromHotspot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isAwakeHeld = try container.decode(Bool.self, forKey: .isAwakeHeld)
        watchedApps = try container.decode([WatchedApp].self, forKey: .watchedApps)
        runningWatchedIDs = try container.decode(Set<String>.self, forKey: .runningWatchedIDs)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        // Older Macs will not send this field.
        hasLostNetwork = try container.decodeIfPresent(Bool.self, forKey: .hasLostNetwork) ?? false
        // Nor this one. `.other` rather than `.none`, so an older Mac is not
        // reported as offline — and, since `.other` is not hotspot-worthy, the
        // nudge still follows `hasLostNetwork` alone for those Macs.
        connection = try container.decodeIfPresent(NetworkConnection.self, forKey: .connection)
            ?? (hasLostNetwork ? .none : .other)
    }

    public var activeApps: [WatchedApp] {
        watchedApps.filter { runningWatchedIDs.contains($0.bundleID) }
    }
}
