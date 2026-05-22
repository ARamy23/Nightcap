import Foundation

extension AppFeature {
    func syncAssertion(_ state: inout State) {
        let reasons = assertionReasons(in: state)
        if reasons.isEmpty {
            assertion.release()
            state.assertionHeld = false
        } else {
            state.assertionHeld = assertion.acquire("Nightcap: \(reasons.joined(separator: ", "))")
        }
    }

    private func assertionReasons(in state: State) -> [String] {
        let appNames = state.watchedApps
            .filter { state.runningWatchedIDs.contains($0.bundleID) }
            .map(\.displayName)

        guard let manualSession = state.manualSession else { return appNames }
        return appNames + [manualSession.assertionReason]
    }
}
