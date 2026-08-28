import SwiftUI
import FinPlanCore

struct GoalsView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var isPresentingEditor = false
    @State private var path: [UUID] = []

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $path) {
            Group {
                if store.goals.isEmpty {
                    EmptyStateView(
                        systemImage: "target",
                        title: "goals.empty.title",
                        message: "goals.empty.message"
                    )
                } else {
                    goalsList
                }
            }
            .navigationTitle(Text("goals.title"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("goals.add.a11y"))
                }
            }
            .sheet(isPresented: $isPresentingEditor) {
                GoalEditorView(existing: nil)
            }
            .alert(
                "error.title",
                isPresented: Binding(
                    get: { store.lastError != nil },
                    set: { if !$0 { store.lastError = nil } }
                )
            ) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(verbatim: store.lastError ?? "")
            }
            .navigationDestination(for: UUID.self) { goalID in
                GoalDetailView(goalID: goalID)
            }
            .onChange(of: router.pendingRoute, initial: true) { _, route in
                consume(route)
            }
        }
    }

    private func consume(_ route: AppRoute?) {
        guard case .goal(let goalID) = route else { return }
        router.pendingRoute = nil
        path.append(goalID)
    }

    private var goalsList: some View {
        List {
            section(titleKey: "goals.section.active", goals: goals(with: [.active]))
            section(titleKey: "goals.section.plannedPaused", goals: goals(with: [.paused, .planned]))
            section(titleKey: "goals.section.finished", goals: goals(with: [.completed, .archived]))
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func section(titleKey: LocalizedStringKey, goals: [Goal]) -> some View {
        if !goals.isEmpty {
            Section {
                ForEach(goals) { goal in
                    NavigationLink(value: goal.id) {
                        GoalsSummaryRow(goal: goal)
                    }
                }
            } header: {
                Text(titleKey)
            }
        }
    }

    private func goals(with statuses: Set<GoalStatus>) -> [Goal] {
        store.goals
            .filter { statuses.contains($0.status) }
            .sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }
}

struct GoalsSummaryRow: View {
    let goal: Goal
    @Environment(FinanceStore.self) private var store

    var body: some View {
        let funded = try? store.goalsFunded(for: goal)
        let bps = store.goalsProgressBasisPoints(funded: funded ?? .zero(goal.targetAmount.currency), target: goal.targetAmount)

        VStack(alignment: .leading, spacing: FP.Spacing.sm) {
            HStack(spacing: FP.Spacing.md) {
                Image(systemName: goal.symbolName)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(minWidth: 28)
                    .accessibilityHidden(true)
                Text(goal.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(verbatim: GoalsDisplay.percentText(basisPoints: bps))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: FP.Spacing.xs) {
                if let funded {
                    MoneyText(money: funded, compact: true)
                } else {
                    Label("goals.row.fundedUnavailable", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(FPStatusTint.attention)
                        .accessibilityLabel(Text("goals.row.fundedUnavailable"))
                }
                Text("goals.row.ofTarget")
                    .foregroundStyle(.secondary)
                MoneyText(money: goal.targetAmount, compact: true)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            ProgressView(value: GoalsDisplay.progressFraction(basisPoints: bps))
                .tint(goal.status == .completed ? FPStatusTint.positive : Color.accentColor)
                .accessibilityLabel(Text("goals.row.progress.a11y"))
                .accessibilityValue(Text(verbatim: GoalsDisplay.percentText(basisPoints: bps)))

            HStack(spacing: FP.Spacing.sm) {
                projectedCompletionLabel
                Spacer(minLength: 0)
                GoalsPriorityBadge(priority: goal.priority)
                if goal.isEmergencyFund {
                    GoalsEmergencyBadge()
                }
            }
        }
        .padding(.vertical, FP.Spacing.xs)
    }

    @ViewBuilder
    private var projectedCompletionLabel: some View {
        if goal.status == .completed {
            Label("goals.row.done", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(FPStatusTint.positive)
        } else if let date = (try? store.goalsProjection(for: goal))?.completionDate {
            Label {
                Text(date, format: .dateTime.month(.abbreviated).year())
            } icon: {
                Image(systemName: "calendar")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("goals.row.projected.a11y"))
            .accessibilityValue(Text(date, format: .dateTime.month(.wide).year()))
        } else {
            Label("goals.row.noForecast", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview("Goals list") {
    GoalsView()
        .environment(GoalsPreviewFixtures.store())
        .environment(AppRouter())
}
#endif

#if DEBUG
#Preview("Goals list — empty") {
    GoalsView()
        .environment(GoalsPreviewFixtures.emptyStore())
        .environment(AppRouter())
}
#endif
