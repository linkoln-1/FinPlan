import SwiftUI
import WidgetKit

struct GoalWidget: Widget {
    static let kind = "FinPlanGoalWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            GoalWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName(Text("widget.goal.displayName"))
        .description(Text("widget.goal.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GoalWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.primaryGoalTitle != nil, snapshot.targetMinor > 0 {
                content(for: snapshot)
            } else {
                WidgetEmptyStateView()
            }
        }
        .widgetURL(URL(string: "finplan://goals"))
    }

    @ViewBuilder
    private func content(for snapshot: WidgetSnapshot) -> some View {
        switch family {
        case .systemMedium:
            mediumContent(for: snapshot)
        default:
            smallContent(for: snapshot)
        }
    }

    private func smallContent(for snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GoalProgressGauge(snapshot: snapshot)
            Spacer(minLength: 0)
            Text(snapshot.primaryGoalTitle ?? "")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            fundedOfTarget(snapshot)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func mediumContent(for snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 14) {
            GoalProgressGauge(snapshot: snapshot)
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.primaryGoalTitle ?? "")
                    .font(.headline)
                    .lineLimit(1)
                fundedOfTarget(snapshot)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    Text("widget.goal.remaining")
                    Text(WidgetMoneyFormat.compact(
                        minor: snapshot.remainingMinor,
                        code: snapshot.currencyCode,
                        exponent: snapshot.currencyExponent
                    ))
                    .fontWeight(.medium)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func fundedOfTarget(_ snapshot: WidgetSnapshot) -> Text {
        let funded = WidgetMoneyFormat.compact(
            minor: snapshot.fundedMinor, code: snapshot.currencyCode, exponent: snapshot.currencyExponent
        )
        let target = WidgetMoneyFormat.compact(
            minor: snapshot.targetMinor, code: snapshot.currencyCode, exponent: snapshot.currencyExponent
        )
        return Text(verbatim: "\(funded) / \(target)")
    }
}
