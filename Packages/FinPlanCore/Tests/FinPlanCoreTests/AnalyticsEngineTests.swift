import Testing
import Foundation
@testable import FinPlanCore

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

@Suite("AnalyticsEngine")
struct AnalyticsEngineTests {
    static let jan1 = Date(timeIntervalSince1970: 1_704_067_200)
    static let feb1 = Date(timeIntervalSince1970: 1_706_745_600)
    static let mar1 = Date(timeIntervalSince1970: 1_709_251_200)
    static let apr1 = Date(timeIntervalSince1970: 1_711_929_600)
    static let created = Date(timeIntervalSince1970: 1_700_000_000)

    static let january = DateInterval(start: jan1, end: feb1)
    static let march = DateInterval(start: mar1, end: apr1)

    static let noRates = ManualExchangeRates()

    static func day(_ base: Date, plus days: Int) -> Date {
        base.addingTimeInterval(TimeInterval(days) * 86_400)
    }

    static func usd(_ minor: Int64) -> Money { Money(minor: minor, currency: .usd) }
    static func rub(_ major: Int64) -> Money { Money(major: major, currency: .rub) }

    @Test("savings rate 4000/4375 USD is exactly 9143 bps (half-away)")
    func savingsRateExactRounding() throws {
        let checking = Account(name: "Checking", currency: .usd, type: .checking, createdAt: Self.created)
        let savings = Account(name: "Savings", currency: .usd, type: .savings, createdAt: Self.created)
        let income = TransactionRecord(
            date: Self.day(Self.jan1, plus: 4), kind: .income,
            amount: Self.usd(437_500),
            destinationAccountID: checking.id,
            createdAt: Self.created
        )
        let goalTransfer = TransactionRecord(
            date: Self.day(Self.jan1, plus: 9), kind: .transfer,
            amount: Self.usd(400_000),
            sourceAccountID: checking.id,
            destinationAccountID: savings.id,
            goalID: UUID(),
            createdAt: Self.created
        )

        let summary = try AnalyticsEngine.monthlySummary(
            interval: Self.january,
            transactions: [income, goalTransfer],
            accounts: [checking, savings],
            rates: Self.noRates,
            baseCurrency: .usd
        )

        #expect(summary.monthStart == Self.jan1)
        #expect(summary.income == Self.usd(437_500))
        #expect(summary.savingsAllocated == Self.usd(400_000))
        #expect(summary.savingsRateBasisPoints == 9_143)
    }

    @Test("savings rate is nil when the month has no income")
    func savingsRateNilWithoutIncome() throws {
        let account = Account(name: "Cash", currency: .rub, type: .cash, createdAt: Self.created)
        let expense = TransactionRecord(
            date: Self.day(Self.jan1, plus: 3), kind: .expense,
            amount: Self.rub(5_000),
            sourceAccountID: account.id,
            createdAt: Self.created
        )

        let summary = try AnalyticsEngine.monthlySummary(
            interval: Self.january,
            transactions: [expense],
            accounts: [account],
            rates: Self.noRates,
            baseCurrency: .rub
        )

        #expect(summary.savingsRateBasisPoints == nil)
        #expect(summary.expenses == Self.rub(5_000))
        #expect(summary.netCashFlow == Self.rub(-5_000))
    }

    @Test("plain transfers and exchanges never count as income or expense")
    func transfersIgnoredInFlows() throws {
        let checking = Account(name: "Checking", currency: .rub, type: .checking, createdAt: Self.created)
        let savings = Account(name: "Savings", currency: .rub, type: .savings, createdAt: Self.created)
        let income = TransactionRecord(
            date: Self.day(Self.jan1, plus: 1), kind: .income,
            amount: Self.rub(100_000),
            destinationAccountID: checking.id,
            createdAt: Self.created
        )
        let expense = TransactionRecord(
            date: Self.day(Self.jan1, plus: 2), kind: .expense,
            amount: Self.rub(30_000),
            sourceAccountID: checking.id,
            createdAt: Self.created
        )
        let transfer = TransactionRecord(
            date: Self.day(Self.jan1, plus: 3), kind: .transfer,
            amount: Self.rub(500_000),
            sourceAccountID: checking.id,
            destinationAccountID: savings.id,
            createdAt: Self.created
        )

        let summary = try AnalyticsEngine.monthlySummary(
            interval: Self.january,
            transactions: [income, expense, transfer],
            accounts: [checking, savings],
            rates: Self.noRates,
            baseCurrency: .rub
        )

        #expect(summary.income == Self.rub(100_000))
        #expect(summary.expenses == Self.rub(30_000))
        #expect(summary.savingsAllocated == Self.rub(0))
        #expect(summary.netCashFlow == Self.rub(70_000))
    }

    @Test("month membership is half-open: boundary transaction belongs to the later month")
    func halfOpenMonthBoundary() throws {
        let account = Account(name: "Cash", currency: .rub, type: .cash, createdAt: Self.created)
        let atStart = TransactionRecord(
            date: Self.jan1, kind: .income,
            amount: Self.rub(1_000),
            destinationAccountID: account.id,
            createdAt: Self.created
        )
        let atEnd = TransactionRecord(
            date: Self.feb1, kind: .income,
            amount: Self.rub(2_000),
            destinationAccountID: account.id,
            createdAt: Self.created
        )

        let summary = try AnalyticsEngine.monthlySummary(
            interval: Self.january,
            transactions: [atStart, atEnd],
            accounts: [account],
            rates: Self.noRates,
            baseCurrency: .rub
        )

        #expect(summary.income == Self.rub(1_000))
    }

    @Test("trends returns N summaries keyed by month start, oldest first")
    func trendsThreeMonths() throws {
        let account = Account(name: "Checking", currency: .rub, type: .checking, createdAt: Self.created)
        let incomes = [
            (Self.day(Self.jan1, plus: 14), Self.rub(1_000)),
            (Self.day(Self.feb1, plus: 14), Self.rub(2_000)),
            (Self.day(Self.mar1, plus: 14), Self.rub(3_000)),
        ].map { date, amount in
            TransactionRecord(
                date: date, kind: .income, amount: amount,
                destinationAccountID: account.id, createdAt: Self.created
            )
        }

        let trends = try AnalyticsEngine.trends(
            monthsBack: 3,
            endingAt: Self.day(Self.mar1, plus: 19),
            calendar: utcCalendar,
            transactions: incomes,
            accounts: [account],
            rates: Self.noRates,
            baseCurrency: .rub
        )

        #expect(trends.count == 3)
        #expect(trends.map(\.monthStart) == [Self.jan1, Self.feb1, Self.mar1])
        #expect(trends.map(\.income) == [Self.rub(1_000), Self.rub(2_000), Self.rub(3_000)])
    }

    @Test("net worth history is flat across 3 months despite a mid-month transfer")
    func netWorthHistoryFlatAcrossTransfer() throws {
        let accountA = Account(
            name: "A", currency: .rub, type: .checking,
            openingBalance: Self.rub(100_000), createdAt: Self.created
        )
        let accountB = Account(name: "B", currency: .rub, type: .savings, createdAt: Self.created)
        let transfer = TransactionRecord(
            date: Self.day(Self.feb1, plus: 13), kind: .transfer,
            amount: Self.rub(40_000),
            sourceAccountID: accountA.id,
            destinationAccountID: accountB.id,
            createdAt: Self.created
        )
        let monthEnds = [
            Self.feb1.addingTimeInterval(-1),
            Self.mar1.addingTimeInterval(-1),
            Self.apr1.addingTimeInterval(-1),
        ]

        let history = try AnalyticsEngine.netWorthHistory(
            monthEnds: monthEnds,
            accounts: [accountA, accountB],
            transactions: [transfer],
            rates: Self.noRates,
            baseCurrency: .rub
        )

        #expect(history.map(\.date) == monthEnds)
        #expect(history.map(\.netWorth) == [Self.rub(100_000), Self.rub(100_000), Self.rub(100_000)])
    }

    static let food = TransactionCategory(name: "Food", symbolName: "fork.knife", isEssential: true)
    static let shopping = TransactionCategory(name: "Shopping", symbolName: "bag.fill")

    private static func essentialExpense(_ amount: Money, on date: Date, from accountID: UUID) -> TransactionRecord {
        TransactionRecord(
            date: date, kind: .expense, amount: amount,
            sourceAccountID: accountID, categoryID: food.id, createdAt: created
        )
    }

    @Test("runway is nil with only 1 fully covered month — never invents data")
    func runwayNilWithOneMonthHistory() throws {
        let account = Account(name: "Cash", currency: .rub, type: .cash, createdAt: Self.created)
        let expense = Self.essentialExpense(Self.rub(40_000), on: Self.feb1, from: account.id)

        let runway = try AnalyticsEngine.runway(
            liquidFree: Self.rub(500_000),
            transactions: [expense],
            categories: [Self.food, Self.shopping],
            asOf: Self.day(Self.mar1, plus: 19),
            calendar: utcCalendar,
            rates: Self.noRates
        )

        #expect(runway == nil)
    }

    @Test("runway: 296,000 ₽ against 40,000 ₽/month essential average is exactly 74 tenths")
    func runwayExactTenths() throws {
        let account = Account(name: "Cash", currency: .rub, type: .cash, createdAt: Self.created)
        let transactions = [
            TransactionRecord(
                date: Self.jan1, kind: .income, amount: Self.rub(300_000),
                destinationAccountID: account.id, createdAt: Self.created
            ),
            Self.essentialExpense(Self.rub(30_000), on: Self.day(Self.jan1, plus: 19), from: account.id),
            Self.essentialExpense(Self.rub(50_000), on: Self.day(Self.feb1, plus: 9), from: account.id),
            TransactionRecord(
                date: Self.day(Self.feb1, plus: 11), kind: .expense, amount: Self.rub(20_000),
                sourceAccountID: account.id, categoryID: Self.shopping.id, createdAt: Self.created
            ),
        ]

        let exact = try AnalyticsEngine.runway(
            liquidFree: Self.rub(296_000),
            transactions: transactions,
            categories: [Self.food, Self.shopping],
            asOf: Self.day(Self.mar1, plus: 19),
            calendar: utcCalendar,
            rates: Self.noRates
        )
        #expect(exact == 74)

        let halfway = try AnalyticsEngine.runway(
            liquidFree: Self.rub(294_000),
            transactions: transactions,
            categories: [Self.food, Self.shopping],
            asOf: Self.day(Self.mar1, plus: 19),
            calendar: utcCalendar,
            rates: Self.noRates
        )
        #expect(halfway == 74)

        let empty = try AnalyticsEngine.runway(
            liquidFree: Self.rub(0),
            transactions: transactions,
            categories: [Self.food, Self.shopping],
            asOf: Self.day(Self.mar1, plus: 19),
            calendar: utcCalendar,
            rates: Self.noRates
        )
        #expect(empty == 0)
    }

    @Test("runway is nil when covered months have no essential spending")
    func runwayNilWithoutEssentialSpend() throws {
        let account = Account(name: "Cash", currency: .rub, type: .cash, createdAt: Self.created)
        let transactions = [
            TransactionRecord(
                date: Self.jan1, kind: .income, amount: Self.rub(300_000),
                destinationAccountID: account.id, createdAt: Self.created
            ),
            TransactionRecord(
                date: Self.day(Self.feb1, plus: 5), kind: .expense, amount: Self.rub(20_000),
                sourceAccountID: account.id, categoryID: Self.shopping.id, createdAt: Self.created
            ),
        ]

        let runway = try AnalyticsEngine.runway(
            liquidFree: Self.rub(500_000),
            transactions: transactions,
            categories: [Self.food, Self.shopping],
            asOf: Self.day(Self.mar1, plus: 19),
            calendar: utcCalendar,
            rates: Self.noRates
        )

        #expect(runway == nil)
    }

    @Test("monthly close: totals, net worth change, biggest category, plan variances")
    func monthlyCloseSnapshot() throws {
        let checking = Account(
            name: "Checking", currency: .usd, type: .checking,
            openingBalance: Self.usd(100_000), createdAt: Self.created
        )
        let savings = Account(name: "Savings", currency: .usd, type: .savings, createdAt: Self.created)
        let foodID = UUID()
        let funID = UUID()
        let transactions = [
            TransactionRecord(
                date: Self.day(Self.feb1, plus: 4), kind: .income, amount: Self.usd(50_000),
                destinationAccountID: checking.id, createdAt: Self.created
            ),
            TransactionRecord(
                date: Self.day(Self.mar1, plus: 4), kind: .income, amount: Self.usd(437_500),
                destinationAccountID: checking.id, createdAt: Self.created
            ),
            TransactionRecord(
                date: Self.day(Self.mar1, plus: 9), kind: .expense, amount: Self.usd(20_000),
                sourceAccountID: checking.id, categoryID: foodID, createdAt: Self.created
            ),
            TransactionRecord(
                date: Self.day(Self.mar1, plus: 11), kind: .expense, amount: Self.usd(5_000),
                sourceAccountID: checking.id, categoryID: funID, createdAt: Self.created
            ),
            TransactionRecord(
                date: Self.day(Self.mar1, plus: 14), kind: .transfer, amount: Self.usd(400_000),
                sourceAccountID: checking.id, destinationAccountID: savings.id,
                goalID: UUID(), createdAt: Self.created
            ),
        ]

        let close = try AnalyticsEngine.monthlyClose(
            month: Self.march,
            transactions: transactions,
            accounts: [checking, savings],
            rates: Self.noRates,
            baseCurrency: .usd,
            plannedIncome: Self.usd(450_000),
            plannedExpenses: Self.usd(20_000)
        )

        #expect(close.monthStart == Self.mar1)
        #expect(close.monthEnd == Self.apr1)
        #expect(close.income == Self.usd(437_500))
        #expect(close.expenses == Self.usd(25_000))
        #expect(close.savingsAllocated == Self.usd(400_000))
        #expect(close.fees == Self.usd(0))
        #expect(close.netCashFlow == Self.usd(412_500))
        #expect(close.savingsRateBasisPoints == 9_143)
        #expect(close.netWorthStart == Self.usd(150_000))
        #expect(close.netWorthEnd == Self.usd(562_500))
        #expect(close.netWorthChange == Self.usd(412_500))
        #expect(close.biggestExpenseCategoryID == foodID)
        #expect(close.incomeVariance == Self.usd(-12_500))
        #expect(close.expenseVariance == Self.usd(5_000))
    }

    @Test("monthly close survives a Codable round-trip unchanged")
    func monthlyCloseCodableRoundTrip() throws {
        let close = MonthlyClose(
            monthStart: Self.mar1,
            monthEnd: Self.apr1,
            income: Self.usd(437_500),
            expenses: Self.usd(25_000),
            savingsAllocated: Self.usd(400_000),
            fees: Self.usd(150),
            netCashFlow: Self.usd(412_500),
            savingsRateBasisPoints: 9_143,
            netWorthStart: Self.usd(150_000),
            netWorthEnd: Self.usd(562_500),
            netWorthChange: Self.usd(412_500),
            biggestExpenseCategoryID: UUID(),
            plannedIncome: Self.usd(450_000),
            plannedExpenses: Self.usd(20_000),
            incomeVariance: Self.usd(-12_500),
            expenseVariance: Self.usd(5_000)
        )

        let data = try JSONEncoder().encode(close)
        let decoded = try JSONDecoder().decode(MonthlyClose.self, from: data)

        #expect(decoded == close)
    }
}
