import Foundation
import FinPlanCore

@MainActor
enum SafeToSpendSnapshot {
    struct Output {
        let result: SafeToSpendResult
        let liquid: Money
    }

    private static let upcomingWindowDays = 30
    private static let incomeLookaheadDays = 62

    static func compute(
        store: FinanceStore,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Output {
        let scheduler = RecurringScheduler(calendar: calendar)
        let base = store.baseCurrency
        let rates = store.planningRates

        var liquid = Money.zero(base)
        for account in store.accounts where account.includedInSafeToSpend && !account.isArchived {
            let balance = try LedgerEngine.balance(of: account, transactions: store.transactions, asOf: now)
            liquid = try liquid.adding(converted(balance, to: base, rates: rates))
        }

        var reserved = Money.zero(base)
        for allocation in store.allocations where allocation.date <= now {
            reserved = try reserved.adding(converted(allocation.amount, to: base, rates: rates))
        }

        let nextIncome = nextIncomeDate(store: store, scheduler: scheduler, now: now, calendar: calendar)
        var mandatory = Money.zero(base)
        if nextIncome > now {
            let window = DateInterval(start: now, end: nextIncome)
            let mandatoryTemplates = store.recurringTemplates.filter {
                $0.isActive && $0.kind == .expense && $0.goalID == nil
            }
            for record in scheduler.plannedRecords(for: mandatoryTemplates, in: window) {
                mandatory = try mandatory.adding(converted(record.amount, to: base, rates: rates))
            }
        }

        let input = SafeToSpendInput(
            liquidBalance: liquid,
            reservedTotal: reserved,
            upcomingMandatory: mandatory,
            minimumBuffer: store.minimumCashBuffer
        )
        return Output(result: try SafeToSpendEngine.evaluate(input), liquid: liquid)
    }

    private static func nextIncomeDate(
        store: FinanceStore,
        scheduler: RecurringScheduler,
        now: Date,
        calendar: Calendar
    ) -> Date {
        let fallback = calendar.date(byAdding: .day, value: upcomingWindowDays, to: now) ?? now
        guard let horizon = calendar.date(byAdding: .day, value: incomeLookaheadDays, to: now),
              horizon > now else { return fallback }
        let window = DateInterval(start: now, end: horizon)
        var dates: [Date] = []
        for template in store.recurringTemplates where template.isActive && template.kind == .income {
            dates.append(contentsOf: scheduler.occurrences(of: template, in: window))
        }
        for source in store.incomeSources where source.isActive && source.grossAmount.isPositive {
            let synthetic = RecurringTemplate(
                name: source.name,
                kind: .income,
                amount: source.grossAmount,
                recurrence: source.recurrence,
                startDate: calendar.date(byAdding: .year, value: -1, to: now) ?? now
            )
            dates.append(contentsOf: scheduler.occurrences(of: synthetic, in: window))
        }
        return dates.min() ?? fallback
    }

    private static func converted(
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
