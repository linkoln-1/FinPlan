import SwiftUI
import Charts
import FinPlanCore

struct DashboardChartCard: View {
    let data: DashboardChartData
    @Environment(FinanceStore.self) private var store

    private static let chartHeight: CGFloat = 220

    private var actualLabel: String { String(localized: "dashboard.chart.actual") }
    private var forecastLabel: String { String(localized: "dashboard.chart.forecast") }

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                Text("dashboard.chart.title")
                    .font(.headline)
                chart
                    .frame(height: Self.chartHeight)
            }
        }
    }

    private var chart: some View {
        let xDomain = FPProjectionDomain.clampedDomain(for: data.points.map(\.date))
        return Chart {
            ForEach(data.points) { point in
                LineMark(
                    x: .value(String(localized: "dashboard.chart.axisDate"), point.date),
                    y: .value(String(localized: "dashboard.chart.axisAmount"), data.majorUnits(point.amountMinor)),
                    series: .value(String(localized: "dashboard.chart.series"), label(for: point.series))
                )
                .foregroundStyle(by: .value(String(localized: "dashboard.chart.series"), label(for: point.series)))
                .lineStyle(by: .value(String(localized: "dashboard.chart.series"), label(for: point.series)))
                .interpolationMethod(.monotone)
            }
            RuleMark(
                y: .value(String(localized: "dashboard.chart.target"), data.majorUnits(data.target.amountMinor))
            )
            .foregroundStyle(FPStatusTint.attention)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .annotation(position: .bottom, alignment: .trailing, spacing: 2) {
                FPTargetAnnotationLabel(titleKey: "dashboard.chart.target")
            }
        }
        .chartForegroundStyleScale(
            domain: [actualLabel, forecastLabel],
            range: [Color.accentColor, Color.secondary]
        )
        .chartLineStyleScale(
            domain: [actualLabel, forecastLabel],
            range: [StrokeStyle(lineWidth: 2), StrokeStyle(lineWidth: 2, dash: [5, 4])]
        )
        .chartXScale(domain: xDomain)
        .fpProjectionXAxis(spansYears: FPProjectionDomain.spansYears(xDomain))
        .fpMoneyYAxis(currencyCode: data.target.currency.code, hidden: store.hideBalances)
        .chartLegend(position: .bottom, spacing: FP.Spacing.sm)
        .accessibilityLabel(String(localized: "a11y.dashboard.chart"))
        .accessibilityValue(accessibilityValueText)
    }

    private func label(for series: DashboardChartPoint.Series) -> String {
        switch series {
        case .actual: actualLabel
        case .forecast: forecastLabel
        }
    }

    private var accessibilityValueText: String {
        if store.hideBalances {
            return String(localized: "a11y.hiddenAmount")
        }
        return String(localized: "a11y.dashboard.chartValue \(data.target.formatted())")
    }
}

#if DEBUG
#Preview("Large values — 1.5B USD") {
    let controller = PersistenceController.preview()
    let store = FinanceStore(context: controller.container.mainContext)
    let calendar = Calendar.current
    let now = Date()
    let actual: [DashboardChartPoint] = (0..<12).map { monthsAgo in
        let date = calendar.date(byAdding: .month, value: monthsAgo - 12, to: now) ?? now
        let major = Int64(400_000_000 + 30_000_000 * monthsAgo)
        return DashboardChartPoint(date: date, amountMinor: major * 100, series: .actual)
    }
    let forecast: [DashboardChartPoint] = (0..<24).map { month in
        let date = calendar.date(byAdding: .month, value: month, to: now) ?? now
        let major = Int64(760_000_000 + 32_000_000 * month)
        return DashboardChartPoint(date: date, amountMinor: major * 100, series: .forecast)
    }
    let data = DashboardChartData(
        points: actual + forecast,
        target: Money(major: 1_500_000_000, currency: .usd)
    )
    return DashboardChartCard(data: data)
        .environment(store)
        .padding()
}
#endif
