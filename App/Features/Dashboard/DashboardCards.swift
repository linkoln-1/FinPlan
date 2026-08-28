import SwiftUI
import FinPlanCore

struct DashboardHeroCard: View {
    let data: DashboardHeroData

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                HStack(spacing: FP.Spacing.sm) {
                    Image(systemName: data.goal.symbolName)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text(verbatim: data.goal.title)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer(minLength: FP.Spacing.sm)
                    if let status = data.planStatus {
                        DashboardPlanChip(status: status)
                    }
                }

                MoneyText(money: data.funded, compact: true)
                    .font(.system(.largeTitle, design: .rounded).bold())

                ProgressView(value: data.progressFraction)
                    .tint(Color.accentColor)
                    .accessibilityLabel(String(localized: "a11y.dashboard.goalProgress"))
                    .accessibilityValue(Text(verbatim: GoalsDisplay.percentText(basisPoints: data.percentBasisPoints)))

                HStack {
                    Text(verbatim: GoalsDisplay.percentText(basisPoints: data.percentBasisPoints))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    HStack(spacing: FP.Spacing.xs) {
                        Text("dashboard.hero.target")
                        MoneyText(money: data.goal.targetAmount, compact: true)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Divider()

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                        Text("dashboard.hero.remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        MoneyText(money: data.remaining, compact: true)
                            .font(.callout.weight(.semibold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: FP.Spacing.xs) {
                        Text("dashboard.hero.projected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let date = data.completionDate, let cycles = data.completionCycles {
                            HStack(spacing: FP.Spacing.xs) {
                                Text(date, format: .dateTime.month(.abbreviated).year())
                                Text("dashboard.hero.cycles \(cycles)")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout.weight(.semibold))
                        } else {
                            Label("dashboard.hero.beyondHorizon", systemImage: "exclamationmark.circle")
                                .font(.callout)
                                .foregroundStyle(FPStatusTint.attention)
                        }
                    }
                }
            }
        }
    }
}

struct DashboardPlanChip: View {
    let status: PlanStatus

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, FP.Spacing.sm)
            .padding(.vertical, FP.Spacing.xs)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
            .accessibilityLabel(accessibilityText)
    }

    private var days: Int { abs(status.timeImpactDays) }

    private var title: LocalizedStringKey {
        switch status.standing {
        case .ahead: "dashboard.plan.ahead \(days)"
        case .behind: "dashboard.plan.behind \(days)"
        case .onTrack: "dashboard.plan.onTrack"
        }
    }

    private var symbolName: String {
        switch status.standing {
        case .ahead: "arrow.up.right"
        case .behind: "arrow.down.right"
        case .onTrack: "checkmark.circle"
        }
    }

    private var tint: Color {
        switch status.standing {
        case .ahead: FPStatusTint.positive
        case .behind: FPStatusTint.negative
        case .onTrack: FPStatusTint.neutral
        }
    }

    private var accessibilityText: String {
        switch status.standing {
        case .ahead: String(localized: "a11y.dashboard.planAhead \(days)")
        case .behind: String(localized: "a11y.dashboard.planBehind \(days)")
        case .onTrack: String(localized: "a11y.dashboard.planOnTrack")
        }
    }
}

struct DashboardSafeToSpendCard: View {
    let result: SafeToSpendResult
    var details: DashboardSafeToSpendDetails?
    @State private var isBreakdownExpanded = false

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                FPExplainedHeader(
                    titleKey: "dashboard.sts.title",
                    infoTitleKey: "dashboard.sts.title",
                    infoBodyKey: "dashboard.info.sts"
                )

                MoneyText(money: result.available, compact: true)
                    .font(.system(.title, design: .rounded).bold())
                    .foregroundStyle(result.shortfall != nil ? FPStatusTint.attention : Color.primary)

                if let shortfall = result.shortfall {
                    HStack(spacing: FP.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)
                        Text("dashboard.shortfall")
                        MoneyText(money: shortfall, compact: true)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(FPStatusTint.negative)
                    .accessibilityElement(children: .combine)
                }

                DisclosureGroup(isExpanded: $isBreakdownExpanded) {
                    VStack(spacing: FP.Spacing.sm) {
                        ForEach(result.breakdown.filter { !$0.amount.isZero || $0.label == .liquidBalance }, id: \.label) { item in
                            HStack {
                                Text(item.label.dashboardRowTitleKey)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                MoneyText(money: item.amount, compact: true)
                                    .foregroundStyle(item.amount.isNegative ? Color.secondary : Color.primary)
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)

                            if item.label == .goalReserved, let reserves = details?.goalReserves, !reserves.isEmpty {
                                ForEach(reserves) { reserve in
                                    HStack {
                                        Label(reserve.title, systemImage: "target")
                                            .foregroundStyle(.tertiary)
                                        Spacer()
                                        MoneyText(money: reserve.amount, compact: true)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .font(.footnote)
                                    .padding(.leading, FP.Spacing.lg)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                            if item.label == .upcomingMandatory, let payments = details?.upcomingPayments, !payments.isEmpty {
                                ForEach(payments) { payment in
                                    HStack {
                                        Text(verbatim: payment.name)
                                            .foregroundStyle(.tertiary)
                                        Text(payment.date, format: .dateTime.day().month(.abbreviated))
                                            .foregroundStyle(.tertiary)
                                        Spacer()
                                        MoneyText(money: payment.amount, compact: true)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .font(.footnote)
                                    .padding(.leading, FP.Spacing.lg)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }

                        if !result.available.isPositive,
                           let reserves = details?.goalReserves, !reserves.isEmpty {
                            Label("dashboard.sts.hint.allReserved", systemImage: "lightbulb")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, FP.Spacing.xs)
                        }
                    }
                    .padding(.top, FP.Spacing.sm)
                } label: {
                    Text("dashboard.sts.why")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct DashboardMonthCard: View {
    let data: DashboardMonthData

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                FPExplainedHeader(
                    titleKey: "dashboard.month.title",
                    infoTitleKey: "dashboard.month.title",
                    infoBodyKey: "dashboard.info.month"
                )

                HStack(alignment: .top, spacing: FP.Spacing.md) {
                    DashboardMonthStat(titleKey: "dashboard.month.income", amount: data.summary.income, tint: FPStatusTint.positive)
                    Divider()
                    DashboardMonthStat(titleKey: "dashboard.month.expenses", amount: data.summary.expenses, tint: FPStatusTint.negative)
                    Divider()
                    DashboardMonthStat(titleKey: "dashboard.month.saved", amount: data.summary.savingsAllocated, tint: Color.accentColor)
                }

                if let rate = data.savingsRatePercent {
                    Label {
                        Text("dashboard.month.savingsRate \(rate)")
                    } icon: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if data.plannedSavings.isPositive, let fraction = data.planFraction {
                    VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                        HStack(spacing: FP.Spacing.xs) {
                            Text("dashboard.month.planProgress")
                            Spacer()
                            MoneyText(money: data.summary.savingsAllocated, compact: true)
                            Text(verbatim: "/")
                                .foregroundStyle(.tertiary)
                            MoneyText(money: data.plannedSavings, compact: true)
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        ProgressView(value: fraction)
                            .tint(fraction >= 1 ? FPStatusTint.positive : Color.accentColor)
                            .accessibilityLabel(String(localized: "a11y.dashboard.monthPlan"))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct DashboardMonthStat: View {
    let titleKey: LocalizedStringKey
    let amount: Money
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: FP.Spacing.xs) {
            Text(titleKey)
                .font(.caption)
                .foregroundStyle(.secondary)
            MoneyText(money: amount, compact: true)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct DashboardUpcomingCard: View {
    let items: [DashboardUpcomingItem]
    @Environment(FinanceStore.self) private var store
    @State private var templateToEdit: RecurringTemplate?
    @State private var eventToEdit: ExpectedEvent?

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                Text("dashboard.upcoming.title")
                    .font(.headline)
                if items.isEmpty {
                    EmptyStateView(
                        systemImage: "calendar",
                        title: "dashboard.upcoming.emptyTitle",
                        message: "dashboard.upcoming.emptyMessage"
                    )
                } else {
                    VStack(spacing: FP.Spacing.md) {
                        ForEach(items) { item in
                            Button {
                                edit(item)
                            } label: {
                                DashboardUpcomingRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("a11y.upcoming.editHint"))
                        }
                    }
                }
            }
        }
        .sheet(item: $templateToEdit) { template in
            RecurringTemplateEditorView(template: template)
        }
        .sheet(item: $eventToEdit) { event in
            ExpectedEventEditorView(event: event)
        }
    }

    private func edit(_ item: DashboardUpcomingItem) {
        if let id = item.templateID,
           let template = store.recurringTemplates.first(where: { $0.id == id }) {
            templateToEdit = template
        } else if let id = item.eventID,
                  let event = store.expectedEvents.first(where: { $0.id == id }) {
            eventToEdit = event
        }
    }
}

private struct DashboardUpcomingRow: View {
    let item: DashboardUpcomingItem

    var body: some View {
        HStack(spacing: FP.Spacing.md) {
            Image(systemName: item.symbolName)
                .font(.title3)
                .foregroundStyle(item.isInflow ? FPStatusTint.positive : FPStatusTint.neutral)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                Text(verbatim: item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(item.date, format: .dateTime.weekday(.abbreviated).day().month())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: FP.Spacing.sm)
            MoneyText(money: item.amount, compact: true)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(item.isInflow ? FPStatusTint.positive : Color.primary)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct DashboardInsightBanner: View {
    let insight: Insight

    var body: some View {
        FPCard {
            HStack(alignment: .top, spacing: FP.Spacing.md) {
                Image(systemName: symbolName)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                    Text(LocalizedStringKey(insight.messageKey))
                        .font(.subheadline)
                    if let value = insight.value {
                        MoneyText(money: value, compact: true)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch insight.severity {
        case .info: FPStatusTint.positive
        case .attention: FPStatusTint.attention
        case .warning: FPStatusTint.negative
        }
    }

    private var symbolName: String {
        switch insight.severity {
        case .info: "lightbulb"
        case .attention: "exclamationmark.circle"
        case .warning: "exclamationmark.triangle.fill"
        }
    }
}

struct DashboardFirstGoalCard: View {
    @Environment(AppRouter.self) private var router

    private static let goalsTabIndex = 1

    var body: some View {
        FPCard {
            VStack(spacing: FP.Spacing.md) {
                EmptyStateView(
                    systemImage: "target",
                    title: "dashboard.empty.title",
                    message: "dashboard.empty.message"
                )
                Button("dashboard.empty.cta", systemImage: "plus.circle.fill") {
                    router.selectedTab = Self.goalsTabIndex
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

extension SafeToSpendComponent {
    fileprivate var dashboardRowTitleKey: LocalizedStringKey {
        switch self {
        case .liquidBalance: "dashboard.sts.liquidBalance"
        case .goalReserved: "dashboard.sts.goalReserved"
        case .emergencyReserve: "dashboard.sts.emergencyReserve"
        case .upcomingMandatory: "dashboard.sts.upcomingMandatory"
        case .minimumBuffer: "dashboard.sts.minimumBuffer"
        }
    }
}
