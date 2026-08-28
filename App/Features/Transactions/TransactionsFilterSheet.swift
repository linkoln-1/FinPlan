import SwiftUI
import FinPlanCore

struct TransactionsFilterSheet: View {
    @Binding var filter: TransactionsFilter
    let accounts: [Account]
    let categories: [TransactionCategory]
    let tags: [TransactionTag]
    let currencyCodes: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TransactionsFilter
    @State private var hasDateRange: Bool
    @State private var startDate: Date
    @State private var endDate: Date

    init(
        filter: Binding<TransactionsFilter>,
        accounts: [Account],
        categories: [TransactionCategory],
        tags: [TransactionTag],
        currencyCodes: [String]
    ) {
        _filter = filter
        self.accounts = accounts
        self.categories = categories
        self.tags = tags
        self.currencyCodes = currencyCodes
        let value = filter.wrappedValue
        _draft = State(initialValue: value)
        _hasDateRange = State(initialValue: value.startDate != nil || value.endDate != nil)
        let now = Date()
        let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        _startDate = State(initialValue: value.startDate ?? monthAgo)
        _endDate = State(initialValue: value.endDate ?? now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("transactions.filter.account", selection: $draft.accountID) {
                        Text("transactions.filter.any").tag(UUID?.none)
                        ForEach(accounts.filter { !$0.isArchived }) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    Picker("transactions.filter.kind", selection: $draft.kind) {
                        Text("transactions.filter.any").tag(TransactionKind?.none)
                        ForEach(TransactionKind.allCases, id: \.self) { kind in
                            Text(TransactionsLabels.kindKey(kind)).tag(Optional(kind))
                        }
                    }
                    Picker("transactions.filter.category", selection: $draft.categoryID) {
                        Text("transactions.filter.any").tag(UUID?.none)
                        ForEach(categories.filter { !$0.isArchived }) { category in
                            Label(category.name, systemImage: category.symbolName)
                                .tag(Optional(category.id))
                        }
                    }
                    if !tags.isEmpty {
                        Picker("transactions.filter.tag", selection: $draft.tagID) {
                            Text("transactions.filter.any").tag(UUID?.none)
                            ForEach(tags) { tag in
                                Text(tag.name).tag(Optional(tag.id))
                            }
                        }
                    }
                    Picker("transactions.filter.status", selection: $draft.status) {
                        Text("transactions.filter.any").tag(TransactionStatus?.none)
                        ForEach(TransactionStatus.allCases, id: \.self) { status in
                            Text(TransactionsLabels.statusKey(status)).tag(Optional(status))
                        }
                    }
                    if currencyCodes.count > 1 {
                        Picker("transactions.filter.currency", selection: $draft.currencyCode) {
                            Text("transactions.filter.any").tag(String?.none)
                            ForEach(currencyCodes, id: \.self) { code in
                                Text(verbatim: code).tag(Optional(code))
                            }
                        }
                    }
                }

                Section("transactions.filter.dates") {
                    Toggle("transactions.filter.byDate", isOn: $hasDateRange)
                    if hasDateRange {
                        DatePicker(
                            "transactions.filter.dateFrom",
                            selection: $startDate,
                            in: ...endDate,
                            displayedComponents: .date
                        )
                        DatePicker(
                            "transactions.filter.dateTo",
                            selection: $endDate,
                            in: startDate...,
                            displayedComponents: .date
                        )
                    }
                }

                Section {
                    Button("transactions.filter.reset", role: .destructive) {
                        draft = TransactionsFilter()
                        hasDateRange = false
                    }
                }
            }
            .navigationTitle("transactions.filter.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("transactions.filter.apply") {
                        var applied = draft
                        applied.startDate = hasDateRange ? startDate : nil
                        applied.endDate = hasDateRange ? endDate : nil
                        filter = applied
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TransactionsFilterChipsBar: View {
    @Binding var filter: TransactionsFilter
    let accounts: [Account]
    let categories: [TransactionCategory]
    let tags: [TransactionTag]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FP.Spacing.sm) {
                if let id = filter.accountID {
                    chip(Text(accounts.first(where: { $0.id == id })?.name ?? "")) {
                        filter.accountID = nil
                    }
                }
                if let kind = filter.kind {
                    chip(Text(TransactionsLabels.kindKey(kind))) { filter.kind = nil }
                }
                if let id = filter.categoryID {
                    chip(Text(categories.first(where: { $0.id == id })?.name ?? "")) {
                        filter.categoryID = nil
                    }
                }
                if let id = filter.tagID {
                    chip(Text(tags.first(where: { $0.id == id })?.name ?? "")) {
                        filter.tagID = nil
                    }
                }
                if let status = filter.status {
                    chip(Text(TransactionsLabels.statusKey(status))) { filter.status = nil }
                }
                if filter.startDate != nil || filter.endDate != nil {
                    chip(dateRangeLabel) {
                        filter.startDate = nil
                        filter.endDate = nil
                    }
                }
                if let code = filter.currencyCode {
                    chip(Text(verbatim: code)) { filter.currencyCode = nil }
                }
            }
            .padding(.horizontal, FP.Spacing.lg)
            .padding(.vertical, FP.Spacing.sm)
        }
        .background(.bar)
    }

    private var dateRangeLabel: Text {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        switch (filter.startDate, filter.endDate) {
        case (let start?, let end?):
            return Text(start, format: style) + Text(verbatim: " – ") + Text(end, format: style)
        case (let start?, nil):
            return Text(start, format: style)
        case (nil, let end?):
            return Text(end, format: style)
        case (nil, nil):
            return Text(verbatim: "")
        }
    }

    private func chip(_ label: Text, clear: @escaping () -> Void) -> some View {
        HStack(spacing: FP.Spacing.xs) {
            label
                .font(.footnote)
                .lineLimit(1)
            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("transactions.filter.removeFilter")
        }
        .padding(.horizontal, FP.Spacing.md)
        .padding(.vertical, FP.Spacing.xs)
        .background(Color(.secondarySystemFill), in: Capsule())
    }
}

#if DEBUG
#Preview {
    @Previewable @State var filter = TransactionsFilter()
    let store = TransactionsPreviewData.makeStore()
    TransactionsFilterSheet(
        filter: $filter,
        accounts: store.accounts,
        categories: store.categories,
        tags: store.tags,
        currencyCodes: ["RUB", "USD"]
    )
    .environment(store)
}
#endif
