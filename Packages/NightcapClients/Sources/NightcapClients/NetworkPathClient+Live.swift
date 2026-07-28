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
        }
    )
}
