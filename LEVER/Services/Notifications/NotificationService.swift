import Foundation
import UserNotifications

/// Wraps UNUserNotificationCenter behind `NotificationScheduling`.
struct NotificationService: NotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func authorizationGranted() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func schedule(identifier: String, title: String, body: String, at date: Date, userInfo: [String: String]) async {
        guard date > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancel(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }
}

struct PlannedNotification: Equatable, Sendable {
    var identifier: String
    var title: String
    var body: String
    var fireDate: Date
    var userInfo: [String: String] = [:]
}

/// Pure planner: which reminders a purchase deserves. Every notification is about the user's money — never "come back".
enum DeadlineNotificationPlanner {
    static func plan(for p: PurchaseSnapshot, now: Date = .now, calendar: Calendar = .current) -> [PlannedNotification] {
        var planned: [PlannedNotification] = []
        let money = Money.format(p.amount, code: p.currencyCode)

        func at(_ date: Date, daysBefore: Int, hour: Int = 9) -> Date? {
            guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: date) else { return nil }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour
            comps.minute = 0
            return calendar.date(from: comps)
        }

        if let deadline = p.returnWindow?.deadline {
            for days in [2, 1] {
                if let fire = at(deadline, daysBefore: days), fire > now {
                    planned.append(PlannedNotification(
                        identifier: "return.\(p.id.uuidString).\(days)",
                        title: days == 1 ? "Return window closes tomorrow" : "Return window closes in 2 days",
                        body: "Your \(money) \(p.title) from \(p.merchantName) can still be returned until \(deadline.leverShort).",
                        fireDate: fire,
                        userInfo: [NotificationDelegate.purchaseKey: p.id.uuidString]
                    ))
                }
            }
        }

        for warranty in p.warranties {
            guard let end = warranty.endDate else { continue }
            for days in [30, 7] {
                if let fire = at(end, daysBefore: days), fire > now {
                    planned.append(PlannedNotification(
                        identifier: "warranty.\(p.id.uuidString).\(warranty.type.rawValue).\(days)",
                        title: "\(p.title) warranty ends in \(days) days",
                        body: "\(warranty.provider) coverage ends \(end.leverShort). Check the product now while a claim is still possible.",
                        fireDate: fire,
                        userInfo: [NotificationDelegate.purchaseKey: p.id.uuidString]
                    ))
                }
            }
        }

        if let sub = p.subscription, sub.status != .cancelled, let next = sub.nextBillingDate {
            let price = Money.format(sub.price, code: p.currencyCode) + sub.cycle.shortSuffix
            for days in [3, 1] {
                if let fire = at(next, daysBefore: days), fire > now {
                    planned.append(PlannedNotification(
                        identifier: "renewal.\(p.id.uuidString).\(days)",
                        title: "\(p.merchantName) renews \(days == 1 ? "tomorrow" : "in 3 days")",
                        body: "\(price) will be charged on \(next.leverShort). Cancel or renegotiate before then if it's not worth it.",
                        fireDate: fire,
                        userInfo: [NotificationDelegate.purchaseKey: p.id.uuidString]
                    ))
                }
            }
        }
        return planned
    }

    static func prefixes(for purchaseID: UUID) -> [String] {
        ["return.\(purchaseID.uuidString)", "warranty.\(purchaseID.uuidString)", "renewal.\(purchaseID.uuidString)"]
    }
}
