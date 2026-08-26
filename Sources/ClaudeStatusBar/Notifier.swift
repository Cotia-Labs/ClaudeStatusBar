import AppKit
import Foundation
import UserNotifications

/// Posts local notifications (status changes, usage thresholds, new releases).
/// No-ops when the executable is not running from an app bundle, since
/// UNUserNotificationCenter requires a bundle identifier.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private static let linkKey = "link"

    private let isAvailable = Bundle.main.bundleIdentifier != nil

    func requestAuthorizationIfNeeded() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// `link`, quando presente, abre no navegador ao clicar na notificação.
    func notify(title: String, body: String, link: URL? = nil) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let link { content.userInfo = [Self.linkKey: link.absoluteString] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // O app é .accessory e normalmente está em background; sem isto o banner
    // só apareceria na central de notificações.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let string = response.notification.request.content.userInfo[Self.linkKey] as? String,
           let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
