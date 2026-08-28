import Foundation

public enum BudgetPace: String, Hashable, Sendable, Codable {
    case onTrack
    case ahead
    case hot
}

public struct BudgetStatus: Hashable, Sendable {
    public let spent: Money
    public let remaining: Money
    public let fractionUsedBasisPoints: Int
    public let periodElapsedBasisPoints: Int
    public let pace: BudgetPace

    public init(
        spent: Money,
        remaining: Money,
        fractionUsedBasisPoints: Int,
        periodElapsedBasisPoints: Int,
        pace: BudgetPace
    ) {
        self.spent = spent
        self.remaining = remaining
        self.fractionUsedBasisPoints = fractionUsedBasisPoints
        self.periodElapsedBasisPoints = periodElapsedBasisPoints
        self.pace = pace
    }
}

public enum BudgetReleaseDestination: String, Hashable, Sendable, Codable {
    case goal
    case freeCash
}

public struct BudgetRolloverOutcome: Hashable, Sendable {
    public let nextCarriedOverMinor: Int64
    public let released: Money?
    public let releaseDestination: BudgetReleaseDestination?

    public init(
        nextCarriedOverMinor: Int64,
        released: Money? = nil,
        releaseDestination: BudgetReleaseDestination? = nil
    ) {
        self.nextCarriedOverMinor = nextCarriedOverMinor
        self.released = released
        self.releaseDestination = releaseDestination
    }
}

public enum BudgetEngine {
    public static let fullScaleBasisPoints = 10_000
    public static let defaultPaceToleranceBasisPoints = 500

    public static func status(
        budget: Budget,
        expenses: [TransactionRecord],
        period: DateInterval,
        now: Date,
        paceToleranceBasisPoints: Int = defaultPaceToleranceBasisPoints
    ) throws -> BudgetStatus {
        let spent = try completedSpending(for: budget, in: expenses, during: period)
        let carried = Money(minor: budget.carriedOverMinor, currency: budget.amount.currency)
        let available = try budget.amount.adding(carried)
        let remaining = try available.subtracting(spent)
        let fractionUsed = fractionBasisPoints(
            spentMinor: spent.amountMinor,
            availableMinor: available.amountMinor
        )
        let elapsed = elapsedBasisPoints(period: period, now: now)
        return BudgetStatus(
            spent: spent,
            remaining: remaining,
            fractionUsedBasisPoints: fractionUsed,
            periodElapsedBasisPoints: elapsed,
            pace: pace(
                spentBasisPoints: fractionUsed,
                elapsedBasisPoints: elapsed,
                toleranceBasisPoints: paceToleranceBasisPoints
            )
        )
    }

    public static func completedSpending(
        for budget: Budget,
        in expenses: [TransactionRecord],
        during period: DateInterval
    ) throws -> Money {
        var total = Money.zero(budget.amount.currency)
        for record in expenses {
            guard record.kind == .expense,
                  record.status.affectsActualBalance,
                  record.goalID == nil,
                  record.date >= period.start,
                  record.date < period.end
            else { continue }
            if record.splits.isEmpty {
                if record.categoryID == budget.categoryID {
                    total = try total.adding(record.amount)
                }
            } else {
                for split in record.splits where split.categoryID == budget.categoryID {
                    total = try total.adding(split.amount)
                }
            }
        }
        return total
    }

    public static func pace(
        spentBasisPoints: Int,
        elapsedBasisPoints: Int,
        toleranceBasisPoints: Int = defaultPaceToleranceBasisPoints
    ) -> BudgetPace {
        if spentBasisPoints > elapsedBasisPoints + toleranceBasisPoints { return .hot }
        if spentBasisPoints < elapsedBasisPoints - toleranceBasisPoints { return .ahead }
        return .onTrack
    }

    public static func rollover(
        budget: Budget,
        spent: Money,
        policy: BudgetRolloverPolicy? = nil
    ) throws -> BudgetRolloverOutcome {
        guard spent.currency == budget.amount.currency else {
            throw MoneyError.currencyMismatch(spent.currency.code, budget.amount.currency.code)
        }
        let carried = Money(minor: budget.carriedOverMinor, currency: budget.amount.currency)
        let unused = try budget.amount.adding(carried).subtracting(spent)
        switch policy ?? budget.rollover {
        case .expires:
            return BudgetRolloverOutcome(nextCarriedOverMinor: 0)
        case .rollsOver:
            return BudgetRolloverOutcome(nextCarriedOverMinor: max(0, unused.amountMinor))
        case .toGoal:
            return releaseOutcome(unused: unused, destination: .goal)
        case .toFreeCash:
            return releaseOutcome(unused: unused, destination: .freeCash)
        }
    }

    private static func releaseOutcome(
        unused: Money,
        destination: BudgetReleaseDestination
    ) -> BudgetRolloverOutcome {
        guard unused.isPositive else {
            return BudgetRolloverOutcome(nextCarriedOverMinor: 0)
        }
        return BudgetRolloverOutcome(
            nextCarriedOverMinor: 0,
            released: unused,
            releaseDestination: destination
        )
    }

    static func fractionBasisPoints(spentMinor: Int64, availableMinor: Int64) -> Int {
        guard availableMinor > 0 else {
            return spentMinor > 0 ? fullScaleBasisPoints : 0
        }
        let wide = Int128(spentMinor) * Int128(fullScaleBasisPoints)
        return Int(Money.divideRoundingHalfAwayFromZero(wide, by: Int128(availableMinor)))
    }

    static func elapsedBasisPoints(period: DateInterval, now: Date) -> Int {
        let startSeconds = Int64(period.start.timeIntervalSince1970.rounded())
        let endSeconds = Int64(period.end.timeIntervalSince1970.rounded())
        let nowSeconds = Int64(now.timeIntervalSince1970.rounded())
        guard endSeconds > startSeconds else {
            return nowSeconds >= endSeconds ? fullScaleBasisPoints : 0
        }
        if nowSeconds <= startSeconds { return 0 }
        if nowSeconds >= endSeconds { return fullScaleBasisPoints }
        let widened = Int128(nowSeconds - startSeconds) * Int128(fullScaleBasisPoints)
        return Int(Money.divideRoundingHalfAwayFromZero(widened, by: Int128(endSeconds - startSeconds)))
    }
}
