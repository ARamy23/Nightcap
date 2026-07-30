import Dependencies
import Foundation
import NightcapDomain
import UserNotifications

/// The companion-side notifier. Lives here rather than in NightcapClients
/// because that module is the macOS adapter layer — it imports AppKit and IOKit
/// and does not build for iOS or watchOS, which are the only platforms that ever
/// deliver this alert.
extension HotspotNotifierClient {
    public static let userNotifications = HotspotNotifierClient(
        requestAuthorization: {
            await withCheckedContinuation { continuation in
                UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        continuation.resume(returning: granted)
                    }
            }
        },
        notify: { title, body in
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            // nil trigger: deliver now. The Mac being offline is only worth
            // saying while it is still true.
            let request = UNNotificationRequest(
                identifier: "nightcap.hotspot.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    )
}
