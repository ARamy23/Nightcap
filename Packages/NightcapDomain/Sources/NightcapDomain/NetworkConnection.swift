import Foundation

/// How the Mac is reaching the internet, as far as the companions need to care.
///
/// The distinction that matters is `hotspot` versus everything else: the whole
/// point of the companion nudge is "turn your hotspot on", which is noise if the
/// Mac is already tethered to it.
public enum NetworkConnection: String, Codable, Equatable, Sendable {
    /// No usable path at all.
    case none
    case wifi
    case wired
    /// Tethered to a phone — Personal Hotspot, or cellular directly.
    case hotspot
    /// Satisfied, but over something we do not label (Bluetooth PAN, VPN-only,
    /// a loopback-ish path). Treated as connected.
    case other

    /// Whether the Mac can currently reach anything.
    public var isConnected: Bool { self != .none }

    /// Whether turning a phone hotspot on would actually help.
    ///
    /// Phrased as "not already tethered" rather than "is offline" on purpose.
    /// The two differ for `.other`, which means *unknown* — a Mac that has not
    /// reported a connection type yet, or an older one that never will. Treating
    /// unknown as "no hotspot needed" would silently swallow the nudge for
    /// exactly those users; the only case worth suppressing is the one we can
    /// positively identify, where the user is already on the hotspot we would be
    /// telling them to enable.
    public var wouldBenefitFromHotspot: Bool { self != .hotspot }
}
