import SwiftUI
import FinPlanCore

struct SettingsRatesView: View {
    @Environment(FinanceStore.self) private var store
    @State private var editorContext: SettingsRateEditorContext?

    var body: some View {
        Group {
            if store.planningRates.rates.isEmpty {
                EmptyStateView(
                    systemImage: "arrow.left.arrow.right.circle",
                    title: "settings.rates.empty.title",
                    message: "settings.rates.empty.message"
                )
            } else {
                List {
                    Section {
                        ForEach(Array(store.planningRates.rates.enumerated()), id: \.offset) { index, rate in
                            Button {
                                editorContext = .edit(index: index, rate: rate)
                            } label: {
                                SettingsRateRow(rate: rate)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteRates)
                    } footer: {
                        Text("settings.rates.footer")
                    }
                }
            }
        }
        .navigationTitle("settings.rates.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorContext = .add
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "a11y.settings.addRate"))
            }
        }
        .sheet(item: $editorContext) { context in
            SettingsRateEditorSheet(context: context)
        }
    }

    private func deleteRates(at offsets: IndexSet) {
        var rates = store.planningRates.rates
        rates.remove(atOffsets: offsets)
        store.planningRates = ManualExchangeRates(rates: rates)
    }
}

enum SettingsRateFormat {
    static func decimalString(rateScaled: Int64, scale: Int) -> String {
        var digits = String(rateScaled)
        if digits.count <= scale {
            digits = String(repeating: "0", count: scale - digits.count + 1) + digits
        }
        let splitIndex = digits.index(digits.endIndex, offsetBy: -scale)
        let whole = String(digits[..<splitIndex])
        var fraction = String(digits[splitIndex...])
        while fraction.hasSuffix("0") { fraction.removeLast() }
        return fraction.isEmpty ? whole : "\(whole).\(fraction)"
    }

    static func display(_ rate: ExchangeRate) -> String {
        decimalString(rateScaled: rate.rateScaled, scale: rate.scale)
    }
}

private struct SettingsRateRow: View {
    let rate: ExchangeRate

    var body: some View {
        HStack(spacing: FP.Spacing.sm) {
            Text(verbatim: "1 \(rate.base.code)")
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(verbatim: "\(SettingsRateFormat.display(rate)) \(rate.quote.code)")
                .monospacedDigit()
            Spacer()
            Image(systemName: "pencil")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("a11y.settings.rateRow \(rate.base.code) \(SettingsRateFormat.display(rate)) \(rate.quote.code)")
        )
    }
}

private enum SettingsRateEditorContext: Identifiable {
    case add
    case edit(index: Int, rate: ExchangeRate)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let index, _): return "edit-\(index)"
        }
    }
}

private struct SettingsRateEditorSheet: View {
    let context: SettingsRateEditorContext
    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var baseCode: String
    @State private var quoteCode: String
    @State private var rateText: String
    @State private var enteredRate: ExchangeRate?

    init(context: SettingsRateEditorContext) {
        self.context = context
        guard case .edit(_, let rate) = context else {
            _baseCode = State(initialValue: "USD")
            _quoteCode = State(initialValue: "RUB")
            _rateText = State(initialValue: "")
            _enteredRate = State(initialValue: nil)
            return
        }
        let displayBase = RateEntryField.preferredBase(rate.base, rate.quote)
        let displayRate = rate.base == displayBase ? rate : rate.inverted
        _baseCode = State(initialValue: rate.base.code)
        _quoteCode = State(initialValue: rate.quote.code)
        _rateText = State(initialValue: displayRate.map(SettingsRateFormat.display) ?? "")
        _enteredRate = State(initialValue: displayRate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("settings.rate.base", selection: $baseCode) {
                        ForEach(currencyOptions, id: \.self) { code in
                            Text(verbatim: code).tag(code)
                        }
                    }
                    Picker("settings.rate.quote", selection: $quoteCode) {
                        ForEach(currencyOptions, id: \.self) { code in
                            Text(verbatim: code).tag(code)
                        }
                    }
                    if baseCode != quoteCode {
                        RateEntryField(
                            currencyA: Currency.known(code: baseCode),
                            currencyB: Currency.known(code: quoteCode),
                            sampleAmount: sampleAmount,
                            rateText: $rateText,
                            onRateChange: { enteredRate = $0 }
                        )
                        .id("settings-rate-\(baseCode)-\(quoteCode)")
                    }
                } footer: {
                    footerText
                }
            }
            .navigationTitle(isEditing ? "settings.rate.editTitle" : "settings.rate.addTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(enteredRate == nil || baseCode == quoteCode)
                }
            }
            .onChange(of: baseCode) { _, _ in clearRateEntry() }
            .onChange(of: quoteCode) { _, _ in clearRateEntry() }
        }
    }

    private var isEditing: Bool {
        if case .edit = context { return true }
        return false
    }

    private var currencyOptions: [String] {
        SettingsSupportedCurrencies.codes(including: [baseCode, quoteCode])
    }

    private var sampleAmount: Money? {
        store.recurringTemplates
            .first { $0.isActive && $0.kind == .transfer && $0.goalID != nil }?
            .amount
    }

    @ViewBuilder
    private var footerText: some View {
        if baseCode == quoteCode {
            Text("settings.rate.samePair")
                .foregroundStyle(FPStatusTint.negative)
        } else {
            Text("settings.rate.hint")
        }
    }

    private func clearRateEntry() {
        rateText = ""
        enteredRate = nil
    }

    private func save() {
        guard let rate = enteredRate, baseCode != quoteCode else { return }
        if case .edit(let index, _) = context {
            var rates = store.planningRates.rates
            if rates.indices.contains(index) {
                rates.remove(at: index)
                store.planningRates = ManualExchangeRates(rates: rates)
            }
        }
        store.upsertPlanningRate(rate)
        dismiss()
    }
}

#if DEBUG
#Preview {
    let fixture = SettingsPreviewFactory.make()
    NavigationStack {
        SettingsRatesView()
    }
    .environment(fixture.store)
    .environment(PrivacyShieldModel())
    .modelContainer(fixture.controller.container)
}
#endif
