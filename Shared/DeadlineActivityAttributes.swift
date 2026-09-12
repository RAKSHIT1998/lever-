import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity for the single most urgent money deadline (≤ 48h). Shown on the Lock Screen and Dynamic Island.
struct DeadlineActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var deadline: Date
        var amountText: String
        var lane: String   // "urgent" | "opportunity" | "protection"
    }

    var opportunityID: UUID
    var merchantName: String
}
#endif
