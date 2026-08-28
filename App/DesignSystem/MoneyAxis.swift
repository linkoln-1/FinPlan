import SwiftUI
import Charts
import FinPlanCore

enum FPMoneyAxis {
    static func compactLabel(_ value: Double, code: String) -> String {
        let symbol: String
        switch code {
        case "RUB": symbol = "₽"
        case "USD": symbol = "$"
        case "EUR": symbol = "€"
        default: symbol = code
        }
        let magnitude = abs(value)
        let formatted: String
        switch magnitude {
        case 1_000_000_000...:
            formatted = trim(value / 1_000_000_000) + "B"
        case 1_000_000...:
            formatted = trim(value / 1_000_000) + "M"
        case 10_000...:
            formatted = trim(value / 1_000) + "K"
        default:
            formatted = trim(value)
        }
        return "\(formatted) \(symbol)"
    }

    private static func trim(_ value: Double) -> String {
        Decimal(value).formatted(.number.precision(.fractionLength(0...1)))
    }
}

extension View {
    func fpMoneyYAxis(currencyCode: String, hidden: Bool) -> some View {
        chartYAxis {
            if !hidden {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(verbatim: FPMoneyAxis.compactLabel(doubleValue, code: currencyCode))
                                .font(.caption2)
                        }
                    }
                }
            }
        }
    }

    func fpProjectionXAxis(spansYears: Bool) -> some View {
        chartXAxis {
            AxisMarks(values: .stride(by: .month, count: spansYears ? 6 : 1)) { _ in
                AxisGridLine()
                AxisValueLabel(format: spansYears ? .dateTime.month(.abbreviated).year(.twoDigits) : .dateTime.month(.abbreviated), centered: false)
                    .font(.caption2)
            }
        }
    }
}

enum FPProjectionDomain {
    private static let minimumVisibleMonths = 6
    private static let yearSpanThresholdDays: Double = 350
    private static let secondsPerDay: Double = 86_400

    static func clampedDomain(
        for dates: [Date],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> ClosedRange<Date> {
        let start = dates.min() ?? now
        let end = dates.max() ?? now
        let minimumEnd = calendar.date(byAdding: .month, value: minimumVisibleMonths, to: start) ?? end
        return start...max(end, minimumEnd)
    }

    static func spansYears(_ domain: ClosedRange<Date>) -> Bool {
        domain.upperBound.timeIntervalSince(domain.lowerBound) > yearSpanThresholdDays * secondsPerDay
    }
}

struct FPTargetAnnotationLabel: View {
    let titleKey: LocalizedStringKey

    var body: some View {
        Text(titleKey)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, FP.Spacing.sm)
            .padding(.vertical, FP.Spacing.xs / 2)
            .background(.background.opacity(0.85), in: Capsule())
    }
}
