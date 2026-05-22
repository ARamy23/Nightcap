import ComposableArchitecture
import Foundation

extension AppFeature {
    func handleLaunchAtLoginToggled(
        _ enable: Bool,
        state: inout State
    ) -> Effect<Action> {
        let previous = state.launchAtLoginStatus
        state.launchAtLoginStatus = enable ? .enabled : .disabled

        return .run { send in
            do {
                try launchAtLogin.setEnabled(enable)
                let actual = launchAtLogin.status()
                let resolved: LaunchAtLoginStatus
                switch actual {
                case .enabled, .disabled, .requiresApproval:
                    resolved = actual
                case .unknown, .error:
                    resolved = enable ? .enabled : .disabled
                }
                await send(.launchAtLoginStatusUpdated(resolved))
            } catch {
                await send(.launchAtLoginStatusUpdated(previous))
            }
        }
        .cancellable(id: CancelID.launchAtLogin, cancelInFlight: true)
    }
}
