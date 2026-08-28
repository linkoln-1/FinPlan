import SwiftUI
import FinPlanCore

@MainActor
struct AnalyticsMonthlyCloseCard: View {
    let info: AnalyticsCloseInfo

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.sm) {
                HStack {
                    Text("analytics.close.title")
                        .font(.headline)
                    Spacer()
                    Text(info.close.monthStart, format: .dateTime.month(.wide).year())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                amountRow("analytics.close.income", money: info.close.income)
                amountRow("analytics.close.expenses", money: info.close.expenses)
                amountRow("analytics.close.savings", money: info.close.savingsAllocated)
                if info.close.fees.isPositive {
                    amountRow("analytics.close.fees", money: info.close.fees)
                }
                amountRow("analytics.close.netCashFlow", money: info.close.netCashFlow)
                if let basisPoints = info.close.savingsRateBasisPoints {
                    HStack {
                        Text("analytics.close.savingsRate")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: AnalyticsFormat.percent(basisPoints: basisPoints))
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                }

                Divider()

                HStack {
                    Label {
                        Text("analytics.close.netWorthChange")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: info.close.netWorthChange.isNegative ? "arrow.down.right" : "arrow.up.right")
                            .foregroundStyle(info.close.netWorthChange.isNegative ? FPStatusTint.negative : FPStatusTint.positive)
                    }
                    Spacer()
                    MoneyText(money: info.close.netWorthChange, compact: true)
                        .font(.subheadline.weight(.semibold))
                }

                if let name = info.biggestCategoryName {
                    HStack {
                        Label {
                            Text("analytics.close.biggestCategory")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: info.biggestCategorySymbol ?? "questionmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(verbatim: name)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private func amountRow(_ titleKey: LocalizedStringKey, money: Money) -> some View {
        HStack {
            Text(titleKey)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            MoneyText(money: money, compact: true)
                .font(.subheadline)
        }
    }
}

@MainActor
struct AnalyticsInsightsSection: View {
    let insights: [Insight]

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                Text("analytics.insights.title")
                    .font(.headline)
                if insights.isEmpty {
                    EmptyStateView(
                        systemImage: "checkmark.seal",
                        title: "analytics.insights.empty.title",
                        message: "analytics.insights.empty.message"
                    )
                } else {
                    ForEach(insights, id: \.self) { insight in
                        AnalyticsInsightRow(insight: insight)
                        if insight != insights.last {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

@MainActor
struct AnalyticsInsightRow: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: FP.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: FP.Spacing.sm) {
                Image(systemName: insight.severity.analyticsIconName)
                    .foregroundStyle(insight.severity.analyticsTint)
                    .accessibilityLabel(Text(insight.severity.analyticsSeverityKey))
                VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                    Text(LocalizedStringKey(insight.messageKey))
                        .font(.subheadline)
                    if let value = insight.value {
                        HStack(spacing: FP.Spacing.xs) {
                            MoneyText(money: value)
                                .font(.subheadline.weight(.medium))
                            if let secondary = insight.secondaryValue {
                                Text("analytics.insight.vs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                MoneyText(money: secondary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            DisclosureGroup {
                Text(verbatim: insight.basis)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("analytics.insight.basisTitle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension InsightSeverity {
    fileprivate var analyticsIconName: String {
        switch self {
        case .info: return "info.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    fileprivate var analyticsTint: Color {
        switch self {
        case .info: return FPStatusTint.neutral
        case .attention: return FPStatusTint.attention
        case .warning: return FPStatusTint.negative
        }
    }

    fileprivate var analyticsSeverityKey: LocalizedStringKey {
        switch self {
        case .info: return "analytics.insight.severity.info"
        case .attention: return "analytics.insight.severity.attention"
        case .warning: return "analytics.insight.severity.warning"
        }
    }
}
