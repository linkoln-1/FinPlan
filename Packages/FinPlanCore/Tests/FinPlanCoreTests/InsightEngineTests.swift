import Testing
import Foundation
@testable import FinPlanCore

@Suite("InsightEngine")
struct InsightEngineTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func rub(_ major: Int64) -> Money { Money(major: major, currency: .rub) }
    private func rubMinor(_ minor: Int64) -> Money { Money(minor: minor, currency: .rub) }

    private func date(daysFromNow days: Int64) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(days * 86_400))
    }

    private func emptyContext() -> InsightContext { InsightContext(now: now) }

    private func goal(
        current: Money,
        planStatus: PlanStatus? = nil,
        milestones: [Money] = [],
        shortfall: Money? = nil,
        remainingCycles: Int? = nil
    ) -> GoalInsightSnapshot {
        GoalInsightSnapshot(
            goalID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
            target: rub(1_000_000),
            currentAmount: current,
            planStatus: planStatus,
            milestoneThresholds: milestones,
            shortfallAtHorizon: shortfall,
            remainingCycles: remainingCycles
        )
    }

    private func planStatus(deltaMinor: Int64) -> PlanStatus {
        PlanStatus(
            delta: rubMinor(deltaMinor),
            standing: deltaMinor > 0 ? .ahead : (deltaMinor < 0 ? .behind : .onTrack),
            timeImpactDays: 0
        )
    }

    private func types(_ insights: [Insight]) -> [InsightType] { insights.map(\.type) }

    @Test("empty context yields no insights")
    func emptyContextIsSilent() throws {
        #expect(try InsightEngine.evaluate(context: emptyContext()).isEmpty)
    }

    @Test("behindPlan fires when actual is below plan by more than 1% of target")
    func behindPlanFires() throws {
        let context = InsightContext(
            now: now,
            goals: [goal(current: rub(100_000), planStatus: planStatus(deltaMinor: -1_000_001))]
        )

        let insights = try InsightEngine.evaluate(context: context)

        let insight = try #require(insights.first)
        #expect(insight.type == .behindPlan)
        #expect(insight.severity == .attention)
        #expect(insight.messageKey == "insight.behindPlan")
        #expect(insight.value == rubMinor(-1_000_001))
        #expect(insight.basis.contains("-1000001m RUB"))
    }

    @Test("behindPlan stays silent at exactly 1% of target behind")
    func behindPlanBoundarySilent() throws {
        let context = InsightContext(
            now: now,
            goals: [goal(current: rub(100_000), planStatus: planStatus(deltaMinor: -1_000_000))]
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("aheadOfPlan fires as info when actual exceeds plan by more than 1% of target")
    func aheadOfPlanFires() throws {
        let context = InsightContext(
            now: now,
            goals: [goal(current: rub(100_000), planStatus: planStatus(deltaMinor: 1_000_001))]
        )
        let insight = try #require(try InsightEngine.evaluate(context: context).first)
        #expect(insight.type == .aheadOfPlan)
        #expect(insight.severity == .info)
    }

    @Test("aheadOfPlan stays silent at exactly 1% of target ahead")
    func aheadOfPlanBoundarySilent() throws {
        let context = InsightContext(
            now: now,
            goals: [goal(current: rub(100_000), planStatus: planStatus(deltaMinor: 1_000_000))]
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("goalReached fires when current amount meets the target and suppresses pace/milestones")
    func goalReachedFiresAndSuppresses() throws {
        let context = InsightContext(
            now: now,
            goals: [goal(
                current: rub(1_000_000),
                planStatus: planStatus(deltaMinor: 5_000_000),
                milestones: [rub(500_000)],
                shortfall: rub(1),
                remainingCycles: 2
            )]
        )

        let insights = try InsightEngine.evaluate(context: context)

        #expect(types(insights) == [.goalReached])
        #expect(insights[0].severity == .info)
        #expect(insights[0].value == rub(1_000_000))
    }

    @Test("goalReached stays silent one kopeck below the target")
    func goalReachedBoundarySilent() throws {
        let context = InsightContext(
            now: now,
            goals: [goal(current: rubMinor(99_999_999))]
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("milestoneReached reports the highest threshold covered")
    func milestoneReachedFires() throws {
        let context = InsightContext(
            now: now,
            goals: [goal(
                current: rub(600_000),
                milestones: [rub(250_000), rub(500_000), rub(750_000)]
            )]
        )
        let insight = try #require(try InsightEngine.evaluate(context: context).first)
        #expect(insight.type == .milestoneReached)
        #expect(insight.value == rub(500_000))
        #expect(insight.secondaryValue == rub(600_000))
    }

    @Test("milestoneReached stays silent one kopeck below the lowest threshold")
    func milestoneBoundarySilent() throws {
        let context = InsightContext(
            now: now,
            goals: [goal(
                current: rubMinor(24_999_999),
                milestones: [rub(250_000), rub(500_000)]
            )]
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    private func budgetSnapshot(remainingMinor: Int64, spentMinor: Int64) -> BudgetInsightSnapshot {
        BudgetInsightSnapshot(
            categoryID: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!,
            status: BudgetStatus(
                spent: rubMinor(spentMinor),
                remaining: rubMinor(remainingMinor),
                fractionUsedBasisPoints: 12_000,
                periodElapsedBasisPoints: 5_000,
                pace: .hot
            )
        )
    }

    @Test("overspendingCategory fires as warning when remaining is negative")
    func overspendingFires() throws {
        let context = InsightContext(
            now: now,
            budgets: [budgetSnapshot(remainingMinor: -50_000, spentMinor: 300_000)]
        )
        let insight = try #require(try InsightEngine.evaluate(context: context).first)
        #expect(insight.type == .overspendingCategory)
        #expect(insight.severity == .warning)
        #expect(insight.value == rubMinor(50_000))
        #expect(insight.secondaryValue == rubMinor(300_000))
    }

    @Test("overspendingCategory stays silent when the envelope is exactly used up")
    func overspendingBoundarySilent() throws {
        let context = InsightContext(
            now: now,
            budgets: [budgetSnapshot(remainingMinor: 0, spentMinor: 300_000)]
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    private func history(currentMinor: Int64, trailing: [Int64]) -> CategorySpendingHistory {
        CategorySpendingHistory(
            categoryID: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!,
            currentMonthSpend: rubMinor(currentMinor),
            trailingMonthlySpend: trailing.map { rubMinor($0) }
        )
    }

    @Test("unusualSpending fires when month spend exceeds 2x the 3-month average")
    func unusualSpendingFires() throws {
        let context = InsightContext(
            now: now,
            categoryHistories: [history(currentMinor: 20_001, trailing: [9_000, 10_000, 11_000])]
        )

        let insight = try #require(try InsightEngine.evaluate(context: context).first)

        #expect(insight.type == .unusualSpending)
        #expect(insight.severity == .attention)
        #expect(insight.value == rubMinor(20_001))
        #expect(insight.secondaryValue == rubMinor(10_000))
    }

    @Test("unusualSpending stays silent at exactly 2x the average")
    func unusualSpendingBoundarySilent() throws {
        let context = InsightContext(
            now: now,
            categoryHistories: [history(currentMinor: 20_000, trailing: [9_000, 10_000, 11_000])]
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("unusualSpending never fires with fewer than 3 months of history")
    func unusualSpendingInsufficientHistory() throws {
        let context = InsightContext(
            now: now,
            categoryHistories: [history(currentMinor: 100_000, trailing: [10_000, 10_000])]
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("unusualSpending never fires against an all-zero history")
    func unusualSpendingZeroHistorySilent() throws {
        let context = InsightContext(
            now: now,
            categoryHistories: [history(currentMinor: 100_000, trailing: [0, 0, 0])]
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("upcomingLargePayment fires at exactly 20% of liquid due within the window")
    func largePaymentFires() throws {
        let context = InsightContext(
            now: now,
            upcomingPayments: [UpcomingPaymentSnapshot(amount: rub(20_000), dueDate: date(daysFromNow: 14))],
            liquidBalance: rub(100_000)
        )
        let insight = try #require(try InsightEngine.evaluate(context: context).first)
        #expect(insight.type == .upcomingLargePayment)
        #expect(insight.severity == .attention)
        #expect(insight.value == rub(20_000))
        #expect(insight.secondaryValue == rub(100_000))
    }

    @Test("upcomingLargePayment stays silent one kopeck below 20% of liquid")
    func largePaymentBoundarySilent() throws {
        let context = InsightContext(
            now: now,
            upcomingPayments: [
                UpcomingPaymentSnapshot(amount: rubMinor(1_999_999), dueDate: date(daysFromNow: 7))
            ],
            liquidBalance: rub(100_000)
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("upcomingLargePayment ignores payments beyond the 14-day lookahead")
    func largePaymentOutsideWindowSilent() throws {
        let context = InsightContext(
            now: now,
            upcomingPayments: [UpcomingPaymentSnapshot(amount: rub(90_000), dueDate: date(daysFromNow: 15))],
            liquidBalance: rub(100_000)
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("upcomingLargePayment fires for any positive payment when liquid is zero")
    func largePaymentZeroLiquid() throws {
        let context = InsightContext(
            now: now,
            upcomingPayments: [UpcomingPaymentSnapshot(amount: rub(1), dueDate: date(daysFromNow: 1))],
            liquidBalance: rub(0)
        )
        #expect(types(try InsightEngine.evaluate(context: context)) == [.upcomingLargePayment])
    }

    @Test("expectedIncomeOverdue fires for an event explicitly marked overdue")
    func overdueStateFires() throws {
        let event = ExpectedEvent(
            title: "Invoice",
            amount: rub(1_695_000),
            expectedDate: date(daysFromNow: 3),
            state: .overdue
        )
        let context = InsightContext(now: now, expectedEvents: [event])
        let insight = try #require(try InsightEngine.evaluate(context: context).first)
        #expect(insight.type == .expectedIncomeOverdue)
        #expect(insight.severity == .attention)
        #expect(insight.value == rub(1_695_000))
    }

    @Test("expectedIncomeOverdue fires for an expected event whose date has passed")
    func expectedPastDateFires() throws {
        let event = ExpectedEvent(
            title: "Invoice",
            amount: rub(50_000),
            expectedDate: date(daysFromNow: -1),
            state: .expected
        )
        let context = InsightContext(now: now, expectedEvents: [event])
        #expect(types(try InsightEngine.evaluate(context: context)) == [.expectedIncomeOverdue])
    }

    @Test("expectedIncomeOverdue stays silent when the expected date is exactly now")
    func expectedDueNowSilent() throws {
        let event = ExpectedEvent(title: "Invoice", amount: rub(50_000), expectedDate: now, state: .expected)
        let context = InsightContext(now: now, expectedEvents: [event])
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("expectedIncomeOverdue ignores received and cancelled events with past dates")
    func settledEventsSilent() throws {
        let received = ExpectedEvent(
            title: "A", amount: rub(1), expectedDate: date(daysFromNow: -5), state: .received
        )
        let cancelled = ExpectedEvent(
            title: "B", amount: rub(1), expectedDate: date(daysFromNow: -5), state: .cancelled
        )
        let context = InsightContext(now: now, expectedEvents: [received, cancelled])
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("savingsTargetMissed fires when actual falls short by more than 1% of target")
    func savingsMissedFires() throws {
        let context = InsightContext(
            now: now,
            savings: SavingsPeriodSnapshot(target: rub(100_000), actual: rubMinor(9_899_999))
        )
        let insight = try #require(try InsightEngine.evaluate(context: context).first)
        #expect(insight.type == .savingsTargetMissed)
        #expect(insight.severity == .attention)
        #expect(insight.value == rubMinor(9_899_999))
        #expect(insight.secondaryValue == rub(100_000))
    }

    @Test("savingsTargetMissed stays silent at exactly 1% short")
    func savingsMissedBoundarySilent() throws {
        let context = InsightContext(
            now: now,
            savings: SavingsPeriodSnapshot(target: rub(100_000), actual: rub(99_000))
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("savingsTargetExceeded fires as info when actual beats target by more than 1%")
    func savingsExceededFires() throws {
        let context = InsightContext(
            now: now,
            savings: SavingsPeriodSnapshot(target: rub(100_000), actual: rubMinor(10_100_001))
        )
        let insight = try #require(try InsightEngine.evaluate(context: context).first)
        #expect(insight.type == .savingsTargetExceeded)
        #expect(insight.severity == .info)
    }

    @Test("savingsTargetExceeded stays silent at exactly 1% over")
    func savingsExceededBoundarySilent() throws {
        let context = InsightContext(
            now: now,
            savings: SavingsPeriodSnapshot(target: rub(100_000), actual: rub(101_000))
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("runwayLow fires when liquid covers less than 3 months of essentials")
    func runwayLowFires() throws {
        let context = InsightContext(
            now: now,
            liquidBalance: rubMinor(14_999_999),
            monthlyEssentialSpending: rub(50_000)
        )
        let insight = try #require(try InsightEngine.evaluate(context: context).first)
        #expect(insight.type == .runwayLow)
        #expect(insight.severity == .warning)
        #expect(insight.value == rubMinor(14_999_999))
        #expect(insight.secondaryValue == rub(50_000))
        #expect(insight.basis.contains("299 month-hundredths"))
    }

    @Test("runwayLow stays silent at exactly 3 months of runway")
    func runwayBoundarySilent() throws {
        let context = InsightContext(
            now: now,
            liquidBalance: rub(150_000),
            monthlyEssentialSpending: rub(50_000)
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("runwayLow needs an essential-spending figure — silent without one")
    func runwayNoEssentialsSilent() throws {
        let context = InsightContext(now: now, liquidBalance: rub(1))
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    private func stsResult(availableMinor: Int64, liquidMinor: Int64, shortfallMinor: Int64? = nil) -> SafeToSpendResult {
        SafeToSpendResult(
            available: rubMinor(availableMinor),
            shortfall: shortfallMinor.map { rubMinor($0) },
            breakdown: [
                SafeToSpendBreakdownItem(label: .liquidBalance, amount: rubMinor(liquidMinor)),
                SafeToSpendBreakdownItem(label: .goalReserved, amount: rubMinor(-liquidMinor + availableMinor - (shortfallMinor ?? 0))),
            ]
        )
    }

    @Test("safeToSpendLow fires as warning when reserves exceed liquidity (shortfall)")
    func safeToSpendShortfallFires() throws {
        let context = InsightContext(
            now: now,
            safeToSpend: stsResult(availableMinor: 0, liquidMinor: 100_000, shortfallMinor: 25_000)
        )
        let insight = try #require(try InsightEngine.evaluate(context: context).first)
        #expect(insight.type == .safeToSpendLow)
        #expect(insight.severity == .warning)
        #expect(insight.secondaryValue == rubMinor(25_000))
    }

    @Test("safeToSpendLow fires when available drops below 10% of liquid")
    func safeToSpendLowShareFires() throws {
        let context = InsightContext(
            now: now,
            safeToSpend: stsResult(availableMinor: 999_999, liquidMinor: 10_000_000)
        )
        let insight = try #require(try InsightEngine.evaluate(context: context).first)
        #expect(insight.type == .safeToSpendLow)
        #expect(insight.value == rubMinor(999_999))
        #expect(insight.secondaryValue == rubMinor(10_000_000))
    }

    @Test("safeToSpendLow stays silent at exactly 10% of liquid available")
    func safeToSpendBoundarySilent() throws {
        let context = InsightContext(
            now: now,
            safeToSpend: stsResult(availableMinor: 1_000_000, liquidMinor: 10_000_000)
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("currencyPlanDeviation fires when the market rate drifts more than 5% off plan")
    func currencyDeviationFires() throws {
        let plan = ExchangeRate(base: .usd, quote: .rub, rateScaled: 100_000_000, scale: 6)
        let current = ExchangeRate(base: .usd, quote: .rub, rateScaled: 105_000_001, scale: 6)
        let context = InsightContext(
            now: now,
            rateComparisons: [PlanningRateComparison(planning: plan, current: current)]
        )
        let insight = try #require(try InsightEngine.evaluate(context: context).first)
        #expect(insight.type == .currencyPlanDeviation)
        #expect(insight.severity == .attention)
        #expect(insight.value == nil)
        #expect(insight.basis.contains("USD/RUB"))
    }

    @Test("currencyPlanDeviation stays silent at exactly 5% drift (both directions)")
    func currencyDeviationBoundarySilent() throws {
        let plan = ExchangeRate(base: .usd, quote: .rub, rateScaled: 100_000_000, scale: 6)
        let up = ExchangeRate(base: .usd, quote: .rub, rateScaled: 105_000_000, scale: 6)
        let down = ExchangeRate(base: .usd, quote: .rub, rateScaled: 95_000_000, scale: 6)
        let context = InsightContext(
            now: now,
            rateComparisons: [
                PlanningRateComparison(planning: plan, current: up),
                PlanningRateComparison(planning: plan, current: down),
            ]
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("currencyPlanDeviation normalizes differing rate scales before comparing")
    func currencyDeviationMixedScales() throws {
        let plan = ExchangeRate(base: .usd, quote: .rub, rateScaled: 84_282, scale: 3)
        let current = ExchangeRate(base: .usd, quote: .rub, rateScaled: 84_282_000, scale: 6)
        let context = InsightContext(
            now: now,
            rateComparisons: [PlanningRateComparison(planning: plan, current: current)]
        )
        #expect(try InsightEngine.evaluate(context: context).isEmpty)
    }

    @Test("recoveryPlanAvailable fires with the exact ceiling-division extra per cycle")
    func recoveryPlanFires() throws {
        let context = InsightContext(
            now: now,
            goals: [goal(current: rub(100_000), shortfall: rubMinor(100_001), remainingCycles: 3)]
        )
        let insight = try #require(try InsightEngine.evaluate(context: context).first)
        #expect(insight.type == .recoveryPlanAvailable)
        #expect(insight.severity == .info)
        #expect(insight.value == rubMinor(33_334))
        #expect(insight.secondaryValue == rubMinor(100_001))
        #expect(insight.actionKey == "insight.recoveryPlanAvailable.action")
    }

    @Test("recoveryPlanAvailable stays silent with zero shortfall or no remaining cycles")
    func recoveryPlanSilent() throws {
        let zeroShortfall = InsightContext(
            now: now,
            goals: [goal(current: rub(100_000), shortfall: rub(0), remainingCycles: 3)]
        )
        let noCycles = InsightContext(
            now: now,
            goals: [goal(current: rub(100_000), shortfall: rub(50_000), remainingCycles: 0)]
        )
        #expect(try InsightEngine.evaluate(context: zeroShortfall).isEmpty)
        #expect(try InsightEngine.evaluate(context: noCycles).isEmpty)
    }

    @Test("insights sort by severity (warnings first), then by type declaration order")
    func sortOrder() throws {
        let context = InsightContext(
            now: now,
            goals: [goal(
                current: rub(100_000),
                planStatus: planStatus(deltaMinor: -2_000_000),
                shortfall: rub(50_000),
                remainingCycles: 5
            )],
            budgets: [budgetSnapshot(remainingMinor: -1, spentMinor: 100)],
            liquidBalance: rub(10_000),
            monthlyEssentialSpending: rub(50_000)
        )

        let insights = try InsightEngine.evaluate(context: context)

        #expect(types(insights) == [.overspendingCategory, .runwayLow, .behindPlan, .recoveryPlanAvailable])
        #expect(insights.map(\.severity) == [.warning, .warning, .attention, .info])
    }

    @Test("equal severity and type fall back to basis for a total deterministic order")
    func sortTiebreakDeterministic() throws {
        let older = ExpectedEvent(
            id: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000001")!,
            title: "A", amount: rub(10), expectedDate: date(daysFromNow: -2), state: .overdue
        )
        let newer = ExpectedEvent(
            id: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000002")!,
            title: "B", amount: rub(20), expectedDate: date(daysFromNow: -1), state: .overdue
        )

        let forward = try InsightEngine.evaluate(context: InsightContext(now: now, expectedEvents: [older, newer]))
        let reversed = try InsightEngine.evaluate(context: InsightContext(now: now, expectedEvents: [newer, older]))

        #expect(forward.count == 2)
        #expect(forward == reversed)
    }

    @Test("mixed currencies inside one rule throw instead of silently converting")
    func currencyMismatchThrows() throws {
        let context = InsightContext(
            now: now,
            upcomingPayments: [
                UpcomingPaymentSnapshot(amount: Money(major: 100, currency: .usd), dueDate: date(daysFromNow: 1))
            ],
            liquidBalance: rub(100_000)
        )
        #expect(throws: MoneyError.currencyMismatch("USD", "RUB")) {
            try InsightEngine.evaluate(context: context)
        }
    }
}
