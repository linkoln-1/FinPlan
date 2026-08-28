import Foundation
import FinPlanCore

struct Achievement: Identifiable, Hashable, Sendable {
    let id: String
    let symbolName: String
    let titleKey: String
    let achievedDate: Date?
}

enum AchievementsEvaluator {
    private static let totalSavedMilestones: [(majorUnits: Int64, id: String, symbol: String, titleKey: String)] = [
        (100_000, "saved.100k", "medal", "achievements.saved.100k"),
        (1_000_000, "saved.1m", "trophy", "achievements.saved.1m"),
    ]

    private static let goalMilestonesBasisPoints: [(bps: Int64, id: String, symbol: String, titleKey: String)] = [
        (2_500, "primaryGoal.25", "flag", "achievements.primaryGoal.25"),
        (5_000, "primaryGoal.50", "flag.fill", "achievements.primaryGoal.50"),
        (7_500, "primaryGoal.75", "flag.2.crossed", "achievements.primaryGoal.75"),
        (10_000, "primaryGoal.100", "checkmark.seal.fill", "achievements.primaryGoal.100"),
    ]

    private static let savingsStreakMonths = 3

    static func evaluate(
        goals: [Goal],
        allocations: [GoalAllocation],
        transactions: [TransactionRecord],
        accounts: [Account],
        baseCurrency: Currency,
        rates: ManualExchangeRates,
        calendar: Calendar,
        now: Date
    ) throws -> [Achievement] {
        var achievements: [Achievement] = []
        achievements += try totalSavedAchievements(
            allocations: allocations, baseCurrency: baseCurrency, rates: rates, now: now
        )
        achievements += try primaryGoalAchievements(
            goals: goals, allocations: allocations, rates: rates, now: now
        )
        achievements += try savingsStreakAchievements(
            transactions: transactions, accounts: accounts,
            baseCurrency: baseCurrency, rates: rates, calendar: calendar, now: now
        )
        return achievements.sorted { lhs, rhs in
            switch (lhs.achievedDate, rhs.achievedDate) {
            case let (left?, right?) where left != right: return left < right
            case (nil, .some): return false
            case (.some, nil): return true
            default: return lhs.id < rhs.id
            }
        }
    }

    private static func totalSavedAchievements(
        allocations: [GoalAllocation],
        baseCurrency: Currency,
        rates: ManualExchangeRates,
        now: Date
    ) throws -> [Achievement] {
        var running = Money.zero(baseCurrency)
        var result: [Achievement] = []
        var milestoneIndex = 0
        for allocation in sortedByDate(allocations.filter { $0.date <= now }) {
            running = try running.adding(convert(allocation.amount, to: baseCurrency, rates: rates))
            while milestoneIndex < totalSavedMilestones.count {
                let milestone = totalSavedMilestones[milestoneIndex]
                let threshold = Money(major: milestone.majorUnits, currency: baseCurrency)
                guard try running.comparing(threshold) >= 0 else { break }
                result.append(Achievement(
                    id: milestone.id,
                    symbolName: milestone.symbol,
                    titleKey: milestone.titleKey,
                    achievedDate: allocation.date
                ))
                milestoneIndex += 1
            }
        }
        return result
    }

    private static func primaryGoalAchievements(
        goals: [Goal],
        allocations: [GoalAllocation],
        rates: ManualExchangeRates,
        now: Date
    ) throws -> [Achievement] {
        guard let goal = primaryGoal(in: goals) else { return [] }
        let currency = goal.targetAmount.currency
        var running = Money.zero(currency)
        var result: [Achievement] = []
        var milestoneIndex = 0
        for allocation in sortedByDate(allocations.filter { $0.goalID == goal.id && $0.date <= now }) {
            running = try running.adding(convert(allocation.amount, to: currency, rates: rates))
            while milestoneIndex < goalMilestonesBasisPoints.count {
                let milestone = goalMilestonesBasisPoints[milestoneIndex]
                let threshold = goal.targetAmount.multiplied(
                    byNumerator: milestone.bps, denominator: 10_000
                )
                guard try running.comparing(threshold) >= 0 else { break }
                result.append(Achievement(
                    id: milestone.id,
                    symbolName: milestone.symbol,
                    titleKey: milestone.titleKey,
                    achievedDate: allocation.date
                ))
                milestoneIndex += 1
            }
        }
        return result
    }

    private static func primaryGoal(in goals: [Goal]) -> Goal? {
        goals
            .filter { $0.status == .active && !$0.isEmergencyFund }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first
    }

    private static func savingsStreakAchievements(
        transactions: [TransactionRecord],
        accounts: [Account],
        baseCurrency: Currency,
        rates: ManualExchangeRates,
        calendar: Calendar,
        now: Date
    ) throws -> [Achievement] {
        let monthsBack = savingsStreakMonths + 1
        let trends = try AnalyticsEngine.trends(
            monthsBack: monthsBack,
            endingAt: now,
            calendar: calendar,
            transactions: transactions,
            accounts: accounts,
            rates: rates,
            baseCurrency: baseCurrency
        )
        guard trends.count == monthsBack else { return [] }
        let completedMonths = trends.dropLast()
        guard completedMonths.allSatisfy({ $0.savingsAllocated.isPositive }) else { return [] }
        return [Achievement(
            id: "savingsStreak.3",
            symbolName: "calendar.badge.checkmark",
            titleKey: "achievements.savingsStreak.3",
            achievedDate: trends.last?.monthStart
        )]
    }

    private static func sortedByDate(_ allocations: [GoalAllocation]) -> [GoalAllocation] {
        allocations.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func convert(
        _ money: Money,
        to currency: Currency,
        rates: ManualExchangeRates
    ) throws -> Money {
        if money.currency == currency { return money }
        guard let rate = rates.rate(from: money.currency, to: currency) else {
            throw LedgerError.missingExchangeRate(base: money.currency.code, quote: currency.code)
        }
        return try rate.convert(money)
    }
}
