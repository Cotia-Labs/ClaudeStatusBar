import Foundation
import UserNotifications

/// Posts a local notification when the overall status changes.
/// No-ops when the executable is not running from an app bundle, since
/// UNUserNotificationCenter requires a bundle identifier.
final class Notifier {
    private let isAvailable = Bundle.main.bundleIdentifier != nil

    func requestAuthorizationIfNeeded() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(title: String, body: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
