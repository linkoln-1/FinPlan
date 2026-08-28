import Testing
import Foundation
@testable import FinPlanCore

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func ts(_ seconds: Int64) -> Date {
    Date(timeIntervalSince1970: TimeInterval(seconds))
}

private enum Epoch {
    static let jan1_2024: Int64 = 1_704_067_200
    static let jan31_2024: Int64 = 1_706_659_200
    static let feb29_2024: Int64 = 1_709_164_800
    static let mar1_2024: Int64 = 1_709_251_200

    static let jan1_2025: Int64 = 1_735_689_600
    static let jan6_2025: Int64 = 1_736_121_600
    static let jan13_2025: Int64 = 1_736_726_400
    static let jan20_2025: Int64 = 1_737_331_200
    static let jan21_2025: Int64 = 1_737_417_600
    static let jan25_2025: Int64 = 1_737_763_200
    static let jan27_2025: Int64 = 1_737_936_000
    static let jan31_2025: Int64 = 1_738_281_600
    static let feb1_2025: Int64 = 1_738_368_000
    static let feb3_2025: Int64 = 1_738_540_800
    static let feb10_2025: Int64 = 1_739_145_600
    static let feb17_2025: Int64 = 1_739_750_400
    static let feb20_2025: Int64 = 1_740_009_600
    static let feb28_2025: Int64 = 1_740_700_800
    static let mar1_2025: Int64 = 1_740_787_200
    static let mar31_2025: Int64 = 1_743_379_200
    static let apr30_2025: Int64 = 1_745_971_200
    static let may1_2025: Int64 = 1_746_057_600
    static let jun1_2025: Int64 = 1_748_736_000

    static let jan1_2023: Int64 = 1_672_531_200
    static let feb28_2023: Int64 = 1_677_542_400
}

private let categoryA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
private let categoryB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
private let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let secondAccountID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
private let goalID = UUID(uuidString: "00000000-0000-0000-0000-00000000000F")!

private func rub(_ minor: Int64) -> Money { Money(minor: minor, currency: .rub) }

private func expense(
    _ minor: Int64,
    category: UUID?,
    date: Date,
    status: TransactionStatus = .completed,
    splits: [TransactionSplit] = [],
    currency: Currency = .rub,
    kind: TransactionKind = .expense
) -> TransactionRecord {
    TransactionRecord(
        date: date,
        kind: kind,
        status: status,
        amount: Money(minor: minor, currency: currency),
        sourceAccountID: accountID,
        destinationAccountID: kind == .expense ? nil : secondAccountID,
        categoryID: category,
        splits: splits,
        createdAt: date
    )
}

@Suite("BudgetEngine")
struct BudgetEngineTests {
    private let period = DateInterval(start: ts(Epoch.jan1_2025), end: ts(Epoch.feb1_2025))
    private let midJanuary = ts(Epoch.jan1_2025 + 15 * 86_400)

    private func makeBudget(
        amountMinor: Int64 = 100_000,
        rollover: BudgetRolloverPolicy = .expires,
        carriedOverMinor: Int64 = 0
    ) -> Budget {
        Budget(
            categoryID: categoryA,
            amount: rub(amountMinor),
            period: .monthly,
            rollover: rollover,
            carriedOverMinor: carriedOverMinor
        )
    }

    @Test("splits are authoritative: only matching split amounts count")
    func spendingHonorsSplits() throws {
        let budget = makeBudget()
        let mixedSplits = [
            TransactionSplit(categoryID: categoryA, amount: rub(30_000)),
            TransactionSplit(categoryID: categoryB, amount: rub(70_000)),
        ]
        let foreignSplits = [TransactionSplit(categoryID: categoryB, amount: rub(10_000))]
        let records = [
            expense(100_000, category: nil, date: ts(Epoch.jan1_2025 + 4 * 86_400), splits: mixedSplits),
            expense(20_000, category: categoryA, date: ts(Epoch.jan6_2025)),
            expense(10_000, category: categoryA, date: ts(Epoch.jan13_2025), splits: foreignSplits),
        ]

        let status = try BudgetEngine.status(budget: budget, expenses: records, period: period, now: midJanuary)

        #expect(status.spent == rub(50_000))
        #expect(status.remaining == rub(50_000))
        #expect(status.fractionUsedBasisPoints == 5_000)
    }

    @Test("only completed expenses count; period is half-open [start, end)")
    func statusAndPeriodFilters() throws {
        let budget = makeBudget()
        let records = [
            expense(10_000, category: categoryA, date: ts(Epoch.jan6_2025)),
            expense(40_000, category: categoryA, date: ts(Epoch.jan6_2025), status: .planned),
            expense(40_000, category: categoryA, date: ts(Epoch.jan6_2025), status: .expected),
            expense(40_000, category: categoryA, date: ts(Epoch.jan6_2025), status: .skipped),
            expense(40_000, category: categoryA, date: ts(Epoch.jan6_2025), status: .cancelled),
            expense(40_000, category: categoryA, date: ts(Epoch.feb1_2025)),
            expense(40_000, category: categoryA, date: ts(Epoch.jan1_2025 - 1)),
            expense(40_000, category: categoryA, date: ts(Epoch.jan1_2025)),
            expense(40_000, category: categoryA, date: ts(Epoch.jan6_2025), kind: .transfer),
        ]

        let status = try BudgetEngine.status(budget: budget, expenses: records, period: period, now: midJanuary)

        #expect(status.spent == rub(50_000))
    }

    @Test("pace: 72% spent at 48% elapsed reads hot")
    func paceHot() throws {
        let budget = makeBudget()
        let start = Epoch.jan1_2025
        let interval = DateInterval(start: ts(start), end: ts(start + 1_000_000))
        let now = ts(start + 480_000)
        let records = [expense(72_000, category: categoryA, date: ts(start + 100))]

        let status = try BudgetEngine.status(budget: budget, expenses: records, period: interval, now: now)

        #expect(status.fractionUsedBasisPoints == 7_200)
        #expect(status.periodElapsedBasisPoints == 4_800)
        #expect(status.pace == .hot)
    }

    @Test("pace: ahead when under-spending, onTrack within tolerance")
    func paceAheadAndOnTrack() throws {
        let budget = makeBudget()
        let start = Epoch.jan1_2025
        let interval = DateInterval(start: ts(start), end: ts(start + 1_000_000))
        let now = ts(start + 480_000)

        let ahead = try BudgetEngine.status(
            budget: budget,
            expenses: [expense(20_000, category: categoryA, date: ts(start + 100))],
            period: interval,
            now: now
        )
        let onTrack = try BudgetEngine.status(
            budget: budget,
            expenses: [expense(50_000, category: categoryA, date: ts(start + 100))],
            period: interval,
            now: now
        )

        #expect(ahead.pace == .ahead)
        #expect(onTrack.pace == .onTrack)
    }

    @Test("elapsed fraction clamps to 0 before start and 10000 after end")
    func elapsedClamping() throws {
        let budget = makeBudget()
        let before = try BudgetEngine.status(
            budget: budget, expenses: [], period: period, now: ts(Epoch.jan1_2025 - 86_400)
        )
        let after = try BudgetEngine.status(
            budget: budget, expenses: [], period: period, now: ts(Epoch.mar1_2025)
        )
        #expect(before.periodElapsedBasisPoints == 0)
        #expect(after.periodElapsedBasisPoints == 10_000)
    }

    @Test("overspend: remaining goes negative, fraction exceeds 10000")
    func overspendIsNotClamped() throws {
        let budget = makeBudget()
        let records = [expense(120_000, category: categoryA, date: ts(Epoch.jan6_2025))]

        let status = try BudgetEngine.status(budget: budget, expenses: records, period: period, now: midJanuary)

        #expect(status.remaining == rub(-20_000))
        #expect(status.fractionUsedBasisPoints == 12_000)
        #expect(status.pace == .hot)
    }

    @Test("carried-over amount extends the effective limit")
    func carriedOverExtendsLimit() throws {
        let budget = makeBudget(carriedOverMinor: 50_000)
        let records = [expense(60_000, category: categoryA, date: ts(Epoch.jan6_2025))]

        let status = try BudgetEngine.status(budget: budget, expenses: records, period: period, now: midJanuary)

        #expect(status.remaining == rub(90_000))
        #expect(status.fractionUsedBasisPoints == 4_000)
    }

    @Test("currency mismatch throws instead of silently under-counting")
    func currencyMismatchThrows() {
        let budget = makeBudget()
        let records = [expense(10_000, category: categoryA, date: ts(Epoch.jan6_2025), currency: .usd)]

        #expect(throws: MoneyError.self) {
            _ = try BudgetEngine.status(budget: budget, expenses: records, period: period, now: midJanuary)
        }
        #expect(throws: MoneyError.self) {
            _ = try BudgetEngine.rollover(budget: budget, spent: Money(minor: 1, currency: .usd))
        }
    }

    @Test("rollover: expires carries nothing and releases nothing")
    func rolloverExpires() throws {
        let outcome = try BudgetEngine.rollover(budget: makeBudget(rollover: .expires), spent: rub(40_000))
        #expect(outcome.nextCarriedOverMinor == 0)
        #expect(outcome.released == nil)
        #expect(outcome.releaseDestination == nil)
    }

    @Test("rollover: rollsOver carries positive unused, includes prior carry")
    func rolloverRollsOver() throws {
        let plain = try BudgetEngine.rollover(budget: makeBudget(rollover: .rollsOver), spent: rub(40_000))
        #expect(plain.nextCarriedOverMinor == 60_000)
        #expect(plain.released == nil)

        let withCarry = try BudgetEngine.rollover(
            budget: makeBudget(rollover: .rollsOver, carriedOverMinor: 20_000),
            spent: rub(40_000)
        )
        #expect(withCarry.nextCarriedOverMinor == 80_000)
    }

    @Test("rollover: overspend does not roll forward as debt by default")
    func rolloverOverspendDoesNotCarryDebt() throws {
        let outcome = try BudgetEngine.rollover(budget: makeBudget(rollover: .rollsOver), spent: rub(120_000))
        #expect(outcome.nextCarriedOverMinor == 0)
        #expect(outcome.released == nil)
    }

    @Test("rollover: toGoal and toFreeCash release unused money separately")
    func rolloverReleases() throws {
        let toGoal = try BudgetEngine.rollover(budget: makeBudget(rollover: .toGoal), spent: rub(40_000))
        #expect(toGoal.nextCarriedOverMinor == 0)
        #expect(toGoal.released == rub(60_000))
        #expect(toGoal.releaseDestination == .goal)

        let toFreeCash = try BudgetEngine.rollover(budget: makeBudget(rollover: .toFreeCash), spent: rub(40_000))
        #expect(toFreeCash.released == rub(60_000))
        #expect(toFreeCash.releaseDestination == .freeCash)

        let overspent = try BudgetEngine.rollover(budget: makeBudget(rollover: .toGoal), spent: rub(150_000))
        #expect(overspent.nextCarriedOverMinor == 0)
        #expect(overspent.released == nil)
        #expect(overspent.releaseDestination == nil)
    }

    @Test("explicit policy parameter overrides the budget's own policy")
    func rolloverPolicyOverride() throws {
        let outcome = try BudgetEngine.rollover(
            budget: makeBudget(rollover: .expires),
            spent: rub(40_000),
            policy: .rollsOver
        )
        #expect(outcome.nextCarriedOverMinor == 60_000)
    }
}

@Suite("RecurringScheduler")
struct RecurringSchedulerTests {
    private let scheduler = RecurringScheduler(calendar: utcCalendar)

    private func makeTemplate(
        kind: TransactionKind = .expense,
        amountMinor: Int64 = 10_000,
        recurrence: Recurrence,
        start: Int64,
        end: Int64? = nil,
        isActive: Bool = true,
        category: UUID? = categoryA,
        goal: UUID? = nil,
        name: String = "Template"
    ) -> RecurringTemplate {
        RecurringTemplate(
            name: name,
            kind: kind,
            amount: rub(amountMinor),
            recurrence: recurrence,
            sourceAccountID: kind == .income ? nil : accountID,
            destinationAccountID: kind == .expense ? nil : secondAccountID,
            categoryID: category,
            goalID: goal,
            isActive: isActive,
            startDate: ts(start),
            endDate: end.map { ts($0) }
        )
    }

    @Test("monthly on day 31 clamps to the last day of shorter months")
    func monthlyDay31ClampsAcrossFebruary() {
        let template = makeTemplate(recurrence: .monthly(day: 31), start: Epoch.jan31_2025)
        let interval = DateInterval(start: ts(Epoch.jan1_2025), end: ts(Epoch.may1_2025))

        let dates = scheduler.occurrences(of: template, in: interval)

        #expect(dates == [
            ts(Epoch.jan31_2025),
            ts(Epoch.feb28_2025),
            ts(Epoch.mar31_2025),
            ts(Epoch.apr30_2025),
        ])
    }

    @Test("monthly on day 31 lands on Feb 29 in a leap year")
    func monthlyDay31LeapFebruary() {
        let template = makeTemplate(recurrence: .monthly(day: 31), start: Epoch.jan1_2024)
        let interval = DateInterval(start: ts(Epoch.jan1_2024), end: ts(Epoch.mar1_2024))

        let dates = scheduler.occurrences(of: template, in: interval)

        #expect(dates == [ts(Epoch.jan31_2024), ts(Epoch.feb29_2024)])
    }

    @Test("weekly occurrences cross the month boundary; interval end excluded")
    func weeklyAcrossMonthBoundary() {
        let template = makeTemplate(recurrence: .weekly(weekday: 2), start: Epoch.jan27_2025)
        let interval = DateInterval(start: ts(Epoch.jan27_2025), end: ts(Epoch.feb17_2025))

        let dates = scheduler.occurrences(of: template, in: interval)

        #expect(dates == [ts(Epoch.jan27_2025), ts(Epoch.feb3_2025), ts(Epoch.feb10_2025)])
    }

    @Test("weekly first occurrence snaps forward to the requested weekday")
    func weeklySnapsToWeekday() {
        let template = makeTemplate(recurrence: .weekly(weekday: 2), start: Epoch.jan1_2025)
        let interval = DateInterval(start: ts(Epoch.jan1_2025), end: ts(Epoch.jan21_2025))

        let dates = scheduler.occurrences(of: template, in: interval)

        #expect(dates == [ts(Epoch.jan6_2025), ts(Epoch.jan13_2025), ts(Epoch.jan20_2025)])
    }

    @Test("everyNDays keeps cadence anchored to startDate across a window")
    func everyNDaysWindow() {
        let template = makeTemplate(recurrence: .everyNDays(10), start: Epoch.jan1_2025)
        let interval = DateInterval(start: ts(Epoch.jan25_2025), end: ts(Epoch.feb20_2025))

        let dates = scheduler.occurrences(of: template, in: interval)

        #expect(dates == [ts(Epoch.jan31_2025), ts(Epoch.feb10_2025)])
    }

    @Test("yearly Feb 30 clamps to Feb 28, or Feb 29 in leap years")
    func yearlyClampsFebruary() {
        let template = makeTemplate(recurrence: .yearly(month: 2, day: 30), start: Epoch.jan1_2023)
        let interval = DateInterval(start: ts(Epoch.jan1_2023), end: ts(Epoch.jun1_2025))

        let dates = scheduler.occurrences(of: template, in: interval)

        #expect(dates == [ts(Epoch.feb28_2023), ts(Epoch.feb29_2024), ts(Epoch.feb28_2025)])
    }

    @Test("isActive, startDate and inclusive endDate bound the series")
    func lifecycleBounds() {
        let interval = DateInterval(start: ts(Epoch.jan1_2025), end: ts(Epoch.mar1_2025))

        let inactive = makeTemplate(recurrence: .daily, start: Epoch.jan1_2025, isActive: false)
        #expect(scheduler.occurrences(of: inactive, in: interval).isEmpty)

        let lateStart = makeTemplate(recurrence: .monthly(day: 1), start: Epoch.feb1_2025)
        #expect(scheduler.occurrences(of: lateStart, in: interval) == [ts(Epoch.feb1_2025)])

        let ended = makeTemplate(
            recurrence: .daily,
            start: Epoch.jan1_2025,
            end: Epoch.jan1_2025 + 2 * 86_400
        )
        #expect(scheduler.occurrences(of: ended, in: interval) == [
            ts(Epoch.jan1_2025),
            ts(Epoch.jan1_2025 + 86_400),
            ts(Epoch.jan1_2025 + 2 * 86_400),
        ])
    }

    @Test("plannedRecords carry template identity and stay pure forecasts")
    func plannedRecordsFields() {
        let rent = makeTemplate(
            recurrence: .monthly(day: 1),
            start: Epoch.jan1_2025,
            name: "Rent"
        )
        let saving = makeTemplate(
            kind: .transfer,
            amountMinor: 25_000,
            recurrence: .monthly(day: 10),
            start: Epoch.jan1_2025,
            category: nil,
            goal: goalID,
            name: "Goal contribution"
        )
        let interval = DateInterval(start: ts(Epoch.jan1_2025), end: ts(Epoch.mar1_2025))

        let records = scheduler.plannedRecords(for: [saving, rent], in: interval)

        #expect(records.count == 4)
        #expect(records.map(\.date) == [
            ts(Epoch.jan1_2025), ts(Epoch.jan1_2025 + 9 * 86_400),
            ts(Epoch.feb1_2025), ts(Epoch.feb1_2025 + 9 * 86_400),
        ])
        #expect(records.allSatisfy { $0.status == .planned })
        #expect(records.allSatisfy { !$0.status.affectsActualBalance })

        let firstRent = records[0]
        #expect(firstRent.recurringTemplateID == rent.id)
        #expect(firstRent.kind == .expense)
        #expect(firstRent.amount == rub(10_000))
        #expect(firstRent.sourceAccountID == accountID)
        #expect(firstRent.categoryID == categoryA)
        #expect(firstRent.goalID == nil)

        let firstSaving = records[1]
        #expect(firstSaving.recurringTemplateID == saving.id)
        #expect(firstSaving.kind == .transfer)
        #expect(firstSaving.amount == rub(25_000))
        #expect(firstSaving.sourceAccountID == accountID)
        #expect(firstSaving.destinationAccountID == secondAccountID)
        #expect(firstSaving.goalID == goalID)
    }

    @Test("subscriptionSummary normalizes each cadence; view only")
    func subscriptionSummaryConversions() {
        let monthly = makeTemplate(amountMinor: 99_900, recurrence: .monthly(day: 1), start: Epoch.jan1_2025, name: "Streaming")
        let weekly = makeTemplate(amountMinor: 10_000, recurrence: .weekly(weekday: 2), start: Epoch.jan1_2025, name: "Cleaning")
        let daily = makeTemplate(amountMinor: 500, recurrence: .daily, start: Epoch.jan1_2025, name: "Coffee")
        let yearly = makeTemplate(amountMinor: 120_000, recurrence: .yearly(month: 1, day: 1), start: Epoch.jan1_2025, name: "Domain")
        let every30 = makeTemplate(amountMinor: 30_000, recurrence: .everyNDays(30), start: Epoch.jan1_2025, name: "Lenses")
        let inactive = makeTemplate(recurrence: .monthly(day: 1), start: Epoch.jan1_2025, isActive: false, name: "Paused")
        let income = makeTemplate(kind: .income, recurrence: .monthly(day: 5), start: Epoch.jan1_2025, name: "Salary")

        let summaries = RecurringScheduler.subscriptionSummary(
            templates: [monthly, weekly, daily, yearly, every30, inactive, income]
        )

        #expect(summaries.count == 5)
        #expect(summaries[0].monthlyEquivalent == rub(99_900))
        #expect(summaries[0].yearlyEquivalent == rub(1_198_800))
        #expect(summaries[1].yearlyEquivalent == rub(520_000))
        #expect(summaries[1].monthlyEquivalent == rub(43_333))
        #expect(summaries[2].yearlyEquivalent == rub(182_500))
        #expect(summaries[2].monthlyEquivalent == rub(15_208))
        #expect(summaries[3].monthlyEquivalent == rub(10_000))
        #expect(summaries[3].yearlyEquivalent == rub(120_000))
        #expect(summaries[4].yearlyEquivalent == rub(365_000))
        #expect(summaries[4].monthlyEquivalent == rub(30_417))
        #expect(summaries[0].templateID == monthly.id)
        #expect(summaries[0].name == "Streaming")
    }

    @Test("expectedEventStatus partitions without auto-converting state")
    func expectedEventPartition() {
        let now = ts(Epoch.feb1_2025)
        let future = ExpectedEvent(title: "Bonus", amount: rub(100), expectedDate: ts(Epoch.mar1_2025))
        let dueNow = ExpectedEvent(title: "Due now", amount: rub(100), expectedDate: now)
        let pastStillExpected = ExpectedEvent(title: "Late invoice", amount: rub(100), expectedDate: ts(Epoch.jan13_2025))
        let markedOverdue = ExpectedEvent(title: "Old invoice", amount: rub(100), expectedDate: ts(Epoch.jan6_2025), state: .overdue)
        let received = ExpectedEvent(title: "Paid", amount: rub(100), expectedDate: ts(Epoch.jan1_2025), state: .received)
        let cancelled = ExpectedEvent(title: "Void", amount: rub(100), expectedDate: ts(Epoch.may1_2025), state: .cancelled)

        let partition = RecurringScheduler.expectedEventStatus(
            events: [future, dueNow, pastStillExpected, markedOverdue, received, cancelled],
            now: now
        )

        #expect(partition.upcoming.map(\.id) == [dueNow.id, future.id])
        #expect(partition.needsAttention.map(\.id) == [markedOverdue.id, pastStillExpected.id])
        #expect(partition.needsAttention.last?.state == .expected)
        #expect(!partition.needsAttention.contains(where: { $0.id == received.id }))
        #expect(!partition.upcoming.contains(where: { $0.id == cancelled.id }))
    }
}
