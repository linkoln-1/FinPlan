import Foundation
import Observation
import FinPlanCore

struct DashboardHeroData {
    let goal: Goal
    let funded: Money
    let remaining: Money
    let percentBasisPoints: Int
    let completionDate: Date?
    let completionCycles: Int?
    let planStatus: PlanStatus?

    var progressFraction: Double {
        min(1.0, max(0.0, Double(percentBasisPoints) / 10_000.0))
    }

    var percentWhole: Int { percentBasisPoints / 100 }
}

struct DashboardMonthData {
    let summary: MonthlySummary
    let plannedSavings: Money
    let planCompletionBasisPoints: Int?

    var savingsRatePercent: Int? {
        summary.savingsRateBasisPoints.map { $0 / 100 }
    }

    var planFraction: Double? {
        planCompletionBasisPoints.map { min(1.0, max(0.0, Double($0) / 10_000.0)) }
    }
}

struct DashboardUpcomingItem: Identifiable {
    enum Kind {
        case recurring(TransactionKind)
        case expectedEvent
    }

    let id: UUID
    let title: String
    let date: Date
    let amount: Money
    let kind: Kind
    var templateID: UUID? = nil
    var eventID: UUID? = nil

    var symbolName: String {
        switch kind {
        case .recurring(.income): "arrow.down.circle.fill"
        case .recurring(.expense): "arrow.up.circle"
        case .recurring(.transfer): "arrow.left.arrow.right.circle"
        case .recurring(.currencyExchange): "arrow.triangle.2.circlepath.circle"
        case .recurring(.adjustment): "slider.horizontal.3"
        case .expectedEvent: "calendar.badge.clock"
        }
    }

    var isInflow: Bool {
        switch kind {
        case .recurring(.income), .expectedEvent: true
        default: false
        }
    }
}

struct DashboardChartPoint: Identifiable {
    enum Series {
        case actual
        case forecast
    }

    let id = UUID()
    let date: Date
    let amountMinor: Int64
    let series: Series
}

struct DashboardChartData {
    let points: [DashboardChartPoint]
    let target: Money

    func majorUnits(_ minor: Int64) -> Double {
        Double(minor) / Double(target.currency.minorUnitsPerMajor)
    }
}

@MainActor
@Observable
final class DashboardModel {
    private(set) var hero: DashboardHeroData?
    private(set) var safeToSpend: SafeToSpendResult?
    private(set) var safeToSpendDetails: DashboardSafeToSpendDetails?
    private(set) var month: DashboardMonthData?
    private(set) var upcoming: [DashboardUpcomingItem] = []
    private(set) var chart: DashboardChartData?
    private(set) var topInsight: Insight?
    var errorMessage: String?

    private static let projectionHorizonCycles = 120
    private static let forecastChartCycles = 24
    private static let actualChartMonths = 12
    private static let upcomingWindowDays = 30
    private static let incomeLookaheadDays = 62
    private static let insightPaymentLookaheadDays = 14
    private static let upcomingItemLimit = 5
    private static let fullScaleBasisPoints: Int64 = 10_000

    func recompute(store: FinanceStore, now: Date = Date(), calendar: Calendar = .current) {
        var firstFailure: String?
        func note(_ error: Error) {
            guard firstFailure == nil else { return }
            if case LedgerError.missingExchangeRate(let from, let to) = error {
                firstFailure = String(localized: "dashboard.error.missingRate \(from) \(to)")
            } else if let projectionError = error as? ProjectionError,
                      case .missingPlanningRate(let from, let to) = projectionError {
                firstFailure = String(localized: "dashboard.error.missingRate \(from) \(to)")
            } else {
                firstFailure = String(describing: error)
            }
        }

        let scheduler = RecurringScheduler(calendar: calendar)
        let primaryGoal = Self.primaryGoal(in: store.goals)

        var projection: ProjectionResult?
        if let goal = primaryGoal {
            do {
                let computed = try Self.heroData(for: goal, store: store, scheduler: scheduler, now: now, calendar: calendar)
                hero = computed.data
                projection = computed.projection
            } catch {
                hero = nil
                note(error)
            }
        } else {
            hero = nil
        }

        var liquid: Money?
        do {
            let computed = try Self.safeToSpendData(store: store, scheduler: scheduler, now: now, calendar: calendar)
            safeToSpend = computed.result
            safeToSpendDetails = computed.details
            liquid = computed.liquid
        } catch {
            safeToSpend = nil
            note(error)
        }

        do {
            month = try Self.monthData(store: store, scheduler: scheduler, now: now, calendar: calendar)
        } catch {
            month = nil
            note(error)
        }

        upcoming = Self.upcomingItems(store: store, scheduler: scheduler, now: now, calendar: calendar)

        if let goal = primaryGoal, let projection {
            do {
                chart = try Self.chartData(goal: goal, projection: projection, store: store, now: now, calendar: calendar)
            } catch {
                chart = nil
                note(error)
            }
        } else {
            chart = nil
        }

        do {
            topInsight = try Self.topInsight(
                store: store, hero: hero, month: month,
                safeToSpend: safeToSpend, liquid: liquid,
                scheduler: scheduler, now: now, calendar: calendar
            )
        } catch {
            topInsight = nil
            note(error)
        }

        if errorMessage != firstFailure {
            errorMessage = firstFailure
        }
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

    private static func heroData(
        for goal: Goal,
        store: FinanceStore,
        scheduler: RecurringScheduler,
        now: Date,
        calendar: Calendar
    ) throws -> (data: DashboardHeroData, projection: ProjectionResult) {
        let currency = goal.targetAmount.currency
        let funded = try LedgerEngine.allocatedTotal(
            toGoal: goal.id, allocations: store.allocations,
            asOf: now, in: currency, rates: store.planningRates
        )
        let remainingRaw = try goal.targetAmount.subtracting(funded)
        let remaining = remainingRaw.isNegative ? .zero(currency) : remainingRaw
        let percentBasisPoints: Int
        if goal.targetAmount.isPositive {
            percentBasisPoints = Int(
                funded.multiplied(byNumerator: fullScaleBasisPoints, denominator: goal.targetAmount.amountMinor).amountMinor
            )
        } else {
            percentBasisPoints = 0
        }

        let contributions = plannedContributions(for: goal, store: store, scheduler: scheduler, now: now, calendar: calendar)
        let oneTimeEvents = store.expectedEvents
            .filter { $0.goalID == goal.id && $0.state == .expected && $0.expectedDate >= now }
            .map { PlannedOneTime(amount: $0.amount, timing: .date($0.expectedDate)) }

        let projection = try ProjectionEngine.project(
            ProjectionInput(
                startingAmount: funded,
                target: goal.targetAmount,
                startDate: now,
                contributions: contributions,
                oneTimeEvents: oneTimeEvents,
                planningRates: store.planningRates,
                horizonCycles: projectionHorizonCycles
            )
        )

        let status = planStatus(goal: goal, projection: projection, calendar: calendar)
        let data = DashboardHeroData(
            goal: goal,
            funded: funded,
            remaining: remaining,
            percentBasisPoints: percentBasisPoints,
            completionDate: projection.completionDate,
            completionCycles: projection.completionCycle,
            planStatus: status
        )
        return (data, projection)
    }

    private static func plannedContributions(
        for goal: Goal,
        store: FinanceStore,
        scheduler: RecurringScheduler,
        now: Date,
        calendar: Calendar
    ) -> [PlannedContribution] {
        let templates = store.recurringTemplates.filter { $0.goalID == goal.id && $0.isActive }
        guard !templates.isEmpty else { return [] }
        var contributions: [PlannedContribution] = []
        for template in templates {
            switch template.recurrence {
            case .monthly(let day):
                contributions.append(
                    PlannedContribution(amount: template.amount, schedule: .monthly(day: day), end: template.endDate)
                )
            default:
                guard let horizonEnd = calendar.date(byAdding: .month, value: projectionHorizonCycles, to: now),
                      horizonEnd > now else { continue }
                let dates = scheduler.occurrences(of: template, in: DateInterval(start: now, end: horizonEnd))
                if !dates.isEmpty {
                    contributions.append(
                        PlannedContribution(amount: template.amount, schedule: .dates(dates), end: template.endDate)
                    )
                }
            }
        }
        return contributions
    }

    private static let onTrackToleranceDays = 3

    private static func planStatus(
        goal: Goal,
        projection: ProjectionResult,
        calendar: Calendar
    ) -> PlanStatus? {
        guard let desired = goal.desiredCompletionDate,
              let completion = projection.completionDate else { return nil }
        let days = calendar.dateComponents([.day], from: completion, to: desired).day ?? 0
        let standing: PlanStatus.Standing
        if days > onTrackToleranceDays {
            standing = .ahead
        } else if days < -onTrackToleranceDays {
            standing = .behind
        } else {
            standing = .onTrack
        }
        return PlanStatus(
            delta: .zero(goal.targetAmount.currency),
            standing: standing,
            timeImpactDays: days
        )
    }

    private static func safeToSpendData(
        store: FinanceStore,
        scheduler: RecurringScheduler,
        now: Date,
        calendar: Calendar
    ) throws -> (result: SafeToSpendResult, liquid: Money, details: DashboardSafeToSpendDetails) {
        let base = store.baseCurrency
        let rates = store.planningRates

        var liquid = Money.zero(base)
        for account in store.accounts where account.includedInSafeToSpend && !account.isArchived {
            let balance = try LedgerEngine.balance(of: account, transactions: store.transactions, asOf: now)
            liquid = try liquid.adding(converted(balance, to: base, rates: rates))
        }

        var reserved = Money.zero(base)
        var reservedByGoal: [UUID: Money] = [:]
        for allocation in store.allocations where allocation.date <= now {
            let converted = try converted(allocation.amount, to: base, rates: rates)
            reserved = try reserved.adding(converted)
            if let existing = reservedByGoal[allocation.goalID] {
                reservedByGoal[allocation.goalID] = try existing.adding(converted)
            } else {
                reservedByGoal[allocation.goalID] = converted
            }
        }
        let goalTitles = Dictionary(uniqueKeysWithValues: store.goals.map { ($0.id, $0.title) })
        let goalReserves = reservedByGoal
            .compactMap { id, amount -> DashboardSafeToSpendDetails.GoalReserve? in
                guard amount.isPositive else { return nil }
                return DashboardSafeToSpendDetails.GoalReserve(
                    id: id, title: goalTitles[id] ?? "", amount: amount
                )
            }
            .sorted { $0.amount.amountMinor > $1.amount.amountMinor }

        let nextIncome = nextIncomeDate(store: store, scheduler: scheduler, now: now, calendar: calendar)
        var mandatory = Money.zero(base)
        var upcomingPayments: [DashboardSafeToSpendDetails.UpcomingPayment] = []
        if nextIncome > now {
            let window = DateInterval(start: now, end: nextIncome)
            let mandatoryTemplates = store.recurringTemplates.filter {
                $0.isActive && $0.kind == .expense && $0.goalID == nil
            }
            let templateNames = Dictionary(uniqueKeysWithValues: mandatoryTemplates.map { ($0.id, $0.name) })
            for record in scheduler.plannedRecords(for: mandatoryTemplates, in: window) {
                let converted = try converted(record.amount, to: base, rates: rates)
                mandatory = try mandatory.adding(converted)
                upcomingPayments.append(DashboardSafeToSpendDetails.UpcomingPayment(
                    id: record.id,
                    name: record.recurringTemplateID.flatMap { templateNames[$0] } ?? "",
                    date: record.date,
                    amount: converted
                ))
            }
            upcomingPayments.sort { $0.date < $1.date }
        }

        let input = SafeToSpendInput(
            liquidBalance: liquid,
            reservedTotal: reserved,
            upcomingMandatory: mandatory,
            minimumBuffer: store.minimumCashBuffer
        )
        let details = DashboardSafeToSpendDetails(
            goalReserves: goalReserves,
            upcomingPayments: upcomingPayments,
            nextIncomeDate: nextIncome
        )
        return (try SafeToSpendEngine.evaluate(input), liquid, details)
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

    private static func monthData(
        store: FinanceStore,
        scheduler: RecurringScheduler,
        now: Date,
        calendar: Calendar
    ) throws -> DashboardMonthData? {
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return nil }
        let summary = try AnalyticsEngine.monthlySummary(
            interval: interval,
            transactions: store.transactions,
            accounts: store.accounts,
            rates: store.planningRates,
            baseCurrency: store.baseCurrency
        )

        var planned = Money.zero(store.baseCurrency)
        let savingsTemplates = store.recurringTemplates.filter { $0.isActive && $0.goalID != nil }
        for record in scheduler.plannedRecords(for: savingsTemplates, in: interval) {
            planned = try planned.adding(converted(record.amount, to: store.baseCurrency, rates: store.planningRates))
        }

        let completion: Int?
        if planned.isPositive {
            completion = Int(
                summary.savingsAllocated
                    .multiplied(byNumerator: fullScaleBasisPoints, denominator: planned.amountMinor)
                    .amountMinor
            )
        } else {
            completion = nil
        }
        return DashboardMonthData(summary: summary, plannedSavings: planned, planCompletionBasisPoints: completion)
    }

    private static func upcomingItems(
        store: FinanceStore,
        scheduler: RecurringScheduler,
        now: Date,
        calendar: Calendar
    ) -> [DashboardUpcomingItem] {
        guard let horizon = calendar.date(byAdding: .day, value: upcomingWindowDays, to: now),
              horizon > now else { return [] }
        let window = DateInterval(start: now, end: horizon)

        var items = scheduler
            .plannedRecords(for: store.recurringTemplates.filter(\.isActive), in: window)
            .map { record in
                DashboardUpcomingItem(
                    id: record.id,
                    title: record.note ?? "",
                    date: record.date,
                    amount: record.amount,
                    kind: .recurring(record.kind),
                    templateID: record.recurringTemplateID
                )
            }

        let partition = RecurringScheduler.expectedEventStatus(events: store.expectedEvents, now: now)
        items += partition.upcoming
            .filter { $0.expectedDate < window.end }
            .map { event in
                DashboardUpcomingItem(
                    id: event.id,
                    title: event.title,
                    date: event.expectedDate,
                    amount: event.amount,
                    kind: .expectedEvent,
                    eventID: event.id
                )
            }

        let sorted = items.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return Array(sorted.prefix(upcomingItemLimit))
    }

    private static func chartData(
        goal: Goal,
        projection: ProjectionResult,
        store: FinanceStore,
        now: Date,
        calendar: Calendar
    ) throws -> DashboardChartData {
        let currency = goal.targetAmount.currency
        var points: [DashboardChartPoint] = []

        let earliest = calendar.date(byAdding: .month, value: -(actualChartMonths - 1), to: now) ?? goal.startDate
        let historyStart = max(goal.startDate, earliest)
        if var cursor = calendar.dateInterval(of: .month, for: historyStart)?.start {
            while cursor <= now {
                guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                let sampleDate = min(monthEnd, now)
                let funded = try LedgerEngine.allocatedTotal(
                    toGoal: goal.id, allocations: store.allocations,
                    asOf: sampleDate, in: currency, rates: store.planningRates
                )
                points.append(DashboardChartPoint(date: sampleDate, amountMinor: funded.amountMinor, series: .actual))
                if monthEnd > now { break }
                cursor = monthEnd
            }
        }

        for point in projection.points.prefix(forecastChartCycles + 1) {
            points.append(DashboardChartPoint(date: point.date, amountMinor: point.balance.amountMinor, series: .forecast))
        }

        return DashboardChartData(points: points, target: goal.targetAmount)
    }

    private static func topInsight(
        store: FinanceStore,
        hero: DashboardHeroData?,
        month: DashboardMonthData?,
        safeToSpend: SafeToSpendResult?,
        liquid: Money?,
        scheduler: RecurringScheduler,
        now: Date,
        calendar: Calendar
    ) throws -> Insight? {
        var goalSnapshots: [GoalInsightSnapshot] = []
        for goal in store.goals where goal.status == .active {
            let currency = goal.targetAmount.currency
            let funded = try LedgerEngine.allocatedTotal(
                toGoal: goal.id, allocations: store.allocations,
                asOf: now, in: currency, rates: store.planningRates
            )
            var remainingCycles: Int?
            if let desired = goal.desiredCompletionDate {
                let months = calendar.dateComponents([.month], from: now, to: desired).month ?? 0
                remainingCycles = months > 0 ? months : nil
            }
            let isPrimary = goal.id == hero?.goal.id
            goalSnapshots.append(
                GoalInsightSnapshot(
                    goalID: goal.id,
                    target: goal.targetAmount,
                    currentAmount: funded,
                    planStatus: isPrimary ? hero?.planStatus : nil,
                    remainingCycles: remainingCycles
                )
            )
        }

        var upcomingPayments: [UpcomingPaymentSnapshot] = []
        if let liquid,
           let horizon = calendar.date(byAdding: .day, value: insightPaymentLookaheadDays, to: now),
           horizon > now {
            let window = DateInterval(start: now, end: horizon)
            let expenseTemplates = store.recurringTemplates.filter { $0.isActive && $0.kind == .expense }
            for record in scheduler.plannedRecords(for: expenseTemplates, in: window) {
                let amount = try converted(record.amount, to: liquid.currency, rates: store.planningRates)
                upcomingPayments.append(UpcomingPaymentSnapshot(amount: amount, dueDate: record.date))
            }
        }

        var savings: SavingsPeriodSnapshot?
        if let month, month.plannedSavings.isPositive {
            savings = SavingsPeriodSnapshot(target: month.plannedSavings, actual: month.summary.savingsAllocated)
        }

        let context = InsightContext(
            now: now,
            goals: goalSnapshots,
            upcomingPayments: upcomingPayments,
            expectedEvents: store.expectedEvents,
            savings: savings,
            liquidBalance: liquid,
            safeToSpend: safeToSpend
        )
        return try InsightEngine.evaluate(context: context).first
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

struct DashboardSafeToSpendDetails: Hashable {
    struct GoalReserve: Hashable, Identifiable {
        let id: UUID
        let title: String
        let amount: Money
    }

    struct UpcomingPayment: Hashable, Identifiable {
        let id: UUID
        let name: String
        let date: Date
        let amount: Money
    }

    var goalReserves: [GoalReserve]
    var upcomingPayments: [UpcomingPayment]
    var nextIncomeDate: Date
}
