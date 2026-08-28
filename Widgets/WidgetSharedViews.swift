import SwiftUI
import WidgetKit

struct WidgetEmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "banknote")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("widget.empty.message")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GoalProgressGauge: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Gauge(value: snapshot.progressFraction) {
            EmptyView()
        } currentValueLabel: {
            Text("\(snapshot.percentWhole)%")
                .font(.system(.caption, design: .rounded).weight(.semibold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(.accentColor)
        .accessibilityLabel(Text("widget.goal.progress.a11y"))
        .accessibilityValue(Text("\(snapshot.percentWhole)%"))
    }
}
