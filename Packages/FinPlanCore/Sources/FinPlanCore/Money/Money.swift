import Foundation

public enum MoneyError: Error, Equatable, Sendable {
    case currencyMismatch(String, String)
    case overflow
}

public struct Money: Hashable, Sendable, Codable {
    public let amountMinor: Int64
    public let currency: Currency

    public init(minor: Int64, currency: Currency) {
        self.amountMinor = minor
        self.currency = currency
    }

    public init(major: Int64, currency: Currency) {
        let (minor, overflow) = major.multipliedReportingOverflow(by: currency.minorUnitsPerMajor)
        precondition(!overflow, "Money(major:) overflow: \(major) \(currency.code)")
        self.amountMinor = minor
        self.currency = currency
    }

    public static func zero(_ currency: Currency) -> Money {
        Money(minor: 0, currency: currency)
    }

    public var isZero: Bool { amountMinor == 0 }
    public var isNegative: Bool { amountMinor < 0 }
    public var isPositive: Bool { amountMinor > 0 }

    public func adding(_ other: Money) throws -> Money {
        try requireSameCurrency(other)
        let (sum, overflow) = amountMinor.addingReportingOverflow(other.amountMinor)
        guard !overflow else { throw MoneyError.overflow }
        return Money(minor: sum, currency: currency)
    }

    public func subtracting(_ other: Money) throws -> Money {
        try requireSameCurrency(other)
        let (diff, overflow) = amountMinor.subtractingReportingOverflow(other.amountMinor)
        guard !overflow else { throw MoneyError.overflow }
        return Money(minor: diff, currency: currency)
    }

    public var negated: Money { Money(minor: -amountMinor, currency: currency) }

    public func multiplied(by factor: Int64) -> Money {
        let (result, overflow) = amountMinor.multipliedReportingOverflow(by: factor)
        precondition(!overflow, "Money.multiplied(by:) overflow")
        return Money(minor: result, currency: currency)
    }

    public func multiplied(byNumerator numerator: Int64, denominator: Int64) -> Money {
        precondition(denominator > 0, "denominator must be positive")
        let wide = Int128(amountMinor) * Int128(numerator)
        return Money(minor: Self.divideRoundingHalfAwayFromZero(wide, by: Int128(denominator)), currency: currency)
    }

    public func comparing(_ other: Money) throws -> Int {
        try requireSameCurrency(other)
        if amountMinor < other.amountMinor { return -1 }
        if amountMinor > other.amountMinor { return 1 }
        return 0
    }

    public func isLess(than other: Money) throws -> Bool {
        try comparing(other) < 0
    }

    private func requireSameCurrency(_ other: Money) throws {
        guard currency == other.currency else {
            throw MoneyError.currencyMismatch(currency.code, other.currency.code)
        }
    }

    static func divideRoundingHalfAwayFromZero(_ value: Int128, by divisor: Int128) -> Int64 {
        let wide = divideRoundingHalfAwayFromZeroWide(value, by: divisor)
        guard let narrow = Int64(exactly: wide) else {
            preconditionFailure("minor-unit result exceeds Int64 range")
        }
        return narrow
    }

    static func divideRoundingHalfAwayFromZeroWide(_ value: Int128, by divisor: Int128) -> Int128 {
        precondition(divisor > 0)
        let quotient = value / divisor
        let remainder = value % divisor
        let doubledRemainder = remainder.magnitude * 2
        if doubledRemainder >= divisor.magnitude {
            return value < 0 ? quotient - 1 : quotient + 1
        }
        return quotient
    }
}

public extension Sequence where Element == Money {
    func sum(in currency: Currency) throws -> Money {
        var total = Money.zero(currency)
        for element in self { total = try total.adding(element) }
        return total
    }
}
