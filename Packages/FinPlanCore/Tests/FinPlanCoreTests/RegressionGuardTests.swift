import Testing
import Foundation
@testable import FinPlanCore

@Suite("Regression guards")
struct RegressionGuardTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let accountID = UUID()

    @Test("period membership is half-open: boundary transaction counted once")
    func halfOpenPeriods() throws {
        let boundary = Date(timeIntervalSince1970: 1_706_745_600)
        let account = Account(id: accountID, name: "A", currency: .rub, type: .checking, createdAt: now)
        let expense = TransactionRecord(
            date: boundary, kind: .expense,
            amount: Money(major: 500, currency: .rub),
            sourceAccountID: accountID, createdAt: now
        )
        _ = account
        let january = DateInterval(start: boundary.addingTimeInterval(-86_400 * 31), end: boundary)
        let february = DateInterval(start: boundary, end: boundary.addingTimeInterval(86_400 * 29))
        let rates = ManualExchangeRates()
        let earlier = try LedgerEngine.periodSummary(
            transactions: [expense], in: january, currency: .rub, rates: rates)
        let later = try LedgerEngine.periodSummary(
            transactions: [expense], in: february, currency: .rub, rates: rates)
        #expect(earlier.expenses.isZero)
        #expect(later.expenses.amountMinor == Money(major: 500, currency: .rub).amountMinor)
    }

    @Test("goal-tagged expense is savings, not budget consumption")
    func goalTaggedExpenseExcludedFromBudget() throws {
        let categoryID = UUID()
        let budget = Budget(categoryID: categoryID, amount: Money(major: 50_000, currency: .rub))
        let record = TransactionRecord(
            date: now, kind: .expense,
            amount: Money(major: 40_000, currency: .rub),
            sourceAccountID: accountID, categoryID: categoryID, goalID: UUID(),
            createdAt: now
        )
        let period = DateInterval(start: now.addingTimeInterval(-86_400), duration: 86_400 * 30)
        let spent = try BudgetEngine.completedSpending(for: budget, in: [record], during: period)
        #expect(spent.isZero)
    }

    @Test("mixed-currency splits rejected by validation")
    func splitCurrencyMismatch() {
        let record = TransactionRecord(
            date: now, kind: .expense,
            amount: Money(major: 100, currency: .usd),
            sourceAccountID: accountID,
            splits: [
                TransactionSplit(categoryID: UUID(), amount: Money(major: 50, currency: .usd)),
                TransactionSplit(categoryID: UUID(), amount: Money(major: 50, currency: .eur)),
            ],
            createdAt: now
        )
        #expect(throws: TransactionValidationError.splitCurrencyMismatch) { try record.validate() }
    }

    @Test("periodSummary rejects unattributable exchange fee like balance()")
    func periodSummaryFeeConsistency() throws {
        let rubID = UUID()
        let exchange = TransactionRecord(
            date: now, kind: .currencyExchange,
            amount: Money(major: 100, currency: .usd),
            sourceAccountID: accountID, destinationAccountID: rubID,
            counterAmount: Money(major: 8_000, currency: .rub),
            fee: Money(major: 5, currency: .eur),
            createdAt: now
        )
        let rate = try #require(ExchangeRate(base: .usd, quote: .rub, decimalString: "80"))
        let interval = DateInterval(start: now.addingTimeInterval(-1), duration: 60)
        #expect(throws: LedgerError.self) {
            _ = try LedgerEngine.periodSummary(
                transactions: [exchange], in: interval, currency: .rub,
                rates: ManualExchangeRates(rates: [rate]))
        }
    }

    @Test("rate parser rejects signs and negative zero trick")
    func parserRejectsSigns() {
        #expect(ExchangeRate(base: .usd, quote: .rub, decimalString: "-0.5") == nil)
        #expect(ExchangeRate(base: .usd, quote: .rub, decimalString: "-1") == nil)
        #expect(ExchangeRate(base: .usd, quote: .rub, decimalString: "+1") == nil)
        #expect(ExchangeRate(base: .usd, quote: .rub, decimalString: "0") == nil)
        #expect(ExchangeRate(base: .usd, quote: .rub, decimalString: "") == nil)
    }

    @Test("rate parser returns nil on overflow instead of trapping")
    func parserOverflowSafe() {
        #expect(ExchangeRate(base: .usd, quote: .rub, decimalString: "10000000000000.0") == nil)
        #expect(ExchangeRate(base: .usd, quote: .rub, decimalString: String(repeating: "9", count: 30)) == nil)
    }

    @Test("conversion overflow throws MoneyError.overflow, never traps")
    func conversionOverflowThrows() throws {
        let rate = ExchangeRate(base: .usd, quote: .rub, rateScaled: 1_000_000_000, scale: 0)
        #expect(throws: MoneyError.overflow) {
            _ = try rate.convert(Money(minor: Int64.max / 10, currency: .usd))
        }
    }

    @Test("requiredMonthlyContribution overflow throws typed error")
    func requiredContributionOverflowThrows() {
        #expect(throws: ProjectionError.amountOverflow) {
            _ = try ProjectionEngine.requiredMonthlyContribution(
                startingAmount: Money(minor: Int64.min + 1, currency: .rub),
                target: Money(minor: Int64.max, currency: .rub),
                inCycles: 1
            )
        }
    }
}
