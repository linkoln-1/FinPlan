import SwiftUI
import FinPlanCore

struct OnboardingFlowView: View {
    @Environment(FinanceStore.self) private var store
    @State private var model: OnboardingModel

    init(model: OnboardingModel = OnboardingModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressHeader(step: model.step)
            stepContent
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            OnboardingNavigationBar(model: model) {
                model.finish(with: store)
            }
        }
        .animation(.snappy, value: model.step)
        .alert("onboarding.error.title", isPresented: storeErrorBinding) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: store.lastError ?? "")
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch model.step {
        case .baseCurrency: OnboardingCurrencyStep(model: model)
        case .account: OnboardingAccountStep(model: model)
        case .goal: OnboardingGoalStep(model: model)
        case .income: OnboardingIncomeStep(model: model)
        case .savings: OnboardingSavingsStep(model: model)
        case .expectedEvents: OnboardingEventsStep(model: model)
        case .recurringExpenses: OnboardingExpensesStep(model: model)
        case .security: OnboardingSecurityStep(model: model)
        }
    }

    private var storeErrorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { isPresented in
                if !isPresented { store.lastError = nil }
            }
        )
    }
}

private struct OnboardingProgressHeader: View {
    let step: OnboardingStep

    private var currentIndex: Int { step.rawValue + 1 }
    private var totalSteps: Int { OnboardingStep.allCases.count }

    var body: some View {
        VStack(alignment: .leading, spacing: FP.Spacing.sm) {
            ProgressView(value: Double(currentIndex), total: Double(totalSteps))
                .accessibilityLabel(Text("onboarding.progress.a11y \(currentIndex) \(totalSteps)"))
            Text("onboarding.step.counter \(currentIndex) \(totalSteps)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(step.titleKey)
                .font(.title2.bold())
            Text(step.subtitleKey)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FP.Spacing.lg)
        .padding(.top, FP.Spacing.lg)
        .padding(.bottom, FP.Spacing.sm)
    }
}

private struct OnboardingNavigationBar: View {
    let model: OnboardingModel
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: FP.Spacing.md) {
            if model.step != .baseCurrency {
                Button("onboarding.back") {
                    model.goBack()
                }
                .buttonStyle(.bordered)
            }
            Spacer(minLength: 0)
            Button(primaryTitleKey) {
                if model.step == .security {
                    onFinish()
                } else {
                    model.advance()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canAdvance)
        }
        .padding(.horizontal, FP.Spacing.lg)
        .padding(.vertical, FP.Spacing.md)
        .background(.bar)
    }

    private var primaryTitleKey: LocalizedStringKey {
        if model.step == .security { return "onboarding.finish" }
        return model.showsSkipLabel ? "onboarding.skip" : "onboarding.continue"
    }
}

#if DEBUG
extension OnboardingModel {
    static func previewFilled(step: OnboardingStep) -> OnboardingModel {
        let model = OnboardingModel()
        model.baseCurrency = .rub
        model.balanceText = "850000"
        model.balanceMinor = 85_000_000
        model.goalTitle = "Apartment down payment"
        model.goalTargetText = "6000000"
        model.goalTargetMinor = 600_000_000
        model.incomeDrafts = [
            OnboardingIncomeDraft(name: "Salary", amountText: "400000", amountMinor: 40_000_000, currency: .rub),
            OnboardingIncomeDraft(name: "Consulting", amountText: "2000", amountMinor: 200_000, currency: .usd, sharePreset: .half),
        ]
        model.savingsAmountText = "4000"
        model.savingsAmountMinor = 400_000
        model.savingsCurrency = .usd
        model.savingsRateText = "84.282"
        model.step = step
        return model
    }
}

#Preview("Fresh start") {
    let controller = PersistenceController.preview()
    let store = FinanceStore(context: controller.container.mainContext)
    OnboardingFlowView()
        .environment(store)
        .modelContainer(controller.container)
}

#Preview("Income step") {
    let controller = PersistenceController.preview()
    let store = FinanceStore(context: controller.container.mainContext)
    OnboardingFlowView(model: .previewFilled(step: .income))
        .environment(store)
        .modelContainer(controller.container)
}

#Preview("Savings step, dark") {
    let controller = PersistenceController.preview()
    let store = FinanceStore(context: controller.container.mainContext)
    OnboardingFlowView(model: .previewFilled(step: .savings))
        .environment(store)
        .modelContainer(controller.container)
        .preferredColorScheme(.dark)
}
#endif
