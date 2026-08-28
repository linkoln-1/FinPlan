import Testing
import Foundation
@testable import FinPlanCore

@Suite("PurchaseImpactEngine")
struct PurchaseImpactTests {
    private let startDate = Date(timeIntervalSince1970: 1_767_225_600)
    private let december2026 = Date(timeIntervalSince1970: 1_796_083_200)
    private let january2027 = Date(timeIntervalSince1970: 1_798_761_600)

    private func rub(_ major: Int64) -> Money {
        Money(major: major, currency: .rub)
    }

    private var usdRubRates: ManualExchangeRates {
        ManualExchangeRates(rates: [
            ExchangeRate(base: .usd, quote: .rub, decimalString: "84.282")!
        ])
    }

    private var budget: SafeToSpendInput {
        SafeToSpendInput(
            liquidBalance: rub(500_000),
            goalAllocatedTotal: rub(200_000),
            emergencyReserve: rub(100_000),
            upcomingMandatory: rub(50_000),
            minimumBuffer: rub(50_000)
        )
    }

    private var goalPlan: ProjectionInput {
        ProjectionInput(
            startingAmount: Money(minor: 85_000_000, currency: .rub),
            target: Money(minor: 600_000_000, currency: .rub),
            startDate: startDate,
            contributions: [
                PlannedContribution(
                    amount: Money(minor: 400_000, currency: .usd),
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

    private func evaluate(_ amount: Money, budget: SafeToSpendInput? = nil) throws -> PurchaseImpact {
        try PurchaseImpactEngine.evaluate(
            purchase: PurchaseCandidate(amount: amount, date: startDate),
            safeToSpend: budget ?? self.budget,
            goalProjection: goalPlan,
            planningRates: usdRubRates
        )
    }

    @Test("purchase within available → safe, remaining reduced, goal date unchanged")
    func safeWithinAvailable() throws {
        let impact = try evaluate(rub(40_000))

        #expect(impact.verdict == .safe)
        #expect(impact.remainingSafeToSpend == rub(60_000))
        #expect(impact.goalDelayDays == nil)
        #expect(impact.newCompletionCycle == 11)
        #expect(impact.newCompletionDate == december2026)
        #expect(impact.affectsNextMilestone == false)
        #expect(impact.shortfall == nil)
    }

    @Test("boundary: purchase exactly equal to available is still safe")
    func safeAtExactBoundary() throws {
        let impact = try evaluate(rub(100_000))

        #expect(impact.verdict == .safe)
        #expect(impact.remainingSafeToSpend == rub(0))
        #expect(impact.goalDelayDays == nil)
        #expect(impact.shortfall == nil)
    }

    @Test("spec example: 100,000 ₽ over budget with 337,128 ₽/month → 9-day delay")
    func specExampleDelaysGoal() throws {
        let impact = try evaluate(rub(200_000))

        #expect(impact.verdict == .delaysGoal)
        #expect(impact.goalDelayDays == 9)

        #expect(impact.remainingSafeToSpend == rub(0))

        #expect(impact.newCompletionCycle == 11)
        #expect(impact.newCompletionDate == december2026)

        #expect(impact.affectsNextMilestone == true)
        #expect(impact.shortfall == nil)
    }

    @Test("overflow beyond cycle slack shifts completion cycle and delay stays sub-cycle exact")
    func delayShiftsCompletionCycle() throws {
        let richBudget = SafeToSpendInput(
            liquidBalance: rub(900_000),
            goalAllocatedTotal: rub(600_000),
            emergencyReserve: rub(100_000),
            upcomingMandatory: rub(50_000),
            minimumBuffer: rub(50_000)
        )

        let impact = try evaluate(rub(400_000), budget: richBudget)

        #expect(impact.verdict == .delaysGoal)
        #expect(impact.goalDelayDays == 27)
        #expect(impact.newCompletionCycle == 12)
        #expect(impact.newCompletionDate == january2027)
        #expect(impact.shortfall == nil)
    }

    @Test("overflow beyond goal reserves → touchesReserve, no repaired plan computed")
    func touchesReserve() throws {
        let impact = try evaluate(rub(350_000))

        #expect(impact.verdict == .touchesReserve)
        #expect(impact.remainingSafeToSpend == rub(0))
        #expect(impact.goalDelayDays == nil)
        #expect(impact.newCompletionCycle == nil)
        #expect(impact.newCompletionDate == nil)
        #expect(impact.affectsNextMilestone == false)
        #expect(impact.shortfall == nil)
    }

    @Test("with zero goal reserves any overflow touches the reserve")
    func zeroGoalReservesOverflowTouchesReserve() throws {
        let noGoalBudget = SafeToSpendInput(
            liquidBalance: rub(200_000),
            goalAllocatedTotal: rub(0),
            emergencyReserve: rub(100_000),
            upcomingMandatory: rub(0),
            minimumBuffer: rub(0)
        )

        let impact = try evaluate(rub(150_000), budget: noGoalBudget)

        #expect(impact.verdict == .touchesReserve)
        #expect(impact.shortfall == nil)
    }

    @Test("boundary: purchase exactly equal to liquid is affordable, not unaffordable")
    func liquidBoundaryIsAffordable() throws {
        let impact = try evaluate(rub(500_000))

        #expect(impact.verdict == .touchesReserve)
        #expect(impact.shortfall == nil)
    }

    @Test("purchase beyond all liquid money → unaffordable with exact shortfall")
    func unaffordable() throws {
        let impact = try evaluate(rub(600_000))

        #expect(impact.verdict == .unaffordable)
        #expect(impact.shortfall == rub(100_000))
        #expect(impact.remainingSafeToSpend == rub(0))
        #expect(impact.goalDelayDays == nil)
        #expect(impact.newCompletionCycle == nil)
        #expect(impact.newCompletionDate == nil)
        #expect(impact.affectsNextMilestone == false)
    }

    @Test("foreign-currency purchase converts kopeck-exactly via planning rates")
    func foreignCurrencyPurchase() throws {
        let impact = try evaluate(Money(minor: 100_000, currency: .usd))

        #expect(impact.verdict == .safe)
        #expect(impact.remainingSafeToSpend == Money(minor: 1_571_800, currency: .rub))
    }

    @Test("missing planning rate for the purchase currency throws a typed error")
    func missingRateThrows() {
        #expect(throws: PurchaseImpactError.missingPlanningRate(base: "EUR", quote: "RUB")) {
            _ = try evaluate(Money(major: 100, currency: .eur))
        }
    }

    @Test("non-positive purchase amount throws instead of crashing")
    func nonPositiveAmountThrows() {
        #expect(throws: PurchaseImpactError.nonPositiveAmount) {
            _ = try evaluate(rub(0))
        }
        #expect(throws: PurchaseImpactError.nonPositiveAmount) {
            _ = try evaluate(rub(-10))
        }
    }

    @Test("overflow rounding to zero goal-currency units → delaysGoal with zero delay")
    func subMinorOverflowHasNoMeasurableGoalImpact() throws {
        let tinyBudget = SafeToSpendInput(
            liquidBalance: rub(100),
            goalAllocatedTotal: rub(50),
            emergencyReserve: rub(0),
            upcomingMandatory: rub(0),
            minimumBuffer: rub(0)
        )
        let usdGoal = ProjectionInput(
            startingAmount: Money(minor: 0, currency: .usd),
            target: Money(minor: 100_000, currency: .usd),
            startDate: startDate,
            contributions: [
                PlannedContribution(
                    amount: Money(minor: 10_000, currency: .usd),
                    schedule: .monthly(day: 1)
                )
            ],
            planningRates: ManualExchangeRates(),
            horizonCycles: 600
        )

        let impact = try PurchaseImpactEngine.evaluate(
            purchase: PurchaseCandidate(amount: Money(minor: 5_001, currency: .rub), date: startDate),
            safeToSpend: tinyBudget,
            goalProjection: usdGoal,
            planningRates: usdRubRates
        )

        #expect(impact.verdict == .delaysGoal)
        #expect(impact.goalDelayDays == 0)
        #expect(impact.newCompletionCycle == 10)
        #expect(impact.affectsNextMilestone == false)
    }

    @Test("evaluation is a pure simulation: no input is mutated")
    func evaluationNeverMutatesInputs() throws {
        let purchase = PurchaseCandidate(amount: rub(200_000), date: startDate)
        let budgetBefore = budget
        let planBefore = goalPlan
        let ratesBefore = usdRubRates

        let budgetInput = budgetBefore
        let planInput = planBefore
        let ratesInput = ratesBefore

        let first = try PurchaseImpactEngine.evaluate(
            purchase: purchase,
            safeToSpend: budgetInput,
            goalProjection: planInput,
            planningRates: ratesInput
        )
        let second = try PurchaseImpactEngine.evaluate(
            purchase: purchase,
            safeToSpend: budgetInput,
            goalProjection: planInput,
            planningRates: ratesInput
        )

        #expect(first == second)

        #expect(budgetInput == budgetBefore)

        #expect(planInput.startingAmount == planBefore.startingAmount)
        #expect(planInput.target == planBefore.target)
        #expect(planInput.startDate == planBefore.startDate)
        #expect(planInput.contributions == planBefore.contributions)
        #expect(planInput.oneTimeEvents == planBefore.oneTimeEvents)
        #expect(planInput.planningRates == planBefore.planningRates)
        #expect(planInput.horizonCycles == planBefore.horizonCycles)

        #expect(ratesInput == ratesBefore)
        #expect(purchase.amount == rub(200_000))
        #expect(purchase.date == startDate)
    }
}
