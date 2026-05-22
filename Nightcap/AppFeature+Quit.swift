import ComposableArchitecture
import Foundation

extension AppFeature {
    func handleQuitTapped(state: inout State) -> Effect<Action> {
        assertion.release()
        state.manualSession = nil
        state.assertionHeld = false
        quitter.quit()
        return .cancel(id: CancelID.manualSession)
    }
}
