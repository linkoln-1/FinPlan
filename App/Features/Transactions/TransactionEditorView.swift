import SwiftUI
import FinPlanCore

struct TransactionEditorView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var model: TransactionsEditorModel
    @State private var orderedCategories: [TransactionCategory] = []
    @State private var saveError: String?
    private let isEditing: Bool

    init(record: TransactionRecord? = nil, initialKind: TransactionKind = .expense) {
        _model = State(initialValue: TransactionsEditorModel(record: record, defaultKind: initialKind))
        isEditing = record != nil
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Picker("transactions.field.kind", selection: $model.kind) {
                        ForEach(model.availableKinds, id: \.self) { kind in
                            Text(TransactionsLabels.kindKey(kind)).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                amountSection
                accountsSection

                switch model.kind {
                case .expense:
                    if !model.splitsEnabled {
                        categoryGridSection
                    }
                    splitSection
                case .income:
                    incomeCategorySection
                case .transfer:
                    goalSection
                case .currencyExchange, .adjustment:
                    EmptyView()
                }

                detailsSection
            }
            .navigationTitle(isEditing ? "transactions.editor.editTitle" : "transactions.editor.addTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(!model.canSave(accounts: store.accounts, fallback: store.baseCurrency))
                }
            }
            .onAppear { prepare() }
            .onChange(of: model.kind) { contextChanged() }
            .onChange(of: model.sourceAccountID) { contextChanged() }
            .onChange(of: model.destinationAccountID) { contextChanged() }
            .onChange(of: model.feeSide) {
                model.reparse(accounts: store.accounts, fallback: store.baseCurrency)
            }
            .onChange(of: model.splitsEnabled) {
                if model.splitsEnabled, model.splits.isEmpty {
                    model.splits.append(TransactionsSplitDraft())
                }
            }
            .alert("error.title", isPresented: saveErrorPresented) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(verbatim: saveError ?? "")
            }
        }
    }

    private var amountSection: some View {
        @Bindable var model = model
        return Section("transactions.field.amount") {
            MoneyField(
                titleKey: "transactions.field.amount",
                currency: amountCurrency,
                text: $model.amountText,
                amountMinor: $model.amountMinor
            )
            if model.kind == .currencyExchange {
                MoneyField(
                    titleKey: "transactions.field.received",
                    currency: counterCurrency,
                    text: $model.counterText,
                    amountMinor: $model.counterMinor
                )
                MoneyField(
                    titleKey: "transactions.field.fee",
                    currency: feeCurrency,
                    text: $model.feeText,
                    amountMinor: $model.feeMinor
                )
                Picker("transactions.field.feeSide", selection: $model.feeSide) {
                    Text("transactions.feeSide.source").tag(TransactionsFeeSide.source)
                    Text("transactions.feeSide.destination").tag(TransactionsFeeSide.destination)
                }
                .pickerStyle(.segmented)
                if let rate = model.derivedRate(accounts: store.accounts) {
                    LabeledContent("transactions.exchange.rate") {
                        Text(verbatim: TransactionsEditorModel.rateDisplay(rate))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var accountsSection: some View {
        @Bindable var model = model
        let selectable = model.selectableAccounts(in: store.accounts)
        Section("transactions.section.accounts") {
            if selectable.isEmpty {
                Text("transactions.editor.noAccounts")
                    .foregroundStyle(.secondary)
            } else {
                switch model.kind {
                case .expense:
                    accountPicker("transactions.field.account", selection: $model.sourceAccountID, options: selectable)
                case .income:
                    accountPicker("transactions.field.toAccount", selection: $model.destinationAccountID, options: selectable)
                case .transfer:
                    accountPicker("transactions.field.fromAccount", selection: $model.sourceAccountID, options: selectable)
                    let candidates = model.transferDestinationCandidates(accounts: store.accounts)
                    if candidates.isEmpty {
                        Text("transactions.transfer.noDestination")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        accountPicker("transactions.field.toAccount", selection: $model.destinationAccountID, options: candidates)
                    }
                case .currencyExchange:
                    accountPicker("transactions.field.fromAccount", selection: $model.sourceAccountID, options: selectable)
                    let candidates = model.exchangeDestinationCandidates(accounts: store.accounts)
                    if candidates.isEmpty {
                        Text("transactions.exchange.noDestination")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        accountPicker("transactions.field.toAccount", selection: $model.destinationAccountID, options: candidates)
                    }
                case .adjustment:
                    accountPicker("transactions.field.account", selection: $model.sourceAccountID, options: selectable)
                    Picker("transactions.adjustment.side", selection: $model.adjustmentDirection) {
                        Text("transactions.adjustment.increase").tag(TransactionsAdjustmentDirection.increase)
                        Text("transactions.adjustment.decrease").tag(TransactionsAdjustmentDirection.decrease)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private func accountPicker(
        _ titleKey: LocalizedStringKey,
        selection: Binding<UUID?>,
        options: [Account]
    ) -> some View {
        Picker(titleKey, selection: selection) {
            ForEach(options) { account in
                Text(verbatim: "\(account.name) · \(account.currency.code)")
                    .tag(Optional(account.id))
            }
        }
    }

    private var categoryGridSection: some View {
        Section("transactions.field.category") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: FP.Spacing.sm)], spacing: FP.Spacing.sm) {
                ForEach(orderedCategories) { category in
                    categoryCell(category)
                }
            }
            .padding(.vertical, FP.Spacing.xs)
        }
    }

    private func categoryCell(_ category: TransactionCategory) -> some View {
        let isSelected = model.categoryID == category.id
        return Button {
            model.categoryID = isSelected ? nil : category.id
        } label: {
            VStack(spacing: FP.Spacing.xs) {
                Image(systemName: category.symbolName)
                    .font(.title3)
                Text(category.name)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, FP.Spacing.sm)
            .background(
                isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemFill),
                in: RoundedRectangle(cornerRadius: FP.Radius.control)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: FP.Radius.control)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var incomeCategorySection: some View {
        @Bindable var model = model
        return Section {
            Picker("transactions.field.category", selection: $model.categoryID) {
                Text("common.none").tag(UUID?.none)
                ForEach(orderedCategories) { category in
                    Label(category.name, systemImage: category.symbolName)
                        .tag(Optional(category.id))
                }
            }
        }
    }

    @ViewBuilder private var goalSection: some View {
        @Bindable var model = model
        let goals = store.goals.filter { $0.status == .active || $0.status == .planned || $0.status == .paused }
        if !goals.isEmpty {
            Section {
                Picker("transactions.allocateToGoal", selection: $model.goalID) {
                    Text("common.none").tag(UUID?.none)
                    ForEach(goals) { goal in
                        Label(goal.title, systemImage: goal.symbolName)
                            .tag(Optional(goal.id))
                    }
                }
            } footer: {
                Text("transactions.allocateToGoal.footer")
            }
        }
    }

    @ViewBuilder private var splitSection: some View {
        @Bindable var model = model
        Section {
            Toggle("transactions.split.enable", isOn: $model.splitsEnabled)
            if model.splitsEnabled {
                ForEach($model.splits) { $split in
                    TransactionsSplitRow(
                        split: $split,
                        categories: orderedCategories,
                        currency: amountCurrency,
                        onRemove: { model.splits.removeAll { $0.id == split.id } }
                    )
                }
                Button {
                    model.splits.append(TransactionsSplitDraft())
                } label: {
                    Label("transactions.split.addRow", systemImage: "plus.circle")
                }
                splitRemainderRow
            }
        } header: {
            Text("transactions.split.title")
        }
    }

    private var splitRemainderRow: some View {
        let remainder = model.splitRemainder(accounts: store.accounts, fallback: store.baseCurrency)
        let isBalanced = remainder?.isZero ?? false
        return LabeledContent("transactions.split.remainder") {
            HStack(spacing: FP.Spacing.xs) {
                Image(systemName: isBalanced ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                if let remainder {
                    MoneyText(money: remainder)
                } else {
                    Text("transactions.split.remainderUnavailable")
                }
            }
            .foregroundStyle(isBalanced ? FPStatusTint.positive : FPStatusTint.attention)
        }
        .accessibilityElement(children: .combine)
    }

    private var detailsSection: some View {
        @Bindable var model = model
        return Section("transactions.section.details") {
            DatePicker("transactions.field.date", selection: $model.date, displayedComponents: .date)
            TextField("transactions.field.note", text: $model.note, axis: .vertical)
            Picker("transactions.field.status", selection: $model.status) {
                ForEach(TransactionStatus.allCases, id: \.self) { status in
                    Text(TransactionsLabels.statusKey(status)).tag(status)
                }
            }
            if !store.tags.isEmpty {
                tagsRow
            }
        }
    }

    private var tagsRow: some View {
        VStack(alignment: .leading, spacing: FP.Spacing.sm) {
            Text("transactions.field.tags")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: FP.Spacing.sm)], spacing: FP.Spacing.sm) {
                ForEach(store.tags) { tag in
                    tagCell(tag)
                }
            }
        }
        .padding(.vertical, FP.Spacing.xs)
    }

    private func tagCell(_ tag: TransactionTag) -> some View {
        let isSelected = model.tagIDs.contains(tag.id)
        return Button {
            if isSelected {
                model.tagIDs.remove(tag.id)
            } else {
                model.tagIDs.insert(tag.id)
            }
        } label: {
            HStack(spacing: FP.Spacing.xs) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                Text(tag.name)
                    .font(.footnote)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, FP.Spacing.xs)
            .padding(.horizontal, FP.Spacing.sm)
            .background(
                isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemFill),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var amountCurrency: Currency {
        model.amountCurrency(accounts: store.accounts) ?? store.baseCurrency
    }

    private var counterCurrency: Currency {
        model.counterCurrency(accounts: store.accounts) ?? store.baseCurrency
    }

    private var feeCurrency: Currency {
        model.feeCurrency(accounts: store.accounts) ?? store.baseCurrency
    }

    private var saveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    private func prepare() {
        model.ensureValidSelections(accounts: store.accounts)
        model.reparse(accounts: store.accounts, fallback: store.baseCurrency)
        orderedCategories = TransactionsEditorModel.orderedCategories(
            all: store.categories,
            recentTransactions: store.transactions
        )
    }

    private func contextChanged() {
        model.ensureValidSelections(accounts: store.accounts)
        model.reparse(accounts: store.accounts, fallback: store.baseCurrency)
    }

    private func save() {
        guard let record = model.buildRecord(accounts: store.accounts) else { return }
        do {
            if isEditing {
                try store.updateTransaction(record)
            } else {
                try store.addTransaction(record)
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct TransactionsSplitRow: View {
    @Binding var split: TransactionsSplitDraft
    let categories: [TransactionCategory]
    let currency: Currency
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: FP.Spacing.sm) {
            Picker("transactions.split.category", selection: $split.categoryID) {
                Text("common.none").tag(UUID?.none)
                ForEach(categories) { category in
                    Label(category.name, systemImage: category.symbolName)
                        .tag(Optional(category.id))
                }
            }
            .labelsHidden()
            MoneyField(
                titleKey: "transactions.split.amount",
                currency: currency,
                text: $split.amountText,
                amountMinor: $split.amountMinor
            )
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(FPStatusTint.negative)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("transactions.a11y.removeSplit")
        }
    }
}

#if DEBUG
#Preview("Add expense") {
    TransactionEditorView(initialKind: .expense)
        .environment(TransactionsPreviewData.makeStore())
        .environment(AppRouter())
}

#Preview("Add transfer") {
    TransactionEditorView(initialKind: .transfer)
        .environment(TransactionsPreviewData.makeStore())
        .environment(AppRouter())
}

#Preview("Add exchange") {
    TransactionEditorView(initialKind: .currencyExchange)
        .environment(TransactionsPreviewData.makeStore())
        .environment(AppRouter())
}
#endif
