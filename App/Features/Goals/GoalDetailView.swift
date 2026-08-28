import SwiftUI
import Charts
import FinPlanCore

struct GoalsDetailModel {
    let funded: Money
    let progressBasisPoints: Int
    let projection: ProjectionResult
    let actualSeries: [GoalsSeriesPoint]
    let monthlyContribution: Money
    let required: GoalsRequiredContribution
    let standardMilestones: [ProjectionMilestone]
    let roundMilestones: [ProjectionMilestone]
    let roundThresholds: [Money]
}

struct GoalDetailView: View {
    let goalID: UUID

    @Environment(FinanceStore.self) private var store
    @State private var isPresentingEditor = false
    @State private var isPresentingAllocation = false
    @State private var isPresentingPurchase = false
    @State private var isConfirmingArchive = false
    @State private var actionError: String?

    private var goal: Goal? { store.goals.first { $0.id == goalID } }

    var body: some View {
        Group {
            if let goal {
                content(for: goal)
            } else {
                EmptyStateView(
                    systemImage: "target",
                    title: "goals.detail.missing.title",
                    message: "goals.detail.missing.message"
                )
            }
        }
        .alert(
            "error.title",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: actionError ?? "")
        }
    }

    @ViewBuilder
    private func content(for goal: Goal) -> some View {
        ScrollView {
            VStack(spacing: FP.Spacing.lg) {
                switch makeModel(for: goal) {
                case .success(let model):
                    GoalsHeroCard(goal: goal, model: model)
                    purchaseImpactButton
                    GoalsForecastChartCard(goal: goal, model: model)
                    GoalsContributionCard(goal: goal, model: model)
                    GoalsMilestonesCard(goal: goal, model: model)
                case .failure(let error):
                    GoalsHeroCard(goal: goal, model: nil)
                    FPCard {
                        Label {
                            VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                                Text("goals.detail.computeFailed")
                                    .font(.subheadline.weight(.semibold))
                                Text(verbatim: error.localizedDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(FPStatusTint.attention)
                        }
                    }
                }

                GoalsAllocationsCard(goal: goal) {
                    isPresentingAllocation = true
                }
                GoalsEventsCard(goal: goal)
                GoalsHistoryCard(goal: goal)
            }
            .padding(FP.Spacing.lg)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text(verbatim: goal.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                lifecycleMenu(for: goal)
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            GoalEditorView(existing: goal)
        }
        .sheet(isPresented: $isPresentingAllocation) {
            GoalAllocationSheet(goal: goal)
        }
        .sheet(isPresented: $isPresentingPurchase) {
            GoalPurchaseImpactSheet(goal: goal)
        }
        .confirmationDialog(
            "goals.action.archive.confirmTitle",
            isPresented: $isConfirmingArchive,
            titleVisibility: .visible
        ) {
            Button("goals.action.archive", role: .destructive) {
                setStatus(.archived, for: goal)
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("goals.action.archive.confirmMessage")
        }
    }

    private var purchaseImpactButton: some View {
        Button {
            isPresentingPurchase = true
        } label: {
            Label("goals.canIBuy", systemImage: "cart.badge.questionmark")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func lifecycleMenu(for goal: Goal) -> some View {
        Menu {
            Button {
                isPresentingEditor = true
            } label: {
                Label("goals.action.edit", systemImage: "pencil")
            }
            if goal.status == .active {
                Button {
                    setStatus(.paused, for: goal)
                } label: {
                    Label("goals.action.pause", systemImage: "pause.circle")
                }
            }
            if goal.status == .paused || goal.status == .planned {
                Button {
                    setStatus(.active, for: goal)
                } label: {
                    Label("goals.action.activate", systemImage: "play.circle")
                }
            }
            if goal.status != .completed && goal.status != .archived {
                Button {
                    setStatus(.completed, for: goal)
                } label: {
                    Label("goals.action.complete", systemImage: "checkmark.circle")
                }
            }
            if goal.status != .archived {
                Button(role: .destructive) {
                    isConfirmingArchive = true
                } label: {
                    Label("goals.action.archive", systemImage: "archivebox")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(Text("goals.action.menu.a11y"))
    }

    private func setStatus(_ status: GoalStatus, for goal: Goal) {
        do {
            try store.goalsSetStatus(status, for: goal)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func makeModel(for goal: Goal) -> Result<GoalsDetailModel, Error> {
        do {
            let funded = try store.goalsFunded(for: goal)
            let projection = try store.goalsProjection(for: goal)
            let roundThresholds = store.goalsRoundThresholds(for: goal)
            return .success(
                GoalsDetailModel(
                    funded: funded,
                    progressBasisPoints: store.goalsProgressBasisPoints(funded: funded, target: goal.targetAmount),
                    projection: projection,
                    actualSeries: try store.goalsActualSeries(for: goal),
                    monthlyContribution: try store.goalsMonthlyContribution(for: goal),
                    required: try store.goalsRequiredContribution(for: goal),
                    standardMilestones: projection.standardPercentMilestones(),
                    roundMilestones: try projection.milestoneDates(for: roundThresholds),
                    roundThresholds: roundThresholds
                )
            )
        } catch {
            return .failure(error)
        }
    }
}

private struct GoalsHeroCard: View {
    let goal: Goal
    let model: GoalsDetailModel?
    @Environment(FinanceStore.self) private var store

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                HStack(spacing: FP.Spacing.md) {
                    Image(systemName: goal.symbolName)
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                        Text(verbatim: goal.title)
                            .font(.title3.weight(.semibold))
                        HStack(spacing: FP.Spacing.sm) {
                            GoalsStatusBadge(status: goal.status)
                            GoalsPriorityBadge(priority: goal.priority)
                            if goal.isEmergencyFund {
                                GoalsEmergencyBadge()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                if let model {
                    HStack(alignment: .firstTextBaseline, spacing: FP.Spacing.sm) {
                        MoneyText(money: model.funded, compact: true)
                            .font(.title.weight(.bold))
                        Text("goals.row.ofTarget")
                            .foregroundStyle(.secondary)
                        MoneyText(money: goal.targetAmount, compact: true)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: GoalsDisplay.progressFraction(basisPoints: model.progressBasisPoints))
                        .tint(goal.status == .completed ? FPStatusTint.positive : Color.accentColor)
                        .accessibilityLabel(Text("goals.row.progress.a11y"))
                        .accessibilityValue(Text(verbatim: GoalsDisplay.percentText(basisPoints: model.progressBasisPoints)))

                    HStack {
                        Text(verbatim: GoalsDisplay.percentText(basisPoints: model.progressBasisPoints))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Spacer(minLength: 0)
                        completionLabel(model: model)
                    }

                    if let desired = goal.desiredCompletionDate {
                        Label {
                            Text("goals.detail.desiredDate")
                            Text(desired, format: .dateTime.day().month().year())
                        } icon: {
                            Image(systemName: "flag.checkered")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func completionLabel(model: GoalsDetailModel) -> some View {
        if let date = model.projection.completionDate {
            Label {
                Text("goals.detail.projectedCompletion")
                Text(date, format: .dateTime.month(.abbreviated).year())
            } icon: {
                Image(systemName: "calendar")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Label("goals.detail.notReachedInHorizon", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(FPStatusTint.attention)
        }
    }
}

private struct GoalsForecastChartCard: View {
    let goal: Goal
    let model: GoalsDetailModel
    @Environment(FinanceStore.self) private var store

    private var actualLabel: String { String(localized: "goals.chart.actual") }
    private var forecastLabel: String { String(localized: "goals.chart.forecast") }

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                Text("goals.chart.title")
                    .font(.headline)
                if store.hideBalances {
                    Label("goals.chart.hidden", systemImage: "eye.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    chart
                }
            }
        }
    }

    private var chart: some View {
        let xDomain = FPProjectionDomain.clampedDomain(
            for: model.actualSeries.map(\.date) + model.projection.points.map(\.date)
        )
        return Chart {
            ForEach(model.actualSeries) { point in
                LineMark(
                    x: .value("goals.chart.axis.date", point.date),
                    y: .value("goals.chart.axis.amount", plotValue(point.balance)),
                    series: .value("goals.chart.series", "actual")
                )
                .foregroundStyle(by: .value("goals.chart.legend", actualLabel))
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            ForEach(model.projection.points, id: \.cycleIndex) { point in
                LineMark(
                    x: .value("goals.chart.axis.date", point.date),
                    y: .value("goals.chart.axis.amount", plotValue(point.balance)),
                    series: .value("goals.chart.series", "forecast")
                )
                .foregroundStyle(by: .value("goals.chart.legend", forecastLabel))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
            ForEach(model.roundThresholds, id: \.amountMinor) { threshold in
                RuleMark(y: .value("goals.chart.axis.amount", plotValue(threshold)))
                    .foregroundStyle(Color.secondary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }
            RuleMark(y: .value("goals.chart.axis.amount", plotValue(goal.targetAmount)))
                .foregroundStyle(FPStatusTint.positive.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .bottom, alignment: .trailing, spacing: 2) {
                    FPTargetAnnotationLabel(titleKey: "goals.chart.targetLine")
                }
        }
        .chartForegroundStyleScale([
            actualLabel: Color.blue,
            forecastLabel: Color.teal,
        ])
        .chartXScale(domain: xDomain)
        .fpProjectionXAxis(spansYears: FPProjectionDomain.spansYears(xDomain))
        .fpMoneyYAxis(currencyCode: goal.targetAmount.currency.code, hidden: false)
        .chartLegend(position: .bottom, spacing: FP.Spacing.sm)
        .frame(height: 220)
        .accessibilityElement()
        .accessibilityLabel(Text("goals.chart.a11y"))
        .accessibilityValue(Text(verbatim: accessibilitySummary))
    }

    private func plotValue(_ money: Money) -> Double {
        Double(money.amountMinor) / Double(money.currency.minorUnitsPerMajor)
    }

    private var accessibilitySummary: String {
        let funded = model.funded.formatted()
        let target = goal.targetAmount.formatted()
        if let date = model.projection.completionDate {
            let dateText = date.formatted(date: .abbreviated, time: .omitted)
            return String(localized: "goals.chart.a11y.value \(funded) \(target) \(dateText)")
        }
        return String(localized: "goals.chart.a11y.valueNoCompletion \(funded) \(target)")
    }
}

#if DEBUG
#Preview("Goal detail") {
    let store = GoalsPreviewFixtures.store()
    return NavigationStack {
        GoalDetailView(goalID: GoalsPreviewFixtures.apartmentGoalID)
    }
    .environment(store)
}
#endif

#if DEBUG
#Preview("Goal detail — emergency fund") {
    let store = GoalsPreviewFixtures.store()
    return NavigationStack {
        GoalDetailView(goalID: GoalsPreviewFixtures.emergencyGoalID)
    }
    .environment(store)
}
#endif
