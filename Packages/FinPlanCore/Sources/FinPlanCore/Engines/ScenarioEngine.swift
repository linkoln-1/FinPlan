import Foundation

public enum ScenarioError: Error, Equatable, Sendable {
    case unknownIncomeSource(UUID)
    case invalidShareBasisPoints(Int)
    case invalidSavingsPercent(Int)
    case negativeSavingsAmount
    case nonPositiveTarget
    case currencyMismatch(expected: String, actual: String)
    case invalidPlanningRateOverride
    case missingPlanningRate(base: String, quote: String)
    case zeroOneTimeEventAmount
    case targetDateBeforeStart
}

public struct ScenarioOneTime: Hashable, Sendable, Codable {
    public enum Timing: Hashable, Sendable, Codable {
        case cycleIndex(Int)
        case date(Date)
    }

    public var amount: Money
    public var timing: Timing

    public init(amount: Money, timing: Timing) {
        self.amount = amount
        self.timing = timing
    }

    func plannedOneTime() throws -> PlannedOneTime {
        guard !amount.isZero else { throw ScenarioError.zeroOneTimeEventAmount }
        switch timing {
        case .cycleIndex(let index):
            return PlannedOneTime(amount: amount, timing: .cycleIndex(index))
        case .date(let date):
            return PlannedOneTime(amount: amount, timing: .date(date))
        }
    }
}

public enum ScenarioRateOverride: Hashable, Sendable, Codable {
    case rate(ExchangeRate)
    case decimalString(base: Currency, quote: Currency, value: String)

    func resolvedRate() -> ExchangeRate? {
        switch self {
        case .rate(let rate):
            return rate
        case .decimalString(let base, let quote, let value):
            return ExchangeRate(base: base, quote: quote, decimalString: value)
        }
    }
}

public struct ScenarioOverrides: Hashable, Sendable, Codable {
    public var incomeShareBps: [UUID: Int]?
    public var monthlySavingsAmount: Money?
    public var savingsPercentBps: Int?
    public var planningRate: ScenarioRateOverride?
    public var extraOneTimeEvents: [ScenarioOneTime]?
    public var targetAmount: Money?
    public var targetDate: Date?
    public var monthlyExpenseDelta: Money?

    public init(
        incomeShareBps: [UUID: Int]? = nil,
        monthlySavingsAmount: Money? = nil,
        savingsPercentBps: Int? = nil,
        planningRate: ScenarioRateOverride? = nil,
        extraOneTimeEvents: [ScenarioOneTime]? = nil,
        targetAmount: Money? = nil,
        targetDate: Date? = nil,
        monthlyExpenseDelta: Money? = nil
    ) {
        self.incomeShareBps = incomeShareBps
        self.monthlySavingsAmount = monthlySavingsAmount
        self.savingsPercentBps = savingsPercentBps
        self.planningRate = planningRate
        self.extraOneTimeEvents = extraOneTimeEvents
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.monthlyExpenseDelta = monthlyExpenseDelta
    }
}

public struct Scenario: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var overrides: ScenarioOverrides

    public init(id: UUID = UUID(), name: String, overrides: ScenarioOverrides = ScenarioOverrides()) {
        self.id = id
        self.name = name
        self.overrides = overrides
    }
}

public struct ScenarioBasePlan: Hashable, Sendable, Codable {
    public var startingAmount: Money
    public var targetAmount: Money
    public var targetDate: Date?
    public var startDate: Date
    public var incomeSources: [IncomeSource]
    public var monthlySavings: Money
    public var savingsDay: Int
    public var oneTimeEvents: [ScenarioOneTime]
    public var planningRates: ManualExchangeRates
    public var horizonCycles: Int
    public var baselineMonthlyExpenses: Money?

    public init(
        startingAmount: Money,
        targetAmount: Money,
        targetDate: Date? = nil,
        startDate: Date,
        incomeSources: [IncomeSource] = [],
        monthlySavings: Money,
        savingsDay: Int = 1,
        oneTimeEvents: [ScenarioOneTime] = [],
        planningRates: ManualExchangeRates = ManualExchangeRates(),
        horizonCycles: Int = ProjectionInput.defaultHorizonCycles,
        baselineMonthlyExpenses: Money? = nil
    ) {
        precondition(targetAmount.isPositive, "base plan target must be positive")
        precondition(!monthlySavings.isNegative, "base plan savings must not be negative")
        precondition((1...31).contains(savingsDay), "savings day must be 1...31")
        self.startingAmount = startingAmount
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.startDate = startDate
        self.incomeSources = incomeSources
        self.monthlySavings = monthlySavings
        self.savingsDay = savingsDay
        self.oneTimeEvents = oneTimeEvents
        self.planningRates = planningRates
        self.horizonCycles = horizonCycles
        self.baselineMonthlyExpenses = baselineMonthlyExpenses
    }
}

public struct ScenarioOutcome: Hashable, Sendable, Codable {
    public let monthlyContribution: Money
    public let completionCycle: Int?
    public let completionDate: Date?
    public let totalProjectedIncome: Money
    public let freeMonthly: Money

    public init(
        monthlyContribution: Money,
        completionCycle: Int?,
        completionDate: Date?,
        totalProjectedIncome: Money,
        freeMonthly: Money
    ) {
        self.monthlyContribution = monthlyContribution
        self.completionCycle = completionCycle
        self.completionDate = completionDate
        self.totalProjectedIncome = totalProjectedIncome
        self.freeMonthly = freeMonthly
    }
}

public struct ScenarioComparison: Hashable, Sendable, Codable {
    public let base: ScenarioOutcome
    public let scenario: ScenarioOutcome

    public init(base: ScenarioOutcome, scenario: ScenarioOutcome) {
        self.base = base
        self.scenario = scenario
    }

    public var cyclesSaved: Int? {
        guard let baseCycle = base.completionCycle,
              let scenarioCycle = scenario.completionCycle else { return nil }
        return baseCycle - scenarioCycle
    }

    public var contributionDelta: Money? {
        try? scenario.monthlyContribution.subtracting(base.monthlyContribution)
    }
}

public enum ScenarioEngine {
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public static func apply(
        _ overrides: ScenarioOverrides,
        to base: ScenarioBasePlan
    ) throws -> ProjectionInput {
        try derive(overrides, base: base).input
    }

    public static func apply(_ scenario: Scenario, to base: ScenarioBasePlan) throws -> ProjectionInput {
        try apply(scenario.overrides, to: base)
    }

    public static func compare(
        base: ScenarioBasePlan,
        scenario: Scenario
    ) throws -> ScenarioComparison {
        let baseLeg = try derive(ScenarioOverrides(), base: base)
        let scenarioLeg = try derive(scenario.overrides, base: base)
        return ScenarioComparison(
            base: try outcome(of: baseLeg),
            scenario: try outcome(of: scenarioLeg)
        )
    }

    struct DerivedPlan {
        let input: ProjectionInput
        let monthlyContribution: Money
        let totalProjectedIncome: Money
        let freeMonthly: Money
    }

    static func derive(_ overrides: ScenarioOverrides, base: ScenarioBasePlan) throws -> DerivedPlan {
        let rates = try effectiveRates(base: base, overrides: overrides)
        let sources = try effectiveSources(base: base, overrides: overrides)

        let savingsCurrency = overrides.monthlySavingsAmount?.currency ?? base.monthlySavings.currency

        var totalIncome = Money.zero(savingsCurrency)
        for source in sources where source.isActive {
            let converted = try convert(source.personalAmount, to: savingsCurrency, rates: rates)
            totalIncome = try totalIncome.adding(converted)
        }

        let plannedSavings: Money
        if let amount = overrides.monthlySavingsAmount {
            guard !amount.isNegative else { throw ScenarioError.negativeSavingsAmount }
            plannedSavings = amount
        } else if let bps = overrides.savingsPercentBps {
            guard (0...10_000).contains(bps) else { throw ScenarioError.invalidSavingsPercent(bps) }
            plannedSavings = totalIncome.multiplied(byNumerator: Int64(bps), denominator: 10_000)
        } else {
            plannedSavings = base.monthlySavings
        }

        var contribution = plannedSavings
        if let delta = overrides.monthlyExpenseDelta {
            let converted = try convert(delta, to: savingsCurrency, rates: rates)
            contribution = try contribution.subtracting(converted)
            if contribution.isNegative { contribution = .zero(savingsCurrency) }
        }

        let target = overrides.targetAmount ?? base.targetAmount
        guard target.isPositive else { throw ScenarioError.nonPositiveTarget }
        guard target.currency == base.startingAmount.currency else {
            throw ScenarioError.currencyMismatch(
                expected: base.startingAmount.currency.code,
                actual: target.currency.code
            )
        }

        var horizon = base.horizonCycles
        if let targetDate = overrides.targetDate ?? base.targetDate {
            let months = utcCalendar.dateComponents([.month], from: base.startDate, to: targetDate).month ?? 0
            guard months >= 1 else { throw ScenarioError.targetDateBeforeStart }
            horizon = min(horizon, months)
        }

        var contributions: [PlannedContribution] = []
        if contribution.isPositive {
            contributions.append(
                PlannedContribution(amount: contribution, schedule: .monthly(day: base.savingsDay))
            )
        }
        let oneTimes = try (base.oneTimeEvents + (overrides.extraOneTimeEvents ?? []))
            .map { try $0.plannedOneTime() }

        let input = ProjectionInput(
            startingAmount: base.startingAmount,
            target: target,
            startDate: base.startDate,
            contributions: contributions,
            oneTimeEvents: oneTimes,
            planningRates: rates,
            horizonCycles: horizon
        )
        var freeMonthly = try totalIncome.subtracting(contribution)
        if let baseline = base.baselineMonthlyExpenses {
            freeMonthly = try freeMonthly.subtracting(convert(baseline, to: savingsCurrency, rates: rates))
        }
        if let delta = overrides.monthlyExpenseDelta {
            freeMonthly = try freeMonthly.subtracting(convert(delta, to: savingsCurrency, rates: rates))
        }
        return DerivedPlan(
            input: input,
            monthlyContribution: contribution,
            totalProjectedIncome: totalIncome,
            freeMonthly: freeMonthly
        )
    }

    private static func effectiveRates(
        base: ScenarioBasePlan,
        overrides: ScenarioOverrides
    ) throws -> ManualExchangeRates {
        guard let rateOverride = overrides.planningRate else { return base.planningRates }
        guard let resolved = rateOverride.resolvedRate() else {
            throw ScenarioError.invalidPlanningRateOverride
        }
        let kept = base.planningRates.rates.filter { !coversSamePair($0, resolved) }
        return ManualExchangeRates(rates: kept + [resolved])
    }

    private static func coversSamePair(_ lhs: ExchangeRate, _ rhs: ExchangeRate) -> Bool {
        (lhs.base == rhs.base && lhs.quote == rhs.quote)
            || (lhs.base == rhs.quote && lhs.quote == rhs.base)
    }

    private static func effectiveSources(
        base: ScenarioBasePlan,
        overrides: ScenarioOverrides
    ) throws -> [IncomeSource] {
        guard let shareOverrides = overrides.incomeShareBps, !shareOverrides.isEmpty else {
            return base.incomeSources
        }
        for (sourceID, bps) in shareOverrides {
            guard (0...10_000).contains(bps) else {
                throw ScenarioError.invalidShareBasisPoints(bps)
            }
            guard base.incomeSources.contains(where: { $0.id == sourceID }) else {
                throw ScenarioError.unknownIncomeSource(sourceID)
            }
        }
        return base.incomeSources.map { source in
            guard let bps = shareOverrides[source.id] else { return source }
            var updated = source
            updated.share = .percentageBasisPoints(bps)
            return updated
        }
    }

    private static func convert(
        _ amount: Money,
        to currency: Currency,
        rates: ManualExchangeRates
    ) throws -> Money {
        if amount.currency == currency { return amount }
        guard let rate = rates.rate(from: amount.currency, to: currency) else {
            throw ScenarioError.missingPlanningRate(
                base: amount.currency.code,
                quote: currency.code
            )
        }
        return try rate.convert(amount)
    }

    private static func outcome(of leg: DerivedPlan) throws -> ScenarioOutcome {
        let result = try ProjectionEngine.project(leg.input)
        return ScenarioOutcome(
            monthlyContribution: leg.monthlyContribution,
            completionCycle: result.completionCycle,
            completionDate: result.completionDate,
            totalProjectedIncome: leg.totalProjectedIncome,
            freeMonthly: leg.freeMonthly
        )
    }
}
