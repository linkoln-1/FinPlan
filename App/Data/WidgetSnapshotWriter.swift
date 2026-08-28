import Foundation
import FinPlanCore
#if canImport(WidgetKit)
import WidgetKit
#endif

struct WidgetSnapshot: Codable, Sendable {
    let primaryGoalTitle: String?
    let fundedMinor: Int64
    let targetMinor: Int64
    let currencyCode: String
    let currencyExponent: Int
    let percentBasisPoints: Int
    let safeToSpendMinor: Int64
    let monthIncomeMinor: Int64
    let monthExpensesMinor: Int64
    let monthSavedMinor: Int64
    let generatedAt: Date
}

@MainActor
enum WidgetSnapshotWriter {
    static let appGroupIdentifier = "group.com.alinashkhoev.finplan"
    static let snapshotFileName = "widget-snapshot.json"

    private static let fullScaleBasisPoints: Int64 = 10_000

    static func publish(from store: FinanceStore, now: Date = Date(), calendar: Calendar = .current) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return }

        let snapshot = makeSnapshot(store: store, now: now, calendar: calendar)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: containerURL.appendingPathComponent(snapshotFileName), options: .atomic)
        } catch {
            return
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private static func makeSnapshot(store: FinanceStore, now: Date, calendar: Calendar) -> WidgetSnapshot {
        let base = store.baseCurrency

        let goalPart = goalValues(store: store, base: base, now: now)
        let safeMinor = safeToSpendMinor(store: store, now: now, calendar: calendar)
        let monthPart = monthValues(store: store, now: now, calendar: calendar)

        return WidgetSnapshot(
            primaryGoalTitle: goalPart?.title,
            fundedMinor: goalPart?.fundedMinor ?? 0,
            targetMinor: goalPart?.targetMinor ?? 0,
            currencyCode: base.code,
            currencyExponent: base.minorUnitExponent,
            percentBasisPoints: goalPart?.percentBasisPoints ?? 0,
            safeToSpendMinor: safeMinor,
            monthIncomeMinor: monthPart?.income ?? 0,
            monthExpensesMinor: monthPart?.expenses ?? 0,
            monthSavedMinor: monthPart?.saved ?? 0,
            generatedAt: now
        )
    }

    private static func primaryGoal(in goals: [Goal]) -> Goal? {
        goals
            .filter { $0.status == .active && !$0.isEmergencyFund }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first
    }

    private static func goalValues(
        store: FinanceStore, base: Currency, now: Date
    ) -> (title: String, fundedMinor: Int64, targetMinor: Int64, percentBasisPoints: Int)? {
        guard let goal = primaryGoal(in: store.goals) else { return nil }
        do {
            let currency = goal.targetAmount.currency
            let funded = try LedgerEngine.allocatedTotal(
                toGoal: goal.id, allocations: store.allocations,
                asOf: now, in: currency, rates: store.planningRates
            )
            let percentBasisPoints = Int(
                funded.multiplied(byNumerator: fullScaleBasisPoints, denominator: goal.targetAmount.amountMinor).amountMinor
            )
            let fundedBase = try converted(funded, to: base, rates: store.planningRates)
            let targetBase = try converted(goal.targetAmount, to: base, rates: store.planningRates)
            return (goal.title, fundedBase.amountMinor, targetBase.amountMinor, percentBasisPoints)
        } catch {
            return nil
        }
    }

    private static func safeToSpendMinor(
        store: FinanceStore, now: Date, calendar: Calendar
    ) -> Int64 {
        do {
            return try SafeToSpendSnapshot.compute(store: store, now: now, calendar: calendar)
                .result.available.amountMinor
        } catch {
            return 0
        }
    }

    private static func monthValues(
        store: FinanceStore, now: Date, calendar: Calendar
    ) -> (income: Int64, expenses: Int64, saved: Int64)? {
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return nil }
        do {
            let summary = try AnalyticsEngine.monthlySummary(
                interval: interval,
                transactions: store.transactions,
                accounts: store.accounts,
                rates: store.planningRates,
                baseCurrency: store.baseCurrency
            )
            return (
                summary.income.amountMinor,
                summary.expenses.amountMinor,
                summary.savingsAllocated.amountMinor
            )
        } catch {
            return nil
        }
    }

    private static func converted(
        _ money: Money, to currency: Currency, rates: ManualExchangeRates
    ) throws -> Money {
        if money.currency == currency { return money }
        guard let rate = rates.rate(from: money.currency, to: currency) else {
            throw LedgerError.missingExchangeRate(base: money.currency.code, quote: currency.code)
        }
        return try rate.convert(money)
    }
}
