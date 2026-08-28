#if DEBUG
import Foundation
import FinPlanCore

@MainActor
enum GoalsPreviewFixtures {
    static let apartmentGoalID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    static let emergencyGoalID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!

    static func emptyStore() -> FinanceStore {
        let controller = PersistenceController.preview()
        return FinanceStore(context: controller.container.mainContext)
    }

    static func store() -> FinanceStore {
        let store = emptyStore()
        let calendar = Calendar.current
        let now = Date()
        func monthsAgo(_ months: Int) -> Date {
            calendar.date(byAdding: .month, value: -months, to: now) ?? now
        }
        func monthsAhead(_ months: Int) -> Date {
            calendar.date(byAdding: .month, value: months, to: now) ?? now
        }

        store.planningRates = ManualExchangeRates(rates: [
            ExchangeRate(base: .usd, quote: .rub, rateScaled: 84_282_000, scale: 6),
        ])
        store.minimumCashBuffer = Money(major: 100_000, currency: .rub)

        let card = Account(
            name: "Debit card", currency: .rub, type: .checking,
            openingBalance: Money(major: 500_000, currency: .rub), createdAt: monthsAgo(12)
        )
        let savings = Account(
            name: "Savings", currency: .rub, type: .savings,
            openingBalance: Money(major: 750_000, currency: .rub), createdAt: monthsAgo(12)
        )
        let usdCash = Account(
            name: "USD cash", currency: .usd, type: .cash,
            openingBalance: Money(major: 2_000, currency: .usd), createdAt: monthsAgo(10)
        )
        store.addAccount(card)
        store.addAccount(savings)
        store.addAccount(usdCash)

        let apartment = Goal(
            id: apartmentGoalID,
            title: "Apartment",
            symbolName: "house.fill",
            targetAmount: Money(major: 6_000_000, currency: .rub),
            startDate: monthsAgo(6),
            desiredCompletionDate: monthsAhead(14),
            priority: .high,
            status: .active
        )
        let emergency = Goal(
            id: emergencyGoalID,
            title: "Emergency fund",
            symbolName: "shield.lefthalf.filled",
            targetAmount: Money(major: 600_000, currency: .rub),
            startDate: monthsAgo(4),
            priority: .medium,
            status: .active,
            isEmergencyFund: true,
            desiredMonthsOfExpenses: 6
        )
        let car = Goal(
            title: "New car",
            symbolName: "car.fill",
            targetAmount: Money(major: 1_500_000, currency: .rub),
            startDate: monthsAgo(2),
            priority: .low,
            status: .paused
        )
        let vacation = Goal(
            title: "Vacation",
            symbolName: "airplane",
            targetAmount: Money(major: 200_000, currency: .rub),
            startDate: monthsAgo(8),
            priority: .low,
            status: .completed
        )
        store.addGoal(apartment)
        store.addGoal(emergency)
        store.addGoal(car)
        store.addGoal(vacation)

        store.addAllocation(GoalAllocation(
            goalID: apartment.id, accountID: savings.id,
            amount: Money(major: 500_000, currency: .rub), date: monthsAgo(5)
        ))
        store.addAllocation(GoalAllocation(
            goalID: apartment.id, accountID: savings.id,
            amount: Money(major: 350_000, currency: .rub), date: monthsAgo(2)
        ))
        store.addAllocation(GoalAllocation(
            goalID: emergency.id, accountID: card.id,
            amount: Money(major: 150_000, currency: .rub), date: monthsAgo(3)
        ))
        store.addAllocation(GoalAllocation(
            goalID: vacation.id, accountID: savings.id,
            amount: Money(major: 200_000, currency: .rub), date: monthsAgo(7)
        ))

        store.addRecurringTemplate(RecurringTemplate(
            name: "Monthly savings",
            kind: .transfer,
            amount: Money(major: 4_000, currency: .usd),
            recurrence: .monthly(day: 5),
            sourceAccountID: card.id,
            destinationAccountID: savings.id,
            goalID: apartment.id,
            startDate: monthsAgo(6)
        ))

        store.addExpectedEvent(ExpectedEvent(
            title: "Apartment sale proceeds",
            amount: Money(major: 1_695_000, currency: .rub),
            expectedDate: monthsAhead(3),
            goalID: apartment.id
        ))

        try? store.addTransaction(TransactionRecord(
            date: monthsAgo(4),
            kind: .transfer,
            amount: Money(major: 150_000, currency: .rub),
            sourceAccountID: card.id,
            destinationAccountID: savings.id,
            goalID: apartment.id,
            createdAt: monthsAgo(4)
        ))
        try? store.addTransaction(TransactionRecord(
            date: monthsAgo(1),
            kind: .transfer,
            amount: Money(major: 150_000, currency: .rub),
            sourceAccountID: card.id,
            destinationAccountID: savings.id,
            goalID: apartment.id,
            createdAt: monthsAgo(1)
        ))

        return store
    }
}
#endif
