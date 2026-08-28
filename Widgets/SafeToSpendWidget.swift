import SwiftUI
import WidgetKit

struct SafeToSpendWidget: Widget {
    static let kind = "FinPlanSafeToSpendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            SafeToSpendWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName(Text("widget.safeToSpend.displayName"))
        .description(Text("widget.safeToSpend.description"))
        .supportedFamilies([.systemSmall])
    }
}

struct SafeToSpendWidgetView: View {
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
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(WidgetMoneyFormat.compact(
                minor: snapshot.safeToSpendMinor,
                code: snapshot.currencyCode,
                exponent: snapshot.currencyExponent
            ))
            .font(.system(.title2, design: .rounded).weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            Text("widget.safeToSpend.label")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
