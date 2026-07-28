import Foundation

#if canImport(ServiceManagement)
import ServiceManagement
#endif

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case unknown
    case disabled
    case enabled
    case requiresApproval
    case error(String)

    public var isOn: Bool {
        if case .enabled = self { return true }
        return false
    }
}

#if canImport(ServiceManagement)
extension LaunchAtLoginStatus {
    public init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .disabled
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .error("Login item not found in bundle.")
        @unknown default: self = .unknown
        }
    }
}
#endif
