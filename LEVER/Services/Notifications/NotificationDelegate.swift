import Foundation
import UserNotifications

/// Routes notification taps to the right purchase/opportunity and lets money alerts show while the app is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onOpenPurchase: ((UUID) -> Void)?
    var onOpenOpportunity: ((UUID) -> Void)?

    static let purchaseKey = "purchaseID"
    static let opportunityKey = "opportunityID"

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let raw = info[Self.opportunityKey] as? String, let id = UUID(uuidString: raw) {
            await MainActor.run { onOpenOpportunity?(id) }
        } else if let raw = info[Self.purchaseKey] as? String, let id = UUID(uuidString: raw) {
            await MainActor.run { onOpenPurchase?(id) }
        }
    }
}
