import Testing
import Foundation
@testable import FinPlanCore

@Suite("ProjectionEngine")
struct ProjectionEngineTests {
    private let startDate = Date(timeIntervalSince1970: 1_767_225_600)
    private let july2026 = Date(timeIntervalSince1970: 1_782_864_000)
    private let august2026 = Date(timeIntervalSince1970: 1_785_542_400)
    private let december2026 = Date(timeIntervalSince1970: 1_796_083_200)

    private var usdRubRates: ManualExchangeRates {
        ManualExchangeRates(rates: [
            ExchangeRate(base: .usd, quote: .rub, decimalString: "84.282")!
        ])
    }

    private func scenarioInput(monthlyUSDMinor: Int64) -> ProjectionInput {
        ProjectionInput(
            startingAmount: Money(minor: 85_000_000, currency: .rub),
            target: Money(minor: 600_000_000, currency: .rub),
            startDate: startDate,
            contributions: [
                PlannedContribution(
                    amount: Money(minor: monthlyUSDMinor, currency: .usd),
                    schedule: .monthly(day: 1)
                )
            ],
            oneTimeEvents: [
                PlannedOneTime(
                    amount: Money(minor: 169_500_000, currency: .rub),
                    timing: .cycleIndex(6)
                )
            ],
            planningRates: usdRubRates,
            horizonCycles: 600
        )
    }

    @Test("regression A: exact kopecks for $4,000/month, one-time at cycle 6")
    func regressionScenarioA() throws {
        let input = scenarioInput(monthlyUSDMinor: 400_000)

        let result = try ProjectionEngine.project(input)

        let convertedMonthly = result.points[1].balance.amountMinor - result.points[0].balance.amountMinor
        #expect(convertedMonthly == 33_712_800)

        #expect(result.points[0].balance.amountMinor == 85_000_000)
        #expect(result.points[5].balance.amountMinor == 253_564_000)
        #expect(result.points[6].balance.amountMinor == 456_776_800)
        #expect(result.points[10].balance.amountMinor == 591_628_000)
        #expect(result.points[11].balance.amountMinor == 625_340_800)

        #expect(result.completionCycle == 11)
        #expect(result.isTargetReached)
        #expect(result.completionDate == december2026)
        #expect(result.shortfallAtHorizon == nil)
        #expect(result.points.count == 12)
        for (offset, point) in result.points.enumerated() {
            #expect(point.cycleIndex == offset)
        }
    }

    @Test("regression B: exact kopecks for $6,250/month")
    func regressionScenarioB() throws {
        let input = scenarioInput(monthlyUSDMinor: 625_000)

        let result = try ProjectionEngine.project(input)

        let convertedMonthly = result.points[1].balance.amountMinor - result.points[0].balance.amountMinor
        #expect(convertedMonthly == 52_676_250)
        for k in 1...5 {
            let increment = result.points[k].balance.amountMinor - result.points[k - 1].balance.amountMinor
            #expect(increment == 52_676_250)
        }

        #expect(result.points[5].balance.amountMinor == 348_381_250)
        #expect(result.points[6].balance.amountMinor == 570_557_500)
        #expect(result.points[7].balance.amountMinor == 623_233_750)
        #expect(result.completionCycle == 7)
        #expect(result.completionDate == august2026)
    }

    @Test("target never reached within horizon reports shortfall")
    func shortfallAtHorizon() throws {
        let input = ProjectionInput(
            startingAmount: .zero(.rub),
            target: Money(minor: 1_000_000, currency: .rub),
            startDate: startDate,
            contributions: [
                PlannedContribution(amount: Money(minor: 10_000, currency: .rub), schedule: .monthly(day: 1))
            ],
            horizonCycles: 12
        )

        let result = try ProjectionEngine.project(input)

        #expect(result.completionCycle == nil)
        #expect(result.completionDate == nil)
        #expect(!result.isTargetReached)
        #expect(result.points.count == 13)
        #expect(result.points[12].balance.amountMinor == 120_000)
        #expect(result.shortfallAtHorizon == Money(minor: 880_000, currency: .rub))
    }

    @Test("start already at target completes at cycle 0")
    func immediateCompletion() throws {
        let input = ProjectionInput(
            startingAmount: Money(minor: 600_000_000, currency: .rub),
            target: Money(minor: 600_000_000, currency: .rub),
            startDate: startDate,
            horizonCycles: 600
        )
        let result = try ProjectionEngine.project(input)
        #expect(result.completionCycle == 0)
        #expect(result.completionDate == startDate)
        #expect(result.points.count == 1)
    }

    @Test("invalid horizon throws")
    func invalidHorizon() {
        let input = ProjectionInput(
            startingAmount: .zero(.rub),
            target: Money(minor: 100, currency: .rub),
            startDate: startDate,
            horizonCycles: 0
        )
        #expect(throws: ProjectionError.invalidHorizon(0)) {
            _ = try ProjectionEngine.project(input)
        }
    }

    @Test("contribution in goal currency needs no planning rate")
    func sameCurrencyNoRate() throws {
        let input = ProjectionInput(
            startingAmount: .zero(.rub),
            target: Money(minor: 50_000, currency: .rub),
            startDate: startDate,
            contributions: [
                PlannedContribution(amount: Money(minor: 10_000, currency: .rub), schedule: .monthly(day: 15))
            ],
            planningRates: ManualExchangeRates(),
            horizonCycles: 24
        )

        let result = try ProjectionEngine.project(input)

        #expect(result.completionCycle == 5)
        #expect(result.points[5].balance.amountMinor == 50_000)
    }

    @Test("missing planning rate throws typed error")
    func missingPlanningRate() {
        let input = ProjectionInput(
            startingAmount: .zero(.rub),
            target: Money(minor: 1_000_000, currency: .rub),
            startDate: startDate,
            contributions: [
                PlannedContribution(amount: Money(minor: 10_000, currency: .eur), schedule: .monthly(day: 1))
            ],
            planningRates: ManualExchangeRates(),
            horizonCycles: 12
        )
        #expect(throws: ProjectionError.missingPlanningRate(base: "EUR", quote: "RUB")) {
            _ = try ProjectionEngine.project(input)
        }
    }

    @Test("starting amount in a different currency than target throws")
    func startCurrencyMismatch() {
        let input = ProjectionInput(
            startingAmount: Money(minor: 100, currency: .usd),
            target: Money(minor: 1_000, currency: .rub),
            startDate: startDate
        )
        #expect(throws: ProjectionError.currencyMismatch(expected: "RUB", actual: "USD")) {
            _ = try ProjectionEngine.project(input)
        }
    }

    @Test("multiple contributions in mixed currencies accumulate exactly")
    func multipleContributions() throws {
        let input = ProjectionInput(
            startingAmount: .zero(.rub),
            target: Money(minor: 600_000_000, currency: .rub),
            startDate: startDate,
            contributions: [
                PlannedContribution(amount: Money(minor: 10_000, currency: .rub), schedule: .monthly(day: 1)),
                PlannedContribution(amount: Money(minor: 10_000, currency: .usd), schedule: .monthly(day: 5)),
            ],
            planningRates: usdRubRates,
            horizonCycles: 3
        )

        let result = try ProjectionEngine.project(input)

        #expect(result.points[1].balance.amountMinor == 852_820)
        #expect(result.points[2].balance.amountMinor == 1_705_640)
        #expect(result.points[3].balance.amountMinor == 2_558_460)
    }

    @Test("monthly contribution stops after its end date")
    func contributionEndDate() throws {
        let endDate = Date(timeIntervalSince1970: 1_776_211_200)
        let input = ProjectionInput(
            startingAmount: .zero(.rub),
            target: Money(minor: 100_000_000, currency: .rub),
            startDate: startDate,
            contributions: [
                PlannedContribution(
                    amount: Money(minor: 10_000, currency: .rub),
                    schedule: .monthly(day: 1),
                    end: endDate
                )
            ],
            horizonCycles: 6
        )

        let result = try ProjectionEngine.project(input)

        #expect(result.points[3].balance.amountMinor == 30_000)
        #expect(result.points[4].balance.amountMinor == 30_000)
        #expect(result.points[6].balance.amountMinor == 30_000)
    }

    @Test("explicit-dates schedule lands each date in its containing cycle")
    func explicitDatesSchedule() throws {
        let feb10 = Date(timeIntervalSince1970: 1_770_681_600)
        let may05 = Date(timeIntervalSince1970: 1_777_939_200)
        let input = ProjectionInput(
            startingAmount: .zero(.rub),
            target: Money(minor: 100_000_000, currency: .rub),
            startDate: startDate,
            contributions: [
                PlannedContribution(amount: Money(minor: 5_000, currency: .rub), schedule: .dates([feb10, may05]))
            ],
            horizonCycles: 6
        )

        let result = try ProjectionEngine.project(input)

        #expect(result.points[1].balance.amountMinor == 0)
        #expect(result.points[2].balance.amountMinor == 5_000)
        #expect(result.points[4].balance.amountMinor == 5_000)
        #expect(result.points[5].balance.amountMinor == 10_000)
    }

    @Test("date-based one-time event maps to first cycle on/after its date")
    func oneTimeByDate() throws {
        let march15 = Date(timeIntervalSince1970: 1_773_532_800)
        let input = ProjectionInput(
            startingAmount: .zero(.rub),
            target: Money(minor: 100_000_000, currency: .rub),
            startDate: startDate,
            oneTimeEvents: [
                PlannedOneTime(amount: Money(minor: 7_777, currency: .rub), timing: .date(march15))
            ],
            horizonCycles: 6
        )

        let result = try ProjectionEngine.project(input)

        #expect(result.points[2].balance.amountMinor == 0)
        #expect(result.points[3].balance.amountMinor == 7_777)
    }

    @Test("milestone 50% in scenario A is reached at cycle 6 (July 2026)")
    func milestoneFiftyPercentScenarioA() throws {
        let result = try ProjectionEngine.project(scenarioInput(monthlyUSDMinor: 400_000))
        let milestones = try result.milestoneDates(for: [Money(minor: 300_000_000, currency: .rub)])

        #expect(milestones.count == 1)
        #expect(milestones[0].cycleIndex == 6)
        #expect(milestones[0].date == july2026)
        #expect(milestones[0].isReached)
    }

    @Test("standard percent milestones use basis-point math on target")
    func standardPercentMilestones() throws {
        let result = try ProjectionEngine.project(scenarioInput(monthlyUSDMinor: 400_000))
        let milestones = result.standardPercentMilestones()

        #expect(milestones.map(\.basisPoints) == [1_000, 2_500, 5_000, 7_500, 9_000, 10_000])
        #expect(milestones.map(\.threshold.amountMinor) ==
                [60_000_000, 150_000_000, 300_000_000, 450_000_000, 540_000_000, 600_000_000])

        #expect(milestones[0].cycleIndex == 0)
        #expect(milestones[1].cycleIndex == 2)
        #expect(milestones[2].cycleIndex == 6)
        #expect(milestones[3].cycleIndex == 6)
        #expect(milestones[4].cycleIndex == 9)
        #expect(milestones[5].cycleIndex == 11)
        #expect(milestones[5].date == result.completionDate)
    }

    @Test("unreached milestone reports nil cycle and date")
    func unreachedMilestone() throws {
        let input = ProjectionInput(
            startingAmount: .zero(.rub),
            target: Money(minor: 1_000_000, currency: .rub),
            startDate: startDate,
            contributions: [
                PlannedContribution(amount: Money(minor: 10_000, currency: .rub), schedule: .monthly(day: 1))
            ],
            horizonCycles: 12
        )
        let result = try ProjectionEngine.project(input)
        let milestones = try result.milestoneDates(for: [Money(minor: 500_000, currency: .rub)])
        #expect(milestones[0].cycleIndex == nil)
        #expect(milestones[0].date == nil)
        #expect(!milestones[0].isReached)
    }

    @Test("milestone threshold in wrong currency throws")
    func milestoneCurrencyMismatch() throws {
        let result = try ProjectionEngine.project(scenarioInput(monthlyUSDMinor: 400_000))
        #expect(throws: ProjectionError.currencyMismatch(expected: "RUB", actual: "USD")) {
            _ = try result.milestoneDates(for: [Money(minor: 100, currency: .usd)])
        }
    }

    @Test("required monthly for 6M target from 850k over 12 cycles rounds up")
    func requiredMonthlyTwelveCycles() throws {
        let required = try ProjectionEngine.requiredMonthlyContribution(
            startingAmount: Money(minor: 85_000_000, currency: .rub),
            target: Money(minor: 600_000_000, currency: .rub),
            inCycles: 12
        )

        #expect(required.amountMinor == 42_916_667)
        #expect(12 * required.amountMinor + 85_000_000 >= 600_000_000)
        #expect(12 * (required.amountMinor - 1) + 85_000_000 < 600_000_000)
    }

    @Test("required monthly accounts for one-time events within range")
    func requiredMonthlyWithOneTime() throws {
        let required = try ProjectionEngine.requiredMonthlyContribution(
            startingAmount: Money(minor: 85_000_000, currency: .rub),
            target: Money(minor: 600_000_000, currency: .rub),
            inCycles: 12,
            oneTimeEvents: [
                PlannedOneTime(amount: Money(minor: 169_500_000, currency: .rub), timing: .cycleIndex(6))
            ]
        )
        #expect(required.amountMinor == 28_791_667)
    }

    @Test("required monthly ignores one-time events beyond the range")
    func requiredMonthlyIgnoresOutOfRangeOneTime() throws {
        let required = try ProjectionEngine.requiredMonthlyContribution(
            startingAmount: Money(minor: 85_000_000, currency: .rub),
            target: Money(minor: 600_000_000, currency: .rub),
            inCycles: 12,
            oneTimeEvents: [
                PlannedOneTime(amount: Money(minor: 169_500_000, currency: .rub), timing: .cycleIndex(13))
            ]
        )
        #expect(required.amountMinor == 42_916_667)
    }

    @Test("required monthly by desired date floors whole months")
    func requiredMonthlyByDate() throws {
        let desired = Date(timeIntervalSince1970: 1_798_761_600)
        let required = try ProjectionEngine.requiredMonthlyContribution(
            startingAmount: Money(minor: 85_000_000, currency: .rub),
            target: Money(minor: 600_000_000, currency: .rub),
            by: desired,
            startDate: startDate
        )
        #expect(required.amountMinor == 42_916_667)
    }

    @Test("required monthly is zero when the goal is already funded")
    func requiredMonthlyAlreadyFunded() throws {
        let required = try ProjectionEngine.requiredMonthlyContribution(
            startingAmount: Money(minor: 700_000_000, currency: .rub),
            target: Money(minor: 600_000_000, currency: .rub),
            inCycles: 12
        )
        #expect(required.isZero)
        #expect(required.currency == .rub)
    }

    @Test("required monthly with non-positive cycle count throws")
    func requiredMonthlyInvalidCycles() {
        #expect(throws: ProjectionError.nonPositiveCycleCount(0)) {
            _ = try ProjectionEngine.requiredMonthlyContribution(
                startingAmount: .zero(.rub),
                target: Money(minor: 100, currency: .rub),
                inCycles: 0
            )
        }
    }

    @Test("projecting with the required contribution reaches target in the cycle count")
    func requiredMonthlyRoundTrip() throws {
        let required = try ProjectionEngine.requiredMonthlyContribution(
            startingAmount: Money(minor: 85_000_000, currency: .rub),
            target: Money(minor: 600_000_000, currency: .rub),
            inCycles: 12
        )
        let input = ProjectionInput(
            startingAmount: Money(minor: 85_000_000, currency: .rub),
            target: Money(minor: 600_000_000, currency: .rub),
            startDate: startDate,
            contributions: [
                PlannedContribution(amount: required, schedule: .monthly(day: 1))
            ],
            horizonCycles: 24
        )

        let result = try ProjectionEngine.project(input)

        #expect(result.completionCycle != nil)
        #expect(result.completionCycle! <= 12)
    }

    @Test("plan status behind by one full contribution is 30 days behind")
    func planStatusBehind() throws {
        let status = try ProjectionEngine.planStatus(
            actualBalance: Money(minor: 219_851_200, currency: .rub),
            plannedBalance: Money(minor: 253_564_000, currency: .rub),
            monthlyPlannedContribution: Money(minor: 33_712_800, currency: .rub)
        )
        #expect(status.standing == .behind)
        #expect(status.delta.amountMinor == -33_712_800)
        #expect(status.timeImpactDays == -30)
    }

    @Test("plan status ahead by half a contribution is 15 days ahead")
    func planStatusAhead() throws {
        let status = try ProjectionEngine.planStatus(
            actualBalance: Money(minor: 270_420_400, currency: .rub),
            plannedBalance: Money(minor: 253_564_000, currency: .rub),
            monthlyPlannedContribution: Money(minor: 33_712_800, currency: .rub)
        )
        #expect(status.standing == .ahead)
        #expect(status.delta.amountMinor == 16_856_400)
        #expect(status.timeImpactDays == 15)
    }

    @Test("plan status on track has zero delta and zero days")
    func planStatusOnTrack() throws {
        let balance = Money(minor: 253_564_000, currency: .rub)
        let status = try ProjectionEngine.planStatus(
            actualBalance: balance,
            plannedBalance: balance,
            monthlyPlannedContribution: Money(minor: 33_712_800, currency: .rub)
        )
        #expect(status.standing == .onTrack)
        #expect(status.delta.isZero)
        #expect(status.timeImpactDays == 0)
    }

    @Test("time impact truncates toward zero (conservative)")
    func planStatusTruncation() throws {
        let status = try ProjectionEngine.planStatus(
            actualBalance: Money(minor: 1_099, currency: .rub),
            plannedBalance: Money(minor: 1_000, currency: .rub),
            monthlyPlannedContribution: Money(minor: 3_000, currency: .rub)
        )
        #expect(status.standing == .ahead)
        #expect(status.timeImpactDays == 0)
    }

    @Test("plan status with non-positive planned rate throws")
    func planStatusInvalidRate() {
        #expect(throws: ProjectionError.nonPositivePlannedRate) {
            _ = try ProjectionEngine.planStatus(
                actualBalance: Money(minor: 100, currency: .rub),
                plannedBalance: Money(minor: 50, currency: .rub),
                monthlyPlannedContribution: .zero(.rub)
            )
        }
    }

    @Test("recovery plan ceil-divides shortfall across remaining cycles")
    func recoveryPlanCeiling() throws {
        let extra = try ProjectionEngine.recoveryPlan(
            shortfall: Money(minor: 100, currency: .rub),
            remainingCycles: 3
        )
        #expect(extra.amountMinor == 34)

        let exact = try ProjectionEngine.recoveryPlan(
            shortfall: Money(minor: 90, currency: .rub),
            remainingCycles: 3
        )
        #expect(exact.amountMinor == 30)
    }

    @Test("recovery plan for non-positive shortfall is zero")
    func recoveryPlanNoShortfall() throws {
        let extra = try ProjectionEngine.recoveryPlan(
            shortfall: Money(minor: -500, currency: .rub),
            remainingCycles: 4
        )
        #expect(extra.isZero)
    }

    @Test("recovery plan with non-positive cycles throws")
    func recoveryPlanInvalidCycles() {
        #expect(throws: ProjectionError.nonPositiveCycleCount(0)) {
            _ = try ProjectionEngine.recoveryPlan(
                shortfall: Money(minor: 100, currency: .rub),
                remainingCycles: 0
            )
        }
    }
}
