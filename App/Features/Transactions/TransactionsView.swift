import SwiftUI
import FinPlanCore

struct TransactionsView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var model = TransactionsListModel()
    @State private var activeSheet: TransactionsSheet?
    @State private var pendingDelete: TransactionRecord?
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if !model.hasAnyTransactions {
                    emptyState
                } else if model.sections.isEmpty {
                    filteredEmptyState
                } else {
                    transactionsList
                }
            }
            .navigationTitle("transactions.title")
            .searchable(text: $model.searchText, prompt: Text("transactions.search.prompt"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .filters
                    } label: {
                        Label(
                            "transactions.a11y.openFilters",
                            systemImage: model.filter.isActive
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .add(.expense)
                    } label: {
                        Label("transactions.a11y.addTransaction", systemImage: "plus")
                    }
                }
            }
        }
        .onChange(of: store.transactions, initial: true) { syncModel() }
        .onChange(of: store.categories) { syncModel() }
        .onChange(of: store.tags) { syncModel() }
        .onChange(of: store.accounts) { syncModel() }
        .onChange(of: router.pendingRoute, initial: true) { _, route in
            consume(route)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .filters:
                TransactionsFilterSheet(
                    filter: $model.filter,
                    accounts: store.accounts,
                    categories: store.categories,
                    tags: store.tags,
                    currencyCodes: model.currencyCodes
                )
                .presentationDetents([.medium, .large])
            case .add(let kind):
                TransactionEditorView(initialKind: kind)
            case .edit(let record):
                TransactionEditorView(record: record)
            }
        }
        .confirmationDialog(
            "transactions.delete.title",
            isPresented: deleteConfirmPresented,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { record in
            Button("transactions.delete.confirm", role: .destructive) { delete(record) }
            Button("common.cancel", role: .cancel) {}
        } message: { _ in
            Text("transactions.delete.message")
        }
        .alert("error.title", isPresented: localErrorPresented) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
        .alert("error.title", isPresented: storeErrorPresented) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: store.lastError ?? "")
        }
    }

    private var transactionsList: some View {
        @Bindable var model = model
        return List {
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.rows) { item in
                        TransactionsRowView(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture { activeSheet = .edit(item.record) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    pendingDelete = item.record
                                } label: {
                                    Label("transactions.action.delete", systemImage: "trash")
                                }
                                .tint(FPStatusTint.negative)
                                Button {
                                    activeSheet = .edit(item.record)
                                } label: {
                                    Label("transactions.action.edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                } header: {
                    sectionHeader(section)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.filter.isActive {
                TransactionsFilterChipsBar(
                    filter: $model.filter,
                    accounts: store.accounts,
                    categories: store.categories,
                    tags: store.tags
                )
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ section: TransactionsDaySection) -> some View {
        switch section.kind {
        case .today:
            Text("transactions.section.today")
        case .yesterday:
            Text("transactions.section.yesterday")
        case .other:
            Text(section.day, format: Date.FormatStyle(date: .abbreviated, time: .omitted))
        }
    }

    private var emptyState: some View {
        VStack(spacing: FP.Spacing.lg) {
            EmptyStateView(
                systemImage: "list.bullet.rectangle",
                title: "transactions.empty.title",
                message: "transactions.empty.message"
            )
            .fixedSize(horizontal: false, vertical: true)
            Button {
                activeSheet = .add(.expense)
            } label: {
                Label("transactions.empty.addFirst", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: FP.Spacing.lg) {
            EmptyStateView(
                systemImage: "line.3.horizontal.decrease.circle",
                title: "transactions.empty.filtered.title",
                message: "transactions.empty.filtered.message"
            )
            .fixedSize(horizontal: false, vertical: true)
            Button("transactions.filter.clearAll") {
                model.filter = TransactionsFilter()
                model.searchText = ""
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deleteConfirmPresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var localErrorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var storeErrorPresented: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }

    private func syncModel() {
        model.update(
            transactions: store.transactions,
            categories: store.categories,
            tags: store.tags,
            accounts: store.accounts
        )
    }

    private func consume(_ route: AppRoute?) {
        switch route {
        case .addExpense:
            activeSheet = .add(.expense)
            router.pendingRoute = nil
        case .transactions:
            router.pendingRoute = nil
        default:
            break
        }
    }

    private func delete(_ record: TransactionRecord) {
        do {
            try store.deleteTransaction(id: record.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum TransactionsSheet: Identifiable {
    case filters
    case add(TransactionKind)
    case edit(TransactionRecord)

    var id: String {
        switch self {
        case .filters: "filters"
        case .add(let kind): "add-\(kind.rawValue)"
        case .edit(let record): "edit-\(record.id.uuidString)"
        }
    }
}

private struct TransactionsRowView: View {
    let item: TransactionsRowItem

    var body: some View {
        HStack(spacing: FP.Spacing.md) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconTint)
                .frame(minWidth: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                title
                    .font(.body)
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: FP.Spacing.sm)

            VStack(alignment: .trailing, spacing: FP.Spacing.xs) {
                amountView
                if item.record.status != .completed {
                    TransactionsStatusBadge(status: item.record.status)
                }
            }
        }
        .padding(.vertical, FP.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch item.record.kind {
        case .expense: item.categorySymbol ?? "cart.fill"
        case .income: "arrow.down.circle.fill"
        case .transfer: item.record.goalID != nil ? "target" : "arrow.left.arrow.right"
        case .currencyExchange: "arrow.triangle.2.circlepath"
        case .adjustment: "plus.forwardslash.minus"
        }
    }

    private var iconTint: Color {
        switch item.record.kind {
        case .income: FPStatusTint.positive
        case .transfer: item.record.goalID != nil ? Color.accentColor : FPStatusTint.neutral
        case .expense: Color.primary
        case .currencyExchange, .adjustment: FPStatusTint.neutral
        }
    }

    private var title: Text {
        switch item.record.kind {
        case .expense:
            if let name = item.categoryName {
                Text(name)
            } else {
                Text("transactions.uncategorized")
            }
        case .income:
            if let name = item.categoryName {
                Text(name)
            } else {
                Text("transactions.kind.income")
            }
        case .transfer:
            if item.record.goalID != nil {
                Text("transactions.savingsContribution")
            } else {
                Text("transactions.kind.transfer")
            }
        case .currencyExchange:
            Text("transactions.kind.exchange")
        case .adjustment:
            Text("transactions.kind.adjustment")
        }
    }

    @ViewBuilder private var amountView: some View {
        switch item.record.kind {
        case .income:
            HStack(spacing: 0) {
                Text(verbatim: "+")
                MoneyText(money: item.record.amount)
            }
            .foregroundStyle(FPStatusTint.positive)
        case .expense:
            MoneyText(money: item.record.amount.negated)
                .foregroundStyle(.primary)
        case .transfer:
            HStack(spacing: FP.Spacing.xs) {
                Image(systemName: item.record.goalID != nil ? "target" : "arrow.right")
                    .font(.caption)
                    .accessibilityLabel(
                        item.record.goalID != nil
                            ? Text("transactions.a11y.goalContribution")
                            : Text("transactions.a11y.transfer")
                    )
                MoneyText(money: item.record.amount)
            }
            .foregroundStyle(.secondary)
        case .currencyExchange:
            VStack(alignment: .trailing, spacing: 0) {
                MoneyText(money: item.record.amount.negated)
                if let counter = item.record.counterAmount {
                    HStack(spacing: 0) {
                        Text(verbatim: "+")
                        MoneyText(money: counter)
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        case .adjustment:
            MoneyText(money: item.record.amount)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TransactionsStatusBadge: View {
    let status: TransactionStatus

    var body: some View {
        Text(TransactionsLabels.statusKey(status))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, FP.Spacing.sm)
            .padding(.vertical, FP.Spacing.xs / 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch status {
        case .planned: FPStatusTint.attention
        case .expected: .blue
        case .completed: FPStatusTint.positive
        case .skipped, .cancelled: FPStatusTint.neutral
        }
    }
}

#if DEBUG
#Preview("Transactions") {
    TransactionsView()
        .environment(TransactionsPreviewData.makeStore())
        .environment(AppRouter())
}

#Preview("Empty") {
    TransactionsView()
        .environment(TransactionsPreviewData.makeStore(seeded: false))
        .environment(AppRouter())
}
#endif
