import SwiftUI
import FinPlanCore

struct GoalPurchaseImpactSheet: View {
    let goal: Goal

    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var amountMinor: Int64?
    @State private var date = Date()
    @State private var impact: PurchaseImpact?
    @State private var errorMessage: String?

    private var isValid: Bool {
        guard let amountMinor, amountMinor > 0 else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("goals.canIBuy.section.purchase") {
                    MoneyField(
                        titleKey: "goals.canIBuy.amountField",
                        currency: store.baseCurrency,
                        text: $amountText,
                        amountMinor: $amountMinor
                    )
                    DatePicker("goals.canIBuy.date", selection: $date, displayedComponents: .date)
                    Button {
                        evaluate()
                    } label: {
                        Label("goals.canIBuy.evaluate", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!isValid)
                }

                if let impact {
                    Section("goals.canIBuy.section.result") {
                        GoalsPurchaseVerdictCard(impact: impact)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("goals.canIBuy.simulationNote")
                }
            }
            .navigationTitle(Text("goals.canIBuy"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close", role: .cancel) { dismiss() }
                }
            }
            .alert(
                "error.title",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(verbatim: errorMessage ?? "")
            }
            .onChange(of: amountText) { _, _ in
                impact = nil
            }
            .onChange(of: date) { _, _ in
                impact = nil
            }
        }
    }

    private func evaluate() {
        guard let amountMinor, amountMinor > 0 else { return }
        do {
            impact = try store.goalsPurchaseImpact(
                for: goal,
                amount: Money(minor: amountMinor, currency: store.baseCurrency),
                date: date
            )
        } catch {
            impact = nil
            errorMessage = error.localizedDescription
        }
    }
}

struct GoalsPurchaseVerdictCard: View {
    let impact: PurchaseImpact

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                Label {
                    Text(verdictKey)
                        .font(.headline)
                } icon: {
                    Image(systemName: verdictSymbol)
                        .font(.title2)
                }
                .foregroundStyle(verdictTint)

                Divider()

                HStack {
                    Label("goals.canIBuy.remainingSafeToSpend", systemImage: "wallet.bifold")
                        .font(.subheadline)
                    Spacer(minLength: FP.Spacing.sm)
                    MoneyText(money: impact.remainingSafeToSpend)
                        .font(.subheadline.weight(.semibold))
                }

                if let delay = impact.goalDelayDays, delay > 0 {
                    HStack {
                        Label("goals.canIBuy.delay", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                        Spacer(minLength: FP.Spacing.sm)
                        Text("goals.canIBuy.delayDays \(delay)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FPStatusTint.attention)
                    }
                }

                if let newDate = impact.newCompletionDate {
                    HStack {
                        Label("goals.canIBuy.newCompletion", systemImage: "calendar")
                            .font(.subheadline)
                        Spacer(minLength: FP.Spacing.sm)
                        Text(newDate, format: .dateTime.month(.abbreviated).year())
                            .font(.subheadline.weight(.semibold))
                    }
                }

                if let shortfall = impact.shortfall {
                    HStack {
                        Label("goals.canIBuy.shortfall", systemImage: "minus.circle")
                            .font(.subheadline)
                        Spacer(minLength: FP.Spacing.sm)
                        MoneyText(money: shortfall, compact: true)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FPStatusTint.negative)
                    }
                }

                if impact.affectsNextMilestone {
                    Label("goals.canIBuy.milestoneAffected", systemImage: "flag.slash")
                        .font(.caption)
                        .foregroundStyle(FPStatusTint.attention)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var verdictKey: LocalizedStringKey {
        switch impact.verdict {
        case .safe: return "goals.canIBuy.verdict.safe"
        case .delaysGoal: return "goals.canIBuy.verdict.delaysGoal"
        case .touchesReserve: return "goals.canIBuy.verdict.touchesReserve"
        case .unaffordable: return "goals.canIBuy.verdict.unaffordable"
        }
    }

    private var verdictSymbol: String {
        switch impact.verdict {
        case .safe: return "checkmark.seal.fill"
        case .delaysGoal: return "clock.badge.exclamationmark.fill"
        case .touchesReserve: return "shield.slash.fill"
        case .unaffordable: return "xmark.octagon.fill"
        }
    }

    private var verdictTint: Color {
        switch impact.verdict {
        case .safe: return FPStatusTint.positive
        case .delaysGoal: return FPStatusTint.attention
        case .touchesReserve: return FPStatusTint.attention
        case .unaffordable: return FPStatusTint.negative
        }
    }
}

#if DEBUG
#Preview("Can I buy") {
    let store = GoalsPreviewFixtures.store()
    return GoalPurchaseImpactSheet(goal: store.goals.first { $0.id == GoalsPreviewFixtures.apartmentGoalID }!)
        .environment(store)
}
#endif
