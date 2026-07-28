import Dependencies
import NightcapDomain
import ServiceManagement

extension LaunchAtLoginClient: DependencyKey {
    public static let liveValue: LaunchAtLoginClient = .init(
        status: { LaunchAtLoginStatus(SMAppService.mainApp.status) },
        setEnabled: { enable in
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        }
    )
}
