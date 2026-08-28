import SwiftUI
import FinPlanCore

struct OnboardingIncomeStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            if model.incomeDrafts.isEmpty {
                Section {
                    EmptyStateView(
                        systemImage: "banknote",
                        title: "onboarding.income.empty.title",
                        message: "onboarding.income.empty.message"
                    )
                }
            }
            ForEach($model.incomeDrafts) { $draft in
                OnboardingIncomeRow(draft: $draft) {
                    model.removeIncomeDraft(id: draft.id)
                }
            }
            Section {
                Button {
                    model.addIncomeDraft()
                } label: {
                    Label("onboarding.income.add", systemImage: "plus.circle.fill")
                }
            }
            summarySection
        }
    }

    @ViewBuilder private var summarySection: some View {
        Section {
            switch model.incomeSummary {
            case .empty:
                Text("onboarding.income.summary.empty")
                    .foregroundStyle(.secondary)
            case .total(let money):
                LabeledContent {
                    MoneyText(money: money)
                } label: {
                    Text("onboarding.income.summary.total")
                }
            case .subtotals(let subtotals):
                ForEach(subtotals, id: \.currency.code) { subtotal in
                    LabeledContent {
                        MoneyText(money: subtotal)
                    } label: {
                        Text(verbatim: subtotal.currency.code)
                    }
                }
            }
        } header: {
            Text("onboarding.income.summary.header")
        } footer: {
            if case .subtotals = model.incomeSummary {
                Text("onboarding.income.summary.mixedHint")
            }
        }
    }
}

private struct OnboardingIncomeRow: View {
    @Binding var draft: OnboardingIncomeDraft
    let onDelete: () -> Void

    var body: some View {
        Section {
            TextField("onboarding.income.namePlaceholder", text: $draft.name)
            MoneyField(
                titleKey: "onboarding.income.amountPlaceholder",
                currency: draft.currency,
                text: $draft.amountText,
                amountMinor: $draft.amountMinor
            )
            Picker("onboarding.income.currency", selection: $draft.currency) {
                ForEach(OnboardingModel.supportedCurrencies, id: \.code) { currency in
                    Text(verbatim: currency.code).tag(currency)
                }
            }
            Picker("onboarding.income.share", selection: $draft.sharePreset) {
                ForEach(OnboardingIncomeDraft.SharePreset.allCases, id: \.self) { preset in
                    if let basisPoints = preset.basisPoints {
                        Text(basisPoints / 100, format: .percent).tag(preset)
                    } else {
                        Text("onboarding.income.share.custom").tag(preset)
                    }
                }
            }
            .pickerStyle(.segmented)
            if draft.sharePreset == .custom {
                Stepper(value: $draft.customBasisPoints, in: 100...10_000, step: 100) {
                    LabeledContent("onboarding.income.share.customLabel") {
                        Text(draft.customBasisPoints / 100, format: .percent)
                    }
                }
            }
            Button("onboarding.row.delete", role: .destructive, action: onDelete)
        }
        .onChange(of: draft.currency) { _, newCurrency in
            draft.amountMinor = MoneyParser.minorUnits(from: draft.amountText, currency: newCurrency)
        }
    }
}

struct OnboardingSavingsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            Section {
                MoneyField(
                    titleKey: "onboarding.savings.amountPlaceholder",
                    currency: model.savingsCurrency,
                    text: $model.savingsAmountText,
                    amountMinor: $model.savingsAmountMinor
                )
                Picker("onboarding.savings.currency", selection: $model.savingsCurrency) {
                    ForEach(OnboardingModel.supportedCurrencies, id: \.code) { currency in
                        Text(verbatim: currency.code).tag(currency)
                    }
                }
            } header: {
                Text("onboarding.savings.header")
            } footer: {
                Text("onboarding.savings.footer")
            }
            if model.needsPlanningRate {
                Section {
                    RateEntryField(
                        currencyA: model.savingsCurrency,
                        currencyB: model.baseCurrency,
                        sampleAmount: model.savingsSampleAmount,
                        rateText: $model.savingsRateText,
                        onRateChange: { model.enteredPlanningRate = $0 }
                    )
                    .id("onboarding-rate-\(model.savingsCurrency.code)-\(model.baseCurrency.code)")
                } header: {
                    Text("onboarding.savings.rateHeader")
                } footer: {
                    VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                        if model.isPlanningRateSuspicious {
                            Text("onboarding.savings.rateBlocked")
                                .foregroundStyle(FPStatusTint.attention)
                        } else {
                            Text("onboarding.savings.rateFooter")
                        }
                        Text("onboarding.info.rate")
                    }
                }
            }
        }
        .onChange(of: model.savingsCurrency) { _, newCurrency in
            model.savingsAmountMinor = MoneyParser.minorUnits(from: model.savingsAmountText, currency: newCurrency)
            model.resetPlanningRateEntry()
        }
    }
}

struct OnboardingEventsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            if model.eventDrafts.isEmpty {
                Section {
                    EmptyStateView(
                        systemImage: "gift",
                        title: "onboarding.events.empty.title",
                        message: "onboarding.events.empty.message"
                    )
                }
            }
            ForEach($model.eventDrafts) { $draft in
                Section {
                    TextField("onboarding.events.titlePlaceholder", text: $draft.title)
                    MoneyField(
                        titleKey: "onboarding.events.amountPlaceholder",
                        currency: model.baseCurrency,
                        text: $draft.amountText,
                        amountMinor: $draft.amountMinor
                    )
                    DatePicker(
                        "onboarding.events.date",
                        selection: $draft.date,
                        in: Date.now...,
                        displayedComponents: .date
                    )
                    .environment(\.locale, Locale(identifier: Locale.preferredLanguages.first ?? "en"))
                    Button("onboarding.row.delete", role: .destructive) {
                        model.removeEventDraft(id: draft.id)
                    }
                }
            }
            Section {
                Button {
                    model.addEventDraft()
                } label: {
                    Label("onboarding.events.add", systemImage: "plus.circle.fill")
                }
            }
        }
    }
}

struct OnboardingExpensesStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            if model.expenseDrafts.isEmpty {
                Section {
                    EmptyStateView(
                        systemImage: "creditcard",
                        title: "onboarding.expenses.empty.title",
                        message: "onboarding.expenses.empty.message"
                    )
                }
            }
            ForEach($model.expenseDrafts) { $draft in
                Section {
                    TextField("onboarding.expenses.namePlaceholder", text: $draft.name)
                    MoneyField(
                        titleKey: "onboarding.expenses.amountPlaceholder",
                        currency: model.baseCurrency,
                        text: $draft.amountText,
                        amountMinor: $draft.amountMinor
                    )
                    Stepper(value: $draft.day, in: 1...31) {
                        LabeledContent("onboarding.expenses.dayLabel") {
                            Text(draft.day, format: .number)
                        }
                    }
                    Button("onboarding.row.delete", role: .destructive) {
                        model.removeExpenseDraft(id: draft.id)
                    }
                }
            }
            Section {
                Button {
                    model.addExpenseDraft()
                } label: {
                    Label("onboarding.expenses.add", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("onboarding.expenses.footer")
            }
        }
    }
}
