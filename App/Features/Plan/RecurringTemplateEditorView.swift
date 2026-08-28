import SwiftUI
import FinPlanCore

enum PlanMoneyEditText {
    static func text(for money: Money) -> String {
        var divisor = Decimal(1)
        for _ in 0..<money.currency.minorUnitExponent { divisor *= 10 }
        return (Decimal(money.amountMinor) / divisor)
            .formatted(.number.grouping(.never).precision(.fractionLength(0...money.currency.minorUnitExponent)))
    }
}

struct RecurringTemplateEditorView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let template: RecurringTemplate

    @State private var name: String
    @State private var amountText: String
    @State private var amountMinor: Int64?
    @State private var currency: Currency
    @State private var cadence: RecurringEditorCadence
    @State private var monthDay: Int
    @State private var weekday: Int
    @State private var yearMonth: Int
    @State private var stepDays: Int
    @State private var sourceAccountID: UUID?
    @State private var destinationAccountID: UUID?
    @State private var goalID: UUID?
    @State private var isActive: Bool
    @State private var isDeleteConfirmPresented = false
    @State private var saveError: String?

    init(template: RecurringTemplate) {
        self.template = template
        _name = State(initialValue: template.name)
        _amountText = State(initialValue: PlanMoneyEditText.text(for: template.amount))
        _amountMinor = State(initialValue: template.amount.amountMinor)
        _currency = State(initialValue: template.amount.currency)
        _sourceAccountID = State(initialValue: template.sourceAccountID)
        _destinationAccountID = State(initialValue: template.destinationAccountID)
        _goalID = State(initialValue: template.goalID)
        _isActive = State(initialValue: template.isActive)

        var cadence = RecurringEditorCadence.monthly
        var monthDay = 1
        var weekday = 2
        var yearMonth = 1
        var stepDays = 30
        switch template.recurrence {
        case .daily:
            cadence = .daily
        case .weekly(let day):
            cadence = .weekly
            weekday = day
        case .monthly(let day):
            cadence = .monthly
            monthDay = day
        case .yearly(let month, let day):
            cadence = .yearly
            yearMonth = month
            monthDay = day
        case .everyNDays(let n):
            cadence = .everyNDays
            stepDays = max(1, n)
        }
        _cadence = State(initialValue: cadence)
        _monthDay = State(initialValue: monthDay)
        _weekday = State(initialValue: weekday)
        _yearMonth = State(initialValue: yearMonth)
        _stepDays = State(initialValue: stepDays)
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                scheduleSection
                accountsSection
                if template.kind == .transfer {
                    goalSection
                }
                Section {
                    Toggle("recurring.editor.field.active", isOn: $isActive)
                } footer: {
                    Text("recurring.editor.activeFooter")
                }
                deleteSection
            }
            .navigationTitle("recurring.editor.titleShort")
            .navigationBarTitleDisplayMode(.inline)
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
            .onChange(of: currency) {
                amountMinor = MoneyParser.minorUnits(from: amountText, currency: currency)
            }
            .alert("error.title", isPresented: saveErrorPresented) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(verbatim: saveError ?? "")
            }
        }
    }

    private var detailsSection: some View {
        Section("recurring.editor.section.details") {
            TextField("recurring.editor.field.name", text: $name)
            LabeledContent("recurring.editor.field.kind") {
                Text(TransactionsLabels.kindKey(template.kind))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            MoneyField(
                titleKey: "recurring.editor.field.amount",
                currency: currency,
                text: $amountText,
                amountMinor: $amountMinor
            )
            if currencyOptions.count > 1 {
                Picker("recurring.editor.field.currency", selection: $currency) {
                    ForEach(currencyOptions, id: \.code) { option in
                        Text(verbatim: option.code).tag(option)
                    }
                }
            }
        }
    }

    private var scheduleSection: some View {
        Section("recurring.editor.section.schedule") {
            Picker("recurring.editor.field.cadence", selection: $cadence) {
                ForEach(RecurringEditorCadence.allCases) { option in
                    Text(option.titleKey).tag(option)
                }
            }
            switch cadence {
            case .daily:
                EmptyView()
            case .weekly:
                Picker("recurring.editor.field.weekday", selection: $weekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(verbatim: Self.weekdayName(day)).tag(day)
                    }
                }
            case .monthly:
                monthDayStepper
            case .yearly:
                Picker("recurring.editor.field.month", selection: $yearMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(verbatim: Self.monthName(month)).tag(month)
                    }
                }
                monthDayStepper
            case .everyNDays:
                Stepper(value: $stepDays, in: 1...365) {
                    HStack {
                        Text("recurring.editor.field.stepDays")
                        Spacer()
                        Text(verbatim: "\(stepDays)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var monthDayStepper: some View {
        Stepper(value: $monthDay, in: 1...31) {
            HStack {
                Text("recurring.editor.field.monthDay")
                Spacer()
                Text(verbatim: "\(monthDay)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder private var accountsSection: some View {
        let options = store.accounts.filter { !$0.isArchived }
        if !options.isEmpty {
            Section("recurring.editor.section.accounts") {
                switch template.kind {
                case .expense, .adjustment:
                    accountPicker("transactions.field.account", selection: $sourceAccountID, options: options)
                case .income:
                    accountPicker("transactions.field.toAccount", selection: $destinationAccountID, options: options)
                case .transfer, .currencyExchange:
                    accountPicker("transactions.field.fromAccount", selection: $sourceAccountID, options: options)
                    accountPicker("transactions.field.toAccount", selection: $destinationAccountID, options: options)
                    if hasSameSourceAndDestination {
                        Text("recurring.editor.validation.sameAccounts")
                            .font(.footnote)
                            .foregroundStyle(FPStatusTint.attention)
                    }
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
            Text("common.none").tag(UUID?.none)
            ForEach(options) { account in
                Text(verbatim: "\(account.name) · \(account.currency.code)")
                    .tag(Optional(account.id))
            }
        }
    }

    @ViewBuilder private var goalSection: some View {
        let goals = store.goals.filter { $0.status == .active || $0.status == .planned || $0.status == .paused }
        if !goals.isEmpty {
            Section {
                Picker("transactions.allocateToGoal", selection: $goalID) {
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

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                isDeleteConfirmPresented = true
            } label: {
                Label("recurring.editor.delete", systemImage: "trash")
            }
            .confirmationDialog(
                "recurring.editor.deleteConfirm.title",
                isPresented: $isDeleteConfirmPresented,
                titleVisibility: .visible
            ) {
                Button("recurring.editor.deleteConfirm.confirm", role: .destructive) { delete() }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("recurring.editor.deleteConfirm.message")
            }
        } footer: {
            Text("recurring.editor.deleteFooter")
        }
    }

    private var currencyOptions: [Currency] {
        var seen = Set<String>()
        var options: [Currency] = []
        for account in store.accounts where !account.isArchived {
            if seen.insert(account.currency.code).inserted {
                options.append(account.currency)
            }
        }
        if seen.insert(currency.code).inserted {
            options.append(currency)
        }
        return options
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSameSourceAndDestination: Bool {
        guard let source = sourceAccountID, let destination = destinationAccountID else { return false }
        return source == destination
    }

    private var canSave: Bool {
        guard let minor = amountMinor, minor > 0 else { return false }
        return !trimmedName.isEmpty && !hasSameSourceAndDestination
    }

    private var builtRecurrence: Recurrence {
        switch cadence {
        case .daily: return .daily
        case .weekly: return .weekly(weekday: weekday)
        case .monthly: return .monthly(day: monthDay)
        case .yearly: return .yearly(month: yearMonth, day: monthDay)
        case .everyNDays: return .everyNDays(stepDays)
        }
    }

    private var saveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    private func save() {
        guard let minor = amountMinor, minor > 0 else { return }
        var updated = template
        updated.name = trimmedName
        updated.amount = Money(minor: minor, currency: currency)
        updated.recurrence = builtRecurrence
        updated.isActive = isActive
        switch template.kind {
        case .expense, .adjustment:
            updated.sourceAccountID = sourceAccountID
        case .income:
            updated.destinationAccountID = destinationAccountID
        case .transfer, .currencyExchange:
            updated.sourceAccountID = sourceAccountID
            updated.destinationAccountID = destinationAccountID
        }
        if template.kind == .transfer {
            updated.goalID = goalID
        }
        do {
            try store.updateRecurringTemplate(updated)
            dismiss()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func delete() {
        do {
            try store.deleteRecurringTemplate(id: template.id)
            dismiss()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.standaloneWeekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "\(weekday)" }
        return symbols[index].capitalized
    }

    private static func monthName(_ month: Int) -> String {
        let symbols = Calendar.current.standaloneMonthSymbols
        let index = month - 1
        guard symbols.indices.contains(index) else { return "\(month)" }
        return symbols[index].capitalized
    }
}

enum RecurringEditorCadence: Hashable, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly, everyNDays

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .daily: return "recurring.editor.cadence.daily"
        case .weekly: return "recurring.editor.cadence.weekly"
        case .monthly: return "recurring.editor.cadence.monthly"
        case .yearly: return "recurring.editor.cadence.yearly"
        case .everyNDays: return "recurring.editor.cadence.everyNDays"
        }
    }
}

#if DEBUG
#Preview("Recurring editor") {
    let store = PlanPreviewFactory.makeStore()
    let template = store.recurringTemplates.first
        ?? RecurringTemplate(
            name: "Rent",
            kind: .expense,
            amount: Money(minor: 90_000_00, currency: .rub),
            recurrence: .monthly(day: 1),
            startDate: .now
        )
    RecurringTemplateEditorView(template: template)
        .environment(store)
}
#endif
