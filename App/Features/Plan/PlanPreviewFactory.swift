#if DEBUG
import Foundation
import FinPlanCore

@MainActor
enum PlanPreviewFactory {
    static func makeEmptyStore() -> FinanceStore {
        let controller = PersistenceController.preview()
        return FinanceStore(context: controller.container.mainContext)
    }

    static func makeStore() -> FinanceStore {
        let store = makeEmptyStore()
        seed(store)
        return store
    }

    private static func seed(_ store: FinanceStore) {
        let calendar = Calendar.current
        let now = Date.now
        func months(_ delta: Int) -> Date {
            calendar.date(byAdding: .month, value: delta, to: now) ?? now
        }
        func days(_ delta: Int) -> Date {
            calendar.date(byAdding: .day, value: delta, to: now) ?? now
        }

        store.setBaseCurrency(.rub)
        if let rate = ExchangeRate(base: .usd, quote: .rub, decimalString: "84.282") {
            store.planningRates = ManualExchangeRates(rates: [rate])
        }

        let card = Account(
            name: "Card RUB", currency: .rub, type: .checking,
            openingBalance: Money(major: 250_000, currency: .rub), createdAt: months(-9)
        )
        let cash = Account(
            name: "USD Cash", currency: .usd, type: .cash,
            openingBalance: Money(major: 6_000, currency: .usd), createdAt: months(-9)
        )
        let broker = Account(
            name: "Broker", currency: .usd, type: .investment,
            openingBalance: Money(major: 2_000, currency: .usd), createdAt: months(-9)
        )
        store.addAccount(card)
        store.addAccount(cash)
        store.addAccount(broker)

        let goal = Goal(
            title: "Apartment",
            symbolName: "house.fill",
            targetAmount: Money(major: 6_000_000, currency: .rub),
            startDate: months(-8),
            desiredCompletionDate: months(13),
            priority: .high
        )
        store.addGoal(goal)
        store.addAllocation(GoalAllocation(
            goalID: goal.id,
            accountID: card.id,
            amount: Money(major: 850_000, currency: .rub),
            date: days(-2)
        ))

        store.addIncomeSource(IncomeSource(
            name: "Business",
            grossAmount: Money(major: 8_000, currency: .usd),
            share: .percentageBasisPoints(5_000),
            recurrence: .monthly(day: 10),
            destinationAccountID: cash.id
        ))
        store.addIncomeSource(IncomeSource(
            name: "Salary",
            grossAmount: Money(major: 150_000, currency: .rub),
            share: .percentageBasisPoints(10_000),
            recurrence: .monthly(day: 5),
            destinationAccountID: card.id
        ))

        store.addRecurringTemplate(RecurringTemplate(
            name: "Goal contribution",
            kind: .transfer,
            amount: Money(major: 4_000, currency: .usd),
            recurrence: .monthly(day: 12),
            sourceAccountID: cash.id,
            destinationAccountID: broker.id,
            goalID: goal.id,
            startDate: months(-8)
        ))
        store.addRecurringTemplate(RecurringTemplate(
            name: "Rent",
            kind: .expense,
            amount: Money(major: 60_000, currency: .rub),
            recurrence: .monthly(day: 1),
            sourceAccountID: card.id,
            startDate: months(-8)
        ))
        store.addRecurringTemplate(RecurringTemplate(
            name: "Internet",
            kind: .expense,
            amount: Money(major: 900, currency: .rub),
            recurrence: .monthly(day: 20),
            sourceAccountID: card.id,
            startDate: months(-6)
        ))

        store.addExpectedEvent(ExpectedEvent(
            title: "Bonus",
            amount: Money(major: 1_695_000, currency: .rub),
            expectedDate: months(3),
            destinationAccountID: card.id,
            goalID: goal.id
        ))
        store.addExpectedEvent(ExpectedEvent(
            title: "Client payment",
            amount: Money(major: 120_000, currency: .rub),
            expectedDate: days(-6),
            destinationAccountID: card.id
        ))

        let category = store.categories.first?.id
        try? store.addTransaction(TransactionRecord(
            date: days(-20),
            kind: .income,
            amount: Money(major: 150_000, currency: .rub),
            destinationAccountID: card.id,
            note: "Salary",
            createdAt: days(-20)
        ))
        try? store.addTransaction(TransactionRecord(
            date: days(-3),
            kind: .income,
            amount: Money(major: 150_000, currency: .rub),
            destinationAccountID: card.id,
            note: "Salary",
            createdAt: days(-3)
        ))
        try? store.addTransaction(TransactionRecord(
            date: days(-2),
            kind: .transfer,
            amount: Money(major: 4_000, currency: .usd),
            sourceAccountID: cash.id,
            destinationAccountID: broker.id,
            goalID: goal.id,
            note: "Goal contribution",
            createdAt: days(-2)
        ))
        try? store.addTransaction(TransactionRecord(
            date: days(-1),
            kind: .expense,
            amount: Money(major: 12_400, currency: .rub),
            sourceAccountID: card.id,
            categoryID: category,
            note: "Groceries",
            createdAt: days(-1)
        ))
    }
}
#endif
