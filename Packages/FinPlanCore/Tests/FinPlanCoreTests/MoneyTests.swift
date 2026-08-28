import Testing
import Foundation
@testable import FinPlanCore

@Suite("Money foundation")
struct MoneyTests {
    @Test("addition and subtraction are exact")
    func additionSubtraction() throws {
        let a = Money(minor: 10_025, currency: .usd)
        let b = Money(minor: 4_975, currency: .usd)

        #expect(try a.adding(b).amountMinor == 15_000)
        #expect(try a.subtracting(b).amountMinor == 5_050)
    }

    @Test("currency mismatch throws")
    func currencyMismatch() {
        let usd = Money(minor: 100, currency: .usd)
        let rub = Money(minor: 100, currency: .rub)
        #expect(throws: MoneyError.currencyMismatch("USD", "RUB")) {
            _ = try usd.adding(rub)
        }
    }

    @Test("comparison within currency")
    func comparison() throws {
        let small = Money(minor: 1, currency: .rub)
        let large = Money(minor: 2, currency: .rub)
        #expect(try small.isLess(than: large))
        #expect(try !(large.isLess(than: small)))
    }

    @Test("major-unit init respects currency exponent")
    func majorUnits() {
        #expect(Money(major: 100, currency: .rub).amountMinor == 10_000)
        #expect(Money(major: 100, currency: Currency.known(code: "JPY")).amountMinor == 100)
        #expect(Money(major: 1, currency: Currency.known(code: "BHD")).amountMinor == 1_000)
    }

    @Test("percentage share: 50% of $3,750 = $1,875 exact")
    func percentageShare() {
        let gross = Money(major: 3_750, currency: .usd)
        let personal = gross.multiplied(byNumerator: 5_000, denominator: 10_000)
        #expect(personal.amountMinor == Money(major: 1_875, currency: .usd).amountMinor)
    }

    @Test("half-away-from-zero rounding")
    func rounding() {
        #expect(Money.divideRoundingHalfAwayFromZero(5, by: 10) == 1)
        #expect(Money.divideRoundingHalfAwayFromZero(4, by: 10) == 0)
        #expect(Money.divideRoundingHalfAwayFromZero(-5, by: 10) == -1)
        #expect(Money.divideRoundingHalfAwayFromZero(-4, by: 10) == 0)
        #expect(Money.divideRoundingHalfAwayFromZero(15, by: 10) == 2)
    }

    @Test("sum of sequence")
    func sumSequence() throws {
        let values = [Money(minor: 1, currency: .rub), Money(minor: 2, currency: .rub)]
        #expect(try values.sum(in: .rub).amountMinor == 3)
        #expect(try [Money]().sum(in: .rub).amountMinor == 0)
    }
}

@Suite("Exchange rate")
struct ExchangeRateTests {
    @Test("reference conversion: $4,000 × 84.282 = 337,128.00 RUB exact")
    func referenceConversion() throws {
        let rate = try #require(ExchangeRate(base: .usd, quote: .rub, decimalString: "84.282"))
        let usd = Money(major: 4_000, currency: .usd)

        let rub = try rate.convert(usd)

        #expect(rub.amountMinor == 33_712_800)
        #expect(rub.currency == .rub)
    }

    @Test("reference conversion B: $6,250 × 84.282 = 526,762.50 RUB exact")
    func referenceConversionB() throws {
        let rate = try #require(ExchangeRate(base: .usd, quote: .rub, decimalString: "84.282"))
        let rub = try rate.convert(Money(major: 6_250, currency: .usd))
        #expect(rub.amountMinor == 52_676_250)
    }

    @Test("decimal string parsing avoids floating point")
    func decimalParsing() throws {
        let rate = try #require(ExchangeRate(base: .usd, quote: .rub, decimalString: "84.282"))
        #expect(rate.rateScaled == 84_282_000)
        #expect(rate.scale == 6)
        #expect(ExchangeRate(base: .usd, quote: .rub, decimalString: "abc") == nil)
        #expect(ExchangeRate(base: .usd, quote: .rub, decimalString: "1.2345678") == nil)
    }

    @Test("exponent shift between currencies")
    func exponentShift() throws {
        let jpy = Currency.known(code: "JPY")
        let rate = try #require(ExchangeRate(base: .usd, quote: jpy, decimalString: "150"))
        let converted = try rate.convert(Money(major: 10, currency: .usd))
        #expect(converted.amountMinor == 1_500)
    }

    @Test("wrong source currency throws")
    func wrongCurrency() throws {
        let rate = try #require(ExchangeRate(base: .usd, quote: .rub, decimalString: "84.282"))
        #expect(throws: MoneyError.self) {
            _ = try rate.convert(Money(major: 1, currency: .eur))
        }
    }

    @Test("manual provider falls back to inverted rate")
    func manualProvider() throws {
        let usdRub = try #require(ExchangeRate(base: .usd, quote: .rub, decimalString: "80"))
        let provider = ManualExchangeRates(rates: [usdRub])
        let inverse = try #require(provider.rate(from: .rub, to: .usd))
        let converted = try inverse.convert(Money(major: 80_000, currency: .rub))
        #expect(converted.amountMinor == Money(major: 1_000, currency: .usd).amountMinor)
    }
}

@Suite("Transaction invariants")
struct TransactionInvariantTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let accountA = UUID()
    let accountB = UUID()

    @Test("split totals must match transaction amount")
    func splitInvariant() throws {
        var record = TransactionRecord(
            date: now, kind: .expense,
            amount: Money(major: 12_000, currency: .rub),
            sourceAccountID: accountA,
            splits: [
                TransactionSplit(categoryID: UUID(), amount: Money(major: 7_000, currency: .rub)),
                TransactionSplit(categoryID: UUID(), amount: Money(major: 5_000, currency: .rub)),
            ],
            createdAt: now
        )
        try record.validate()

        record.splits[0].amount = Money(major: 6_999, currency: .rub)
        #expect(throws: TransactionValidationError.self) { try record.validate() }
    }

    @Test("transfer to same account rejected")
    func sameAccountTransfer() {
        let record = TransactionRecord(
            date: now, kind: .transfer,
            amount: Money(major: 100, currency: .rub),
            sourceAccountID: accountA, destinationAccountID: accountA,
            createdAt: now
        )
        #expect(throws: TransactionValidationError.sameAccountTransfer) { try record.validate() }
    }

    @Test("exchange requires counter amount in different currency")
    func exchangeInvariants() {
        let missingCounter = TransactionRecord(
            date: now, kind: .currencyExchange,
            amount: Money(major: 4_000, currency: .usd),
            sourceAccountID: accountA, destinationAccountID: accountB,
            createdAt: now
        )
        #expect(throws: TransactionValidationError.exchangeMissingCounterAmount) { try missingCounter.validate() }

        let sameCurrency = TransactionRecord(
            date: now, kind: .currencyExchange,
            amount: Money(major: 4_000, currency: .usd),
            sourceAccountID: accountA, destinationAccountID: accountB,
            counterAmount: Money(major: 4_000, currency: .usd),
            createdAt: now
        )
        #expect(throws: TransactionValidationError.exchangeSameCurrency) { try sameCurrency.validate() }
    }

    @Test("non-positive amounts rejected")
    func nonPositive() {
        let record = TransactionRecord(
            date: now, kind: .expense,
            amount: .zero(.rub),
            sourceAccountID: accountA,
            createdAt: now
        )
        #expect(throws: TransactionValidationError.nonPositiveAmount) { try record.validate() }
    }

    @Test("only completed status affects actual balance")
    func statusSemantics() {
        #expect(TransactionStatus.completed.affectsActualBalance)
        for status in [TransactionStatus.planned, .expected, .skipped, .cancelled] {
            #expect(!status.affectsActualBalance)
        }
    }
}
