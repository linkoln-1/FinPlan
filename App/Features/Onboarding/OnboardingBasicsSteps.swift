import SwiftUI
import FinPlanCore

struct OnboardingCurrencyStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            Section {
                Picker("onboarding.currency.label", selection: $model.baseCurrency) {
                    ForEach(OnboardingModel.supportedCurrencies, id: \.code) { currency in
                        Text(verbatim: currency.code).tag(currency)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("onboarding.currency.header")
            } footer: {
                Text("onboarding.currency.footer")
            }
        }
    }
}

struct OnboardingAccountStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            Section {
                TextField("onboarding.account.namePlaceholder", text: $model.accountName)
                MoneyField(
                    titleKey: "onboarding.account.balancePlaceholder",
                    currency: model.baseCurrency,
                    text: $model.balanceText,
                    amountMinor: $model.balanceMinor
                )
            } header: {
                Text("onboarding.account.header")
            } footer: {
                Text("onboarding.account.footer")
            }
        }
    }
}

struct OnboardingGoalStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            Section {
                TextField("onboarding.goal.titlePlaceholder", text: $model.goalTitle)
                MoneyField(
                    titleKey: "onboarding.goal.targetPlaceholder",
                    currency: model.baseCurrency,
                    text: $model.goalTargetText,
                    amountMinor: $model.goalTargetMinor
                )
            } header: {
                Text("onboarding.goal.header")
            }
            Section {
                Toggle("onboarding.goal.hasDate", isOn: $model.hasDesiredDate)
                if model.hasDesiredDate {
                    DatePicker(
                        "onboarding.goal.date",
                        selection: $model.desiredDate,
                        in: Date.now...,
                        displayedComponents: .date
                    )
                }
            } footer: {
                Text("onboarding.goal.dateFooter")
            }
            Section {
                Toggle("onboarding.goal.allocateOpening", isOn: $model.allocateOpeningToGoal)
            } footer: {
                Text("onboarding.goal.allocateFooter")
            }
        }
    }
}

struct OnboardingSecurityStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.enableBiometrics) {
                    Label("onboarding.security.toggle", systemImage: "faceid")
                }
            } footer: {
                Text("onboarding.security.footer")
            }
            Section {
                Label("onboarding.security.readyTitle", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(FPStatusTint.positive)
            } footer: {
                Text("onboarding.security.finishHint")
            }
        }
    }
}
