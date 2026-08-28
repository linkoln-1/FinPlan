import Foundation

enum WidgetMoneyFormat {
    private static let millionThresholdMajor = Decimal(1_000_000)
    private static let compactThresholdMajor = Decimal(100_000)
    private static let majorPerMillion = Decimal(1_000_000)
    private static let majorPerThousand = Decimal(1_000)

    static func majorUnits(minor: Int64, exponent: Int) -> Decimal {
        let magnitude = Decimal(sign: .plus, exponent: -exponent, significand: Decimal(minor.magnitude))
        return minor < 0 ? -magnitude : magnitude
    }

    static func full(minor: Int64, code: String, exponent: Int) -> String {
        majorUnits(minor: minor, exponent: exponent)
            .formatted(.currency(code: code).presentation(.narrow).precision(.fractionLength(0)))
    }

    static func compact(minor: Int64, code: String, exponent: Int) -> String {
        let value = majorUnits(minor: minor, exponent: exponent)
        let magnitude = abs(value)
        if magnitude >= millionThresholdMajor {
            let scaled = value / majorPerMillion
            let number = scaled.formatted(.number.precision(.fractionLength(0...2)))
            return "\(number)M \(currencySymbol(code: code))"
        }
        if magnitude >= compactThresholdMajor {
            let scaled = value / majorPerThousand
            let number = scaled.formatted(.number.precision(.fractionLength(0...1)))
            return "\(number)K \(currencySymbol(code: code))"
        }
        return full(minor: minor, code: code, exponent: exponent)
    }

    static func currencySymbol(code: String) -> String {
        let zero = Decimal(0).formatted(.currency(code: code).presentation(.narrow).precision(.fractionLength(0)))
        let symbol = zero.filter { !$0.isNumber && !$0.isWhitespace }
        return symbol.isEmpty ? code : symbol
    }
}
