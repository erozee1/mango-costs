import UserNotifications
import Foundation

final class NotificationManager {
    static let shared = NotificationManager()
    private var fired: Set<Double> = []

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func checkThresholds(oldCost: Double, newCost: Double) {
        for checkpoint in CostModel.notificationCheckpoints {
            guard oldCost < checkpoint, newCost >= checkpoint, !fired.contains(checkpoint) else { continue }
            fired.insert(checkpoint)
            fire(cost: newCost, checkpoint: checkpoint)
        }
    }

    private func fire(cost: Double, checkpoint: Double) {
        let content = UNMutableNotificationContent()
        content.title = "🥭 Mango Costs Alert"
        content.body = "Session reached $\(String(format: "%.2f", checkpoint)) — now at $\(String(format: "%.3f", cost))"
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "mango-\(checkpoint)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
