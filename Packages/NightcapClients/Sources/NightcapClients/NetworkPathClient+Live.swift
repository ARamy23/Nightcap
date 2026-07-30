import Dependencies
import Foundation
import Network
import NightcapDomain

extension NetworkPathClient: DependencyKey {
    public static let liveValue = NetworkPathClient(
        isSatisfied: {
            AsyncStream { continuation in
                let monitor = NWPathMonitor()
                monitor.pathUpdateHandler = { path in
                    continuation.yield(path.status == .satisfied)
                }
                monitor.start(queue: DispatchQueue(label: "com.abdocodes.nightcap.networkpath"))
                continuation.onTermination = { _ in monitor.cancel() }
            }
        },
        connection: {
            AsyncStream { continuation in
                let monitor = NWPathMonitor()
                monitor.pathUpdateHandler = { path in
                    continuation.yield(NightcapDomain.NetworkConnection.classify(path))
                }
                monitor.start(queue: DispatchQueue(label: "com.abdocodes.nightcap.networkkind"))
                continuation.onTermination = { _ in monitor.cancel() }
            }
        }
    )
}

// Qualified: the Network framework also exports a NetworkConnection.
extension NightcapDomain.NetworkConnection {
    /// Classify an `NWPath`.
    ///
    /// `isExpensive` is the reliable Personal Hotspot signal on a Mac: tethering
    /// over Wi-Fi still reports `.wifi` as the interface, so interface type alone
    /// cannot tell a hotspot from an ordinary network. Apple sets `isExpensive`
    /// for both cellular and Personal Hotspot — exactly the set we must not nag.
    /// A named factory rather than `init(_:)`, which the compiler resolves
    /// against the synthesized `Decodable` initialiser.
    public static func classify(_ path: NWPath) -> NightcapDomain.NetworkConnection {
        guard path.status == .satisfied else { return .none }

        if path.isExpensive || path.usesInterfaceType(.cellular) {
            return .hotspot
        }
        // Wired is checked before Wi-Fi: a docked Mac often still has Wi-Fi
        // associated, but the wired path is the one actually in use.
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        if path.usesInterfaceType(.wifi) { return .wifi }
        return .other
    }
}
