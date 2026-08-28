#if DEBUG
import Foundation
import FinPlanCore

@MainActor
enum TransactionsPreviewData {
    static func makeStore(seeded: Bool = true) -> FinanceStore {
        let controller = PersistenceController.preview()
        let store = FinanceStore(context: controller.container.mainContext)
        if seeded { seed(store) }
        return store
    }

    private static func seed(_ store: FinanceStore) {
        let now = Date()
        let calendar = Calendar.current
        func days(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: now) ?? now
        }

        let card = Account(
            name: "Debit Card",
            currency: .rub,
            type: .checking,
            openingBalance: Money(major: 120_000, currency: .rub),
            createdAt: days(-400)
        )
        let savings = Account(
            name: "Savings",
            currency: .rub,
            type: .savings,
            openingBalance: Money(major: 850_000, currency: .rub),
            createdAt: days(-400)
        )
        let usdCash = Account(
            name: "USD Cash",
            currency: .usd,
            type: .cash,
            openingBalance: Money(major: 2_500, currency: .usd),
            createdAt: days(-300)
        )
        store.addAccount(card)
        store.addAccount(savings)
        store.addAccount(usdCash)

        let goal = Goal(
            title: "Apartment down payment",
            symbolName: "house.fill",
            targetAmount: Money(major: 6_000_000, currency: .rub),
            startDate: days(-180)
        )
        store.addGoal(goal)

        store.addTag(TransactionTag(name: "family"))
        store.addTag(TransactionTag(name: "vacation"))
        let familyTag = store.tags.first { $0.name == "family" }

        func category(_ name: String) -> UUID? {
            store.categories.first { $0.name == name }?.id
        }

        let records: [TransactionRecord] = [
            TransactionRecord(
                date: days(-3),
                kind: .income,
                amount: Money(major: 4_000, currency: .usd),
                destinationAccountID: usdCash.id,
                note: "Contract payment",
                createdAt: days(-3)
            ),
            TransactionRecord(
                date: days(-2),
                kind: .currencyExchange,
                amount: Money(major: 1_000, currency: .usd),
                sourceAccountID: usdCash.id,
                destinationAccountID: card.id,
                counterAmount: Money(minor: 8_428_200, currency: .rub),
                fee: Money(major: 300, currency: .rub),
                createdAt: days(-2)
            ),
            TransactionRecord(
                date: days(-2),
                kind: .transfer,
                amount: Money(major: 50_000, currency: .rub),
                sourceAccountID: card.id,
                destinationAccountID: savings.id,
                goalID: goal.id,
                createdAt: days(-2)
            ),
            TransactionRecord(
                date: days(-1),
                kind: .expense,
                amount: Money(major: 3_600, currency: .rub),
                sourceAccountID: card.id,
                note: "Hypermarket run",
                splits: [
                    TransactionSplit(categoryID: category("Food"), amount: Money(major: 2_100, currency: .rub)),
                    TransactionSplit(categoryID: category("Home"), amount: Money(major: 1_500, currency: .rub)),
                ],
                createdAt: days(-1)
            ),
            TransactionRecord(
                date: now,
                kind: .expense,
                amount: Money(minor: 125_050, currency: .rub),
                sourceAccountID: card.id,
                categoryID: category("Food"),
                note: "Groceries",
                tagIDs: familyTag.map { [$0.id] } ?? [],
                createdAt: now
            ),
            TransactionRecord(
                date: now,
                kind: .expense,
                amount: Money(major: 450, currency: .rub),
                sourceAccountID: card.id,
                categoryID: category("Transport"),
                createdAt: now
            ),
            TransactionRecord(
                date: days(-5),
                kind: .expense,
                amount: Money(major: 2_300, currency: .rub),
                sourceAccountID: card.id,
                categoryID: category("Entertainment"),
                note: "Cinema night",
                createdAt: days(-5)
            ),
            TransactionRecord(
                date: days(2),
                kind: .expense,
                status: .planned,
                amount: Money(minor: 79_900, currency: .rub),
                sourceAccountID: card.id,
                categoryID: category("Subscriptions"),
                note: "Music subscription",
                createdAt: now
            ),
        ]
        for record in records {
            try? store.addTransaction(record)
        }
    }
}
#endif
