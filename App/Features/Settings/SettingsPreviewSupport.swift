#if DEBUG
import Foundation
import SwiftData
import FinPlanCore

@MainActor
enum SettingsPreviewFactory {
    static func make() -> (controller: PersistenceController, store: FinanceStore) {
        let controller = PersistenceController.preview()
        let store = FinanceStore(context: controller.container.mainContext)
        store.setBaseCurrency(.rub)
        if let usdToRub = ExchangeRate(base: .usd, quote: .rub, decimalString: "84.282") {
            store.planningRates = ManualExchangeRates(rates: [usdToRub])
        }
        store.minimumCashBuffer = Money(major: 100_000, currency: .rub)

        let savings = Account(
            name: "Savings",
            currency: .rub,
            type: .savings,
            openingBalance: Money(major: 850_000, currency: .rub),
            createdAt: .now
        )
        store.addAccount(savings)
        store.addAccount(
            Account(
                name: "USD Card",
                currency: .usd,
                type: .checking,
                openingBalance: Money(major: 2_500, currency: .usd),
                createdAt: .now
            )
        )
        store.addGoal(
            Goal(
                title: "Apartment",
                symbolName: "house.fill",
                targetAmount: Money(major: 6_000_000, currency: .rub),
                startDate: .now,
                priority: .high
            )
        )
        store.addIncomeSource(
            IncomeSource(
                name: "Salary",
                grossAmount: Money(major: 4_000, currency: .usd),
                recurrence: .monthly(day: 5),
                destinationAccountID: savings.id
            )
        )
        store.onboardingCompleted = true
        return (controller, store)
    }
}
#endif
