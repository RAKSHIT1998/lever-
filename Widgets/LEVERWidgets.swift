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
        StaticConfiguration(kind: "com.lever.widget.savings", provider: SnapshotProvider()) { entry in
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
        StaticConfiguration(kind: "com.lever.widget.risk", provider: SnapshotProvider()) { entry in
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
    }
}
