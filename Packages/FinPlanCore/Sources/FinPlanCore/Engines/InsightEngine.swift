import Foundation

public enum InsightType: String, Sendable, Codable, CaseIterable {
    case aheadOfPlan
    case behindPlan
    case goalReached
    case milestoneReached
    case overspendingCategory
    case unusualSpending
    case upcomingLargePayment
    case expectedIncomeOverdue
    case savingsTargetMissed
    case savingsTargetExceeded
    case runwayLow
    case safeToSpendLow
    case currencyPlanDeviation
    case recoveryPlanAvailable

    var sortRank: Int { Self.allCases.firstIndex(of: self) ?? Int.max }
}

public enum InsightSeverity: Int, Sendable, Codable, CaseIterable, Comparable {
    case info = 0
    case attention = 1
    case warning = 2

    public static func < (lhs: InsightSeverity, rhs: InsightSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Insight: Hashable, Sendable, Codable {
    public let type: InsightType
    public let severity: InsightSeverity
    public let messageKey: String
    public let value: Money?
    public let secondaryValue: Money?
    public let basis: String
    public let actionKey: String?

    public init(
        type: InsightType,
        severity: InsightSeverity,
        messageKey: String,
        value: Money? = nil,
        secondaryValue: Money? = nil,
        basis: String,
        actionKey: String? = nil
    ) {
        self.type = type
        self.severity = severity
        self.messageKey = messageKey
        self.value = value
        self.secondaryValue = secondaryValue
        self.basis = basis
        self.actionKey = actionKey
    }
}

public struct GoalInsightSnapshot: Hashable, Sendable {
    public let goalID: UUID
    public let target: Money
    public let currentAmount: Money
    public let planStatus: PlanStatus?
    public let milestoneThresholds: [Money]
    public let shortfallAtHorizon: Money?
    public let remainingCycles: Int?

    public init(
        goalID: UUID,
        target: Money,
        currentAmount: Money,
        planStatus: PlanStatus? = nil,
        milestoneThresholds: [Money] = [],
        shortfallAtHorizon: Money? = nil,
        remainingCycles: Int? = nil
    ) {
        self.goalID = goalID
        self.target = target
        self.currentAmount = currentAmount
        self.planStatus = planStatus
        self.milestoneThresholds = milestoneThresholds
        self.shortfallAtHorizon = shortfallAtHorizon
        self.remainingCycles = remainingCycles
    }
}

public struct BudgetInsightSnapshot: Hashable, Sendable {
    public let categoryID: UUID
    public let status: BudgetStatus

    public init(categoryID: UUID, status: BudgetStatus) {
        self.categoryID = categoryID
        self.status = status
    }
}

public struct CategorySpendingHistory: Hashable, Sendable {
    public let categoryID: UUID
    public let currentMonthSpend: Money
    public let trailingMonthlySpend: [Money]

    public init(categoryID: UUID, currentMonthSpend: Money, trailingMonthlySpend: [Money]) {
        self.categoryID = categoryID
        self.currentMonthSpend = currentMonthSpend
        self.trailingMonthlySpend = trailingMonthlySpend
    }
}

public struct UpcomingPaymentSnapshot: Hashable, Sendable {
    public let id: UUID
    public let amount: Money
    public let dueDate: Date

    public init(id: UUID = UUID(), amount: Money, dueDate: Date) {
        self.id = id
        self.amount = amount
        self.dueDate = dueDate
    }
}

public struct SavingsPeriodSnapshot: Hashable, Sendable {
    public let target: Money
    public let actual: Money

    public init(target: Money, actual: Money) {
        self.target = target
        self.actual = actual
    }
}

public struct PlanningRateComparison: Hashable, Sendable {
    public let planning: ExchangeRate
    public let current: ExchangeRate

    public init(planning: ExchangeRate, current: ExchangeRate) {
        self.planning = planning
        self.current = current
    }
}

public struct InsightContext: Sendable {
    public let now: Date
    public let goals: [GoalInsightSnapshot]
    public let budgets: [BudgetInsightSnapshot]
    public let categoryHistories: [CategorySpendingHistory]
    public let upcomingPayments: [UpcomingPaymentSnapshot]
    public let expectedEvents: [ExpectedEvent]
    public let savings: SavingsPeriodSnapshot?
    public let liquidBalance: Money?
    public let monthlyEssentialSpending: Money?
    public let safeToSpend: SafeToSpendResult?
    public let rateComparisons: [PlanningRateComparison]

    public init(
        now: Date,
        goals: [GoalInsightSnapshot] = [],
        budgets: [BudgetInsightSnapshot] = [],
        categoryHistories: [CategorySpendingHistory] = [],
        upcomingPayments: [UpcomingPaymentSnapshot] = [],
        expectedEvents: [ExpectedEvent] = [],
        savings: SavingsPeriodSnapshot? = nil,
        liquidBalance: Money? = nil,
        monthlyEssentialSpending: Money? = nil,
        safeToSpend: SafeToSpendResult? = nil,
        rateComparisons: [PlanningRateComparison] = []
    ) {
        self.now = now
        self.goals = goals
        self.budgets = budgets
        self.categoryHistories = categoryHistories
        self.upcomingPayments = upcomingPayments
        self.expectedEvents = expectedEvents
        self.savings = savings
        self.liquidBalance = liquidBalance
        self.monthlyEssentialSpending = monthlyEssentialSpending
        self.safeToSpend = safeToSpend
        self.rateComparisons = rateComparisons
    }
}

public enum InsightEngine {
    public static let fullScaleBasisPoints: Int64 = 10_000

    public static let planDeviationToleranceBasisPoints: Int64 = 100

    public static let unusualSpendingRatioBasisPoints: Int64 = 20_000

    public static let unusualSpendingMinimumHistoryMonths = 3

    public static let largePaymentLookaheadSeconds: Int64 = 14 * 24 * 60 * 60

    public static let largePaymentLiquidShareBasisPoints: Int64 = 2_000

    public static let savingsToleranceBasisPoints: Int64 = 100

    public static let runwayLowMonths: Int64 = 3

    public static let safeToSpendLowShareBasisPoints: Int64 = 1_000

    public static let currencyDeviationToleranceBasisPoints: Int64 = 500

    public static func evaluate(context: InsightContext) throws -> [Insight] {
        var insights: [Insight] = []
        for goal in context.goals {
            insights.append(contentsOf: try goalInsights(goal))
        }
        insights.append(contentsOf: budgetInsights(context.budgets))
        insights.append(contentsOf: try unusualSpendingInsights(context.categoryHistories))
        insights.append(contentsOf: try upcomingPaymentInsights(context))
        insights.append(contentsOf: overdueIncomeInsights(context))
        if let savings = context.savings {
            insights.append(contentsOf: try savingsInsights(savings))
        }
        if let runway = try runwayInsight(context) {
            insights.append(runway)
        }
        if let sts = context.safeToSpend, let insight = try safeToSpendInsight(sts) {
            insights.append(insight)
        }
        insights.append(contentsOf: try currencyDeviationInsights(context.rateComparisons))
        return insights.sorted(by: canonicalOrder)
    }

    private static func goalInsights(_ goal: GoalInsightSnapshot) throws -> [Insight] {
        if try goal.currentAmount.comparing(goal.target) >= 0 {
            return [goalReachedInsight(goal)]
        }
        var result: [Insight] = []
        if let milestone = try milestoneInsight(goal) {
            result.append(milestone)
        }
        if let status = goal.planStatus, let pace = try paceInsight(goal, status: status) {
            result.append(pace)
        }
        if let recovery = try recoveryInsight(goal) {
            result.append(recovery)
        }
        return result
    }

    private static func goalReachedInsight(_ goal: GoalInsightSnapshot) -> Insight {
        Insight(
            type: .goalReached,
            severity: .info,
            messageKey: messageKey(.goalReached),
            value: goal.currentAmount,
            secondaryValue: goal.target,
            basis: "goal \(goal.goalID): current \(minor(goal.currentAmount)) >= target \(minor(goal.target))"
        )
    }

    private static func milestoneInsight(_ goal: GoalInsightSnapshot) throws -> Insight? {
        var highest: Money?
        for threshold in goal.milestoneThresholds {
            guard try goal.currentAmount.comparing(threshold) >= 0 else { continue }
            if let current = highest {
                if try threshold.comparing(current) > 0 { highest = threshold }
            } else {
                highest = threshold
            }
        }
        guard let reached = highest else { return nil }
        return Insight(
            type: .milestoneReached,
            severity: .info,
            messageKey: messageKey(.milestoneReached),
            value: reached,
            secondaryValue: goal.currentAmount,
            basis: "goal \(goal.goalID): current \(minor(goal.currentAmount)) >= milestone \(minor(reached))"
        )
    }

    private static func paceInsight(_ goal: GoalInsightSnapshot, status: PlanStatus) throws -> Insight? {
        guard status.delta.currency == goal.target.currency else {
            throw MoneyError.currencyMismatch(status.delta.currency.code, goal.target.currency.code)
        }
        let tolerance = share(of: goal.target, basisPoints: planDeviationToleranceBasisPoints)
        guard status.delta.amountMinor.magnitude > tolerance.amountMinor.magnitude else { return nil }
        let isAhead = status.delta.isPositive
        let basis = "goal \(goal.goalID): delta \(minor(status.delta)) vs plan, "
            + "|delta| > \(planDeviationToleranceBasisPoints)bp of target = \(minor(tolerance)), "
            + "timeImpactDays \(status.timeImpactDays)"
        return Insight(
            type: isAhead ? .aheadOfPlan : .behindPlan,
            severity: isAhead ? .info : .attention,
            messageKey: messageKey(isAhead ? .aheadOfPlan : .behindPlan),
            value: status.delta,
            secondaryValue: goal.target,
            basis: basis
        )
    }

    private static func recoveryInsight(_ goal: GoalInsightSnapshot) throws -> Insight? {
        guard
            let shortfall = goal.shortfallAtHorizon, shortfall.isPositive,
            let cycles = goal.remainingCycles, cycles >= 1
        else { return nil }
        let extra = try ProjectionEngine.recoveryPlan(shortfall: shortfall, remainingCycles: cycles)
        return Insight(
            type: .recoveryPlanAvailable,
            severity: .info,
            messageKey: messageKey(.recoveryPlanAvailable),
            value: extra,
            secondaryValue: shortfall,
            basis: "goal \(goal.goalID): shortfall \(minor(shortfall)) over \(cycles) cycles "
                + "=> extra \(minor(extra))/cycle",
            actionKey: actionKey(.recoveryPlanAvailable)
        )
    }

    private static func budgetInsights(_ budgets: [BudgetInsightSnapshot]) -> [Insight] {
        budgets.compactMap { snapshot in
            guard snapshot.status.remaining.isNegative else { return nil }
            let overspend = snapshot.status.remaining.negated
            return Insight(
                type: .overspendingCategory,
                severity: .warning,
                messageKey: messageKey(.overspendingCategory),
                value: overspend,
                secondaryValue: snapshot.status.spent,
                basis: "category \(snapshot.categoryID): remaining \(minor(snapshot.status.remaining)) < 0, "
                    + "used \(snapshot.status.fractionUsedBasisPoints)bp"
            )
        }
    }

    private static func unusualSpendingInsights(
        _ histories: [CategorySpendingHistory]
    ) throws -> [Insight] {
        var result: [Insight] = []
        for history in histories {
            let months = history.trailingMonthlySpend.count
            guard months >= unusualSpendingMinimumHistoryMonths else { continue }
            let total = try history.trailingMonthlySpend.sum(in: history.currentMonthSpend.currency)
            guard total.isPositive else { continue }
            let lhs = Int128(history.currentMonthSpend.amountMinor)
                * Int128(months) * Int128(fullScaleBasisPoints)
            let rhs = Int128(total.amountMinor) * Int128(unusualSpendingRatioBasisPoints)
            guard lhs > rhs else { continue }
            let average = total.multiplied(byNumerator: 1, denominator: Int64(months))
            result.append(Insight(
                type: .unusualSpending,
                severity: .attention,
                messageKey: messageKey(.unusualSpending),
                value: history.currentMonthSpend,
                secondaryValue: average,
                basis: "category \(history.categoryID): month \(minor(history.currentMonthSpend)) > "
                    + "\(unusualSpendingRatioBasisPoints)bp of \(months)-month avg "
                    + "(total \(minor(total)))"
            ))
        }
        return result
    }

    private static func upcomingPaymentInsights(_ context: InsightContext) throws -> [Insight] {
        guard let liquid = context.liquidBalance else { return [] }
        let nowSeconds = seconds(context.now)
        var result: [Insight] = []
        for payment in context.upcomingPayments {
            guard payment.amount.isPositive else { continue }
            guard payment.amount.currency == liquid.currency else {
                throw MoneyError.currencyMismatch(payment.amount.currency.code, liquid.currency.code)
            }
            let dueSeconds = seconds(payment.dueDate)
            guard dueSeconds >= nowSeconds, dueSeconds - nowSeconds <= largePaymentLookaheadSeconds
            else { continue }
            let isLarge = !liquid.isPositive
                || Int128(payment.amount.amountMinor) * Int128(fullScaleBasisPoints)
                    >= Int128(liquid.amountMinor) * Int128(largePaymentLiquidShareBasisPoints)
            guard isLarge else { continue }
            result.append(Insight(
                type: .upcomingLargePayment,
                severity: .attention,
                messageKey: messageKey(.upcomingLargePayment),
                value: payment.amount,
                secondaryValue: liquid,
                basis: "payment \(payment.id): \(minor(payment.amount)) due in "
                    + "\(dueSeconds - nowSeconds)s <= \(largePaymentLookaheadSeconds)s, "
                    + ">= \(largePaymentLiquidShareBasisPoints)bp of liquid \(minor(liquid))"
            ))
        }
        return result
    }

    private static func overdueIncomeInsights(_ context: InsightContext) -> [Insight] {
        let nowSeconds = seconds(context.now)
        return context.expectedEvents.compactMap { event in
            let isOverdue = event.state == .overdue
                || (event.state == .expected && seconds(event.expectedDate) < nowSeconds)
            guard isOverdue else { return nil }
            return Insight(
                type: .expectedIncomeOverdue,
                severity: .attention,
                messageKey: messageKey(.expectedIncomeOverdue),
                value: event.amount,
                basis: "expected event \(event.id): state \(event.state.rawValue), "
                    + "expected at \(seconds(event.expectedDate))s vs now \(nowSeconds)s"
            )
        }
    }

    private static func savingsInsights(_ savings: SavingsPeriodSnapshot) throws -> [Insight] {
        guard savings.target.isPositive else { return [] }
        let delta = try savings.actual.subtracting(savings.target)
        let tolerance = share(of: savings.target, basisPoints: savingsToleranceBasisPoints)
        guard delta.amountMinor.magnitude > tolerance.amountMinor.magnitude else { return [] }
        let missed = delta.isNegative
        return [Insight(
            type: missed ? .savingsTargetMissed : .savingsTargetExceeded,
            severity: missed ? .attention : .info,
            messageKey: messageKey(missed ? .savingsTargetMissed : .savingsTargetExceeded),
            value: savings.actual,
            secondaryValue: savings.target,
            basis: "savings: actual \(minor(savings.actual)) vs target \(minor(savings.target)), "
                + "|delta \(delta.amountMinor)| > \(savingsToleranceBasisPoints)bp = \(minor(tolerance))"
        )]
    }

    private static func runwayInsight(_ context: InsightContext) throws -> Insight? {
        guard
            let liquid = context.liquidBalance,
            let essential = context.monthlyEssentialSpending, essential.isPositive
        else { return nil }
        guard liquid.currency == essential.currency else {
            throw MoneyError.currencyMismatch(liquid.currency.code, essential.currency.code)
        }
        let required = Int128(essential.amountMinor) * Int128(runwayLowMonths)
        guard Int128(liquid.amountMinor) < required else { return nil }
        let hundredths = Int128(max(liquid.amountMinor, 0)) * 100 / Int128(essential.amountMinor)
        return Insight(
            type: .runwayLow,
            severity: .warning,
            messageKey: messageKey(.runwayLow),
            value: liquid,
            secondaryValue: essential,
            basis: "runway: liquid \(minor(liquid)) < \(runwayLowMonths) x essential "
                + "\(minor(essential)) (~\(hundredths) month-hundredths)"
        )
    }

    private static func safeToSpendInsight(_ result: SafeToSpendResult) throws -> Insight? {
        if let shortfall = result.shortfall {
            return Insight(
                type: .safeToSpendLow,
                severity: .warning,
                messageKey: messageKey(.safeToSpendLow),
                value: result.available,
                secondaryValue: shortfall,
                basis: "safeToSpend: reserved exceeds liquid by \(minor(shortfall)), available 0"
            )
        }
        guard
            let liquid = result.breakdown.first(where: { $0.label == .liquidBalance })?.amount,
            liquid.isPositive
        else { return nil }
        guard result.available.currency == liquid.currency else {
            throw MoneyError.currencyMismatch(result.available.currency.code, liquid.currency.code)
        }
        let lhs = Int128(result.available.amountMinor) * Int128(fullScaleBasisPoints)
        let rhs = Int128(liquid.amountMinor) * Int128(safeToSpendLowShareBasisPoints)
        guard lhs < rhs else { return nil }
        return Insight(
            type: .safeToSpendLow,
            severity: .warning,
            messageKey: messageKey(.safeToSpendLow),
            value: result.available,
            secondaryValue: liquid,
            basis: "safeToSpend: available \(minor(result.available)) < "
                + "\(safeToSpendLowShareBasisPoints)bp of liquid \(minor(liquid))"
        )
    }

    private static func currencyDeviationInsights(
        _ comparisons: [PlanningRateComparison]
    ) throws -> [Insight] {
        var result: [Insight] = []
        for pair in comparisons {
            guard
                pair.planning.base == pair.current.base,
                pair.planning.quote == pair.current.quote
            else {
                throw MoneyError.currencyMismatch(
                    "\(pair.planning.base.code)/\(pair.planning.quote.code)",
                    "\(pair.current.base.code)/\(pair.current.quote.code)"
                )
            }
            let commonScale = max(pair.planning.scale, pair.current.scale)
            let plan = normalized(pair.planning, toScale: commonScale)
            let current = normalized(pair.current, toScale: commonScale)
            let deviation = plan > current ? plan - current : current - plan
            let lhs = deviation * Int128(fullScaleBasisPoints)
            let rhs = plan * Int128(currencyDeviationToleranceBasisPoints)
            guard lhs > rhs else { continue }
            result.append(Insight(
                type: .currencyPlanDeviation,
                severity: .attention,
                messageKey: messageKey(.currencyPlanDeviation),
                basis: "rate \(pair.planning.base.code)/\(pair.planning.quote.code): "
                    + "plan \(plan) vs current \(current) (scale \(commonScale)), "
                    + "|delta| > \(currencyDeviationToleranceBasisPoints)bp"
            ))
        }
        return result
    }

    private static func messageKey(_ type: InsightType) -> String {
        "insight.\(type.rawValue)"
    }

    private static func actionKey(_ type: InsightType) -> String {
        "insight.\(type.rawValue).action"
    }

    private static func share(of amount: Money, basisPoints: Int64) -> Money {
        amount.multiplied(byNumerator: basisPoints, denominator: fullScaleBasisPoints)
    }

    private static func seconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded())
    }

    private static func normalized(_ rate: ExchangeRate, toScale scale: Int) -> Int128 {
        var value = Int128(rate.rateScaled)
        for _ in 0..<(scale - rate.scale) { value *= 10 }
        return value
    }

    private static func minor(_ money: Money) -> String {
        "\(money.amountMinor)m \(money.currency.code)"
    }

    private static func canonicalOrder(_ lhs: Insight, _ rhs: Insight) -> Bool {
        if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
        if lhs.type != rhs.type { return lhs.type.sortRank < rhs.type.sortRank }
        return lhs.basis < rhs.basis
    }
}
