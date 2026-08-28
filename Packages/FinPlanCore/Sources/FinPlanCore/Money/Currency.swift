import Foundation

public struct Currency: Hashable, Sendable, Codable {
    public let code: String
    public let minorUnitExponent: Int

    public init(code: String, minorUnitExponent: Int) {
        precondition(minorUnitExponent >= 0 && minorUnitExponent <= 6, "unsupported currency exponent")
        self.code = code.uppercased()
        self.minorUnitExponent = minorUnitExponent
    }

    public var minorUnitsPerMajor: Int64 {
        var result: Int64 = 1
        for _ in 0..<minorUnitExponent { result *= 10 }
        return result
    }
}

public extension Currency {
    static let rub = Currency(code: "RUB", minorUnitExponent: 2)
    static let usd = Currency(code: "USD", minorUnitExponent: 2)
    static let eur = Currency(code: "EUR", minorUnitExponent: 2)

    static func known(code: String) -> Currency {
        let upper = code.uppercased()
        let exponents: [String: Int] = [
            "RUB": 2, "USD": 2, "EUR": 2, "GBP": 2, "CHF": 2, "CNY": 2,
            "JPY": 0, "KRW": 0, "VND": 0,
            "BHD": 3, "KWD": 3, "OMR": 3,
        ]
        return Currency(code: upper, minorUnitExponent: exponents[upper] ?? 2)
    }
}
