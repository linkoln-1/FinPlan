import Testing
import Foundation
@testable import FinPlanCore

@Suite("LedgerEngine")
struct LedgerEngineTests {
    static let periodStart = Date(timeIntervalSince1970: 1_704_067_200)
    static let day1 = Date(timeIntervalSince1970: 1_704_067_200 + 86_400)
    static let day2 = Date(timeIntervalSince1970: 1_704_067_200 + 2 * 86_400)
    static let day3 = Date(timeIntervalSince1970: 1_704_067_200 + 3 * 86_400)
    static let periodEnd = Date(timeIntervalSince1970: 1_704_067_200 + 31 * 86_400)
    static let period = DateInterval(start: periodStart, end: periodEnd)
    static let created = Date(timeIntervalSince1970: 1_700_000_000)

    static let noRates = ManualExchangeRates()

    @Test("income $4,375 with $4,000 goal transfer: savings, not expense; free = $375")
    func goalTransferAggregation() throws {
        let checking = Account(name: "Checking", currency: .usd, type: .checking, createdAt: Self.created)
        let savings = Account(name: "Savings", currency: .usd, type: .savings, createdAt: Self.created)
        let goalID = UUID()
        let income = TransactionRecord(
            date: Self.day1, kind: .income,
            amount: Money(minor: 437_500, currency: .usd),
            destinationAccountID: checking.id,
            createdAt: Self.day1
        )
        let goalTransfer = TransactionRecord(
            date: Self.day2, kind: .transfer,
            amount: Money(minor: 400_000, currency: .usd),
            sourceAccountID: checking.id,
            destinationAccountID: savings.id,
            goalID: goalID,
            createdAt: Self.day2
        )

        let summary = try LedgerEngine.periodSummary(
            transactions: [income, goalTransfer],
            in: Self.period, currency: .usd, rates: Self.noRates
        )

        #expect(summary.income.amountMinor == 437_500)
        #expect(summary.expenses.amountMinor == 0)
        #expect(summary.savingsAllocated.amountMinor == 400_000)
        #expect(summary.freeCashFlow.amountMinor == 37_500)
    }

    @Test("transfer 40,000 RUB A→B: balances split, net worth and totals untouched")
    func transferNeutrality() throws {
        let accountA = Account(
            name: "A", currency: .rub, type: .checking,
            openingBalance: Money(major: 100_000, currency: .rub),
            createdAt: Self.created
        )
        let accountB = Account(name: "B", currency: .rub, type: .savings, createdAt: Self.created)
        let transfer = TransactionRecord(
            date: Self.day1, kind: .transfer,
            amount: Money(major: 40_000, currency: .rub),
            sourceAccountID: accountA.id,
            destinationAccountID: accountB.id,
            createdAt: Self.day1
        )

        let balanceA = try LedgerEngine.balance(of: accountA, transactions: [transfer], asOf: Self.day2)
        let balanceB = try LedgerEngine.balance(of: accountB, transactions: [transfer], asOf: Self.day2)
        #expect(balanceA == Money(major: 60_000, currency: .rub))
        #expect(balanceB == Money(major: 40_000, currency: .rub))

        let netWorth = try LedgerEngine.netWorth(
            accounts: [accountA, accountB], transactions: [transfer],
            asOf: Self.day2, in: .rub, rates: Self.noRates
        )
        #expect(netWorth == Money(major: 100_000, currency: .rub))

        let summary = try LedgerEngine.periodSummary(
            transactions: [transfer], in: Self.period, currency: .rub, rates: Self.noRates
        )
        #expect(summary.income.isZero)
        #expect(summary.expenses.isZero)
    }

    @Test("USD→RUB exchange: net worth changes only by the explicit fee; no income/expense")
    func currencyExchangeWithFee() throws {
        let usdAccount = Account(
            name: "USD", currency: .usd, type: .checking,
            openingBalance: Money(major: 4_000, currency: .usd),
            createdAt: Self.created
        )
        let rubAccount = Account(name: "RUB", currency: .rub, type: .checking, createdAt: Self.created)
        let exchange = TransactionRecord(
            date: Self.day1, kind: .currencyExchange,
            amount: Money(major: 4_000, currency: .usd),
            sourceAccountID: usdAccount.id,
            destinationAccountID: rubAccount.id,
            counterAmount: Money(minor: 33_712_800, currency: .rub),
            fee: Money(minor: 100_000, currency: .rub),
            createdAt: Self.day1
        )
        let rate = try #require(ExchangeRate(base: .usd, quote: .rub, decimalString: "84.282"))
        let rates = ManualExchangeRates(rates: [rate])
        let accounts = [usdAccount, rubAccount]

        let usdBalance = try LedgerEngine.balance(of: usdAccount, transactions: [exchange], asOf: Self.day2)
        let rubBalance = try LedgerEngine.balance(of: rubAccount, transactions: [exchange], asOf: Self.day2)
        #expect(usdBalance.isZero)
        #expect(rubBalance == Money(minor: 33_612_800, currency: .rub))

        let netWorthBefore = try LedgerEngine.netWorth(
            accounts: accounts, transactions: [], asOf: Self.day2, in: .rub, rates: rates
        )
        #expect(netWorthBefore == Money(minor: 33_712_800, currency: .rub))

        let netWorthAfter = try LedgerEngine.netWorth(
            accounts: accounts, transactions: [exchange], asOf: Self.day2, in: .rub, rates: rates
        )
        #expect(netWorthAfter == Money(minor: 33_612_800, currency: .rub))
        #expect(try netWorthBefore.subtracting(netWorthAfter) == Money(minor: 100_000, currency: .rub))

        let summary = try LedgerEngine.periodSummary(
            transactions: [exchange], in: Self.period, currency: .rub, rates: rates
        )
        #expect(summary.income.isZero)
        #expect(summary.expenses.isZero)
        #expect(summary.fees == Money(minor: 100_000, currency: .rub))
    }

    @Test("exchange fee matching neither side throws a typed error")
    func unattributableFeeThrows() {
        let usdAccount = Account(name: "USD", currency: .usd, type: .checking, createdAt: Self.created)
        let rubAccount = Account(name: "RUB", currency: .rub, type: .checking, createdAt: Self.created)
        let exchange = TransactionRecord(
            date: Self.day1, kind: .currencyExchange,
            amount: Money(major: 100, currency: .usd),
            sourceAccountID: usdAccount.id,
            destinationAccountID: rubAccount.id,
            counterAmount: Money(major: 8_400, currency: .rub),
            fee: Money(major: 1, currency: .eur),
            createdAt: Self.day1
        )
        #expect(throws: LedgerError.unattributableExchangeFee(transactionID: exchange.id)) {
            _ = try LedgerEngine.balance(of: usdAccount, transactions: [exchange], asOf: Self.day2)
        }
    }

    @Test("planned and expected transactions never move balances")
    func nonCompletedStatusesIgnored() throws {
        let account = Account(
            name: "Main", currency: .rub, type: .checking,
            openingBalance: Money(major: 1_000, currency: .rub),
            createdAt: Self.created
        )
        let statuses: [TransactionStatus] = [.planned, .expected, .skipped, .cancelled]
        let transactions = statuses.map { status in
            TransactionRecord(
                date: Self.day1, kind: .expense, status: status,
                amount: Money(major: 100, currency: .rub),
                sourceAccountID: account.id,
                createdAt: Self.day1
            )
        }

        let balance = try LedgerEngine.balance(of: account, transactions: transactions, asOf: Self.day2)
        #expect(balance == Money(major: 1_000, currency: .rub))

        let summary = try LedgerEngine.periodSummary(
            transactions: transactions, in: Self.period, currency: .rub, rates: Self.noRates
        )
        #expect(summary.expenses.isZero)
    }

    @Test("split expense feeds categoryBreakdown per split category")
    func splitCategoryBreakdown() throws {
        let account = Account(name: "Card", currency: .rub, type: .checking, createdAt: Self.created)
        let foodID = UUID()
        let homeID = UUID()
        let receipt = TransactionRecord(
            date: Self.day1, kind: .expense,
            amount: Money(major: 1_000, currency: .rub),
            sourceAccountID: account.id,
            splits: [
                TransactionSplit(categoryID: foodID, amount: Money(major: 600, currency: .rub)),
                TransactionSplit(categoryID: homeID, amount: Money(major: 400, currency: .rub)),
            ],
            createdAt: Self.day1
        )
        try receipt.validate()
        let plainFood = TransactionRecord(
            date: Self.day2, kind: .expense,
            amount: Money(major: 250, currency: .rub),
            sourceAccountID: account.id,
            categoryID: foodID,
            createdAt: Self.day2
        )
        let uncategorized = TransactionRecord(
            date: Self.day3, kind: .expense,
            amount: Money(major: 50, currency: .rub),
            sourceAccountID: account.id,
            createdAt: Self.day3
        )

        let breakdown = try LedgerEngine.categoryBreakdown(
            transactions: [receipt, plainFood, uncategorized],
            in: Self.period, currency: .rub, rates: Self.noRates
        )

        #expect(breakdown[foodID] == Money(major: 850, currency: .rub))
        #expect(breakdown[homeID] == Money(major: 400, currency: .rub))
        #expect(breakdown[UUID?.none] == Money(major: 50, currency: .rub))
    }

    @Test("credit account subtracts as a liability in net worth")
    func liabilitySubtracts() throws {
        let asset = Account(
            name: "Cash", currency: .rub, type: .cash,
            openingBalance: Money(major: 100_000, currency: .rub),
            createdAt: Self.created
        )
        let credit = Account(
            name: "Credit card", currency: .rub, type: .credit,
            openingBalance: Money(major: 30_000, currency: .rub),
            createdAt: Self.created
        )
        let netWorth = try LedgerEngine.netWorth(
            accounts: [asset, credit], transactions: [],
            asOf: Self.day1, in: .rub, rates: Self.noRates
        )
        #expect(netWorth == Money(major: 70_000, currency: .rub))
    }

    @Test("archived and excluded accounts are ignored in net worth")
    func archivedAndExcludedIgnored() throws {
        let visible = Account(
            name: "Visible", currency: .rub, type: .checking,
            openingBalance: Money(major: 5_000, currency: .rub),
            createdAt: Self.created
        )
        let archived = Account(
            name: "Old", currency: .rub, type: .checking,
            openingBalance: Money(major: 9_999, currency: .rub),
            isArchived: true,
            createdAt: Self.created
        )
        let excluded = Account(
            name: "Hidden", currency: .rub, type: .investment,
            openingBalance: Money(major: 7_777, currency: .rub),
            includedInNetWorth: false,
            createdAt: Self.created
        )
        let netWorth = try LedgerEngine.netWorth(
            accounts: [visible, archived, excluded], transactions: [],
            asOf: Self.day1, in: .rub, rates: Self.noRates
        )
        #expect(netWorth == Money(major: 5_000, currency: .rub))
    }

    @Test("missing exchange rate throws a typed error")
    func missingRateThrows() {
        let usdAccount = Account(
            name: "USD", currency: .usd, type: .checking,
            openingBalance: Money(major: 1, currency: .usd),
            createdAt: Self.created
        )
        #expect(throws: LedgerError.missingExchangeRate(base: "USD", quote: "RUB")) {
            _ = try LedgerEngine.netWorth(
                accounts: [usdAccount], transactions: [],
                asOf: Self.day1, in: .rub, rates: Self.noRates
            )
        }
    }

    @Test("balance honors asOf cutoff: later transactions excluded")
    func asOfCutoff() throws {
        let account = Account(
            name: "Main", currency: .rub, type: .checking,
            openingBalance: Money(major: 500, currency: .rub),
            createdAt: Self.created
        )
        let early = TransactionRecord(
            date: Self.day1, kind: .expense,
            amount: Money(major: 100, currency: .rub),
            sourceAccountID: account.id,
            createdAt: Self.day1
        )
        let late = TransactionRecord(
            date: Self.day3, kind: .expense,
            amount: Money(major: 200, currency: .rub),
            sourceAccountID: account.id,
            createdAt: Self.day3
        )

        #expect(try LedgerEngine.balance(of: account, transactions: [early, late], asOf: Self.day2)
            == Money(major: 400, currency: .rub))
        #expect(try LedgerEngine.balance(of: account, transactions: [early, late], asOf: Self.day1)
            == Money(major: 400, currency: .rub))
        #expect(try LedgerEngine.balance(of: account, transactions: [early, late], asOf: Self.day3)
            == Money(major: 200, currency: .rub))
    }

    @Test("adjustment adds to destination and subtracts from source")
    func adjustmentDirection() throws {
        let account = Account(
            name: "Main", currency: .rub, type: .checking,
            openingBalance: Money(major: 1_000, currency: .rub),
            createdAt: Self.created
        )
        let addCorrection = TransactionRecord(
            date: Self.day1, kind: .adjustment,
            amount: Money(major: 150, currency: .rub),
            destinationAccountID: account.id,
            createdAt: Self.day1
        )
        let subtractCorrection = TransactionRecord(
            date: Self.day2, kind: .adjustment,
            amount: Money(major: 50, currency: .rub),
            sourceAccountID: account.id,
            createdAt: Self.day2
        )
        let balance = try LedgerEngine.balance(
            of: account, transactions: [addCorrection, subtractCorrection], asOf: Self.day3
        )
        #expect(balance == Money(major: 1_100, currency: .rub))

        let summary = try LedgerEngine.periodSummary(
            transactions: [addCorrection, subtractCorrection],
            in: Self.period, currency: .rub, rates: Self.noRates
        )
        #expect(summary.income.isZero)
        #expect(summary.expenses.isZero)
    }

    @Test("expense with goalID counts as savings, not consumption")
    func goalDirectedExpenseIsSavings() throws {
        let account = Account(name: "Main", currency: .rub, type: .checking, createdAt: Self.created)
        let goalID = UUID()
        let contribution = TransactionRecord(
            date: Self.day1, kind: .expense,
            amount: Money(major: 10_000, currency: .rub),
            sourceAccountID: account.id,
            goalID: goalID,
            createdAt: Self.day1
        )
        let summary = try LedgerEngine.periodSummary(
            transactions: [contribution], in: Self.period, currency: .rub, rates: Self.noRates
        )
        #expect(summary.expenses.isZero)
        #expect(summary.savingsAllocated == Money(major: 10_000, currency: .rub))

        let breakdown = try LedgerEngine.categoryBreakdown(
            transactions: [contribution], in: Self.period, currency: .rub, rates: Self.noRates
        )
        #expect(breakdown.isEmpty)
    }

    @Test("transactions outside the interval are excluded from aggregation")
    func intervalBoundaries() throws {
        let account = Account(name: "Main", currency: .rub, type: .checking, createdAt: Self.created)
        let before = TransactionRecord(
            date: Date(timeIntervalSince1970: 1_704_067_200 - 1), kind: .income,
            amount: Money(major: 111, currency: .rub),
            destinationAccountID: account.id,
            createdAt: Self.created
        )
        let atStart = TransactionRecord(
            date: Self.periodStart, kind: .income,
            amount: Money(major: 200, currency: .rub),
            destinationAccountID: account.id,
            createdAt: Self.created
        )
        let after = TransactionRecord(
            date: Date(timeIntervalSince1970: 1_704_067_200 + 32 * 86_400), kind: .income,
            amount: Money(major: 333, currency: .rub),
            destinationAccountID: account.id,
            createdAt: Self.created
        )
        let total = try LedgerEngine.incomeTotal(
            transactions: [before, atStart, after],
            in: Self.period, currency: .rub, rates: Self.noRates
        )
        #expect(total == Money(major: 200, currency: .rub))
    }

    @Test("allocatedTotal sums reservations for one goal up to a date")
    func goalAllocationTotal() throws {
        let goalID = UUID()
        let otherGoalID = UUID()
        let accountID = UUID()
        let allocations = [
            GoalAllocation(goalID: goalID, accountID: accountID,
                           amount: Money(major: 1_000, currency: .rub), date: Self.day1),
            GoalAllocation(goalID: goalID, accountID: accountID,
                           amount: Money(major: 500, currency: .rub), date: Self.day2),
            GoalAllocation(goalID: otherGoalID, accountID: accountID,
                           amount: Money(major: 9_999, currency: .rub), date: Self.day1),
            GoalAllocation(goalID: goalID, accountID: accountID,
                           amount: Money(major: 777, currency: .rub), date: Self.day3),
        ]
        let total = try LedgerEngine.allocatedTotal(
            toGoal: goalID, allocations: allocations,
            asOf: Self.day2, in: .rub, rates: Self.noRates
        )
        #expect(total == Money(major: 1_500, currency: .rub))
    }
}
