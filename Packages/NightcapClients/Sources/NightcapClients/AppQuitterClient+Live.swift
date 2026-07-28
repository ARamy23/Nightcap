import AppKit
import Dependencies
import NightcapDomain

extension AppQuitterClient: DependencyKey {
    public static let liveValue: AppQuitterClient = .init(
        quit: {
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    )
}
