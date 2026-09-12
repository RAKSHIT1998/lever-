import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Keeps at most one Live Activity alive: the most urgent money deadline within the next 48 hours.
@MainActor
final class LiveActivityManager {
    static let horizonHours = 48

    /// Chooses which opportunity (if any) deserves the Lock Screen. Pure and testable.
    static func candidate(from opportunities: [Opportunity], now: Date = .now) -> Opportunity? {
        let limit = now.addingTimeInterval(TimeInterval(horizonHours) * 3600)
        return opportunities
            .filter { $0.isActionable && ($0.deadline ?? .distantPast) >= now && ($0.deadline ?? .distantFuture) <= limit }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            .first
    }

    func sync(with opportunities: [Opportunity]) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let existing = Activity<DeadlineActivityAttributes>.activities
        guard let target = Self.candidate(from: opportunities), let deadline = target.deadline else {
            for activity in existing { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let state = DeadlineActivityAttributes.ContentState(
            title: target.title,
            deadline: deadline,
            amountText: target.estimatedSavings.map { Money.format($0, code: target.currencyCode) } ?? "",
            lane: target.lane.rawValue
        )
        let content = ActivityContent(state: state, staleDate: deadline)
        if let current = existing.first(where: { $0.attributes.opportunityID == target.id }) {
            Task { await current.update(content) }
            for other in existing where other.id != current.id { Task { await other.end(nil, dismissalPolicy: .immediate) } }
        } else {
            for other in existing { Task { await other.end(nil, dismissalPolicy: .immediate) } }
            let attributes = DeadlineActivityAttributes(opportunityID: target.id, merchantName: target.merchantName)
            _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        }
        #endif
    }
}

/// One weekly heads-up, and only when the coming fortnight actually holds a deadline. Never "come back".
enum DigestPlanner {
    static let identifier = "digest.weekly"

    static func plan(opportunities: [OpportunitySnapshotLite], currencyCode: String, now: Date = .now, calendar: Calendar = .current) -> PlannedNotification? {
        // Next Monday 09:00.
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        comps.weekday = 2
        comps.hour = 9
        guard var monday = calendar.date(from: comps) else { return nil }
        if monday <= now { monday = calendar.date(byAdding: .weekOfYear, value: 1, to: monday) ?? monday }
        let windowEnd = calendar.date(byAdding: .day, value: 14, to: monday) ?? monday
        let upcoming = opportunities.filter { $0.deadline >= monday && $0.deadline <= windowEnd }
        guard !upcoming.isEmpty else { return nil }
        let atStake = upcoming.filter { !$0.countsAsSaving }.map(\.amount).reduce(0, +)
        let savings = upcoming.filter(\.countsAsSaving).map(\.amount).reduce(0, +)
        var parts: [String] = ["\(upcoming.count) money deadline\(upcoming.count == 1 ? "" : "s") in the next two weeks"]
        if atStake > 0 { parts.append("\(Money.format(atStake, code: currencyCode)) at stake") }
        if savings > 0 { parts.append("\(Money.format(savings, code: currencyCode)) you could still save") }
        let first = upcoming.min { $0.deadline < $1.deadline }
        return PlannedNotification(
            identifier: identifier,
            title: first.map { "First up: \($0.title)" } ?? "Your money week",
            body: parts.joined(separator: " · ") + ".",
            fireDate: monday,
            userInfo: first.map { [NotificationDelegate.opportunityKey: $0.id.uuidString] } ?? [:]
        )
    }
}

/// Minimal value the digest planner needs — keeps it testable without SwiftData.
struct OpportunitySnapshotLite: Equatable, Sendable {
    var id: UUID
    var title: String
    var deadline: Date
    var amount: Decimal
    var countsAsSaving: Bool
}

extension OpportunitySnapshotLite {
    @MainActor
    init?(_ o: Opportunity) {
        guard let deadline = o.deadline, o.isActionable else { return nil }
        self.init(id: o.id, title: o.title, deadline: deadline, amount: o.estimatedSavings ?? 0, countsAsSaving: o.countsAsPotentialSaving)
    }
}
