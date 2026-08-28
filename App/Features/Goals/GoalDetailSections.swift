import SwiftUI
import FinPlanCore

struct GoalsContributionCard: View {
    let goal: Goal
    let model: GoalsDetailModel

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                FPExplainedHeader(
                    titleKey: "goals.contribution.title",
                    infoTitleKey: "goals.contribution.title",
                    infoBodyKey: "goals.info.contribution"
                )

                HStack {
                    Label("goals.contribution.currentMonthly", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                    Spacer(minLength: FP.Spacing.sm)
                    if model.monthlyContribution.isPositive {
                        MoneyText(money: model.monthlyContribution, compact: true)
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("goals.contribution.none")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                switch model.required {
                case .notRequested:
                    EmptyView()
                case .amount(let amount):
                    Divider()
                    HStack {
                        Label("goals.contribution.requiredForDate", systemImage: "flag.checkered")
                            .font(.subheadline)
                        Spacer(minLength: FP.Spacing.sm)
                        MoneyText(money: amount, compact: true)
                            .font(.subheadline.weight(.semibold))
                    }
                case .dateUnreachable:
                    Divider()
                    Label("goals.contribution.desiredDateTooClose", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(FPStatusTint.attention)
                }

                if let shortfall = model.projection.shortfallAtHorizon {
                    Divider()
                    HStack {
                        Label("goals.contribution.horizonShortfall", systemImage: "chart.line.downtrend.xyaxis")
                            .font(.subheadline)
                            .foregroundStyle(FPStatusTint.attention)
                        Spacer(minLength: FP.Spacing.sm)
                        MoneyText(money: shortfall, compact: true)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FPStatusTint.attention)
                    }
                }
            }
        }
    }
}

struct GoalsMilestonesCard: View {
    let goal: Goal
    let model: GoalsDetailModel

    private var allMilestones: [ProjectionMilestone] {
        model.standardMilestones + model.roundMilestones
    }

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                FPExplainedHeader(
                    titleKey: "goals.milestones.title",
                    infoTitleKey: "goals.milestones.title",
                    infoBodyKey: "goals.info.milestones"
                )
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: FP.Spacing.sm)],
                    spacing: FP.Spacing.sm
                ) {
                    ForEach(Array(allMilestones.enumerated()), id: \.offset) { _, milestone in
                        GoalsMilestoneCell(milestone: milestone)
                    }
                }
            }
        }
    }
}

private struct GoalsMilestoneCell: View {
    let milestone: ProjectionMilestone

    private var isReachedNow: Bool { milestone.cycleIndex == 0 }

    var body: some View {
        VStack(spacing: FP.Spacing.xs) {
            if let bps = milestone.basisPoints {
                Text(verbatim: GoalsDisplay.percentText(basisPoints: bps))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            } else {
                MoneyText(money: milestone.threshold, compact: true)
                    .font(.subheadline.weight(.bold))
            }

            if isReachedNow {
                Label("goals.milestones.reached", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(FPStatusTint.positive)
            } else if let date = milestone.date {
                Text(date, format: .dateTime.month(.abbreviated).year(.twoDigits))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Label("goals.milestones.beyondHorizon", systemImage: "hourglass")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(FP.Spacing.sm)
        .background(
            isReachedNow ? FPStatusTint.positive.opacity(0.1) : Color(.tertiarySystemFill),
            in: RoundedRectangle(cornerRadius: FP.Radius.control)
        )
        .accessibilityElement(children: .combine)
    }
}

struct GoalsAllocationsCard: View {
    let goal: Goal
    let onAdd: () -> Void
    @Environment(FinanceStore.self) private var store

    private var allocationGroups: Result<[GoalsAllocationGroup], any Error> {
        Result { try store.goalsAllocationGroups(for: goal) }
    }

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                HStack(spacing: FP.Spacing.sm) {
                    Text("goals.allocation.title")
                        .font(.headline)
                    FPInfoButton(
                        titleKey: "goals.allocation.title",
                        bodyKey: "goals.info.allocations"
                    )
                    Spacer(minLength: 0)
                    Button(action: onAdd) {
                        Label("goals.allocation.add", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                switch allocationGroups {
                case .failure:
                    Label("goals.allocation.groupsUnavailable", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(FPStatusTint.attention)
                case .success(let groups) where groups.isEmpty:
                    Label("goals.allocation.empty", systemImage: "tray")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .success(let groups):
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                            HStack {
                                Label {
                                    if let account = group.account {
                                        Text(verbatim: account.name)
                                    } else {
                                        Text("goals.allocation.unknownAccount")
                                    }
                                } icon: {
                                    Image(systemName: "creditcard")
                                }
                                .font(.subheadline.weight(.semibold))
                                Spacer(minLength: FP.Spacing.sm)
                                MoneyText(money: group.total)
                                    .font(.subheadline.weight(.semibold))
                            }
                            ForEach(group.allocations) { allocation in
                                HStack {
                                    Text(allocation.date, format: .dateTime.day().month().year())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: FP.Spacing.sm)
                                    MoneyText(money: allocation.amount)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.leading, FP.Spacing.xl)
                            }
                        }
                        if group.id != groups.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct GoalsEventsCard: View {
    let goal: Goal
    @Environment(FinanceStore.self) private var store

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                Text("goals.events.title")
                    .font(.headline)
                let events = store.goalsUpcomingEvents(for: goal)
                if events.isEmpty {
                    Label("goals.events.empty", systemImage: "calendar.badge.minus")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(events) { event in
                        HStack(spacing: FP.Spacing.sm) {
                            Image(systemName: event.state == .overdue ? "exclamationmark.circle.fill" : "calendar.badge.clock")
                                .foregroundStyle(event.state == .overdue ? FPStatusTint.attention : Color.accentColor)
                                .accessibilityLabel(
                                    event.state == .overdue
                                        ? Text("goals.events.state.overdue")
                                        : Text("goals.events.state.expected")
                                )
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: event.title)
                                    .font(.subheadline)
                                Text(event.expectedDate, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: FP.Spacing.sm)
                            MoneyText(money: event.amount, compact: true)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
    }
}

struct GoalsHistoryCard: View {
    let goal: Goal
    @Environment(FinanceStore.self) private var store

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                Text("goals.history.title")
                    .font(.headline)
                let history = store.goalsContributionHistory(for: goal)
                if history.isEmpty {
                    Label("goals.history.empty", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(history) { record in
                        HStack(spacing: FP.Spacing.sm) {
                            Image(systemName: symbol(for: record.kind))
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(kindKey(for: record.kind))
                                    .font(.subheadline)
                                Text(record.date, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: FP.Spacing.sm)
                            MoneyText(money: record.amount, compact: true)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
    }

    private func symbol(for kind: TransactionKind) -> String {
        switch kind {
        case .income: return "arrow.down.circle"
        case .expense: return "arrow.up.circle"
        case .transfer: return "arrow.left.arrow.right.circle"
        case .currencyExchange: return "dollarsign.arrow.circlepath"
        case .adjustment: return "slider.horizontal.3"
        }
    }

    private func kindKey(for kind: TransactionKind) -> LocalizedStringKey {
        switch kind {
        case .income: return "goals.history.kind.income"
        case .expense: return "goals.history.kind.expense"
        case .transfer: return "goals.history.kind.transfer"
        case .currencyExchange: return "goals.history.kind.exchange"
        case .adjustment: return "goals.history.kind.adjustment"
        }
    }
}
