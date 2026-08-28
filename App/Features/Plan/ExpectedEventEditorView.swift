import SwiftUI
import FinPlanCore

struct ExpectedEventEditorView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let event: ExpectedEvent

    @State private var title: String
    @State private var amountText: String
    @State private var amountMinor: Int64?
    @State private var currency: Currency
    @State private var expectedDate: Date
    @State private var destinationAccountID: UUID?
    @State private var goalID: UUID?
    @State private var isCancelConfirmPresented = false
    @State private var saveError: String?

    init(event: ExpectedEvent) {
        self.event = event
        _title = State(initialValue: event.title)
        _amountText = State(initialValue: PlanMoneyEditText.text(for: event.amount))
        _amountMinor = State(initialValue: event.amount.amountMinor)
        _currency = State(initialValue: event.amount.currency)
        _expectedDate = State(initialValue: event.expectedDate)
        _destinationAccountID = State(initialValue: event.destinationAccountID)
        _goalID = State(initialValue: event.goalID)
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                if isActionable {
                    actionsSection
                }
            }
            .navigationTitle("expectedEvent.editor.title")
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
        Section("expectedEvent.editor.section.details") {
            TextField("expectedEvent.editor.field.title", text: $title)
            MoneyField(
                titleKey: "expectedEvent.editor.field.amount",
                currency: currency,
                text: $amountText,
                amountMinor: $amountMinor
            )
            if currencyOptions.count > 1 {
                Picker("expectedEvent.editor.field.currency", selection: $currency) {
                    ForEach(currencyOptions, id: \.code) { option in
                        Text(verbatim: option.code).tag(option)
                    }
                }
            }
            DatePicker(
                "expectedEvent.editor.field.date",
                selection: $expectedDate,
                displayedComponents: .date
            )
            accountPicker
            goalPicker
            LabeledContent("expectedEvent.editor.field.state") {
                Text(stateKey)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var accountPicker: some View {
        let options = store.accounts.filter { !$0.isArchived }
        if !options.isEmpty {
            Picker("expectedEvent.editor.field.account", selection: $destinationAccountID) {
                Text("common.none").tag(UUID?.none)
                ForEach(options) { account in
                    Text(verbatim: "\(account.name) · \(account.currency.code)")
                        .tag(Optional(account.id))
                }
            }
        }
    }

    @ViewBuilder private var goalPicker: some View {
        let activeGoals = store.goals.filter { $0.status == .active || $0.status == .paused }
        if !activeGoals.isEmpty {
            Picker("expectedEvent.editor.field.goal", selection: $goalID) {
                Text("expectedEvent.editor.goal.none").tag(UUID?.none)
                ForEach(activeGoals) { goal in
                    Text(goal.title).tag(UUID?.some(goal.id))
                }
            }
            Text("expectedEvent.editor.goal.footer")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var actionsSection: some View {
        Section("expectedEvent.editor.section.actions") {
            Button {
                markReceived()
            } label: {
                Label("plan.calendar.action.markReceived", systemImage: "checkmark.circle")
            }
            .disabled(!canSave)
            Button(role: .destructive) {
                isCancelConfirmPresented = true
            } label: {
                Label("plan.calendar.action.cancelEvent", systemImage: "xmark.circle")
            }
            .confirmationDialog(
                "plan.calendar.cancelConfirm.title",
                isPresented: $isCancelConfirmPresented,
                titleVisibility: .visible
            ) {
                Button("plan.calendar.action.cancelEvent", role: .destructive) { cancelEvent() }
                Button("plan.common.keep", role: .cancel) {}
            }
        }
    }

    private var isActionable: Bool {
        event.state == .expected || event.state == .overdue
    }

    private var stateKey: LocalizedStringKey {
        switch event.state {
        case .expected: return "expectedEvent.state.expected"
        case .received: return "expectedEvent.state.received"
        case .overdue: return "expectedEvent.state.overdue"
        case .cancelled: return "expectedEvent.state.cancelled"
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

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        guard let minor = amountMinor, minor > 0 else { return false }
        return !trimmedTitle.isEmpty
    }

    private var saveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    private var editedEvent: ExpectedEvent? {
        guard let minor = amountMinor, minor > 0, !trimmedTitle.isEmpty else { return nil }
        var updated = event
        updated.title = trimmedTitle
        updated.amount = Money(minor: minor, currency: currency)
        updated.expectedDate = expectedDate
        updated.destinationAccountID = destinationAccountID
        updated.goalID = goalID
        return updated
    }

    private func save() {
        guard let updated = editedEvent else { return }
        perform {
            try store.updateExpectedEvent(updated)
        }
    }

    private func markReceived() {
        guard let updated = editedEvent else { return }
        perform {
            try store.updateExpectedEvent(updated)
            try store.planMarkExpectedEventReceived(updated)
        }
    }

    private func cancelEvent() {
        perform {
            try store.planCancelExpectedEvent(event)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            dismiss()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}

#if DEBUG
#Preview("Expected event editor") {
    let store = PlanPreviewFactory.makeStore()
    let event = store.expectedEvents.first
        ?? ExpectedEvent(
            title: "Annual bonus",
            amount: Money(minor: 300_000_00, currency: .rub),
            expectedDate: .now
        )
    ExpectedEventEditorView(event: event)
        .environment(store)
}
#endif
