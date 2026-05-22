import SwiftUI

struct ManualSessionMenuSection: View {
    let manualSession: ManualSession?
    let onStart: (ManualSessionDuration) -> Void
    let onStop: () -> Void

    var body: some View {
        Menu {
            Button("15 min") { onStart(.minutes15) }
            Button("1 hour") { onStart(.hour1) }
            Button("Until Turned Off") { onStart(.indefinite) }

            if manualSession != nil {
                Divider()
                Button("Stop Keeping Awake") { onStop() }
            }
        } label: {
            Label(labelTitle, systemImage: "timer")
        }
    }

    private var labelTitle: String {
        guard let manualSession else { return "Keep Awake" }
        return "Keep Awake: \(manualSessionLabel(for: manualSession))"
    }

    private func manualSessionLabel(for session: ManualSession) -> String {
        switch session {
        case let .finite(duration):
            duration.title
        case .indefinite:
            "On"
        }
    }
}
