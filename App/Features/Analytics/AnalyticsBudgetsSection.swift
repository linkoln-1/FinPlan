import SwiftUI
import FinPlanCore

@MainActor
struct AnalyticsBudgetsSection: View {
    let rows: [AnalyticsBudgetRow]
    let issue: String?
    @State private var editorTarget: AnalyticsBudgetEditorTarget?

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                HStack {
                    Text("analytics.budgets.title")
                        .font(.headline)
                    Spacer()
                    Button {
                        editorTarget = .new
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel(Text("analytics.budgets.add"))
                }

                if rows.isEmpty {
                    EmptyStateView(
                        systemImage: "chart.pie",
                        title: "analytics.budgets.empty.title",
                        message: "analytics.budgets.empty.message"
                    )
                } else {
                    ForEach(rows) { row in
                        Button {
                            editorTarget = .edit(row.budget)
                        } label: {
                            AnalyticsBudgetRowView(row: row)
                        }
                        .buttonStyle(.plain)
                        if row.id != rows.last?.id {
                            Divider()
                        }
                    }
                }

                if let issue {
                    VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                        Label("analytics.budgets.computeIssue", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(FPStatusTint.attention)
                        Text(verbatim: issue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            AnalyticsBudgetEditorView(target: target)
        }
    }
}

@MainActor
struct AnalyticsBudgetRowView: View {
    let row: AnalyticsBudgetRow

    var body: some View {
        VStack(alignment: .leading, spacing: FP.Spacing.xs) {
            HStack(spacing: FP.Spacing.sm) {
                Label {
                    if let name = row.categoryName {
                        Text(verbatim: name)
                    } else {
                        Text("analytics.category.unknown")
                    }
                } icon: {
                    Image(systemName: row.categorySymbol)
                }
                .font(.subheadline.weight(.medium))
                Text(row.budget.period.analyticsTitleKey)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                paceBadge
            }

            ProgressView(value: progressValue)
                .tint(progressTint)

            HStack(spacing: FP.Spacing.xs) {
                Text("analytics.budget.spent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MoneyText(money: row.status.spent)
                    .font(.caption)
                Spacer()
                if row.status.remaining.isNegative {
                    Text("analytics.budget.over")
                        .font(.caption)
                        .foregroundStyle(FPStatusTint.negative)
                    MoneyText(money: row.status.remaining.negated)
                        .font(.caption)
                        .foregroundStyle(FPStatusTint.negative)
                } else {
                    Text("analytics.budget.remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MoneyText(money: row.status.remaining)
                        .font(.caption)
                }
            }

            Text("analytics.budget.elapsed \(AnalyticsFormat.percent(basisPoints: row.status.periodElapsedBasisPoints)) \(AnalyticsFormat.percent(basisPoints: row.status.fractionUsedBasisPoints))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var progressValue: Double {
        min(1, Double(row.status.fractionUsedBasisPoints) / 10_000)
    }

    private var progressTint: Color {
        if row.status.remaining.isNegative { return FPStatusTint.negative }
        if row.status.pace == .hot { return FPStatusTint.attention }
        return Color.accentColor
    }

    private var paceBadge: some View {
        Text(row.status.pace.analyticsBadgeKey)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, FP.Spacing.sm)
            .padding(.vertical, 2)
            .background(paceTint.opacity(0.15), in: Capsule())
            .foregroundStyle(paceTint)
    }

    private var paceTint: Color {
        switch row.status.pace {
        case .onTrack: return FPStatusTint.neutral
        case .ahead: return FPStatusTint.positive
        case .hot: return FPStatusTint.attention
        }
    }
}

enum AnalyticsBudgetEditorTarget: Identifiable {
    case new
    case edit(Budget)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let budget): return budget.id.uuidString
        }
    }
}

@MainActor
struct AnalyticsBudgetEditorView: View {
    let target: AnalyticsBudgetEditorTarget
    @Environment(FinanceStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var categoryID: UUID?
    @State private var amountText = ""
    @State private var amountMinor: Int64?
    @State private var budgetPeriod: BudgetPeriod = .monthly
    @State private var rollover: BudgetRolloverPolicy = .expires
    @State private var errorMessage: String?
    @State private var isLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("analytics.budget.editor.category") {
                    if selectableCategories.isEmpty {
                        Text("analytics.budget.editor.noCategories")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("analytics.budget.editor.categoryPicker", selection: $categoryID) {
                            Text("analytics.budget.editor.categoryNone").tag(UUID?.none)
                            ForEach(selectableCategories) { category in
                                Label {
                                    Text(verbatim: category.name)
                                } icon: {
                                    Image(systemName: category.symbolName)
                                }
                                .tag(UUID?.some(category.id))
                            }
                        }
                    }
                }
                Section("analytics.budget.editor.amount") {
                    MoneyField(
                        titleKey: "analytics.budget.editor.amountPlaceholder",
                        currency: editingCurrency,
                        text: $amountText,
                        amountMinor: $amountMinor
                    )
                }
                Section {
                    Picker("analytics.budget.editor.period", selection: $budgetPeriod) {
                        ForEach(BudgetPeriod.allCases, id: \.self) { period in
                            Text(period.analyticsTitleKey)
                                .tag(period)
                        }
                    }
                    Picker("analytics.budget.editor.rollover", selection: $rollover) {
                        ForEach(BudgetRolloverPolicy.allCases, id: \.self) { policy in
                            Text(policy.analyticsTitleKey)
                                .tag(policy)
                        }
                    }
                } footer: {
                    Text(rollover.analyticsFootnoteKey)
                }
                if case .edit(let budget) = target {
                    Section {
                        Button("analytics.budget.delete", role: .destructive) {
                            deleteBudget(budget)
                        }
                    }
                }
            }
            .navigationTitle(isNew ? Text("analytics.budget.editor.titleNew") : Text("analytics.budget.editor.titleEdit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .alert("analytics.error.title", isPresented: errorPresented) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(verbatim: errorMessage ?? "")
            }
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private var editingCurrency: Currency {
        if case .edit(let budget) = target { return budget.amount.currency }
        return store.baseCurrency
    }

    private var selectableCategories: [TransactionCategory] {
        store.categories
            .filter { !$0.isArchived }
            .sorted { $0.name < $1.name }
    }

    private var canSave: Bool {
        categoryID != nil && (amountMinor ?? 0) > 0
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        if case .edit(let budget) = target {
            categoryID = budget.categoryID
            amountText = AnalyticsFormat.amountEditText(budget.amount)
            amountMinor = budget.amount.amountMinor
            budgetPeriod = budget.period
            rollover = budget.rollover
        }
    }

    private func save() {
        guard let categoryID, let amountMinor, amountMinor > 0 else { return }
        let amount = Money(minor: amountMinor, currency: editingCurrency)
        do {
            switch target {
            case .new:
                store.addBudget(Budget(
                    categoryID: categoryID,
                    amount: amount,
                    period: budgetPeriod,
                    rollover: rollover
                ))
            case .edit(let existing):
                var updated = existing
                updated.categoryID = categoryID
                updated.amount = amount
                updated.period = budgetPeriod
                updated.rollover = rollover
                try store.updateBudget(updated, context: modelContext)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteBudget(_ budget: Budget) {
        do {
            try store.deleteBudget(id: budget.id, context: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

extension BudgetPeriod {
    fileprivate var analyticsTitleKey: LocalizedStringKey {
        switch self {
        case .monthly: "analytics.budget.period.monthly"
        case .weekly: "analytics.budget.period.weekly"
        }
    }
}

extension BudgetPace {
    fileprivate var analyticsBadgeKey: LocalizedStringKey {
        switch self {
        case .onTrack: "analytics.budget.pace.onTrack"
        case .ahead: "analytics.budget.pace.ahead"
        case .hot: "analytics.budget.pace.hot"
        }
    }
}

extension BudgetRolloverPolicy {
    fileprivate var analyticsTitleKey: LocalizedStringKey {
        switch self {
        case .expires: "analytics.budget.rollover.expires"
        case .rollsOver: "analytics.budget.rollover.rollsOver"
        case .toGoal: "analytics.budget.rollover.toGoal"
        case .toFreeCash: "analytics.budget.rollover.toFreeCash"
        }
    }

    fileprivate var analyticsFootnoteKey: LocalizedStringKey {
        switch self {
        case .expires: "analytics.budget.rollover.footnote.expires"
        case .rollsOver: "analytics.budget.rollover.footnote.rollsOver"
        case .toGoal: "analytics.budget.rollover.footnote.toGoal"
        case .toFreeCash: "analytics.budget.rollover.footnote.toFreeCash"
        }
    }
}
