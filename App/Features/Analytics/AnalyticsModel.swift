import Foundation
import Observation
import FinPlanCore

enum AnalyticsPeriod: String, CaseIterable, Identifiable, Hashable, Sendable {
    case currentMonth
    case threeMonths
    case sixMonths
    case twelveMonths
    case all

    var id: String { rawValue }

    func monthsBack(earliestFact: Date?, now: Date, calendar: Calendar) -> Int {
        switch self {
        case .currentMonth: return 1
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .twelveMonths: return 12
        case .all:
            guard
                let earliestFact,
                let earliestMonth = calendar.dateInterval(of: .month, for: earliestFact)?.start,
                let currentMonth = calendar.dateInterval(of: .month, for: now)?.start,
                let months = calendar.dateComponents([.month], from: earliestMonth, to: currentMonth).month
            else { return 1 }
            return max(1, months + 1)
        }
    }
}

struct AnalyticsCategorySlice: Identifiable, Hashable, Sendable {
    let id: UUID?
    let name: String?
    let symbolName: String
    let amount: Money
}

struct AnalyticsTagSlice: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let amount: Money
}

struct AnalyticsBudgetRow: Identifiable, Hashable, Sendable {
    var id: UUID { budget.id }
    let budget: Budget
    let categoryName: String?
    let categorySymbol: String
    let status: BudgetStatus
    let period: DateInterval
}

struct AnalyticsCloseInfo: Hashable, Sendable {
    let close: MonthlyClose
    let biggestCategoryName: String?
    let biggestCategorySymbol: String?
}

struct AnalyticsSnapshot: Sendable {
    let period: AnalyticsPeriod
    let interval: DateInterval
    let currentMonthStart: Date
    let summary: MonthlySummary
    let trends: [MonthlySummary]
    let categorySlices: [AnalyticsCategorySlice]
    let tagSlices: [AnalyticsTagSlice]
    let netWorthPoints: [NetWorthPoint]
    let budgetRows: [AnalyticsBudgetRow]
    let budgetIssue: String?
    let runwayTenths: Int?
    let monthlyClose: AnalyticsCloseInfo?
    let insights: [Insight]
    let achievements: [Achievement]
    let hasFacts: Bool
}

enum AnalyticsFormat {
    static func percent(basisPoints: Int) -> String {
        (Decimal(basisPoints) / Decimal(10_000))
            .formatted(.percent.precision(.fractionLength(0...1)))
    }

    static func monthsTenths(_ tenths: Int) -> String {
        (Decimal(tenths) / Decimal(10))
            .formatted(.number.precision(.fractionLength(0...1)))
    }

    static func share(partMinor: Int64, totalMinor: Int64) -> String? {
        guard totalMinor > 0 else { return nil }
        return (Decimal(partMinor) / Decimal(totalMinor))
            .formatted(.percent.precision(.fractionLength(0...1)))
    }

    static func amountEditText(_ money: Money) -> String {
        (Decimal(money.amountMinor) / pow(10, money.currency.minorUnitExponent))
            .formatted(.number.grouping(.never)
                .precision(.fractionLength(0...money.currency.minorUnitExponent)))
    }
}

@MainActor
@Observable
final class AnalyticsModel {
    var period: AnalyticsPeriod = .sixMonths
    private(set) var snapshot: AnalyticsSnapshot?
    private(set) var computeError: String?

    private struct CacheKey: Hashable {
        let period: AnalyticsPeriod
        let dataHash: Int
    }

    private var cache: [CacheKey: AnalyticsSnapshot] = [:]
    private var cachedDataHash: Int?

    static func dataFingerprint(of store: FinanceStore) -> Int {
        var hasher = Hasher()
        hasher.combine(store.transactions)
        hasher.combine(store.accounts)
        hasher.combine(store.categories)
        hasher.combine(store.tags)
        hasher.combine(store.budgets)
        hasher.combine(store.goals)
        hasher.combine(store.allocations)
        hasher.combine(store.expectedEvents)
        hasher.combine(store.baseCurrency)
        hasher.combine(store.planningRates)
        return hasher.finalize()
    }

    func recompute(store: FinanceStore, now: Date = Date(), calendar: Calendar = .current) {
        let dataHash = Self.dataFingerprint(of: store)
        if cachedDataHash != dataHash {
            cache.removeAll()
            cachedDataHash = dataHash
        }
        let key = CacheKey(period: period, dataHash: dataHash)
        if let hit = cache[key] {
            snapshot = hit
            computeError = nil
            return
        }
        do {
            let built = try Self.build(store: store, period: period, now: now, calendar: calendar)
            cache[key] = built
            snapshot = built
            computeError = nil
        } catch {
            computeError = error.localizedDescription
        }
    }

    private static func build(
        store: FinanceStore,
        period: AnalyticsPeriod,
        now: Date,
        calendar: Calendar
    ) throws -> AnalyticsSnapshot {
        let base = store.baseCurrency
        let rates = store.planningRates
        let transactions = store.transactions
        let accounts = store.accounts

        guard let currentMonth = calendar.dateInterval(of: .month, for: now) else {
            throw AnalyticsError.calendarComputationFailed
        }

        let facts = transactions.filter { $0.status.affectsActualBalance }
        let earliestFact = facts.map(\.date).min()
        let monthsBack = period.monthsBack(earliestFact: earliestFact, now: now, calendar: calendar)

        let trends = try AnalyticsEngine.trends(
            monthsBack: monthsBack,
            endingAt: now,
            calendar: calendar,
            transactions: transactions,
            accounts: accounts,
            rates: rates,
            baseCurrency: base
        )

        let interval = DateInterval(
            start: trends.first?.monthStart ?? currentMonth.start,
            end: currentMonth.end
        )

        let summary = try AnalyticsEngine.monthlySummary(
            interval: interval,
            transactions: transactions,
            accounts: accounts,
            rates: rates,
            baseCurrency: base
        )

        let categoriesByID = Dictionary(uniqueKeysWithValues: store.categories.map { ($0.id, $0) })

        let breakdown = try LedgerEngine.categoryBreakdown(
            transactions: transactions,
            in: interval,
            currency: base,
            rates: rates
        )
        let categorySlices = breakdown
            .filter { $0.value.isPositive }
            .map { key, amount in
                AnalyticsCategorySlice(
                    id: key,
                    name: key.flatMap { categoriesByID[$0]?.name },
                    symbolName: key.flatMap { categoriesByID[$0]?.symbolName } ?? "questionmark.circle",
                    amount: amount
                )
            }
            .sorted { lhs, rhs in
                if lhs.amount.amountMinor != rhs.amount.amountMinor {
                    return lhs.amount.amountMinor > rhs.amount.amountMinor
                }
                return (lhs.name ?? "") < (rhs.name ?? "")
            }

        let tagSlices = try tagBreakdown(
            transactions: transactions,
            tags: store.tags,
            interval: interval,
            base: base,
            rates: rates
        )

        var monthEnds: [Date] = []
        for month in trends {
            guard let end = calendar.date(byAdding: .month, value: 1, to: month.monthStart) else {
                throw AnalyticsError.calendarComputationFailed
            }
            monthEnds.append(end)
        }
        let netWorthPoints = try AnalyticsEngine.netWorthHistory(
            monthEnds: monthEnds,
            accounts: accounts,
            transactions: transactions,
            rates: rates,
            baseCurrency: base
        )

        var budgetRows: [AnalyticsBudgetRow] = []
        var budgetIssue: String?
        for budget in store.budgets {
            let budgetPeriod: DateInterval?
            switch budget.period {
            case .monthly: budgetPeriod = currentMonth
            case .weekly: budgetPeriod = calendar.dateInterval(of: .weekOfYear, for: now)
            }
            guard let budgetPeriod else { throw AnalyticsError.calendarComputationFailed }
            do {
                let status = try BudgetEngine.status(
                    budget: budget,
                    expenses: transactions,
                    period: budgetPeriod,
                    now: now
                )
                let category = categoriesByID[budget.categoryID]
                budgetRows.append(AnalyticsBudgetRow(
                    budget: budget,
                    categoryName: category?.name,
                    categorySymbol: category?.symbolName ?? "questionmark.circle",
                    status: status,
                    period: budgetPeriod
                ))
            } catch {
                budgetIssue = error.localizedDescription
            }
        }
        budgetRows.sort { ($0.categoryName ?? "") < ($1.categoryName ?? "") }

        var liquid = Money.zero(base)
        for account in accounts
        where !account.isArchived && !account.isLiability && account.includedInSafeToSpend {
            let balance = try LedgerEngine.balance(of: account, transactions: transactions, asOf: now)
            liquid = try liquid.adding(convert(balance, to: base, rates: rates))
        }
        var allocated = Money.zero(base)
        for goal in store.goals where goal.status != .archived {
            let total = try LedgerEngine.allocatedTotal(
                toGoal: goal.id,
                allocations: store.allocations,
                asOf: now,
                in: base,
                rates: rates
            )
            allocated = try allocated.adding(total)
        }
        let liquidFree = try liquid.subtracting(allocated)
        let runwayTenths = try AnalyticsEngine.runway(
            liquidFree: liquidFree,
            transactions: transactions,
            categories: store.categories,
            asOf: now,
            calendar: calendar,
            rates: rates
        )

        var closeInfo: AnalyticsCloseInfo?
        if let previousStart = calendar.date(byAdding: .month, value: -1, to: currentMonth.start) {
            let previousMonth = DateInterval(start: previousStart, end: currentMonth.start)
            let hadFacts = facts.contains { $0.date >= previousMonth.start && $0.date < previousMonth.end }
            if hadFacts {
                let close = try AnalyticsEngine.monthlyClose(
                    month: previousMonth,
                    transactions: transactions,
                    accounts: accounts,
                    rates: rates,
                    baseCurrency: base
                )
                let category = close.biggestExpenseCategoryID.flatMap { categoriesByID[$0] }
                closeInfo = AnalyticsCloseInfo(
                    close: close,
                    biggestCategoryName: category?.name,
                    biggestCategorySymbol: category?.symbolName
                )
            }
        }

        let achievements = try AchievementsEvaluator.evaluate(
            goals: store.goals,
            allocations: store.allocations,
            transactions: transactions,
            accounts: accounts,
            baseCurrency: base,
            rates: rates,
            calendar: calendar,
            now: now
        )

        let insights = try buildInsights(
            store: store,
            now: now,
            calendar: calendar,
            currentMonth: currentMonth,
            earliestFact: earliestFact,
            budgetRows: budgetRows,
            liquid: liquid,
            base: base,
            rates: rates
        )

        return AnalyticsSnapshot(
            period: period,
            interval: interval,
            currentMonthStart: currentMonth.start,
            summary: summary,
            trends: trends,
            categorySlices: categorySlices,
            tagSlices: tagSlices,
            netWorthPoints: netWorthPoints,
            budgetRows: budgetRows,
            budgetIssue: budgetIssue,
            runwayTenths: runwayTenths,
            monthlyClose: closeInfo,
            insights: insights,
            achievements: achievements,
            hasFacts: !facts.isEmpty
        )
    }

    private static func tagBreakdown(
        transactions: [TransactionRecord],
        tags: [TransactionTag],
        interval: DateInterval,
        base: Currency,
        rates: ManualExchangeRates
    ) throws -> [AnalyticsTagSlice] {
        let tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        var totals: [UUID: Money] = [:]
        for transaction in transactions
        where transaction.kind == .expense
            && transaction.status.affectsActualBalance
            && transaction.goalID == nil
            && transaction.date >= interval.start && transaction.date < interval.end
            && !transaction.tagIDs.isEmpty {
            let amount = try convert(transaction.amount, to: base, rates: rates)
            for tagID in Set(transaction.tagIDs) where tagsByID[tagID] != nil {
                totals[tagID] = try (totals[tagID] ?? .zero(base)).adding(amount)
            }
        }
        return totals
            .compactMap { tagID, amount -> AnalyticsTagSlice? in
                guard amount.isPositive, let tag = tagsByID[tagID] else { return nil }
                return AnalyticsTagSlice(id: tagID, name: tag.name, amount: amount)
            }
            .sorted { lhs, rhs in
                if lhs.amount.amountMinor != rhs.amount.amountMinor {
                    return lhs.amount.amountMinor > rhs.amount.amountMinor
                }
                return lhs.name < rhs.name
            }
    }

    private static func buildInsights(
        store: FinanceStore,
        now: Date,
        calendar: Calendar,
        currentMonth: DateInterval,
        earliestFact: Date?,
        budgetRows: [AnalyticsBudgetRow],
        liquid: Money,
        base: Currency,
        rates: ManualExchangeRates
    ) throws -> [Insight] {
        let currentBreakdown = try LedgerEngine.categoryBreakdown(
            transactions: store.transactions,
            in: currentMonth,
            currency: base,
            rates: rates
        )
        var trailingBreakdowns: [[UUID?: Money]] = []
        if let earliestFact {
            for offset in 1...6 {
                guard
                    let start = calendar.date(byAdding: .month, value: -offset, to: currentMonth.start),
                    let end = calendar.date(byAdding: .month, value: 1, to: start)
                else { throw AnalyticsError.calendarComputationFailed }
                guard earliestFact <= start else { break }
                trailingBreakdowns.append(try LedgerEngine.categoryBreakdown(
                    transactions: store.transactions,
                    in: DateInterval(start: start, end: end),
                    currency: base,
                    rates: rates
                ))
            }
        }
        var histories: [CategorySpendingHistory] = []
        for (key, amount) in currentBreakdown {
            guard let categoryID = key, amount.isPositive else { continue }
            let trailing = trailingBreakdowns.map { $0[categoryID] ?? .zero(base) }
            histories.append(CategorySpendingHistory(
                categoryID: categoryID,
                currentMonthSpend: amount,
                trailingMonthlySpend: trailing
            ))
        }
        histories.sort { $0.categoryID.uuidString < $1.categoryID.uuidString }

        var goalSnapshots: [GoalInsightSnapshot] = []
        for goal in store.goals where goal.status == .active {
            let current = try LedgerEngine.allocatedTotal(
                toGoal: goal.id,
                allocations: store.allocations,
                asOf: now,
                in: goal.targetAmount.currency,
                rates: rates
            )
            let milestones = [Int64(2_500), 5_000, 7_500].map {
                goal.targetAmount.multiplied(byNumerator: $0, denominator: 10_000)
            }
            goalSnapshots.append(GoalInsightSnapshot(
                goalID: goal.id,
                target: goal.targetAmount,
                currentAmount: current,
                milestoneThresholds: milestones
            ))
        }

        var essentialAverage: Money?
        let essentialIDs = Set(store.categories.filter(\.isEssential).map(\.id))
        if trailingBreakdowns.count >= 2, !essentialIDs.isEmpty {
            var total = Money.zero(base)
            for monthBreakdown in trailingBreakdowns {
                for (key, amount) in monthBreakdown {
                    guard let key, essentialIDs.contains(key) else { continue }
                    total = try total.adding(amount)
                }
            }
            if total.isPositive {
                essentialAverage = total.multiplied(
                    byNumerator: 1,
                    denominator: Int64(trailingBreakdowns.count)
                )
            }
        }

        let context = InsightContext(
            now: now,
            goals: goalSnapshots,
            budgets: budgetRows.map {
                BudgetInsightSnapshot(categoryID: $0.budget.categoryID, status: $0.status)
            },
            categoryHistories: histories,
            expectedEvents: store.expectedEvents,
            liquidBalance: liquid,
            monthlyEssentialSpending: essentialAverage
        )
        return try InsightEngine.evaluate(context: context)
    }

    private static func convert(
        _ money: Money,
        to currency: Currency,
        rates: ManualExchangeRates
    ) throws -> Money {
        if money.currency == currency { return money }
        guard let rate = rates.rate(from: money.currency, to: currency) else {
            throw LedgerError.missingExchangeRate(base: money.currency.code, quote: currency.code)
        }
        return try rate.convert(money)
    }
}
