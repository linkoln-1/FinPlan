import SwiftUI
import WidgetKit

struct MonthWidget: Widget {
    static let kind = "FinPlanMonthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            MonthWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName(Text("widget.month.displayName"))
        .description(Text("widget.month.description"))
        .supportedFamilies([.systemMedium])
    }
}

struct MonthWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(for: snapshot)
            } else {
                WidgetEmptyStateView()
            }
        }
        .widgetURL(URL(string: "finplan://dashboard"))
    }

    private func content(for snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("widget.month.title")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            row(
                titleKey: "widget.month.income",
                symbol: "arrow.down.circle.fill",
                color: .green,
                minor: snapshot.monthIncomeMinor,
                snapshot: snapshot
            )
            row(
                titleKey: "widget.month.expenses",
                symbol: "arrow.up.circle",
                color: .red,
                minor: snapshot.monthExpensesMinor,
                snapshot: snapshot
            )
            row(
                titleKey: "widget.month.saved",
                symbol: "target",
                color: .blue,
                minor: snapshot.monthSavedMinor,
                snapshot: snapshot
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func row(
        titleKey: LocalizedStringKey,
        symbol: String,
        color: Color,
        minor: Int64,
        snapshot: WidgetSnapshot
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(titleKey)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(WidgetMoneyFormat.compact(
                minor: minor,
                code: snapshot.currencyCode,
                exponent: snapshot.currencyExponent
            ))
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }
}
