import Foundation
import UserNotifications

struct NotificationManager {
    static func captureComplete(tapeLabel: String, fileSize: String) {
        let content = UNMutableNotificationContent()
        content.title = "Capture Complete"
        content.body  = "\(tapeLabel.isEmpty ? "Tape" : tapeLabel) — \(fileSize)"
        content.sound = .default
        schedule(content)
    }

    static func captureError(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Capture Error"
        content.body  = message
        content.sound = .defaultCritical
        schedule(content)
    }

    private static func schedule(_ content: UNMutableNotificationContent) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
