import SwiftUI
import FinPlanCore

struct SettingsAccountsView: View {
    @Environment(FinanceStore.self) private var store
    @State private var editorContext: SettingsAccountEditorContext?
    @State private var errorMessage: String?

    private var activeAccounts: [Account] { store.accounts.filter { !$0.isArchived } }
    private var archivedAccounts: [Account] { store.accounts.filter(\.isArchived) }

    var body: some View {
        Group {
            if store.accounts.isEmpty {
                EmptyStateView(
                    systemImage: "creditcard",
                    title: "settings.accounts.empty.title",
                    message: "settings.accounts.empty.message"
                )
            } else {
                List {
                    if !activeAccounts.isEmpty {
                        Section {
                            ForEach(activeAccounts) { account in
                                accountRow(account)
                            }
                        } header: {
                            Text("settings.accounts.active")
                        }
                    }
                    if !archivedAccounts.isEmpty {
                        Section {
                            ForEach(archivedAccounts) { account in
                                accountRow(account)
                            }
                        } header: {
                            Text("settings.accounts.archived")
                        } footer: {
                            Text("settings.accounts.archived.footer")
                        }
                    }
                }
            }
        }
        .navigationTitle("settings.accounts.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorContext = .add
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "a11y.settings.addAccount"))
            }
        }
        .sheet(item: $editorContext) { context in
            SettingsAccountEditorSheet(context: context)
        }
        .alert("error.title", isPresented: errorBinding) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func accountRow(_ account: Account) -> some View {
        Button {
            editorContext = .edit(account)
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                        Text(verbatim: account.name)
                        Text(account.type.settingsTitleKey)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: SettingsAccountEditorSheet.symbol(for: account.type))
                        .foregroundStyle(account.isArchived ? FPStatusTint.neutral : Color.accentColor)
                }
                Spacer()
                MoneyText(money: account.openingBalance)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                toggleArchive(account)
            } label: {
                if account.isArchived {
                    Label("settings.accounts.unarchive", systemImage: "tray.and.arrow.up")
                } else {
                    Label("settings.accounts.archive", systemImage: "archivebox")
                }
            }
            .tint(FPStatusTint.attention)
        }
    }

    private func toggleArchive(_ account: Account) {
        var updated = account
        updated.isArchived.toggle()
        do {
            try store.updateAccount(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

private enum SettingsAccountEditorContext: Identifiable {
    case add
    case edit(Account)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let account): return account.id.uuidString
        }
    }
}

private struct SettingsAccountEditorSheet: View {
    let context: SettingsAccountEditorContext
    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var typeRaw = AccountType.checking.rawValue
    @State private var currencyCode = "RUB"
    @State private var balanceText = ""
    @State private var balanceMinor: Int64?
    @State private var includedInNetWorth = true
    @State private var includedInSafeToSpend = true
    @State private var isArchived = false
    @State private var errorMessage: String?

    static func symbol(for type: AccountType) -> String {
        switch type {
        case .cash: return "banknote"
        case .checking: return "creditcard"
        case .savings: return "building.columns"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .credit: return "creditcard.trianglebadge.exclamationmark"
        case .other: return "wallet.pass"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("settings.accounts.name", text: $name)
                    Picker("settings.accounts.type", selection: $typeRaw) {
                        ForEach(AccountType.allCases, id: \.rawValue) { type in
                            Label(
                                type.settingsTitleKey,
                                systemImage: Self.symbol(for: type)
                            )
                            .tag(type.rawValue)
                        }
                    }
                    Picker("settings.accounts.currency", selection: $currencyCode) {
                        ForEach(currencyOptions, id: \.self) { code in
                            Text(verbatim: code).tag(code)
                        }
                    }
                    .disabled(isEditing)
                } footer: {
                    if isEditing {
                        Text("settings.accounts.currencyLocked")
                    }
                }

                Section {
                    MoneyField(
                        titleKey: "settings.accounts.openingBalance",
                        currency: currency,
                        text: $balanceText,
                        amountMinor: $balanceMinor
                    )
                } footer: {
                    if isBalanceInvalid {
                        Text("settings.accounts.openingBalance.invalid")
                            .foregroundStyle(FPStatusTint.negative)
                    } else {
                        Text("settings.accounts.openingBalance.footer")
                    }
                }

                Section {
                    Toggle("settings.accounts.inNetWorth", isOn: $includedInNetWorth)
                    Toggle("settings.accounts.inSafeToSpend", isOn: $includedInSafeToSpend)
                } footer: {
                    Text("settings.accounts.inclusion.footer")
                }

                if isEditing {
                    Section {
                        Toggle("settings.accounts.archiveToggle", isOn: $isArchived)
                    } footer: {
                        Text("settings.accounts.archive.footer")
                    }
                }
            }
            .navigationTitle(isEditing ? "settings.accounts.editTitle" : "settings.accounts.addTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(!isSaveEnabled)
                }
            }
            .onAppear { prefill() }
            .alert("error.title", isPresented: errorBinding) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = context { return true }
        return false
    }

    private var currency: Currency { Currency.known(code: currencyCode) }

    private var currencyOptions: [String] {
        SettingsSupportedCurrencies.codes(including: [currencyCode])
    }

    private var isBalanceInvalid: Bool {
        !balanceText.isEmpty && balanceMinor == nil
    }

    private var isSaveEnabled: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBalanceInvalid
    }

    private func prefill() {
        guard case .edit(let account) = context else { return }
        name = account.name
        typeRaw = account.type.rawValue
        currencyCode = account.currency.code
        includedInNetWorth = account.includedInNetWorth
        includedInSafeToSpend = account.includedInSafeToSpend
        isArchived = account.isArchived
        if !account.openingBalance.isZero {
            balanceText = BackupService.decimalString(account.openingBalance)
            balanceMinor = account.openingBalance.amountMinor
        }
    }

    private func save() {
        guard isSaveEnabled else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = AccountType(rawValue: typeRaw) ?? .other
        switch context {
        case .add:
            let account = Account(
                name: trimmedName,
                currency: currency,
                type: type,
                openingBalance: Money(minor: balanceMinor ?? 0, currency: currency),
                includedInNetWorth: includedInNetWorth,
                includedInSafeToSpend: includedInSafeToSpend,
                createdAt: .now
            )
            store.addAccount(account)
            dismiss()
        case .edit(let existing):
            let account = Account(
                id: existing.id,
                name: trimmedName,
                currency: existing.currency,
                type: type,
                openingBalance: Money(minor: balanceMinor ?? 0, currency: existing.currency),
                includedInNetWorth: includedInNetWorth,
                includedInSafeToSpend: includedInSafeToSpend,
                isArchived: isArchived,
                createdAt: existing.createdAt
            )
            do {
                try store.updateAccount(account)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

#if DEBUG
#Preview {
    let fixture = SettingsPreviewFactory.make()
    NavigationStack {
        SettingsAccountsView()
    }
    .environment(fixture.store)
    .environment(PrivacyShieldModel())
    .modelContainer(fixture.controller.container)
}
#endif

extension AccountType {
    fileprivate var settingsTitleKey: LocalizedStringKey {
        switch self {
        case .cash: "account.type.cash"
        case .checking: "account.type.checking"
        case .savings: "account.type.savings"
        case .investment: "account.type.investment"
        case .credit: "account.type.credit"
        case .other: "account.type.other"
        }
    }
}
