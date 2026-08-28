import Foundation
import FinPlanCore

struct PlanMonthlyFigures {
    let interval: DateInterval
    let plannedIncome: Money
    let actualIncome: Money
    let plannedSavings: Money
    let actualSavings: Money
}

struct PlanRecoveryInfo {
    let shortfall: Money
    let timeImpactDays: Int
    let extraPerMonth: Money
    let remainingMonths: Int
}

enum PlanMath {
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func convert(_ amount: Money, to currency: Currency, rates: ManualExchangeRates) throws -> Money {
        if amount.currency == currency { return amount }
        guard let rate = rates.rate(from: amount.currency, to: currency) else {
            throw MoneyError.currencyMismatch(amount.currency.code, currency.code)
        }
        return try rate.convert(amount)
    }

    static func plannedMonthlyIncome(
        sources: [IncomeSource],
        currency: Currency,
        rates: ManualExchangeRates
    ) throws -> Money {
        var total = Money.zero(currency)
        for source in sources where source.isActive {
            total = try total.adding(convert(source.personalAmount, to: currency, rates: rates))
        }
        return total
    }

    static func plannedSavings(
        templates: [RecurringTemplate],
        in interval: DateInterval,
        currency: Currency,
        rates: ManualExchangeRates,
        calendar: Calendar
    ) throws -> Money {
        let goalTemplates = templates.filter { $0.goalID != nil && $0.isActive }
        let scheduler = RecurringScheduler(calendar: calendar)
        let records = scheduler.plannedRecords(for: goalTemplates, in: interval)
        var total = Money.zero(currency)
        for record in records {
            total = try total.adding(convert(record.amount, to: currency, rates: rates))
        }
        return total
    }

    static func monthlyFigures(
        now: Date,
        calendar: Calendar,
        sources: [IncomeSource],
        templates: [RecurringTemplate],
        transactions: [TransactionRecord],
        currency: Currency,
        rates: ManualExchangeRates
    ) throws -> PlanMonthlyFigures {
        let interval = calendar.dateInterval(of: .month, for: now)
            ?? DateInterval(start: now, duration: 0)
        let summary = try LedgerEngine.periodSummary(
            transactions: transactions,
            in: interval,
            currency: currency,
            rates: rates
        )
        return PlanMonthlyFigures(
            interval: interval,
            plannedIncome: try plannedMonthlyIncome(sources: sources, currency: currency, rates: rates),
            actualIncome: summary.income,
            plannedSavings: try plannedSavings(
                templates: templates,
                in: interval,
                currency: currency,
                rates: rates,
                calendar: calendar
            ),
            actualSavings: summary.savingsAllocated
        )
    }

    static func monthlyEquivalent(of template: RecurringTemplate) -> Money {
        let amount = template.amount
        switch template.recurrence {
        case .daily:
            return amount.multiplied(byNumerator: 365, denominator: 12)
        case .weekly:
            return amount.multiplied(byNumerator: 52, denominator: 12)
        case .monthly:
            return amount
        case .yearly:
            return amount.multiplied(byNumerator: 1, denominator: 12)
        case .everyNDays(let n):
            let step = Int64(max(1, n))
            return amount.multiplied(byNumerator: 365, denominator: 12 * step)
        }
    }

    static func plannedMonthlySavings(
        toward goal: Goal,
        templates: [RecurringTemplate],
        rates: ManualExchangeRates
    ) throws -> (amount: Money, dayOfMonth: Int) {
        let goalTemplates = templates.filter { $0.goalID == goal.id && $0.isActive }
        guard let first = goalTemplates.first else {
            return (Money.zero(goal.targetAmount.currency), 1)
        }
        let savingsCurrency = first.amount.currency
        var total = Money.zero(savingsCurrency)
        for template in goalTemplates {
            total = try total.adding(convert(monthlyEquivalent(of: template), to: savingsCurrency, rates: rates))
        }
        var day = 1
        if case .monthly(let templateDay) = first.recurrence { day = templateDay }
        return (total, min(max(day, 1), 31))
    }

    static func upcomingGoalEvents(
        for goal: Goal,
        expectedEvents: [ExpectedEvent],
        now: Date
    ) -> [ScenarioOneTime] {
        RecurringScheduler.expectedEventStatus(events: expectedEvents, now: now)
            .upcoming
            .filter { $0.goalID == goal.id }
            .map { ScenarioOneTime(amount: $0.amount, timing: .date($0.expectedDate)) }
    }

    static func basePlan(
        goal: Goal,
        balance: Money,
        templates: [RecurringTemplate],
        incomeSources: [IncomeSource],
        expectedEvents: [ExpectedEvent],
        planningRates: ManualExchangeRates,
        now: Date
    ) throws -> ScenarioBasePlan {
        let savings = try plannedMonthlySavings(toward: goal, templates: templates, rates: planningRates)
        let baseline = try baselineMonthlyExpenses(
            templates: templates,
            in: savings.amount.currency,
            rates: planningRates
        )
        return ScenarioBasePlan(
            startingAmount: balance,
            targetAmount: goal.targetAmount,
            targetDate: nil,
            startDate: now,
            incomeSources: incomeSources.filter(\.isActive),
            monthlySavings: savings.amount,
            savingsDay: savings.dayOfMonth,
            oneTimeEvents: upcomingGoalEvents(for: goal, expectedEvents: expectedEvents, now: now),
            planningRates: planningRates,
            baselineMonthlyExpenses: baseline.isPositive ? baseline : nil
        )
    }

    static func baselineMonthlyExpenses(
        templates: [RecurringTemplate],
        in currency: Currency,
        rates: ManualExchangeRates
    ) throws -> Money {
        var total = Money.zero(currency)
        let summaries = RecurringScheduler.subscriptionSummary(
            templates: templates.filter { $0.goalID == nil }
        )
        for summary in summaries {
            total = try total.adding(convert(summary.monthlyEquivalent, to: currency, rates: rates))
        }
        return total
    }

    static func recoveryInfo(
        goal: Goal,
        balance: Money,
        templates: [RecurringTemplate],
        rates: ManualExchangeRates,
        now: Date
    ) throws -> PlanRecoveryInfo? {
        guard let desired = goal.desiredCompletionDate, desired > now else { return nil }
        let savings = try plannedMonthlySavings(toward: goal, templates: templates, rates: rates)
        let goalCurrency = goal.targetAmount.currency
        let monthlyInGoalCurrency = try convert(savings.amount, to: goalCurrency, rates: rates)
        guard monthlyInGoalCurrency.isPositive else { return nil }

        let plannedInput = ProjectionInput(
            startingAmount: .zero(goalCurrency),
            target: goal.targetAmount,
            startDate: goal.startDate,
            contributions: [
                PlannedContribution(
                    amount: monthlyInGoalCurrency,
                    schedule: .monthly(day: savings.dayOfMonth)
                ),
            ],
            planningRates: rates
        )
        let planned = try ProjectionEngine.project(plannedInput)
        let plannedByNow = planned.points.last(where: { $0.date <= now })?.balance
            ?? plannedInput.startingAmount

        let status = try ProjectionEngine.planStatus(
            actualBalance: balance,
            plannedBalance: plannedByNow,
            monthlyPlannedContribution: monthlyInGoalCurrency
        )
        guard status.standing == .behind else { return nil }

        let remainingMonths = utcCalendar.dateComponents([.month], from: now, to: desired).month ?? 0
        guard remainingMonths >= 1 else { return nil }

        let shortfall = try plannedByNow.subtracting(balance)
        let extra = try ProjectionEngine.recoveryPlan(shortfall: shortfall, remainingCycles: remainingMonths)
        guard extra.isPositive else { return nil }
        return PlanRecoveryInfo(
            shortfall: shortfall,
            timeImpactDays: status.timeImpactDays,
            extraPerMonth: extra,
            remainingMonths: remainingMonths
        )
    }
}
