import Foundation

public enum ProjectionError: Error, Equatable, Sendable {
    case amountOverflow
    case missingPlanningRate(base: String, quote: String)
    case currencyMismatch(expected: String, actual: String)
    case invalidContributionDay(Int)
    case invalidHorizon(Int)
    case nonPositiveCycleCount(Int)
    case nonPositivePlannedRate
}

public struct PlannedContribution: Hashable, Sendable {
    public enum Schedule: Hashable, Sendable {
        case monthly(day: Int)
        case dates([Date])
    }

    public let amount: Money
    public let schedule: Schedule
    public let end: Date?

    public init(amount: Money, schedule: Schedule, end: Date? = nil) {
        precondition(amount.isPositive, "contribution amount must be positive")
        self.amount = amount
        self.schedule = schedule
        self.end = end
    }
}

public struct PlannedOneTime: Hashable, Sendable {
    public enum Timing: Hashable, Sendable {
        case cycleIndex(Int)
        case date(Date)
    }

    public let amount: Money
    public let timing: Timing

    public init(amount: Money, timing: Timing) {
        precondition(!amount.isZero, "one-time amount must be non-zero")
        self.amount = amount
        self.timing = timing
    }
}

public struct ProjectionInput: Sendable {
    public static let defaultHorizonCycles = 600

    public let startingAmount: Money
    public let target: Money
    public let startDate: Date
    public let contributions: [PlannedContribution]
    public let oneTimeEvents: [PlannedOneTime]
    public let planningRates: ManualExchangeRates
    public let horizonCycles: Int

    public init(
        startingAmount: Money,
        target: Money,
        startDate: Date,
        contributions: [PlannedContribution] = [],
        oneTimeEvents: [PlannedOneTime] = [],
        planningRates: ManualExchangeRates = ManualExchangeRates(),
        horizonCycles: Int = ProjectionInput.defaultHorizonCycles
    ) {
        precondition(target.isPositive, "projection target must be positive")
        self.startingAmount = startingAmount
        self.target = target
        self.startDate = startDate
        self.contributions = contributions
        self.oneTimeEvents = oneTimeEvents
        self.planningRates = planningRates
        self.horizonCycles = horizonCycles
    }
}

public struct ProjectionPoint: Hashable, Sendable {
    public let cycleIndex: Int
    public let date: Date
    public let balance: Money

    public init(cycleIndex: Int, date: Date, balance: Money) {
        self.cycleIndex = cycleIndex
        self.date = date
        self.balance = balance
    }
}

public struct ProjectionMilestone: Hashable, Sendable {
    public let threshold: Money
    public let basisPoints: Int?
    public let cycleIndex: Int?
    public let date: Date?

    public var isReached: Bool { cycleIndex != nil }

    public init(threshold: Money, basisPoints: Int? = nil, cycleIndex: Int?, date: Date?) {
        self.threshold = threshold
        self.basisPoints = basisPoints
        self.cycleIndex = cycleIndex
        self.date = date
    }
}

public struct ProjectionResult: Sendable {
    public let target: Money
    public let points: [ProjectionPoint]
    public let completionCycle: Int?
    public let completionDate: Date?
    public var isTargetReached: Bool { completionCycle != nil }
    public let shortfallAtHorizon: Money?

    public init(
        target: Money,
        points: [ProjectionPoint],
        completionCycle: Int?,
        completionDate: Date?,
        shortfallAtHorizon: Money?
    ) {
        self.target = target
        self.points = points
        self.completionCycle = completionCycle
        self.completionDate = completionDate
        self.shortfallAtHorizon = shortfallAtHorizon
    }

    public func milestoneDates(for thresholds: [Money]) throws -> [ProjectionMilestone] {
        try thresholds.map { threshold in
            guard threshold.currency == target.currency else {
                throw ProjectionError.currencyMismatch(
                    expected: target.currency.code,
                    actual: threshold.currency.code
                )
            }
            return firstTouch(of: threshold.amountMinor, threshold: threshold, basisPoints: nil)
        }
    }

    public func standardPercentMilestones() -> [ProjectionMilestone] {
        ProjectionEngine.standardMilestoneBasisPoints.map { bps in
            let threshold = target.multiplied(byNumerator: Int64(bps), denominator: 10_000)
            return firstTouch(of: threshold.amountMinor, threshold: threshold, basisPoints: bps)
        }
    }

    private func firstTouch(of thresholdMinor: Int64, threshold: Money, basisPoints: Int?) -> ProjectionMilestone {
        for point in points where point.balance.amountMinor >= thresholdMinor {
            return ProjectionMilestone(
                threshold: threshold,
                basisPoints: basisPoints,
                cycleIndex: point.cycleIndex,
                date: point.date
            )
        }
        return ProjectionMilestone(threshold: threshold, basisPoints: basisPoints, cycleIndex: nil, date: nil)
    }
}

public struct PlanStatus: Hashable, Sendable {
    public enum Standing: String, Sendable {
        case ahead, onTrack, behind
    }

    public let delta: Money
    public let standing: Standing
    public let timeImpactDays: Int

    public init(delta: Money, standing: Standing, timeImpactDays: Int) {
        self.delta = delta
        self.standing = standing
        self.timeImpactDays = timeImpactDays
    }
}

public enum ProjectionEngine {
    public static let daysPerCycle: Int64 = 30

    public static let standardMilestoneBasisPoints: [Int] = [1_000, 2_500, 5_000, 7_500, 9_000, 10_000]

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public static func project(_ input: ProjectionInput) throws -> ProjectionResult {
        let goalCurrency = input.target.currency
        guard input.startingAmount.currency == goalCurrency else {
            throw ProjectionError.currencyMismatch(
                expected: goalCurrency.code,
                actual: input.startingAmount.currency.code
            )
        }
        guard input.horizonCycles >= 1 else {
            throw ProjectionError.invalidHorizon(input.horizonCycles)
        }

        struct MonthlyStream {
            let convertedMinor: Int64
            let day: Int
            let end: Date?
        }
        var monthlyStreams: [MonthlyStream] = []
        var extrasByCycle: [Int: Int64] = [:]

        for contribution in input.contributions {
            let convertedMinor = try convertOnce(contribution.amount, to: goalCurrency, rates: input.planningRates)
            switch contribution.schedule {
            case .monthly(let day):
                guard (1...31).contains(day) else {
                    throw ProjectionError.invalidContributionDay(day)
                }
                monthlyStreams.append(MonthlyStream(convertedMinor: convertedMinor, day: day, end: contribution.end))
            case .dates(let dates):
                for date in dates {
                    if let end = contribution.end, date > end { continue }
                    guard let cycle = cycleIndex(containing: date, startDate: input.startDate, horizon: input.horizonCycles) else { continue }
                    extrasByCycle[cycle, default: 0] += convertedMinor
                }
            }
        }

        for event in input.oneTimeEvents {
            let convertedMinor = try convertOnce(event.amount, to: goalCurrency, rates: input.planningRates)
            switch event.timing {
            case .cycleIndex(let cycle):
                guard cycle >= 0, cycle <= input.horizonCycles else { continue }
                extrasByCycle[cycle, default: 0] += convertedMinor
            case .date(let date):
                guard let cycle = cycleIndex(containing: date, startDate: input.startDate, horizon: input.horizonCycles) else { continue }
                extrasByCycle[cycle, default: 0] += convertedMinor
            }
        }

        var points: [ProjectionPoint] = []
        points.reserveCapacity(min(input.horizonCycles + 1, 1_024))
        var balance = input.startingAmount
        var completionCycle: Int?
        var completionDate: Date?

        for cycle in 0...input.horizonCycles {
            if cycle > 0 {
                for stream in monthlyStreams {
                    let dueDate = contributionDate(startDate: input.startDate, cycle: cycle, day: stream.day)
                    if let end = stream.end, dueDate > end { continue }
                    balance = try balance.adding(Money(minor: stream.convertedMinor, currency: goalCurrency))
                }
            }
            if let extraMinor = extrasByCycle[cycle] {
                balance = try balance.adding(Money(minor: extraMinor, currency: goalCurrency))
            }

            let date = cycleDate(startDate: input.startDate, cycle: cycle)
            points.append(ProjectionPoint(cycleIndex: cycle, date: date, balance: balance))

            if balance.amountMinor >= input.target.amountMinor {
                completionCycle = cycle
                completionDate = date
                break
            }
        }

        let shortfall: Money?
        if completionCycle == nil {
            shortfall = try input.target.subtracting(balance)
        } else {
            shortfall = nil
        }

        return ProjectionResult(
            target: input.target,
            points: points,
            completionCycle: completionCycle,
            completionDate: completionDate,
            shortfallAtHorizon: shortfall
        )
    }

    public static func requiredMonthlyContribution(
        startingAmount: Money,
        target: Money,
        inCycles cycles: Int,
        oneTimeEvents: [PlannedOneTime] = [],
        startDate: Date = Date(timeIntervalSince1970: 0),
        planningRates: ManualExchangeRates = ManualExchangeRates()
    ) throws -> Money {
        let goalCurrency = target.currency
        guard startingAmount.currency == goalCurrency else {
            throw ProjectionError.currencyMismatch(
                expected: goalCurrency.code,
                actual: startingAmount.currency.code
            )
        }
        guard cycles >= 1 else {
            throw ProjectionError.nonPositiveCycleCount(cycles)
        }

        var oneTimeTotal: Int128 = 0
        for event in oneTimeEvents {
            let convertedMinor = try convertOnce(event.amount, to: goalCurrency, rates: planningRates)
            switch event.timing {
            case .cycleIndex(let cycle):
                guard cycle >= 0, cycle <= cycles else { continue }
                oneTimeTotal += Int128(convertedMinor)
            case .date(let date):
                guard cycleIndex(containing: date, startDate: startDate, horizon: cycles) != nil else { continue }
                oneTimeTotal += Int128(convertedMinor)
            }
        }

        let needed = Int128(target.amountMinor) - Int128(startingAmount.amountMinor) - oneTimeTotal
        guard needed > 0 else { return .zero(goalCurrency) }

        let required = (needed + Int128(cycles) - 1) / Int128(cycles)
        guard let requiredMinor = Int64(exactly: required) else { throw ProjectionError.amountOverflow }
        return Money(minor: requiredMinor, currency: goalCurrency)
    }

    public static func requiredMonthlyContribution(
        startingAmount: Money,
        target: Money,
        by desiredDate: Date,
        startDate: Date,
        oneTimeEvents: [PlannedOneTime] = [],
        planningRates: ManualExchangeRates = ManualExchangeRates()
    ) throws -> Money {
        let months = utcCalendar.dateComponents([.month], from: startDate, to: desiredDate).month ?? 0
        guard months >= 1 else {
            throw ProjectionError.nonPositiveCycleCount(months)
        }
        return try requiredMonthlyContribution(
            startingAmount: startingAmount,
            target: target,
            inCycles: months,
            oneTimeEvents: oneTimeEvents,
            startDate: startDate,
            planningRates: planningRates
        )
    }

    public static func planStatus(
        actualBalance: Money,
        plannedBalance: Money,
        monthlyPlannedContribution: Money
    ) throws -> PlanStatus {
        let delta = try actualBalance.subtracting(plannedBalance)
        guard monthlyPlannedContribution.currency == delta.currency else {
            throw ProjectionError.currencyMismatch(
                expected: delta.currency.code,
                actual: monthlyPlannedContribution.currency.code
            )
        }
        guard monthlyPlannedContribution.isPositive else {
            throw ProjectionError.nonPositivePlannedRate
        }

        let wide = Int128(delta.amountMinor) * Int128(daysPerCycle)
        let days = Int(wide / Int128(monthlyPlannedContribution.amountMinor))

        let standing: PlanStatus.Standing
        if delta.isPositive {
            standing = .ahead
        } else if delta.isNegative {
            standing = .behind
        } else {
            standing = .onTrack
        }
        return PlanStatus(delta: delta, standing: standing, timeImpactDays: days)
    }

    public static func recoveryPlan(shortfall: Money, remainingCycles: Int) throws -> Money {
        guard remainingCycles >= 1 else {
            throw ProjectionError.nonPositiveCycleCount(remainingCycles)
        }
        guard shortfall.isPositive else { return .zero(shortfall.currency) }
        let extra = (Int128(shortfall.amountMinor) + Int128(remainingCycles) - 1) / Int128(remainingCycles)
        return Money(minor: Int64(extra), currency: shortfall.currency)
    }

    private static func convertOnce(
        _ amount: Money,
        to goalCurrency: Currency,
        rates: ManualExchangeRates
    ) throws -> Int64 {
        if amount.currency == goalCurrency { return amount.amountMinor }
        guard let rate = rates.rate(from: amount.currency, to: goalCurrency) else {
            throw ProjectionError.missingPlanningRate(
                base: amount.currency.code,
                quote: goalCurrency.code
            )
        }
        return try rate.convert(amount).amountMinor
    }

    static func cycleDate(startDate: Date, cycle: Int) -> Date {
        guard cycle > 0 else { return startDate }
        return utcCalendar.date(byAdding: .month, value: cycle, to: startDate) ?? startDate
    }

    static func contributionDate(startDate: Date, cycle: Int, day: Int) -> Date {
        let anchor = cycleDate(startDate: startDate, cycle: cycle)
        var components = utcCalendar.dateComponents([.year, .month], from: anchor)
        let daysInMonth = utcCalendar.range(of: .day, in: .month, for: anchor)?.count ?? 28
        components.day = min(day, daysInMonth)
        return utcCalendar.date(from: components) ?? anchor
    }

    static func cycleIndex(containing date: Date, startDate: Date, horizon: Int) -> Int? {
        if date <= startDate { return 0 }
        let wholeMonths = utcCalendar.dateComponents([.month], from: startDate, to: date).month ?? 0
        var cycle = max(wholeMonths, 0)
        while cycle <= horizon, cycleDate(startDate: startDate, cycle: cycle) < date {
            cycle += 1
        }
        return cycle <= horizon ? cycle : nil
    }
}
