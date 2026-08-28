import AppIntents
import Foundation
import FinPlanCore

struct AddIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.addIncome.title"
    static let description = IntentDescription("intent.addIncome.description")

    @Parameter(title: "intent.param.amount")
    var amountText: String

    @Parameter(title: "intent.param.currency", optionsProvider: AccountCurrencyOptionsProvider())
    var currencyCode: String

    @Parameter(title: "intent.param.account")
    var account: AccountEntity

    @Parameter(title: "intent.param.category")
    var category: CategoryEntity

    @Parameter(title: "intent.param.note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = IntentBridge.shared.resolveStore()
        let accountSnapshot = try IntentSupport.account(for: account, in: store)
        let amount = try IntentSupport.parseAmount(
            text: amountText, currencyCode: currencyCode, account: accountSnapshot
        )

        try await requestConfirmation(
            actionName: .add,
            dialog: IntentDialog("intent.addIncome.confirm \(amount.formatted()) \(accountSnapshot.name)")
        )

        let record = TransactionRecord(
            date: .now,
            kind: .income,
            status: .completed,
            amount: amount,
            destinationAccountID: accountSnapshot.id,
            categoryID: IntentSupport.categoryID(for: category, in: store),
            note: IntentSupport.normalizedNote(note),
            createdAt: .now
        )
        try store.addTransaction(record)
        return .result(
            dialog: IntentDialog("intent.addIncome.done \(amount.formatted()) \(accountSnapshot.name)")
        )
    }
}
