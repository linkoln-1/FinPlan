import SwiftUI
import FinPlanCore

struct SettingsMissingRatesSheet: View {
    let currencies: [Currency]
    let onDone: () -> Void
    @Environment(FinanceStore.self) private var store
    @State private var rateTexts: [String: String] = [:]
    @State private var savedCodes: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("settings.missingRates.message \(store.baseCurrency.code)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(currencies, id: \.code) { currency in
                    Section {
                        RateEntryField(
                            currencyA: currency,
                            currencyB: store.baseCurrency,
                            sampleAmount: sampleAmount(for: currency),
                            rateText: Binding(
                                get: { rateTexts[currency.code] ?? "" },
                                set: { rateTexts[currency.code] = $0 }
                            )
                        ) { rate in
                            if let rate {
                                store.upsertPlanningRate(rate)
                                savedCodes.insert(currency.code)
                            } else {
                                savedCodes.remove(currency.code)
                            }
                        }
                        if savedCodes.contains(currency.code) {
                            Label("settings.missingRates.saved", systemImage: "checkmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(FPStatusTint.positive)
                        }
                    } header: {
                        Text(verbatim: "\(currency.code) → \(store.baseCurrency.code)")
                    }
                }
            }
            .navigationTitle("settings.missingRates.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings.missingRates.done") { onDone() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func sampleAmount(for currency: Currency) -> Money? {
        if let template = store.recurringTemplates.first(where: { $0.isActive && $0.amount.currency == currency }) {
            return template.amount
        }
        if let income = store.incomeSources.first(where: { $0.isActive && $0.grossAmount.currency == currency }) {
            return income.grossAmount
        }
        if let account = store.accounts.first(where: { !$0.isArchived && $0.currency == currency }) {
            return account.openingBalance.isPositive ? account.openingBalance : nil
        }
        return nil
    }
}
