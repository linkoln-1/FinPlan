import SwiftUI
import FinPlanCore

struct GoalEditorView: View {
    let existing: Goal?

    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var symbolName: String
    @State private var amountText: String
    @State private var amountMinor: Int64?
    @State private var currencyCode: String
    @State private var hasDesiredDate: Bool
    @State private var desiredDate: Date
    @State private var priority: GoalPriority
    @State private var isEmergencyFund: Bool
    @State private var monthsOfExpenses: Int
    @State private var saveError: String?
    @State private var saveSuccessCount = 0

    private static let currencyCodes = ["RUB", "USD", "EUR"]
    private static let monthsRange = 1...24
    private static let defaultMonths = 6

    init(existing: Goal?) {
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _symbolName = State(initialValue: existing?.symbolName ?? "target")
        _amountText = State(initialValue: existing.map { GoalsDisplay.editableText(for: $0.targetAmount) } ?? "")
        _amountMinor = State(initialValue: existing?.targetAmount.amountMinor)
        _currencyCode = State(initialValue: existing?.targetAmount.currency.code ?? "RUB")
        _hasDesiredDate = State(initialValue: existing?.desiredCompletionDate != nil)
        _desiredDate = State(initialValue: existing?.desiredCompletionDate ?? Self.defaultDesiredDate)
        _priority = State(initialValue: existing?.priority ?? .medium)
        _isEmergencyFund = State(initialValue: existing?.isEmergencyFund ?? false)
        _monthsOfExpenses = State(initialValue: existing?.desiredMonthsOfExpenses ?? Self.defaultMonths)
    }

    private static var defaultDesiredDate: Date {
        Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    }

    private var currency: Currency { Currency.known(code: currencyCode) }

    private var suggestedEmergencyTarget: Money? {
        guard let monthly = try? PlanMath.baselineMonthlyExpenses(
            templates: store.recurringTemplates,
            in: currency,
            rates: store.planningRates
        ), monthly.isPositive else { return nil }
        return monthly.multiplied(by: Int64(monthsOfExpenses))
    }

    private var isValid: Bool {
        guard let amountMinor, amountMinor > 0 else { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("goals.editor.section.basics") {
                    TextField("goals.editor.titleField", text: $title)
                    symbolPicker
                }

                Section("goals.editor.section.target") {
                    MoneyField(
                        titleKey: "goals.editor.targetAmount",
                        currency: currency,
                        text: $amountText,
                        amountMinor: $amountMinor
                    )
                    Picker("goals.editor.currency", selection: $currencyCode) {
                        ForEach(Self.currencyCodes, id: \.self) { code in
                            Text(verbatim: code).tag(code)
                        }
                    }
                    .onChange(of: currencyCode) { _, _ in
                        amountMinor = MoneyParser.minorUnits(from: amountText, currency: currency)
                    }
                }

                Section("goals.editor.section.plan") {
                    Toggle("goals.editor.desiredDateToggle", isOn: $hasDesiredDate.animation())
                    if hasDesiredDate {
                        DatePicker(
                            "goals.editor.desiredDate",
                            selection: $desiredDate,
                            displayedComponents: .date
                        )
                    }
                    Picker("goals.editor.priority", selection: $priority) {
                        Text("goals.priority.low").tag(GoalPriority.low)
                        Text("goals.priority.medium").tag(GoalPriority.medium)
                        Text("goals.priority.high").tag(GoalPriority.high)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("goals.editor.emergencyToggle", isOn: $isEmergencyFund.animation())
                    if isEmergencyFund {
                        Stepper(value: $monthsOfExpenses, in: Self.monthsRange) {
                            HStack {
                                Text("goals.editor.monthsOfExpenses")
                                Spacer()
                                Text(monthsOfExpenses, format: .number)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .accessibilityValue(Text(monthsOfExpenses, format: .number))

                        if let suggested = suggestedEmergencyTarget {
                            Button {
                                amountText = BackupService.decimalString(suggested)
                                amountMinor = suggested.amountMinor
                            } label: {
                                HStack {
                                    Text("goals.editor.emergencySuggest")
                                    Spacer()
                                    MoneyText(money: suggested, compact: true)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("goals.editor.section.emergency")
                } footer: {
                    Text("goals.editor.emergencyFooter")
                }
            }
            .navigationTitle(existing == nil ? Text("goals.editor.title.create") : Text("goals.editor.title.edit"))
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
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(verbatim: saveError ?? "")
            }
            .sensoryFeedback(.success, trigger: saveSuccessCount)
        }
    }

    private var symbolPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: FP.Spacing.sm)], spacing: FP.Spacing.sm) {
            ForEach(GoalsSymbolCatalog.symbols, id: \.self) { symbol in
                Button {
                    symbolName = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            symbolName == symbol ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: FP.Radius.control)
                        )
                        .foregroundStyle(symbolName == symbol ? Color.accentColor : Color.secondary)
                        .overlay {
                            if symbolName == symbol {
                                RoundedRectangle(cornerRadius: FP.Radius.control)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("goals.editor.symbol.a11y \(symbol)"))
                .accessibilityAddTraits(symbolName == symbol ? .isSelected : [])
            }
        }
        .padding(.vertical, FP.Spacing.xs)
    }

    private func save() {
        guard let amountMinor, amountMinor > 0 else { return }
        let target = Money(minor: amountMinor, currency: currency)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing {
            var updated = existing
            updated.title = trimmedTitle
            updated.symbolName = symbolName
            updated.targetAmount = target
            updated.desiredCompletionDate = hasDesiredDate ? desiredDate : nil
            updated.priority = priority
            updated.isEmergencyFund = isEmergencyFund
            updated.desiredMonthsOfExpenses = isEmergencyFund ? monthsOfExpenses : nil
            do {
                try store.updateGoal(updated)
                saveSuccessCount += 1
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
        } else {
            let goal = Goal(
                title: trimmedTitle,
                symbolName: symbolName,
                targetAmount: target,
                startDate: Date(),
                desiredCompletionDate: hasDesiredDate ? desiredDate : nil,
                priority: priority,
                status: .active,
                isEmergencyFund: isEmergencyFund,
                desiredMonthsOfExpenses: isEmergencyFund ? monthsOfExpenses : nil
            )
            store.addGoal(goal)
            saveSuccessCount += 1
            dismiss()
        }
    }
}

#if DEBUG
#Preview("Create goal") {
    GoalEditorView(existing: nil)
        .environment(GoalsPreviewFixtures.store())
}
#endif

#if DEBUG
#Preview("Edit goal") {
    let store = GoalsPreviewFixtures.store()
    return GoalEditorView(existing: store.goals.first)
        .environment(store)
}
#endif
