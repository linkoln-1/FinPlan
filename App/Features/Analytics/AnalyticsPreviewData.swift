#if DEBUG
import Foundation
import FinPlanCore

@MainActor
enum AnalyticsPreviewData {
    static func seed(_ store: FinanceStore) {
        let calendar = Calendar.current
        let now = Date()

        store.planningRates = ManualExchangeRates(rates: [
            ExchangeRate(base: .usd, quote: .rub, decimalString: "84.282")
                ?? ExchangeRate(base: .usd, quote: .rub, rateScaled: 84_282_000, scale: 6),
        ])

        let main = Account(
            name: "Main card",
            currency: .rub,
            type: .checking,
            openingBalance: Money(major: 150_000, currency: .rub),
            createdAt: date(monthsAgo: 8, day: 1, calendar: calendar, now: now)
        )
        let savings = Account(
            name: "Savings",
            currency: .rub,
            type: .savings,
            openingBalance: Money(major: 850_000, currency: .rub),
            createdAt: date(monthsAgo: 8, day: 1, calendar: calendar, now: now)
        )
        let usdReserve = Account(
            name: "USD reserve",
            currency: .usd,
            type: .savings,
            openingBalance: Money(major: 2_500, currency: .usd),
            createdAt: date(monthsAgo: 8, day: 1, calendar: calendar, now: now)
        )
        store.addAccount(main)
        store.addAccount(savings)
        store.addAccount(usdReserve)

        let goal = Goal(
            title: "Apartment",
            symbolName: "house.fill",
            targetAmount: Money(major: 6_000_000, currency: .rub),
            startDate: date(monthsAgo: 8, day: 1, calendar: calendar, now: now)
        )
        store.addGoal(goal)
        store.addAllocation(GoalAllocation(
            goalID: goal.id,
            accountID: savings.id,
            amount: Money(major: 850_000, currency: .rub),
            date: date(monthsAgo: 8, day: 2, calendar: calendar, now: now)
        ))

        let vacationTag = TransactionTag(name: "Vacation")
        let familyTag = TransactionTag(name: "Family")
        store.addTag(vacationTag)
        store.addTag(familyTag)

        func categoryID(_ name: String) -> UUID? {
            store.categories.first { $0.name == name }?.id
        }

        let contributionUSD = Money(major: 4_000, currency: .usd)
        let contributionRUB = Money(major: 337_128, currency: .rub)

        for monthsAgo in stride(from: 7, through: 1, by: -1) {
            let day: (Int) -> Date = { day in
                date(monthsAgo: monthsAgo, day: day, calendar: calendar, now: now)
            }

            add(store, kind: .income, date: day(3), amount: Money(major: 250_000, currency: .rub),
                destination: main.id, category: nil)
            add(store, kind: .income, date: day(4), amount: contributionUSD,
                destination: usdReserve.id, category: nil)

            try? store.addTransaction(TransactionRecord(
                date: day(5),
                kind: .currencyExchange,
                amount: contributionUSD,
                sourceAccountID: usdReserve.id,
                destinationAccountID: main.id,
                counterAmount: contributionRUB,
                createdAt: day(5)
            ))
            try? store.addTransaction(TransactionRecord(
                date: day(6),
                kind: .transfer,
                amount: contributionRUB,
                sourceAccountID: main.id,
                destinationAccountID: savings.id,
                goalID: goal.id,
                createdAt: day(6)
            ))
            store.addAllocation(GoalAllocation(
                goalID: goal.id,
                accountID: savings.id,
                amount: contributionRUB,
                date: day(6)
            ))

            add(store, kind: .expense, date: day(8),
                amount: Money(major: 40_000 + Int64(monthsAgo) * 700, currency: .rub),
                source: main.id, category: categoryID("Food"))
            add(store, kind: .expense, date: day(2),
                amount: Money(major: 65_000, currency: .rub),
                source: main.id, category: categoryID("Home"))
            add(store, kind: .expense, date: day(12),
                amount: Money(major: 12_500, currency: .rub),
                source: main.id, category: categoryID("Transport"))
            add(store, kind: .expense, date: day(15),
                amount: Money(major: 7_000, currency: .rub),
                source: main.id, category: categoryID("Entertainment"))
            if monthsAgo % 2 == 0 {
                add(store, kind: .expense, date: day(17),
                    amount: Money(major: 5_200, currency: .rub),
                    source: main.id, category: categoryID("Health"))
            }
            try? store.addTransaction(TransactionRecord(
                date: day(20),
                kind: .expense,
                amount: Money(major: 15_000, currency: .rub),
                sourceAccountID: main.id,
                tagIDs: [familyTag.id],
                splits: [
                    TransactionSplit(categoryID: categoryID("Shopping"),
                                     amount: Money(major: 9_000, currency: .rub)),
                    TransactionSplit(categoryID: categoryID("Technology"),
                                     amount: Money(major: 6_000, currency: .rub)),
                ],
                createdAt: day(20)
            ))
            if monthsAgo == 3 {
                try? store.addTransaction(TransactionRecord(
                    date: day(22),
                    kind: .expense,
                    amount: Money(major: 80_000, currency: .rub),
                    sourceAccountID: main.id,
                    categoryID: categoryID("Travel"),
                    tagIDs: [vacationTag.id],
                    createdAt: day(22)
                ))
            }
        }

        let currentDay: (Int) -> Date = { day in
            min(date(monthsAgo: 0, day: day, calendar: calendar, now: now), now)
        }
        add(store, kind: .income, date: currentDay(3), amount: Money(major: 250_000, currency: .rub),
            destination: main.id, category: nil)
        add(store, kind: .expense, date: currentDay(4),
            amount: Money(major: 18_000, currency: .rub),
            source: main.id, category: categoryID("Food"))
        add(store, kind: .expense, date: currentDay(5),
            amount: Money(major: 12_000, currency: .rub),
            source: main.id, category: categoryID("Entertainment"))

        if let foodID = categoryID("Food") {
            store.addBudget(Budget(
                categoryID: foodID,
                amount: Money(major: 45_000, currency: .rub),
                period: .monthly,
                rollover: .rollsOver
            ))
        }
        if let entertainmentID = categoryID("Entertainment") {
            store.addBudget(Budget(
                categoryID: entertainmentID,
                amount: Money(major: 10_000, currency: .rub),
                period: .monthly,
                rollover: .expires
            ))
        }

        store.addExpectedEvent(ExpectedEvent(
            title: "Contract payout",
            amount: Money(major: 1_695_000, currency: .rub),
            expectedDate: calendar.date(byAdding: .day, value: 20, to: now) ?? now,
            destinationAccountID: main.id
        ))
        store.addExpectedEvent(ExpectedEvent(
            title: "Freelance invoice",
            amount: Money(major: 120_000, currency: .rub),
            expectedDate: calendar.date(byAdding: .day, value: -6, to: now) ?? now,
            state: .overdue,
            destinationAccountID: main.id
        ))
    }

    private static func add(
        _ store: FinanceStore,
        kind: TransactionKind,
        date: Date,
        amount: Money,
        source: UUID? = nil,
        destination: UUID? = nil,
        category: UUID?
    ) {
        try? store.addTransaction(TransactionRecord(
            date: date,
            kind: kind,
            amount: amount,
            sourceAccountID: source,
            destinationAccountID: destination,
            categoryID: category,
            createdAt: date
        ))
    }

    private static func date(monthsAgo: Int, day: Int, calendar: Calendar, now: Date) -> Date {
        let currentMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let monthStart = calendar.date(byAdding: .month, value: -monthsAgo, to: currentMonthStart)
            ?? currentMonthStart
        return calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
    }
}
#endif
