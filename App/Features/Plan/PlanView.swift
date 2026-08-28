import SwiftUI
import FinPlanCore

struct PlanView: View {
    @Environment(FinanceStore.self) private var store
    @State private var section: PlanSection = .monthly

    var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .monthly:
                    PlanMonthlySection()
                case .calendar:
                    PlanCalendarSection()
                case .timeline:
                    PlanTimelineSection()
                case .whatIf:
                    PlanWhatIfSection()
                }
            }
            .navigationTitle("plan.title")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Picker("plan.section.picker", selection: $section) {
                    ForEach(PlanSection.allCases) { section in
                        Text(section.titleKey).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, FP.Spacing.lg)
                .padding(.bottom, FP.Spacing.sm)
                .background(.bar)
            }
            .alert(
                "plan.alert.storeError.title",
                isPresented: Binding(
                    get: { store.lastError != nil },
                    set: { isPresented in if !isPresented { store.lastError = nil } }
                )
            ) {
                Button("plan.common.ok", role: .cancel) {}
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }
}

private enum PlanSection: Hashable, CaseIterable, Identifiable {
    case monthly, calendar, timeline, whatIf

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .monthly: return "plan.section.month"
        case .calendar: return "plan.section.calendar"
        case .timeline: return "plan.section.timeline"
        case .whatIf: return "plan.section.whatif"
        }
    }
}

struct PlanVarianceRow: View {
    let titleKey: LocalizedStringKey
    let planned: Money
    let actual: Money

    var body: some View {
        let delta = try? actual.subtracting(planned)
        VStack(alignment: .leading, spacing: FP.Spacing.sm) {
            Text(titleKey)
                .font(.subheadline.weight(.semibold))
            Grid(horizontalSpacing: FP.Spacing.lg, verticalSpacing: FP.Spacing.xs) {
                GridRow {
                    Text("plan.monthly.planned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)
                    MoneyText(money: planned)
                        .font(.callout)
                        .gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text("plan.monthly.actual")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MoneyText(money: actual)
                        .font(.callout.weight(.semibold))
                }
                GridRow {
                    Text("plan.monthly.variance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let delta {
                        PlanSignedMoneyText(delta: delta)
                            .font(.callout.weight(.semibold))
                    } else {
                        Text("plan.monthly.varianceUnavailable")
                            .font(.caption)
                            .foregroundStyle(FPStatusTint.attention)
                    }
                }
            }
        }
    }
}

struct PlanSignedMoneyText: View {
    let delta: Money
    var compact: Bool = false

    var body: some View {
        let tint: Color = delta.isNegative
            ? FPStatusTint.negative
            : (delta.isPositive ? FPStatusTint.positive : FPStatusTint.neutral)
        HStack(spacing: 2) {
            if delta.isPositive {
                Text(verbatim: "+")
            } else if delta.isNegative {
                Text(verbatim: "−")
            }
            MoneyText(money: delta.isNegative ? delta.negated : delta, compact: compact)
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
    }
}

struct PlanComputationErrorCard: View {
    let error: any Error

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.sm) {
                Label("plan.error.compute", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FPStatusTint.attention)
                Text(verbatim: (error as? LocalizedError)?.errorDescription ?? String(describing: error))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
#Preview("Plan tab") {
    PlanView()
        .environment(PlanPreviewFactory.makeStore())
}
#endif

#if DEBUG
#Preview("Plan tab — empty store") {
    PlanView()
        .environment(PlanPreviewFactory.makeEmptyStore())
}
#endif
