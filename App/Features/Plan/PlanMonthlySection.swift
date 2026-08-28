import SwiftUI
import FinPlanCore

struct PlanMonthlySection: View {
    @Environment(FinanceStore.self) private var store

    var body: some View {
        let hasPlanData = store.incomeSources.contains(where: \.isActive)
            || store.recurringTemplates.contains { $0.goalID != nil && $0.isActive }
        let hasSubscriptions = store.recurringTemplates.contains { $0.isActive && $0.kind == .expense }
        if !hasPlanData && !hasSubscriptions {
            EmptyStateView(
                systemImage: "calendar.badge.checkmark",
                title: "plan.monthly.empty.title",
                message: "plan.monthly.empty.message"
            )
        } else {
            ScrollView {
                VStack(spacing: FP.Spacing.lg) {
                    if hasPlanData {
                        monthlyContent
                    }
                    PlanSubscriptionsCard()
                }
                .padding(FP.Spacing.lg)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    @ViewBuilder
    private var monthlyContent: some View {
        let now = Date.now
        switch monthlyFigures(now: now) {
        case .success(let figures):
            monthHeader(figures.interval)
            FPCard {
                PlanVarianceRow(
                    titleKey: "plan.monthly.incomeTitle",
                    planned: figures.plannedIncome,
                    actual: figures.actualIncome
                )
            }
            FPCard {
                PlanVarianceRow(
                    titleKey: "plan.monthly.savingsTitle",
                    planned: figures.plannedSavings,
                    actual: figures.actualSavings
                )
            }
        case .failure(let error):
            PlanComputationErrorCard(error: error)
        }
        recoveryCard(now: now)
    }

    private func monthHeader(_ interval: DateInterval) -> some View {
        HStack {
            Label {
                Text(interval.start, format: .dateTime.month(.wide).year())
            } icon: {
                Image(systemName: "calendar")
            }
            .font(.headline)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func monthlyFigures(now: Date) -> Result<PlanMonthlyFigures, any Error> {
        Result {
            try PlanMath.monthlyFigures(
                now: now,
                calendar: .current,
                sources: store.incomeSources,
                templates: store.recurringTemplates,
                transactions: store.transactions,
                currency: store.baseCurrency,
                rates: store.planningRates
            )
        }
    }

    @ViewBuilder
    private func recoveryCard(now: Date) -> some View {
        switch recoveryInfo(now: now) {
        case .success(nil):
            EmptyView()
        case .success(.some(let info)):
            FPCard {
                VStack(alignment: .leading, spacing: FP.Spacing.md) {
                    Label("plan.recovery.title", systemImage: "arrow.uturn.up.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FPStatusTint.attention)
                    Grid(horizontalSpacing: FP.Spacing.lg, verticalSpacing: FP.Spacing.xs) {
                        GridRow {
                            Text("plan.recovery.behindBy")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.leading)
                            PlanSignedMoneyText(delta: info.shortfall.negated)
                                .font(.callout)
                                .gridColumnAlignment(.trailing)
                        }
                        GridRow {
                            Text("plan.recovery.daysBehind")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(abs(info.timeImpactDays), format: .number)
                                .font(.callout)
                                .monospacedDigit()
                        }
                        GridRow {
                            Text("plan.recovery.monthsLeft")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(info.remainingMonths, format: .number)
                                .font(.callout)
                                .monospacedDigit()
                        }
                        GridRow {
                            Text("plan.recovery.extraPerMonth")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 2) {
                                Text(verbatim: "+")
                                MoneyText(money: info.extraPerMonth)
                            }
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(FPStatusTint.attention)
                        }
                    }
                }
            }
        case .failure(let error):
            PlanComputationErrorCard(error: error)
        }
    }

    private func recoveryInfo(now: Date) -> Result<PlanRecoveryInfo?, any Error> {
        Result {
            guard let goal = store.planPrimaryGoal() else { return nil }
            return try PlanMath.recoveryInfo(
                goal: goal,
                balance: try store.planGoalBalance(goal, asOf: now),
                templates: store.recurringTemplates,
                rates: store.planningRates,
                now: now
            )
        }
    }
}

#if DEBUG
#Preview("Monthly") {
    NavigationStack { PlanMonthlySection() }
        .environment(PlanPreviewFactory.makeStore())
}
#endif
