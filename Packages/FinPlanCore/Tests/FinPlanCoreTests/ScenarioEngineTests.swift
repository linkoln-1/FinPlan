import Testing
import Foundation
@testable import FinPlanCore

@Suite("ScenarioEngine")
struct ScenarioEngineTests {
    private let startDate = Date(timeIntervalSince1970: 1_767_225_600)
    private let august2026 = Date(timeIntervalSince1970: 1_785_542_400)
    private let september2026 = Date(timeIntervalSince1970: 1_788_220_800)
    private let december2026 = Date(timeIntervalSince1970: 1_796_083_200)

    private let sourceAID = UUID(uuidString: "AAAAAAAA-1111-1111-1111-111111111111")!
    private let sourceBID = UUID(uuidString: "BBBBBBBB-2222-2222-2222-222222222222")!

    private var basePlan: ScenarioBasePlan {
        ScenarioBasePlan(
            startingAmount: Money(minor: 85_000_000, currency: .rub),
            targetAmount: Money(minor: 600_000_000, currency: .rub),
            startDate: startDate,
            incomeSources: [
                IncomeSource(
                    id: sourceAID,
                    name: "Source A",
                    grossAmount: Money(minor: 375_000, currency: .usd),
                    share: .percentageBasisPoints(5_000)
                ),
                IncomeSource(
                    id: sourceBID,
                    name: "Source B",
                    grossAmount: Money(minor: 250_000, currency: .usd),
                    share: .percentageBasisPoints(10_000)
                ),
            ],
            monthlySavings: Money(minor: 400_000, currency: .usd),
            savingsDay: 1,
            oneTimeEvents: [
                ScenarioOneTime(
                    amount: Money(minor: 169_500_000, currency: .rub),
                    timing: .cycleIndex(6)
                )
            ],
            planningRates: ManualExchangeRates(rates: [
                ExchangeRate(base: .usd, quote: .rub, decimalString: "84.282")!
            ]),
            horizonCycles: 600
        )
    }

    private var referenceScenario: Scenario {
        Scenario(
            name: "Save everything",
            overrides: ScenarioOverrides(
                incomeShareBps: [sourceAID: 10_000],
                monthlySavingsAmount: Money(minor: 625_000, currency: .usd)
            )
        )
    }

    @Test("reference comparison: base completes cycle 11, scenario cycle 7")
    func referenceComparison() throws {
        let plan = basePlan

        let comparison = try ScenarioEngine.compare(base: plan, scenario: referenceScenario)

        #expect(comparison.base.completionCycle == 11)
        #expect(comparison.base.completionDate == december2026)
        #expect(comparison.base.monthlyContribution.amountMinor == 400_000)
        #expect(comparison.base.totalProjectedIncome.amountMinor == 437_500)
        #expect(comparison.base.freeMonthly.amountMinor == 37_500)

        #expect(comparison.scenario.completionCycle == 7)
        #expect(comparison.scenario.completionDate == august2026)
        #expect(comparison.scenario.monthlyContribution.amountMinor == 625_000)
        #expect(comparison.scenario.totalProjectedIncome.amountMinor == 625_000)
        #expect(comparison.scenario.freeMonthly.isZero)

        #expect(comparison.cyclesSaved == 4)
        #expect(comparison.contributionDelta?.amountMinor == 225_000)
    }

    @Test("base plan value unchanged after scenario apply + project; still yields cycle 11")
    func baseUntouchedAfterScenarioProjection() throws {
        let plan = basePlan
        let snapshot = plan

        let scenarioInput = try ScenarioEngine.apply(referenceScenario, to: plan)
        let scenarioResult = try ProjectionEngine.project(scenarioInput)
        #expect(scenarioResult.completionCycle == 7)

        #expect(plan == snapshot)

        let baseInput = try ScenarioEngine.apply(ScenarioOverrides(), to: plan)
        let baseResult = try ProjectionEngine.project(baseInput)
        #expect(baseResult.completionCycle == 11)
        #expect(baseResult.completionDate == december2026)
    }

    @Test("empty overrides are the identity derivation")
    func emptyOverridesIdentity() throws {
        let input = try ScenarioEngine.apply(ScenarioOverrides(), to: basePlan)

        #expect(input.startingAmount.amountMinor == 85_000_000)
        #expect(input.target.amountMinor == 600_000_000)
        #expect(input.startDate == startDate)
        #expect(input.contributions.count == 1)
        #expect(input.contributions[0].amount.amountMinor == 400_000)
        #expect(input.oneTimeEvents.count == 1)
        #expect(input.horizonCycles == 600)

        let result = try ProjectionEngine.project(input)
        let perCycle = result.points[1].balance.amountMinor - result.points[0].balance.amountMinor
        #expect(perCycle == 33_712_800)
        #expect(result.completionCycle == 11)
    }

    @Test("planning rate override changes the converted contribution and completion")
    func rateOverrideChangesContribution() throws {
        let scenario = Scenario(
            name: "Rate 100",
            overrides: ScenarioOverrides(
                planningRate: .decimalString(base: .usd, quote: .rub, value: "100")
            )
        )

        let comparison = try ScenarioEngine.compare(base: basePlan, scenario: scenario)
        let scenarioInput = try ScenarioEngine.apply(scenario, to: basePlan)
        let scenarioResult = try ProjectionEngine.project(scenarioInput)

        let perCycle = scenarioResult.points[1].balance.amountMinor
            - scenarioResult.points[0].balance.amountMinor
        #expect(perCycle == 40_000_000)
        #expect(scenarioResult.completionCycle == 9)
        #expect(comparison.scenario.completionCycle == 9)

        #expect(comparison.base.completionCycle == 11)
    }

    @Test("rate override as a ready ExchangeRate value")
    func rateOverrideAsExchangeRate() throws {
        let rate = ExchangeRate(base: .usd, quote: .rub, decimalString: "100")!
        let scenario = Scenario(name: "Rate value", overrides: ScenarioOverrides(planningRate: .rate(rate)))

        let result = try ProjectionEngine.project(try ScenarioEngine.apply(scenario, to: basePlan))

        #expect(result.completionCycle == 9)
    }

    @Test("target amount override moves completion; base target untouched")
    func targetAmountOverride() throws {
        let scenario = Scenario(
            name: "Smaller goal",
            overrides: ScenarioOverrides(targetAmount: Money(minor: 300_000_000, currency: .rub))
        )

        let comparison = try ScenarioEngine.compare(base: basePlan, scenario: scenario)

        #expect(comparison.scenario.completionCycle == 6)
        #expect(comparison.base.completionCycle == 11)
    }

    @Test("target date override bounds the horizon: not reached by September")
    func targetDateOverrideBoundsHorizon() throws {
        let scenario = Scenario(
            name: "By September",
            overrides: ScenarioOverrides(targetDate: september2026)
        )

        let input = try ScenarioEngine.apply(scenario, to: basePlan)
        let result = try ProjectionEngine.project(input)

        #expect(input.horizonCycles == 8)
        #expect(result.completionCycle == nil)
        #expect(result.shortfallAtHorizon?.amountMinor == 75_797_600)
    }

    @Test("savings percent of personal income, exact basis-point math")
    func savingsPercentOverride() throws {
        let scenario = Scenario(name: "Half income", overrides: ScenarioOverrides(savingsPercentBps: 5_000))

        let comparison = try ScenarioEngine.compare(base: basePlan, scenario: scenario)

        #expect(comparison.scenario.monthlyContribution.amountMinor == 218_750)
        #expect(comparison.scenario.freeMonthly.amountMinor == 218_750)
    }

    @Test("share override 100% + save 100% of income equals the reference scenario")
    func shareAndPercentComposeToReference() throws {
        let scenario = Scenario(
            name: "All in",
            overrides: ScenarioOverrides(
                incomeShareBps: [sourceAID: 10_000],
                savingsPercentBps: 10_000
            )
        )

        let comparison = try ScenarioEngine.compare(base: basePlan, scenario: scenario)

        #expect(comparison.scenario.monthlyContribution.amountMinor == 625_000)
        #expect(comparison.scenario.completionCycle == 7)
        #expect(comparison.scenario.freeMonthly.isZero)
    }

    @Test("share override replaces a fixedAmount share")
    func shareOverrideReplacesFixedAmountShare() throws {
        var plan = basePlan
        plan.incomeSources[1].share = .fixedAmount(Money(minor: 100_000, currency: .usd))
        let scenario = Scenario(
            name: "Full B",
            overrides: ScenarioOverrides(incomeShareBps: [sourceBID: 10_000])
        )

        let comparison = try ScenarioEngine.compare(base: plan, scenario: scenario)

        #expect(comparison.base.totalProjectedIncome.amountMinor == 287_500)
        #expect(comparison.scenario.totalProjectedIncome.amountMinor == 437_500)
    }

    @Test("positive expense delta reduces the contribution one-for-one")
    func expenseDeltaReducesContribution() throws {
        let scenario = Scenario(
            name: "Rent up",
            overrides: ScenarioOverrides(monthlyExpenseDelta: Money(minor: 50_000, currency: .usd))
        )

        let comparison = try ScenarioEngine.compare(base: basePlan, scenario: scenario)

        #expect(comparison.scenario.monthlyContribution.amountMinor == 350_000)
        #expect(comparison.scenario.completionCycle == 12)
        #expect(comparison.base.completionCycle == 11)
    }

    @Test("expense delta exceeding savings clamps the contribution at zero")
    func expenseDeltaClampsAtZero() throws {
        let scenario = Scenario(
            name: "Everything burns",
            overrides: ScenarioOverrides(monthlyExpenseDelta: Money(minor: 1_000_000, currency: .usd))
        )

        let comparison = try ScenarioEngine.compare(base: basePlan, scenario: scenario)
        let result = try ProjectionEngine.project(try ScenarioEngine.apply(scenario, to: basePlan))

        #expect(comparison.scenario.monthlyContribution.isZero)
        #expect(comparison.scenario.completionCycle == nil)
        #expect(result.shortfallAtHorizon?.amountMinor == 345_500_000)
        #expect(comparison.scenario.freeMonthly.amountMinor == 437_500 - 1_000_000)
    }

    @Test("extra one-time event accelerates completion")
    func extraOneTimeEvent() throws {
        let scenario = Scenario(
            name: "Bonus",
            overrides: ScenarioOverrides(extraOneTimeEvents: [
                ScenarioOneTime(amount: Money(minor: 100_000_000, currency: .rub), timing: .cycleIndex(1))
            ])
        )

        let comparison = try ScenarioEngine.compare(base: basePlan, scenario: scenario)

        #expect(comparison.scenario.completionCycle == 8)
        #expect(comparison.base.completionCycle == 11)
    }

    @Test("overrides serialize and decode bit-for-bit (Codable round-trip)")
    func overridesCodableRoundTrip() throws {
        let overrides = ScenarioOverrides(
            incomeShareBps: [sourceAID: 10_000, sourceBID: 2_500],
            monthlySavingsAmount: Money(minor: 625_000, currency: .usd),
            savingsPercentBps: 7_500,
            planningRate: .decimalString(base: .usd, quote: .rub, value: "84.282"),
            extraOneTimeEvents: [
                ScenarioOneTime(amount: Money(minor: 100_000_000, currency: .rub), timing: .cycleIndex(3)),
                ScenarioOneTime(amount: Money(minor: -5_000_000, currency: .rub), timing: .date(august2026)),
            ],
            targetAmount: Money(minor: 300_000_000, currency: .rub),
            targetDate: december2026,
            monthlyExpenseDelta: Money(minor: 50_000, currency: .usd)
        )
        let scenario = Scenario(
            id: UUID(uuidString: "CCCCCCCC-3333-3333-3333-333333333333")!,
            name: "Round trip",
            overrides: overrides
        )

        let decodedOverrides = try JSONDecoder().decode(
            ScenarioOverrides.self,
            from: JSONEncoder().encode(overrides)
        )
        let decodedScenario = try JSONDecoder().decode(
            Scenario.self,
            from: JSONEncoder().encode(scenario)
        )

        #expect(decodedOverrides == overrides)
        #expect(decodedScenario == scenario)

        #expect(decodedOverrides.planningRate?.resolvedRate() == overrides.planningRate?.resolvedRate())
    }

    @Test("empty overrides round-trip and stay the identity")
    func emptyOverridesCodableRoundTrip() throws {
        let decoded = try JSONDecoder().decode(
            ScenarioOverrides.self,
            from: JSONEncoder().encode(ScenarioOverrides())
        )

        #expect(decoded == ScenarioOverrides())
        let result = try ProjectionEngine.project(try ScenarioEngine.apply(decoded, to: basePlan))
        #expect(result.completionCycle == 11)
    }

    @Test("unknown income source id in share override throws")
    func unknownIncomeSourceThrows() {
        let ghostID = UUID(uuidString: "DDDDDDDD-4444-4444-4444-444444444444")!
        let overrides = ScenarioOverrides(incomeShareBps: [ghostID: 10_000])
        #expect(throws: ScenarioError.unknownIncomeSource(ghostID)) {
            try ScenarioEngine.apply(overrides, to: basePlan)
        }
    }

    @Test("share basis points outside 0...10000 throw")
    func invalidShareBpsThrows() {
        let overrides = ScenarioOverrides(incomeShareBps: [sourceAID: 12_000])
        #expect(throws: ScenarioError.invalidShareBasisPoints(12_000)) {
            try ScenarioEngine.apply(overrides, to: basePlan)
        }
    }

    @Test("savings percent outside 0...10000 throws")
    func invalidSavingsPercentThrows() {
        let overrides = ScenarioOverrides(savingsPercentBps: 20_000)
        #expect(throws: ScenarioError.invalidSavingsPercent(20_000)) {
            try ScenarioEngine.apply(overrides, to: basePlan)
        }
    }

    @Test("negative savings amount override throws")
    func negativeSavingsThrows() {
        let overrides = ScenarioOverrides(monthlySavingsAmount: Money(minor: -1, currency: .usd))
        #expect(throws: ScenarioError.negativeSavingsAmount) {
            try ScenarioEngine.apply(overrides, to: basePlan)
        }
    }

    @Test("malformed decimal rate string throws")
    func malformedRateStringThrows() {
        let overrides = ScenarioOverrides(
            planningRate: .decimalString(base: .usd, quote: .rub, value: "84.28.2")
        )
        #expect(throws: ScenarioError.invalidPlanningRateOverride) {
            try ScenarioEngine.apply(overrides, to: basePlan)
        }
    }

    @Test("cross-currency target override throws instead of guessing a rate")
    func crossCurrencyTargetThrows() {
        let overrides = ScenarioOverrides(targetAmount: Money(minor: 7_000_000, currency: .usd))
        #expect(throws: ScenarioError.currencyMismatch(expected: "RUB", actual: "USD")) {
            try ScenarioEngine.apply(overrides, to: basePlan)
        }
    }

    @Test("zero one-time event amount throws")
    func zeroOneTimeAmountThrows() {
        let overrides = ScenarioOverrides(extraOneTimeEvents: [
            ScenarioOneTime(amount: Money(minor: 0, currency: .rub), timing: .cycleIndex(1))
        ])
        #expect(throws: ScenarioError.zeroOneTimeEventAmount) {
            try ScenarioEngine.apply(overrides, to: basePlan)
        }
    }

    @Test("target date on/before start date throws")
    func targetDateBeforeStartThrows() {
        let overrides = ScenarioOverrides(targetDate: startDate)
        #expect(throws: ScenarioError.targetDateBeforeStart) {
            try ScenarioEngine.apply(overrides, to: basePlan)
        }
    }

    @Test("missing planning rate for income conversion throws")
    func missingPlanningRateThrows() {
        var plan = basePlan
        plan.incomeSources.append(
            IncomeSource(
                id: UUID(uuidString: "EEEEEEEE-5555-5555-5555-555555555555")!,
                name: "EUR gig",
                grossAmount: Money(minor: 100_000, currency: .eur)
            )
        )
        #expect(throws: ScenarioError.missingPlanningRate(base: "EUR", quote: "USD")) {
            try ScenarioEngine.apply(ScenarioOverrides(), to: plan)
        }
    }

    @Test("inactive income sources are excluded from income totals")
    func inactiveSourcesExcluded() throws {
        var plan = basePlan
        plan.incomeSources[0].isActive = false

        let comparison = try ScenarioEngine.compare(base: plan, scenario: Scenario(name: "noop"))

        #expect(comparison.base.totalProjectedIncome.amountMinor == 250_000)
        #expect(comparison.base.freeMonthly.amountMinor == -150_000)
    }
}
