#if DEBUG
import Foundation
import FinPlanCore

@MainActor
enum DemoSeed {
    static func seedIfRequested(store: FinanceStore) {
        guard ProcessInfo.processInfo.arguments.contains("--demo-seed"),
              store.accounts.isEmpty, !store.onboardingCompleted else { return }

        let now = Date()
        let calendar = Calendar.current
        func day(_ day: Int, monthOffset: Int = 0) -> Date {
            var components = calendar.dateComponents([.year, .month], from: now)
            components.month = (components.month ?? 1) + monthOffset
            components.day = day
            return calendar.date(from: components) ?? now
        }

        store.setBaseCurrency(.rub)
        if let rate = ExchangeRate(base: .usd, quote: .rub, decimalString: "78.5") {
            store.upsertPlanningRate(rate)
        }

        let main = Account(name: "Основной счёт", currency: .rub, type: .checking,
                           openingBalance: Money(major: 850_000, currency: .rub), createdAt: now)
        store.addAccount(main)
        let savings = Account(name: "Накопительный", currency: .rub, type: .savings,
                              openingBalance: .zero(.rub), createdAt: now)
        store.addAccount(savings)

        let goal = Goal(title: "Квартира", symbolName: "house.fill",
                        targetAmount: Money(major: 3_500_000, currency: .rub),
                        startDate: now,
                        desiredCompletionDate: calendar.date(byAdding: .month, value: 24, to: now),
                        priority: .high)
        store.addGoal(goal)
        store.addAllocation(GoalAllocation(goalID: goal.id, accountID: main.id,
                                           amount: Money(major: 850_000, currency: .rub), date: now))

        store.addIncomeSource(IncomeSource(name: "Зарплата", grossAmount: Money(major: 220_000, currency: .rub),
                                           recurrence: .monthly(day: 5), destinationAccountID: main.id))
        store.addIncomeSource(IncomeSource(name: "Фриланс", grossAmount: Money(major: 1_500, currency: .usd),
                                           share: .percentageBasisPoints(5_000),
                                           recurrence: .monthly(day: 20), destinationAccountID: main.id))

        var categories: [String: TransactionCategory] = [:]
        for (name, symbol, essential) in [
            ("Продукты", "cart.fill", true), ("Кафе", "cup.and.saucer.fill", false),
            ("Транспорт", "car.fill", true), ("Подписки", "arrow.triangle.2.circlepath", false),
            ("Аренда", "house.fill", true),
        ] {
            let category = TransactionCategory(name: name, symbolName: symbol, isEssential: essential)
            store.addCategory(category)
            categories[name] = category
        }

        store.addRecurringTemplate(RecurringTemplate(
            name: "Взнос на квартиру", kind: .transfer,
            amount: Money(major: 120_000, currency: .rub), recurrence: .monthly(day: 7),
            sourceAccountID: main.id, destinationAccountID: savings.id,
            goalID: goal.id, startDate: day(7)))
        store.addRecurringTemplate(RecurringTemplate(
            name: "Аренда", kind: .expense, amount: Money(major: 45_000, currency: .rub),
            recurrence: .monthly(day: 20), sourceAccountID: main.id,
            categoryID: categories["Аренда"]?.id, startDate: day(20, monthOffset: -2)))
        store.addRecurringTemplate(RecurringTemplate(
            name: "Подписки", kind: .expense, amount: Money(minor: 199_000, currency: .rub),
            recurrence: .monthly(day: 12), sourceAccountID: main.id,
            categoryID: categories["Подписки"]?.id, startDate: day(12, monthOffset: -2)))

        store.addExpectedEvent(ExpectedEvent(
            title: "Продажа машины", amount: Money(major: 400_000, currency: .rub),
            expectedDate: day(15, monthOffset: 3), destinationAccountID: main.id, goalID: goal.id))

        store.addBudget(Budget(categoryID: categories["Продукты"]!.id,
                               amount: Money(major: 30_000, currency: .rub)))

        let operations: [(TransactionKind, Int64, String?, Int, Int)] = [
            (.income, 220_000, nil, 5, 0), (.income, 220_000, nil, 5, -1),
            (.expense, 6_420, "Продукты", 8, 0), (.expense, 2_340, "Кафе", 10, 0),
            (.expense, 1_200, "Транспорт", 11, 0), (.expense, 1_990, "Подписки", 12, 0),
            (.expense, 45_000, "Аренда", 20, -1), (.expense, 24_300, "Продукты", 18, -1),
        ]
        for (kind, major, categoryName, dayOfMonth, monthOffset) in operations {
            let record = TransactionRecord(
                date: day(dayOfMonth, monthOffset: monthOffset), kind: kind,
                amount: Money(major: major, currency: .rub),
                sourceAccountID: kind == .expense ? main.id : nil,
                destinationAccountID: kind == .income ? main.id : nil,
                categoryID: categoryName.flatMap { categories[$0]?.id },
                createdAt: now)
            try? store.addTransaction(record)
        }
        for offset in [0, -1] {
            try? store.addTransaction(TransactionRecord(
                date: day(7, monthOffset: offset), kind: .transfer,
                amount: Money(major: 120_000, currency: .rub),
                sourceAccountID: main.id, destinationAccountID: savings.id,
                goalID: goal.id, createdAt: now))
        }

        store.onboardingCompleted = true
    }

    static func applyNavigation(router: AppRouter, store: FinanceStore) {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--demo-tab"),
           arguments.indices.contains(index + 1),
           let tab = Int(arguments[index + 1]) {
            router.selectedTab = tab
        }
        if arguments.contains("--demo-goal"), let goal = store.goals.first {
            router.open(.goal(goal.id))
        }
    }
}
#endif
