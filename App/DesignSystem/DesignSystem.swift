import SwiftUI
import FinPlanCore

enum FP {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 16
        static let control: CGFloat = 10
    }
}

struct FPCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(FP.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: FP.Radius.card))
    }
}

enum FPStatusTint {
    static let positive = Color.green
    static let negative = Color.red
    static let attention = Color.orange
    static let neutral = Color.secondary
}

extension Money {
    func formatted(compact: Bool = false) -> String {
        let majorUnits = Decimal(amountMinor) / pow(10, currency.minorUnitExponent)
        if compact, abs(amountMinor) >= 1_000_000 * currency.minorUnitsPerMajor {
            let millions = (Decimal(amountMinor) / pow(10, currency.minorUnitExponent)) / 1_000_000
            let value = millions.formatted(.number.precision(.fractionLength(0...2)))
            return "\(value)M \(currencySymbol)"
        }
        return majorUnits.formatted(
            .currency(code: currency.code)
            .precision(.fractionLength(amountMinor % currency.minorUnitsPerMajor == 0 ? 0 : 2))
        )
    }

    private var currencySymbol: String {
        switch currency.code {
        case "RUB": return "₽"
        case "USD": return "$"
        case "EUR": return "€"
        default: return currency.code
        }
    }
}

struct MoneyText: View {
    let money: Money
    var compact: Bool = false
    @Environment(FinanceStore.self) private var store

    var body: some View {
        Text(store.hideBalances ? "••••••" : money.formatted(compact: compact))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityLabel(store.hideBalances ? String(localized: "a11y.hiddenAmount") : money.formatted())
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}
