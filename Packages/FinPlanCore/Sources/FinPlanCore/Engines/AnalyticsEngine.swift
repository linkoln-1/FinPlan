import Foundation

public enum AnalyticsError: Error, Equatable, Sendable {
    case calendarComputationFailed
}

public struct MonthlySummary: Hashable, Sendable, Codable {
    public let monthStart: Date
    public let income: Money
    public let expenses: Money
    public let savingsAllocated: Money
    public let netCashFlow: Money
    public let savingsRateBasisPoints: Int?

    public init(
        monthStart: Date,
        income: Money,
        expenses: Money,
        savingsAllocated: Money,
        netCashFlow: Money,
        savingsRateBasisPoints: Int?
    ) {
        self.monthStart = monthStart
        self.income = income
        self.expenses = expenses
        self.savingsAllocated = savingsAllocated
        self.netCashFlow = netCashFlow
        self.savingsRateBasisPoints = savingsRateBasisPoints
    }
}

public struct NetWorthPoint: Hashable, Sendable, Codable {
    public let date: Date
    public let netWorth: Money

    public init(date: Date, netWorth: Money) {
        self.date = date
        self.netWorth = netWorth
    }
}

public struct MonthlyClose: Hashable, Sendable, Codable {
    public let monthStart: Date
    public let monthEnd: Date
    public let income: Money
    public let expenses: Money
    public let savingsAllocated: Money
    public let fees: Money
    public let netCashFlow: Money
    public let savingsRateBasisPoints: Int?
    public let netWorthStart: Money
    public let netWorthEnd: Money
    public let netWorthChange: Money
    public let biggestExpenseCategoryID: UUID?
    public let plannedIncome: Money?
    public let plannedExpenses: Money?
    public let incomeVariance: Money?
    public let expenseVariance: Money?

    public init(
        monthStart: Date,
        monthEnd: Date,
        income: Money,
        expenses: Money,
        savingsAllocated: Money,
        fees: Money,
        netCashFlow: Money,
        savingsRateBasisPoints: Int?,
        netWorthStart: Money,
        netWorthEnd: Money,
        netWorthChange: Money,
        biggestExpenseCategoryID: UUID?,
        plannedIncome: Money?,
        plannedExpenses: Money?,
        incomeVariance: Money?,
        expenseVariance: Money?
    ) {
        self.monthStart = monthStart
        self.monthEnd = monthEnd
        self.income = income
        self.expenses = expenses
        self.savingsAllocated = savingsAllocated
        self.fees = fees
        self.netCashFlow = netCashFlow
        self.savingsRateBasisPoints = savingsRateBasisPoints
        self.netWorthStart = netWorthStart
        self.netWorthEnd = netWorthEnd
        self.netWorthChange = netWorthChange
        self.biggestExpenseCategoryID = biggestExpenseCategoryID
        self.plannedIncome = plannedIncome
        self.plannedExpenses = plannedExpenses
        self.incomeVariance = incomeVariance
        self.expenseVariance = expenseVariance
    }
}

public struct AnalyticsEngine: Sendable {
    public init() {}

    public static func monthlySummary(
        interval: DateInterval,
        transactions: [TransactionRecord],
        accounts: [Account],
        rates: any ExchangeRateProvider,
        baseCurrency: Currency
    ) throws -> MonthlySummary {
        let period = try LedgerEngine.periodSummary(
            transactions: clipped(transactions, to: interval),
            in: interval,
            currency: baseCurrency,
            rates: rates
        )
        return MonthlySummary(
            monthStart: interval.start,
            income: period.income,
            expenses: period.expenses,
            savingsAllocated: period.savingsAllocated,
            netCashFlow: try period.income.subtracting(period.expenses),
            savingsRateBasisPoints: savingsRateBasisPoints(
                savingsAllocated: period.savingsAllocated,
                income: period.income
            )
        )
    }

    public static func trends(
        monthsBack: Int,
        endingAt reference: Date,
        calendar: Calendar,
        transactions: [TransactionRecord],
        accounts: [Account],
        rates: any ExchangeRateProvider,
        baseCurrency: Currency
    ) throws -> [MonthlySummary] {
        precondition(monthsBack >= 1, "monthsBack must be at least 1")
        let currentMonthStart = try monthStart(containing: reference, calendar: calendar)
        var result: [MonthlySummary] = []
        result.reserveCapacity(monthsBack)
        for offset in stride(from: monthsBack - 1, through: 0, by: -1) {
            guard
                let start = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart),
                let end = calendar.date(byAdding: .month, value: 1, to: start)
            else { throw AnalyticsError.calendarComputationFailed }
            result.append(try monthlySummary(
                interval: DateInterval(start: start, end: end),
                transactions: transactions,
                accounts: accounts,
                rates: rates,
                baseCurrency: baseCurrency
            ))
        }
        return result
    }

    public static func netWorthHistory(
        monthEnds: [Date],
        accounts: [Account],
        transactions: [TransactionRecord],
        rates: any ExchangeRateProvider,
        baseCurrency: Currency
    ) throws -> [NetWorthPoint] {
        try monthEnds.map { date in
            NetWorthPoint(
                date: date,
                netWorth: try LedgerEngine.netWorth(
                    accounts: accounts,
                    transactions: transactions,
                    asOf: date,
                    in: baseCurrency,
                    rates: rates
                )
            )
        }
    }

    public static func runway(
        liquidFree: Money,
        transactions: [TransactionRecord],
        categories: [TransactionCategory],
        monthsBack: Int = 6,
        asOf reference: Date,
        calendar: Calendar,
        rates: any ExchangeRateProvider
    ) throws -> Int? {
        precondition(monthsBack >= 2, "runway needs at least 2 candidate months")
        guard let firstFactDate = transactions
            .filter({ $0.status.affectsActualBalance })
            .map(\.date)
            .min()
        else { return nil }

        let currentMonthStart = try monthStart(containing: reference, calendar: calendar)
        var coveredStarts: [Date] = []
        for offset in 1...monthsBack {
            guard let start = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart)
            else { throw AnalyticsError.calendarComputationFailed }
            if firstFactDate <= start {
                coveredStarts.append(start)
            }
        }
        let coveredMonths = coveredStarts.count
        guard coveredMonths >= 2, let oldestStart = coveredStarts.min() else { return nil }

        let span = DateInterval(start: oldestStart, end: currentMonthStart)
        let essentialIDs = Set(categories.filter(\.isEssential).map(\.id))
        let breakdown = try LedgerEngine.categoryBreakdown(
            transactions: clipped(transactions, to: span),
            in: span,
            currency: liquidFree.currency,
            rates: rates
        )
        var totalEssential = Money.zero(liquidFree.currency)
        for (categoryID, amount) in breakdown {
            guard let categoryID, essentialIDs.contains(categoryID) else { continue }
            totalEssential = try totalEssential.adding(amount)
        }
        guard totalEssential.isPositive else { return nil }
        guard liquidFree.isPositive else { return 0 }

        let numerator = Int128(liquidFree.amountMinor) * 10 * Int128(coveredMonths)
        let tenths = Money.divideRoundingHalfAwayFromZero(
            numerator,
            by: Int128(totalEssential.amountMinor)
        )
        return Int(tenths)
    }

    public static func monthlyClose(
        month: DateInterval,
        transactions: [TransactionRecord],
        accounts: [Account],
        rates: any ExchangeRateProvider,
        baseCurrency: Currency,
        plannedIncome: Money? = nil,
        plannedExpenses: Money? = nil
    ) throws -> MonthlyClose {
        let inMonth = clipped(transactions, to: month)
        let period = try LedgerEngine.periodSummary(
            transactions: inMonth,
            in: month,
            currency: baseCurrency,
            rates: rates
        )

        let netWorthStart = try LedgerEngine.netWorth(
            accounts: accounts,
            transactions: transactions.filter { $0.date < month.start },
            asOf: month.start,
            in: baseCurrency,
            rates: rates
        )
        let netWorthEnd = try LedgerEngine.netWorth(
            accounts: accounts,
            transactions: transactions.filter { $0.date < month.end },
            asOf: month.end,
            in: baseCurrency,
            rates: rates
        )

        let breakdown = try LedgerEngine.categoryBreakdown(
            transactions: inMonth,
            in: month,
            currency: baseCurrency,
            rates: rates
        )

        return MonthlyClose(
            monthStart: month.start,
            monthEnd: month.end,
            income: period.income,
            expenses: period.expenses,
            savingsAllocated: period.savingsAllocated,
            fees: period.fees,
            netCashFlow: try period.income.subtracting(period.expenses),
            savingsRateBasisPoints: savingsRateBasisPoints(
                savingsAllocated: period.savingsAllocated,
                income: period.income
            ),
            netWorthStart: netWorthStart,
            netWorthEnd: netWorthEnd,
            netWorthChange: try netWorthEnd.subtracting(netWorthStart),
            biggestExpenseCategoryID: biggestCategory(in: breakdown),
            plannedIncome: plannedIncome,
            plannedExpenses: plannedExpenses,
            incomeVariance: try plannedIncome.map { try period.income.subtracting($0) },
            expenseVariance: try plannedExpenses.map { try period.expenses.subtracting($0) }
        )
    }

    private static func clipped(
        _ transactions: [TransactionRecord],
        to interval: DateInterval
    ) -> [TransactionRecord] {
        transactions.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    private static func savingsRateBasisPoints(savingsAllocated: Money, income: Money) -> Int? {
        guard income.isPositive else { return nil }
        let scaled = Int128(savingsAllocated.amountMinor) * 10_000
        return Int(Money.divideRoundingHalfAwayFromZero(scaled, by: Int128(income.amountMinor)))
    }

    private static func biggestCategory(in breakdown: [UUID?: Money]) -> UUID? {
        breakdown
            .compactMap { key, value in key.map { (id: $0, minor: value.amountMinor) } }
            .filter { $0.minor > 0 }
            .max { lhs, rhs in
                if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
                return lhs.id.uuidString > rhs.id.uuidString
            }?
            .id
    }

    private static func monthStart(containing date: Date, calendar: Calendar) throws -> Date {
        guard let interval = calendar.dateInterval(of: .month, for: date) else {
            throw AnalyticsError.calendarComputationFailed
        }
        return interval.start
    }
}
