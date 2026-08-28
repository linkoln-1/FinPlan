import Foundation

public enum PurchaseImpactError: Error, Equatable, Sendable {
    case nonPositiveAmount
    case missingPlanningRate(base: String, quote: String)
}

public struct PurchaseCandidate: Hashable, Sendable, Codable {
    public let amount: Money
    public let date: Date

    public init(amount: Money, date: Date) {
        self.amount = amount
        self.date = date
    }
}

public enum PurchaseVerdict: String, Sendable, Codable, CaseIterable {
    case safe
    case delaysGoal
    case touchesReserve
    case unaffordable
}

public struct PurchaseImpact: Hashable, Sendable, Codable {
    public let verdict: PurchaseVerdict
    public let remainingSafeToSpend: Money
    public let goalDelayDays: Int?
    public let newCompletionCycle: Int?
    public let newCompletionDate: Date?
    public let affectsNextMilestone: Bool
    public let shortfall: Money?

    public init(
        verdict: PurchaseVerdict,
        remainingSafeToSpend: Money,
        goalDelayDays: Int?,
        newCompletionCycle: Int?,
        newCompletionDate: Date?,
        affectsNextMilestone: Bool,
        shortfall: Money?
    ) {
        self.verdict = verdict
        self.remainingSafeToSpend = remainingSafeToSpend
        self.goalDelayDays = goalDelayDays
        self.newCompletionCycle = newCompletionCycle
        self.newCompletionDate = newCompletionDate
        self.affectsNextMilestone = affectsNextMilestone
        self.shortfall = shortfall
    }
}

public enum PurchaseImpactEngine {
    public static func evaluate(
        purchase: PurchaseCandidate,
        safeToSpend: SafeToSpendInput,
        goalProjection: ProjectionInput,
        planningRates: ManualExchangeRates
    ) throws -> PurchaseImpact {
        guard purchase.amount.isPositive else {
            throw PurchaseImpactError.nonPositiveAmount
        }

        let baseCurrency = safeToSpend.liquidBalance.currency
        let purchaseInBase = Money(
            minor: try convertedMinor(purchase.amount, to: baseCurrency, rates: planningRates),
            currency: baseCurrency
        )

        let current = try SafeToSpendEngine.evaluate(safeToSpend)
        let remaining = try remainingAvailable(after: purchaseInBase, in: safeToSpend)

        if purchaseInBase.amountMinor <= current.available.amountMinor {
            let baseline = try ProjectionEngine.project(goalProjection)
            return PurchaseImpact(
                verdict: .safe,
                remainingSafeToSpend: remaining,
                goalDelayDays: nil,
                newCompletionCycle: baseline.completionCycle,
                newCompletionDate: baseline.completionDate,
                affectsNextMilestone: false,
                shortfall: nil
            )
        }

        if purchaseInBase.amountMinor > safeToSpend.liquidBalance.amountMinor {
            let shortfall = try purchaseInBase.subtracting(safeToSpend.liquidBalance)
            return PurchaseImpact(
                verdict: .unaffordable,
                remainingSafeToSpend: remaining,
                goalDelayDays: nil,
                newCompletionCycle: nil,
                newCompletionDate: nil,
                affectsNextMilestone: false,
                shortfall: shortfall
            )
        }

        let overflow = try purchaseInBase.subtracting(current.available)

        if overflow.amountMinor > safeToSpend.goalAllocatedTotal.amountMinor {
            return PurchaseImpact(
                verdict: .touchesReserve,
                remainingSafeToSpend: remaining,
                goalDelayDays: nil,
                newCompletionCycle: nil,
                newCompletionDate: nil,
                affectsNextMilestone: false,
                shortfall: nil
            )
        }

        let impact = try goalImpact(
            ofOverflow: overflow,
            purchaseDate: purchase.date,
            projection: goalProjection,
            planningRates: planningRates
        )
        return PurchaseImpact(
            verdict: .delaysGoal,
            remainingSafeToSpend: remaining,
            goalDelayDays: impact.delayDays,
            newCompletionCycle: impact.newCompletionCycle,
            newCompletionDate: impact.newCompletionDate,
            affectsNextMilestone: impact.affectsNextMilestone,
            shortfall: nil
        )
    }

    private struct GoalImpact {
        let delayDays: Int?
        let newCompletionCycle: Int?
        let newCompletionDate: Date?
        let affectsNextMilestone: Bool
    }

    private static func goalImpact(
        ofOverflow overflow: Money,
        purchaseDate: Date,
        projection input: ProjectionInput,
        planningRates: ManualExchangeRates
    ) throws -> GoalImpact {
        let goalCurrency = input.target.currency
        let overflowGoalMinor = try convertedMinor(overflow, to: goalCurrency, rates: planningRates)
        let baseline = try ProjectionEngine.project(input)

        guard overflowGoalMinor > 0 else {
            return GoalImpact(
                delayDays: 0,
                newCompletionCycle: baseline.completionCycle,
                newCompletionDate: baseline.completionDate,
                affectsNextMilestone: false
            )
        }

        let withdrawal = PlannedOneTime(
            amount: Money(minor: -overflowGoalMinor, currency: goalCurrency),
            timing: .date(purchaseDate)
        )
        let adjustedInput = ProjectionInput(
            startingAmount: input.startingAmount,
            target: input.target,
            startDate: input.startDate,
            contributions: input.contributions,
            oneTimeEvents: input.oneTimeEvents + [withdrawal],
            planningRates: input.planningRates,
            horizonCycles: input.horizonCycles
        )
        let adjusted = try ProjectionEngine.project(adjustedInput)

        return GoalImpact(
            delayDays: try delayDays(
                overflowGoalMinor: overflowGoalMinor,
                baseline: baseline,
                adjusted: adjusted,
                input: input
            ),
            newCompletionCycle: adjusted.completionCycle,
            newCompletionDate: adjusted.completionDate,
            affectsNextMilestone: isNextMilestoneAffected(baseline: baseline, adjusted: adjusted)
        )
    }

    private static func delayDays(
        overflowGoalMinor: Int64,
        baseline: ProjectionResult,
        adjusted: ProjectionResult,
        input: ProjectionInput
    ) throws -> Int? {
        guard
            let baselineCycle = baseline.completionCycle,
            let baselineDate = baseline.completionDate
        else {
            return nil
        }

        let tailMonthlyMinor = try tailMonthlyRateMinor(of: input, activeAt: baselineDate)
        if tailMonthlyMinor > 0 {
            let wide = Int128(overflowGoalMinor) * Int128(ProjectionEngine.daysPerCycle)
            let divisor = Int128(tailMonthlyMinor)
            return Int((wide + divisor - 1) / divisor)
        }

        guard let adjustedCycle = adjusted.completionCycle else { return nil }
        return (adjustedCycle - baselineCycle) * Int(ProjectionEngine.daysPerCycle)
    }

    private static func tailMonthlyRateMinor(
        of input: ProjectionInput,
        activeAt completionDate: Date
    ) throws -> Int64 {
        var total: Int64 = 0
        for contribution in input.contributions {
            guard case .monthly = contribution.schedule else { continue }
            if let end = contribution.end, end < completionDate { continue }
            total += try convertedMinor(
                contribution.amount,
                to: input.target.currency,
                rates: input.planningRates
            )
        }
        return total
    }

    private static func isNextMilestoneAffected(
        baseline: ProjectionResult,
        adjusted: ProjectionResult
    ) -> Bool {
        let baselineMilestones = baseline.standardPercentMilestones()
        guard let next = baselineMilestones.first(where: { $0.cycleIndex != 0 }) else {
            return false
        }
        guard let match = adjusted.standardPercentMilestones()
            .first(where: { $0.basisPoints == next.basisPoints })
        else {
            return false
        }
        switch (next.cycleIndex, match.cycleIndex) {
        case let (baselineCycle?, adjustedCycle?):
            return adjustedCycle > baselineCycle
        case (nil, _):
            return false
        case (_?, nil):
            return true
        }
    }

    private static func remainingAvailable(
        after purchaseInBase: Money,
        in input: SafeToSpendInput
    ) throws -> Money {
        let reducedInput = SafeToSpendInput(
            liquidBalance: try input.liquidBalance.subtracting(purchaseInBase),
            goalAllocatedTotal: input.goalAllocatedTotal,
            emergencyReserve: input.emergencyReserve,
            upcomingMandatory: input.upcomingMandatory,
            minimumBuffer: input.minimumBuffer
        )
        return try SafeToSpendEngine.evaluate(reducedInput).available
    }

    private static func convertedMinor(
        _ amount: Money,
        to currency: Currency,
        rates: ManualExchangeRates
    ) throws -> Int64 {
        if amount.currency == currency { return amount.amountMinor }
        guard let rate = rates.rate(from: amount.currency, to: currency) else {
            throw PurchaseImpactError.missingPlanningRate(
                base: amount.currency.code,
                quote: currency.code
            )
        }
        return try rate.convert(amount).amountMinor
    }
}
