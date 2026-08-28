import SwiftUI
import Charts
import FinPlanCore

@MainActor
struct AnalyticsChartsSection: View {
    let snapshot: AnalyticsSnapshot
    @Environment(FinanceStore.self) private var store

    var body: some View {
        incomeExpenseCard
        savingsCard
        categoryCard
        netWorthCard
        if !snapshot.tagSlices.isEmpty {
            tagCard
        }
    }

    private var incomeExpenseCard: some View {
        AnalyticsChartCard(questionKey: "analytics.chart.incomeVsExpenses.question") {
            Chart {
                ForEach(snapshot.trends, id: \.monthStart) { month in
                    BarMark(
                        x: .value(monthAxis, month.monthStart, unit: .month),
                        y: .value(amountAxis, month.income.chartMajor)
                    )
                    .position(by: .value(seriesAxis, incomeSeries))
                    .foregroundStyle(by: .value(seriesAxis, incomeSeries))
                    .opacity(barOpacity(month.monthStart))

                    BarMark(
                        x: .value(monthAxis, month.monthStart, unit: .month),
                        y: .value(amountAxis, month.expenses.chartMajor)
                    )
                    .position(by: .value(seriesAxis, expenseSeries))
                    .foregroundStyle(by: .value(seriesAxis, expenseSeries))
                    .opacity(barOpacity(month.monthStart))
                }
            }
            .chartForegroundStyleScale([
                incomeSeries: FPStatusTint.positive,
                expenseSeries: FPStatusTint.negative,
            ])
            .fpMoneyYAxis(currencyCode: moneyCurrencyCode, hidden: store.hideBalances)
            .chartLegend(position: .bottom, spacing: FP.Spacing.sm)
            .frame(height: 220)
            .accessibilityLabel(Text("analytics.chart.incomeVsExpenses.question"))
            .accessibilityValue(Text(verbatim: incomeExpenseSummary))
            currentMonthNote
        }
    }

    private struct RatePoint: Identifiable {
        let id: Date
        let month: Date
        let basisPoints: Int
        let scaledValue: Double
    }

    private var ratePoints: [RatePoint] {
        let maxSavings = snapshot.trends.map { $0.savingsAllocated.chartMajor }.max() ?? 0
        guard maxSavings > 0 else { return [] }
        return snapshot.trends.compactMap { month in
            guard let basisPoints = month.savingsRateBasisPoints else { return nil }
            return RatePoint(
                id: month.monthStart,
                month: month.monthStart,
                basisPoints: basisPoints,
                scaledValue: Double(basisPoints) / 10_000 * maxSavings
            )
        }
    }

    private var savingsCard: some View {
        AnalyticsChartCard(questionKey: "analytics.chart.savings.question") {
            Chart {
                ForEach(snapshot.trends, id: \.monthStart) { month in
                    BarMark(
                        x: .value(monthAxis, month.monthStart, unit: .month),
                        y: .value(amountAxis, month.savingsAllocated.chartMajor)
                    )
                    .foregroundStyle(by: .value(seriesAxis, savingsSeries))
                    .opacity(barOpacity(month.monthStart))
                }
                ForEach(ratePoints) { point in
                    LineMark(
                        x: .value(monthAxis, point.month, unit: .month),
                        y: .value(amountAxis, point.scaledValue)
                    )
                    .foregroundStyle(by: .value(seriesAxis, rateSeries))
                    .symbol(.circle)
                    .interpolationMethod(.monotone)
                }
                if let last = ratePoints.last {
                    PointMark(
                        x: .value(monthAxis, last.month, unit: .month),
                        y: .value(amountAxis, last.scaledValue)
                    )
                    .foregroundStyle(by: .value(seriesAxis, rateSeries))
                    .annotation(position: .topTrailing) {
                        Text(verbatim: AnalyticsFormat.percent(basisPoints: last.basisPoints))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartForegroundStyleScale([
                savingsSeries: Color.blue,
                rateSeries: Color.orange,
            ])
            .fpMoneyYAxis(currencyCode: moneyCurrencyCode, hidden: store.hideBalances)
            .chartLegend(position: .bottom, spacing: FP.Spacing.sm)
            .frame(height: 220)
            .accessibilityLabel(Text("analytics.chart.savings.question"))
            .accessibilityValue(Text(verbatim: savingsSummary))
            if !ratePoints.isEmpty {
                Text("analytics.chart.savings.rateNote")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            currentMonthNote
        }
    }

    private var categoryCard: some View {
        AnalyticsChartCard(questionKey: "analytics.chart.category.question") {
            if snapshot.categorySlices.isEmpty {
                EmptyStateView(
                    systemImage: "chart.pie",
                    title: "analytics.chart.category.empty.title",
                    message: "analytics.chart.category.empty.message"
                )
            } else {
                Chart(snapshot.categorySlices) { slice in
                    BarMark(
                        x: .value(amountAxis, slice.amount.chartMajor),
                        y: .value(categoryAxis, sliceDisplayName(slice))
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .chartXAxis(store.hideBalances ? .hidden : .automatic)
                .frame(height: max(120, CGFloat(snapshot.categorySlices.count) * 32))
                .accessibilityLabel(Text("analytics.chart.category.question"))
                .accessibilityValue(Text(verbatim: categorySummary))

                let total = categoryTotal
                VStack(spacing: FP.Spacing.sm) {
                    ForEach(snapshot.categorySlices) { slice in
                        HStack(spacing: FP.Spacing.sm) {
                            Image(systemName: slice.symbolName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            if let name = slice.name {
                                Text(verbatim: name)
                                    .font(.subheadline)
                            } else {
                                Text("analytics.category.uncategorized")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: FP.Spacing.sm)
                            if case .success(let totalAmount) = total,
                               let share = AnalyticsFormat.share(
                                   partMinor: slice.amount.amountMinor,
                                   totalMinor: totalAmount.amountMinor
                               ) {
                                Text(verbatim: share)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            MoneyText(money: slice.amount)
                                .font(.subheadline)
                        }
                    }
                }
                if case .failure = total {
                    Label("analytics.chart.category.computeIssue", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(FPStatusTint.attention)
                }
            }
        }
    }

    private var netWorthCard: some View {
        AnalyticsChartCard(questionKey: "analytics.chart.netWorth.question") {
            Chart(snapshot.netWorthPoints, id: \.date) { point in
                LineMark(
                    x: .value(monthAxis, point.date, unit: .month),
                    y: .value(amountAxis, point.netWorth.chartMajor)
                )
                .foregroundStyle(by: .value(seriesAxis, actualSeries))
                .symbol(.circle)
                .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale([actualSeries: Color.teal])
            .chartYScale(domain: .automatic(includesZero: false))
            .fpMoneyYAxis(currencyCode: netWorthCurrencyCode, hidden: store.hideBalances)
            .chartLegend(position: .bottom, spacing: FP.Spacing.sm)
            .frame(height: 200)
            .accessibilityLabel(Text("analytics.chart.netWorth.question"))
            .accessibilityValue(Text(verbatim: netWorthSummary))
            Text("analytics.chart.netWorth.actualNote")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var tagCard: some View {
        AnalyticsChartCard(questionKey: "analytics.chart.tags.question") {
            Chart(snapshot.tagSlices) { slice in
                BarMark(
                    x: .value(amountAxis, slice.amount.chartMajor),
                    y: .value(tagAxis, slice.name)
                )
                .foregroundStyle(Color.indigo)
            }
            .chartXAxis(store.hideBalances ? .hidden : .automatic)
            .frame(height: max(100, CGFloat(snapshot.tagSlices.count) * 32))
            .accessibilityLabel(Text("analytics.chart.tags.question"))
            .accessibilityValue(Text(verbatim: tagSummary))

            VStack(spacing: FP.Spacing.sm) {
                ForEach(snapshot.tagSlices) { slice in
                    HStack(spacing: FP.Spacing.sm) {
                        Image(systemName: "tag")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(verbatim: slice.name)
                            .font(.subheadline)
                        Spacer(minLength: FP.Spacing.sm)
                        MoneyText(money: slice.amount)
                            .font(.subheadline)
                    }
                }
            }
            Text("analytics.chart.tags.multiCountNote")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func barOpacity(_ monthStart: Date) -> Double {
        monthStart == snapshot.currentMonthStart ? 0.45 : 1
    }

    @ViewBuilder
    private var currentMonthNote: some View {
        if snapshot.trends.contains(where: { $0.monthStart == snapshot.currentMonthStart }) {
            Text("analytics.chart.currentMonthNote")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var categoryTotal: Result<Money, any Error>? {
        guard let currency = snapshot.categorySlices.first?.amount.currency else { return nil }
        return Result { try snapshot.categorySlices.map(\.amount).sum(in: currency) }
    }

    private func sliceDisplayName(_ slice: AnalyticsCategorySlice) -> String {
        slice.name ?? String(localized: "analytics.category.uncategorized")
    }

    private var moneyCurrencyCode: String { snapshot.summary.income.currency.code }

    private var netWorthCurrencyCode: String {
        snapshot.netWorthPoints.first?.netWorth.currency.code ?? moneyCurrencyCode
    }

    private var incomeSeries: String { String(localized: "analytics.series.income") }
    private var expenseSeries: String { String(localized: "analytics.series.expenses") }
    private var savingsSeries: String { String(localized: "analytics.series.savings") }
    private var rateSeries: String { String(localized: "analytics.series.savingsRate") }
    private var actualSeries: String { String(localized: "analytics.series.actual") }
    private var seriesAxis: String { String(localized: "analytics.axis.series") }
    private var monthAxis: String { String(localized: "analytics.axis.month") }
    private var amountAxis: String { String(localized: "analytics.axis.amount") }
    private var categoryAxis: String { String(localized: "analytics.axis.category") }
    private var tagAxis: String { String(localized: "analytics.axis.tag") }

    private var hiddenSummary: String { String(localized: "a11y.hiddenAmount") }

    private func monthLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).year())
    }

    private var incomeExpenseSummary: String {
        guard !store.hideBalances else { return hiddenSummary }
        return snapshot.trends.map { month in
            "\(monthLabel(month.monthStart)): \(incomeSeries) \(month.income.formatted()), \(expenseSeries) \(month.expenses.formatted())"
        }.joined(separator: "; ")
    }

    private var savingsSummary: String {
        guard !store.hideBalances else { return hiddenSummary }
        return snapshot.trends.map { month in
            let rate = month.savingsRateBasisPoints.map {
                AnalyticsFormat.percent(basisPoints: $0)
            } ?? String(localized: "analytics.savingsRate.noIncome")
            return "\(monthLabel(month.monthStart)): \(savingsSeries) \(month.savingsAllocated.formatted()), \(rateSeries) \(rate)"
        }.joined(separator: "; ")
    }

    private var categorySummary: String {
        guard !store.hideBalances else { return hiddenSummary }
        return snapshot.categorySlices.map { slice in
            "\(sliceDisplayName(slice)): \(slice.amount.formatted())"
        }.joined(separator: "; ")
    }

    private var netWorthSummary: String {
        guard !store.hideBalances else { return hiddenSummary }
        return snapshot.netWorthPoints.map { point in
            "\(monthLabel(point.date)): \(point.netWorth.formatted())"
        }.joined(separator: "; ")
    }

    private var tagSummary: String {
        guard !store.hideBalances else { return hiddenSummary }
        return snapshot.tagSlices.map { slice in
            "\(slice.name): \(slice.amount.formatted())"
        }.joined(separator: "; ")
    }
}

@MainActor
private struct AnalyticsChartCard<Content: View>: View {
    let questionKey: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                Text(questionKey)
                    .font(.subheadline.weight(.semibold))
                content
            }
        }
    }
}

extension Money {
    fileprivate var chartMajor: Double {
        Double(amountMinor) / Double(currency.minorUnitsPerMajor)
    }
}
