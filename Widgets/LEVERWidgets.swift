import WidgetKit
import SwiftUI

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        let next = Calendar.current.date(byAdding: .hour, value: 3, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

extension WidgetSnapshot {
    static var placeholder: WidgetSnapshot {
        var s = WidgetSnapshot.empty
        s.currencyCode = "INR"
        s.potentialSavings = 8_400
        s.openOpportunities = 3
        s.moneyAtRisk = 12_400
        s.deadlinesThisWeek = [
            .init(id: UUID(), title: "MacBook return window", date: Date().addingTimeInterval(86_400 * 2), amount: 149_990),
            .init(id: UUID(), title: "Netflix renews", date: Date().addingTimeInterval(86_400), amount: 1_499),
        ]
        return s
    }
}

// MARK: - Shared styling

enum WidgetPalette {
    static let money = Color(red: 0.11, green: 0.60, blue: 0.30)
    static let urgent = Color(red: 0.86, green: 0.22, blue: 0.20)
}

struct WidgetWordmark: View {
    var body: some View {
        Text("LEVER")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Potential savings widget

struct PotentialSavingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rakshit1998.lever.widget.savings", provider: SnapshotProvider()) { entry in
            PotentialSavingsView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Potential savings")
        .description("Money LEVER thinks you can still save or recover.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PotentialSavingsView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetWordmark()
            Spacer(minLength: 0)
            Text("Potential savings")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(snapshot.potentialSavings.currencyString(code: snapshot.currencyCode, fractionDigits: 0))
                .font(.system(size: family == .systemSmall ? 26 : 30, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetPalette.money)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(snapshot.openOpportunities == 0 ? "Nothing to fix right now" : "\(snapshot.openOpportunities) opportunit\(snapshot.openOpportunities == 1 ? "y" : "ies")")
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            if family == .systemMedium, let first = snapshot.deadlinesThisWeek.first {
                Divider()
                HStack {
                    Image(systemName: "clock").foregroundStyle(WidgetPalette.urgent)
                    Text(first.title).lineLimit(1)
                    Spacer()
                    Text(first.date, style: .relative)
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "lever://home"))
    }
}

// MARK: - Money at risk widget

struct MoneyAtRiskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rakshit1998.lever.widget.risk", provider: SnapshotProvider()) { entry in
            MoneyAtRiskView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Money at risk")
        .description("Deadlines closing this week.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct MoneyAtRiskView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(snapshot.deadlinesThisWeek.isEmpty ? "LEVER: no deadlines this week" : "\(snapshot.deadlinesThisWeek.count) deadline\(snapshot.deadlinesThisWeek.count == 1 ? "" : "s") · \(snapshot.moneyAtRisk.currencyString(code: snapshot.currencyCode, fractionDigits: 0)) at risk")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("MONEY AT RISK").font(.caption2.weight(.bold))
                Text(snapshot.moneyAtRisk.currencyString(code: snapshot.currencyCode, fractionDigits: 0)).font(.headline.weight(.bold))
                if let first = snapshot.deadlinesThisWeek.first {
                    Text("\(first.title) · \(first.date, style: .relative)").font(.caption2).lineLimit(1)
                }
            }
            .widgetURL(URL(string: "lever://home"))
        default:
            VStack(alignment: .leading, spacing: 6) {
                WidgetWordmark()
                Spacer(minLength: 0)
                Text("Money at risk").font(.caption).foregroundStyle(.secondary)
                Text(snapshot.moneyAtRisk.currencyString(code: snapshot.currencyCode, fractionDigits: 0))
                    .font(.system(size: family == .systemSmall ? 26 : 30, weight: .bold, design: .rounded))
                    .foregroundStyle(snapshot.moneyAtRisk > 0 ? WidgetPalette.urgent : .primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(snapshot.deadlinesThisWeek.isEmpty ? "No deadlines this week" : "\(snapshot.deadlinesThisWeek.count) deadline\(snapshot.deadlinesThisWeek.count == 1 ? "" : "s") this week")
                    .font(.caption.weight(.medium))
                if family == .systemMedium {
                    ForEach(snapshot.deadlinesThisWeek.prefix(2)) { deadline in
                        HStack {
                            Text(deadline.title).lineLimit(1)
                            Spacer()
                            Text(deadline.date, style: .relative)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(URL(string: "lever://home"))
        }
    }
}

@main
struct LEVERWidgetBundle: WidgetBundle {
    var body: some Widget {
        PotentialSavingsWidget()
        MoneyAtRiskWidget()
        #if canImport(ActivityKit)
        DeadlineLiveActivity()
        #endif
    }
}

// MARK: - Live Activity

#if canImport(ActivityKit)
import ActivityKit

struct DeadlineLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeadlineActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color(red: 0.06, green: 0.07, blue: 0.09))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.merchantName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.deadline, style: .relative).font(.caption.weight(.semibold)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Spacer()
                        if !context.state.amountText.isEmpty { Text(context.state.amountText).font(.subheadline.weight(.bold)).foregroundStyle(laneColor(context.state.lane)) }
                    }
                }
            } compactLeading: {
                Image(systemName: "clock.badge.exclamationmark").foregroundStyle(laneColor(context.state.lane))
            } compactTrailing: {
                compactCountdown(to: context.state.deadline)
            } minimal: {
                Image(systemName: "clock.badge.exclamationmark").foregroundStyle(laneColor(context.state.lane))
            }
            .widgetURL(URL(string: "lever://opportunity/\(context.attributes.opportunityID.uuidString)"))
        }
    }

    /// "23h" / "3d" when far out; a live mm:ss timer only inside the last hour — the compact slot is tiny.
    @ViewBuilder
    private func compactCountdown(to deadline: Date) -> some View {
        let seconds = deadline.timeIntervalSinceNow
        if seconds <= 3600 {
            Text(deadline, style: .timer).monospacedDigit().frame(width: 44)
        } else if seconds < 48 * 3600 {
            Text("\(Int(seconds / 3600))h").font(.caption.weight(.bold)).monospacedDigit()
        } else {
            Text("\(Int(seconds / 86400))d").font(.caption.weight(.bold)).monospacedDigit()
        }
    }

    private func laneColor(_ lane: String) -> Color {
        switch lane {
        case "urgent": WidgetPalette.urgent
        case "protection": Color(red: 0.98, green: 0.80, blue: 0.30)
        default: WidgetPalette.money
        }
    }

    private func lockScreen(_ context: ActivityViewContext<DeadlineActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("LEVER").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.5).foregroundStyle(.secondary)
                    Text(context.attributes.merchantName.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                }
                Text(context.state.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                if !context.state.amountText.isEmpty {
                    Text(context.state.amountText).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(laneColor(context.state.lane))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("closes in").font(.caption2).foregroundStyle(.secondary)
                Text(context.state.deadline, style: .timer).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit().foregroundStyle(.white).frame(width: 96, alignment: .trailing)
            }
        }
        .padding(16)
        .widgetURL(URL(string: "lever://opportunity/\(context.attributes.opportunityID.uuidString)"))
    }
}
#endif
