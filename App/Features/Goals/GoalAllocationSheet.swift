import SwiftUI
import FinPlanCore

struct GoalAllocationSheet: View {
    let goal: Goal

    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAccountID: UUID?
    @State private var amountText = ""
    @State private var amountMinor: Int64?
    @State private var date = Date()
    @State private var errorMessage: String?

    private var availableAccounts: [Account] {
        store.accounts.filter { !$0.isArchived }
    }

    private var selectedAccount: Account? {
        availableAccounts.first { $0.id == selectedAccountID }
    }

    private var isValid: Bool {
        guard selectedAccount != nil, let amountMinor, amountMinor > 0 else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableAccounts.isEmpty {
                    EmptyStateView(
                        systemImage: "creditcard",
                        title: "goals.allocation.noAccounts.title",
                        message: "goals.allocation.noAccounts.message"
                    )
                } else {
                    form
                }
            }
            .navigationTitle(Text("goals.allocation.sheetTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(!isValid)
                }
            }
            .alert(
                "error.title",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(verbatim: errorMessage ?? "")
            }
        }
    }

    private var form: some View {
        Form {
            Section("goals.allocation.section.account") {
                Picker("goals.allocation.accountPicker", selection: $selectedAccountID) {
                    Text("goals.allocation.accountNone").tag(UUID?.none)
                    ForEach(availableAccounts) { account in
                        Text(verbatim: account.name).tag(UUID?.some(account.id))
                    }
                }
                if let account = selectedAccount {
                    HStack {
                        Text("goals.allocation.available")
                        Spacer(minLength: FP.Spacing.sm)
                        unallocatedText(for: account)
                    }
                    .font(.subheadline)
                }
            }

            Section("goals.allocation.section.amount") {
                MoneyField(
                    titleKey: "goals.allocation.amountField",
                    currency: selectedAccount?.currency ?? store.baseCurrency,
                    text: $amountText,
                    amountMinor: $amountMinor
                )
                DatePicker("goals.allocation.date", selection: $date, displayedComponents: .date)
            }
        }
        .onChange(of: selectedAccountID) { _, _ in
            amountMinor = MoneyParser.minorUnits(
                from: amountText,
                currency: selectedAccount?.currency ?? store.baseCurrency
            )
        }
    }

    @ViewBuilder
    private func unallocatedText(for account: Account) -> some View {
        if let available = try? store.goalsUnallocatedBalance(of: account) {
            MoneyText(money: available)
                .foregroundStyle(available.isNegative ? FPStatusTint.negative : FPStatusTint.positive)
        } else {
            Label("goals.allocation.availableUnknown", systemImage: "exclamationmark.triangle")
                .foregroundStyle(FPStatusTint.attention)
        }
    }

    private func save() {
        guard let account = selectedAccount, let amountMinor, amountMinor > 0 else { return }
        do {
            try store.goalsAddAllocation(
                goalID: goal.id,
                account: account,
                amount: Money(minor: amountMinor, currency: account.currency),
                date: date
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview("Add allocation") {
    let store = GoalsPreviewFixtures.store()
    return GoalAllocationSheet(goal: store.goals.first { $0.id == GoalsPreviewFixtures.apartmentGoalID }!)
        .environment(store)
}
#endif
