import Foundation

public struct ExchangeRate: Hashable, Sendable, Codable {
    public let base: Currency
    public let quote: Currency
    public let rateScaled: Int64
    public let scale: Int

    public init(base: Currency, quote: Currency, rateScaled: Int64, scale: Int) {
        precondition(rateScaled > 0, "exchange rate must be positive")
        precondition(scale >= 0 && scale <= 9, "unsupported rate scale")
        self.base = base
        self.quote = quote
        self.rateScaled = rateScaled
        self.scale = scale
    }

    public init?(base: Currency, quote: Currency, decimalString: String, scale: Int = 6) {
        let parts = decimalString.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count <= 2,
              !parts[0].isEmpty,
              parts[0].allSatisfy(\.isNumber),
              let whole = Int64(parts[0]) else { return nil }
        var fractionDigits = parts.count == 2 ? String(parts[1]) : ""
        guard fractionDigits.count <= scale, fractionDigits.allSatisfy(\.isNumber) else { return nil }
        while fractionDigits.count < scale { fractionDigits.append("0") }
        guard let fraction = Int64(fractionDigits.isEmpty ? "0" : fractionDigits) else { return nil }
        var power: Int64 = 1
        for _ in 0..<scale { power *= 10 }
        let (scaledWhole, multiplyOverflow) = whole.multipliedReportingOverflow(by: power)
        guard !multiplyOverflow else { return nil }
        let (rateScaled, addOverflow) = scaledWhole.addingReportingOverflow(fraction)
        guard !addOverflow, rateScaled > 0 else { return nil }
        self.init(base: base, quote: quote, rateScaled: rateScaled, scale: scale)
    }

    private var scaleDivisor: Int128 {
        var power: Int128 = 1
        for _ in 0..<scale { power *= 10 }
        return power
    }

    public func convert(_ money: Money) throws -> Money {
        guard money.currency == base else {
            throw MoneyError.currencyMismatch(money.currency.code, base.code)
        }
        var wide = Int128(money.amountMinor) * Int128(rateScaled)
        var divisor = scaleDivisor
        let exponentShift = quote.minorUnitExponent - base.minorUnitExponent
        if exponentShift > 0 {
            for _ in 0..<exponentShift { wide *= 10 }
        } else if exponentShift < 0 {
            for _ in 0..<(-exponentShift) { divisor *= 10 }
        }
        let wideMinor = Money.divideRoundingHalfAwayFromZeroWide(wide, by: divisor)
        guard let minor = Int64(exactly: wideMinor) else { throw MoneyError.overflow }
        return Money(minor: minor, currency: quote)
    }

    public var inverted: ExchangeRate? {
        var power: Int128 = 1
        for _ in 0..<(scale * 2) { power *= 10 }
        let invertedScaled = Money.divideRoundingHalfAwayFromZero(power, by: Int128(rateScaled))
        guard invertedScaled > 0 else { return nil }
        return ExchangeRate(base: quote, quote: base, rateScaled: invertedScaled, scale: scale)
    }
}

public protocol ExchangeRateProvider: Sendable {
    func rate(from base: Currency, to quote: Currency) -> ExchangeRate?
}

public struct ManualExchangeRates: ExchangeRateProvider, Sendable, Codable, Hashable {
    public var rates: [ExchangeRate]

    public init(rates: [ExchangeRate] = []) {
        self.rates = rates
    }

    public func rate(from base: Currency, to quote: Currency) -> ExchangeRate? {
        if base == quote {
            return ExchangeRate(base: base, quote: quote, rateScaled: 1, scale: 0)
        }
        if let direct = rates.first(where: { $0.base == base && $0.quote == quote }) {
            return direct
        }
        return rates.first(where: { $0.base == quote && $0.quote == base })?.inverted
    }
}
