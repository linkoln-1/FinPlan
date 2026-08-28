import Foundation
import FinPlanCore

enum GoalsFeatureError: LocalizedError {
    case overAllocation(available: Money)
    case missingPlanningRate(base: String, quote: String)
    case goalNotFound

    var errorDescription: String? {
        switch self {
        case .overAllocation:
            return String(localized: "goals.allocation.error.overAllocation")
        case .missingPlanningRate(let base, let quote):
            return String(localized: "goals.error.missingRate \(base) \(quote)")
        case .goalNotFound:
            return String(localized: "error.notFound")
        }
    }
}

struct GoalsSeriesPoint: Identifiable, Hashable, Sendable {
    var id: Date { date }
    let date: Date
    let balance: Money
}

enum GoalsRequiredContribution: Hashable, Sendable {
    case notRequested
    case amount(Money)
    case dateUnreachable
}

struct GoalsAllocationGroup: Identifiable {
    var id: UUID { accountID }
    let accountID: UUID
    let account: Account?
    let allocations: [GoalAllocation]
    let total: Money
}

extension FinanceStore {
    static let goalsHorizonCycles = 240

    func goalsFunded(for goal: Goal) throws -> Money {
        try LedgerEngine.allocatedTotal(
            toGoal: goal.id,
            allocations: allocations,
            asOf: Date(),
            in: goal.targetAmount.currency,
            rates: planningRates
        )
    }

    func goalsProgressBasisPoints(funded: Money, target: Money) -> Int {
        guard target.isPositive else { return 0 }
        let bps = funded.multiplied(byNumerator: 10_000, denominator: target.amountMinor).amountMinor
        return Int(min(max(bps, 0), 10_000))
    }

    func goalsProjectionInput(for goal: Goal) throws -> ProjectionInput {
        let funded = try goalsFunded(for: goal)
        let now = Date()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let horizonEnd = utc.date(byAdding: .month, value: Self.goalsHorizonCycles, to: now) ?? now
        let scheduler = RecurringScheduler(calendar: utc)

        var contributions: [PlannedContribution] = []
        for template in goalsContributionTemplates(for: goal) {
            switch template.recurrence {
            case .monthly(let day):
                contributions.append(
                    PlannedContribution(amount: template.amount, schedule: .monthly(day: day), end: template.endDate)
                )
            default:
                let dates = scheduler.occurrences(of: template, in: DateInterval(start: now, end: horizonEnd))
                guard !dates.isEmpty else { continue }
                contributions.append(
                    PlannedContribution(amount: template.amount, schedule: .dates(dates), end: template.endDate)
                )
            }
        }

        let oneTimes = goalsUpcomingEvents(for: goal)
            .filter { $0.state == .expected }
            .map { PlannedOneTime(amount: $0.amount, timing: .date($0.expectedDate)) }

        return ProjectionInput(
            startingAmount: funded,
            target: goal.targetAmount,
            startDate: now,
            contributions: contributions,
            oneTimeEvents: oneTimes,
            planningRates: planningRates,
            horizonCycles: Self.goalsHorizonCycles
        )
    }

    func goalsProjection(for goal: Goal) throws -> ProjectionResult {
        try ProjectionEngine.project(goalsProjectionInput(for: goal))
    }

    func goalsContributionTemplates(for goal: Goal) -> [RecurringTemplate] {
        recurringTemplates.filter {
            $0.goalID == goal.id && $0.isActive && ($0.kind == .transfer || $0.kind == .expense)
        }
    }

    func goalsMonthlyContribution(for goal: Goal) throws -> Money {
        let goalCurrency = goal.targetAmount.currency
        var total = Money.zero(goalCurrency)
        for template in goalsContributionTemplates(for: goal) {
            let converted = try goalsConvert(template.amount, to: goalCurrency)
            let monthly: Money
            switch template.recurrence {
            case .monthly:
                monthly = converted
            case .weekly:
                monthly = converted.multiplied(byNumerator: 52, denominator: 12)
            case .daily:
                monthly = converted.multiplied(byNumerator: 365, denominator: 12)
            case .yearly:
                monthly = converted.multiplied(byNumerator: 1, denominator: 12)
            case .everyNDays(let n):
                monthly = converted.multiplied(byNumerator: 365, denominator: Int64(max(1, n)) * 12)
            }
            total = try total.adding(monthly)
        }
        return total
    }

    func goalsRequiredContribution(for goal: Goal) throws -> GoalsRequiredContribution {
        guard let desired = goal.desiredCompletionDate else { return .notRequested }
        let funded = try goalsFunded(for: goal)
        let oneTimes = goalsUpcomingEvents(for: goal)
            .filter { $0.state == .expected }
            .map { PlannedOneTime(amount: $0.amount, timing: .date($0.expectedDate)) }
        do {
            let amount = try ProjectionEngine.requiredMonthlyContribution(
                startingAmount: funded,
                target: goal.targetAmount,
                by: desired,
                startDate: Date(),
                oneTimeEvents: oneTimes,
                planningRates: planningRates
            )
            return .amount(amount)
        } catch ProjectionError.nonPositiveCycleCount {
            return .dateUnreachable
        }
    }

    func goalsRoundThresholds(for goal: Goal) -> [Money] {
        let currency = goal.targetAmount.currency
        let millionMinor = Money(major: 1_000_000, currency: currency).amountMinor
        guard millionMinor > 0, goal.targetAmount.amountMinor >= millionMinor else { return [] }
        let count = goal.targetAmount.amountMinor / millionMinor
        return (1...count).compactMap { step in
            let minor = step * millionMinor
            guard minor < goal.targetAmount.amountMinor else { return nil }
            return Money(minor: minor, currency: currency)
        }
    }

    func goalsActualSeries(for goal: Goal) throws -> [GoalsSeriesPoint] {
        let goalCurrency = goal.targetAmount.currency
        let dated = allocations
            .filter { $0.goalID == goal.id }
            .sorted { $0.date < $1.date }
        var points: [GoalsSeriesPoint] = []
        var running = Money.zero(goalCurrency)
        for allocation in dated where allocation.date <= Date() {
            running = try running.adding(goalsConvert(allocation.amount, to: goalCurrency))
            points.append(GoalsSeriesPoint(date: allocation.date, balance: running))
        }
        if let last = points.last, last.date < Date() {
            points.append(GoalsSeriesPoint(date: Date(), balance: last.balance))
        }
        return points
    }

    func goalsAllocationGroups(for goal: Goal) throws -> [GoalsAllocationGroup] {
        let byAccount = Dictionary(grouping: allocations.filter { $0.goalID == goal.id }, by: \.accountID)
        return try byAccount
            .map { accountID, group in
                let account = accounts.first { $0.id == accountID }
                let currency = group.first?.amount.currency ?? account?.currency ?? baseCurrency
                let total = try group.map(\.amount).sum(in: currency)
                return GoalsAllocationGroup(
                    accountID: accountID,
                    account: account,
                    allocations: group.sorted { $0.date > $1.date },
                    total: total
                )
            }
            .sorted { ($0.account?.name ?? "") < ($1.account?.name ?? "") }
    }

    func goalsUnallocatedBalance(of account: Account) throws -> Money {
        let balance = try LedgerEngine.balance(of: account, transactions: transactions, asOf: Date())
        var reserved = Money.zero(account.currency)
        for allocation in allocations where allocation.accountID == account.id {
            reserved = try reserved.adding(goalsConvert(allocation.amount, to: account.currency))
        }
        return try balance.subtracting(reserved)
    }

    func goalsAddAllocation(goalID: UUID, account: Account, amount: Money, date: Date) throws {
        let available = try goalsUnallocatedBalance(of: account)
        let requested = try goalsConvert(amount, to: account.currency)
        if try requested.subtracting(available).isPositive {
            throw GoalsFeatureError.overAllocation(available: available)
        }
        addAllocation(GoalAllocation(goalID: goalID, accountID: account.id, amount: amount, date: date))
    }

    func goalsUpcomingEvents(for goal: Goal) -> [ExpectedEvent] {
        expectedEvents
            .filter { $0.goalID == goal.id && ($0.state == .expected || $0.state == .overdue) }
            .sorted { $0.expectedDate < $1.expectedDate }
    }

    func goalsContributionHistory(for goal: Goal) -> [TransactionRecord] {
        transactions.filter { $0.goalID == goal.id && $0.status == .completed }
    }

    func goalsSetStatus(_ status: GoalStatus, for goal: Goal) throws {
        guard goals.contains(where: { $0.id == goal.id }) else { throw GoalsFeatureError.goalNotFound }
        var updated = goal
        updated.status = status
        try updateGoal(updated)
    }

    func goalsPurchaseImpact(for goal: Goal, amount: Money, date: Date) throws -> PurchaseImpact {
        try PurchaseImpactEngine.evaluate(
            purchase: PurchaseCandidate(amount: amount, date: date),
            safeToSpend: goalsSafeToSpendSnapshot(),
            goalProjection: goalsProjectionInput(for: goal),
            planningRates: planningRates
        )
    }

    private func goalsSafeToSpendSnapshot() throws -> SafeToSpendInput {
        var liquid = Money.zero(baseCurrency)
        for account in accounts where account.includedInSafeToSpend && !account.isArchived {
            let balance = try LedgerEngine.balance(of: account, transactions: transactions, asOf: Date())
            liquid = try liquid.adding(goalsConvert(balance, to: baseCurrency))
        }
        var reserved = Money.zero(baseCurrency)
        for allocation in allocations {
            reserved = try reserved.adding(goalsConvert(allocation.amount, to: baseCurrency))
        }
        return SafeToSpendInput(
            liquidBalance: liquid,
            reservedTotal: reserved,
            upcomingMandatory: .zero(baseCurrency),
            minimumBuffer: minimumCashBuffer
        )
    }

    private func goalsConvert(_ money: Money, to currency: Currency) throws -> Money {
        if money.currency == currency { return money }
        guard let rate = planningRates.rate(from: money.currency, to: currency) else {
            throw GoalsFeatureError.missingPlanningRate(base: money.currency.code, quote: currency.code)
        }
        return try rate.convert(money)
    }
}
