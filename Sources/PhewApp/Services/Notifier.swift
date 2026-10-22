import UserNotifications

enum Notifier {
    static func requestPermission(then done: @escaping @Sendable () -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in done() }
    }

    static func post(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Phew"
        content.body = message
        let request = UNNotificationRequest(identifier: "low-space", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
