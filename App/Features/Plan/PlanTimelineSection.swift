import SwiftUI
import FinPlanCore

struct PlanTimelineSection: View {
    @Environment(FinanceStore.self) private var store
    @State private var templateToEdit: RecurringTemplate?
    @State private var eventToEdit: ExpectedEvent?

    private static let pastLimit = 4
    private static let futureLimit = 10

    var body: some View {
        let now = Date.now
        let built = buildItems(now: now)
        if built.items.count <= 1 && built.milestoneError == nil {
            EmptyStateView(
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                title: "plan.timeline.empty.title",
                message: "plan.timeline.empty.message"
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let error = built.milestoneError {
                        PlanComputationErrorCard(error: error)
                            .padding(.bottom, FP.Spacing.lg)
                    }
                    ForEach(Array(built.items.enumerated()), id: \.element.id) { index, item in
                        PlanTimelineRow(
                            item: item,
                            isFirst: index == 0,
                            isLast: index == built.items.count - 1,
                            onEdit: editAction(for: item)
                        )
                    }
                }
                .padding(FP.Spacing.lg)
            }
            .background(Color(.systemGroupedBackground))
            .sheet(item: $templateToEdit) { template in
                RecurringTemplateEditorView(template: template)
            }
            .sheet(item: $eventToEdit) { event in
                ExpectedEventEditorView(event: event)
            }
        }
    }

    private func editAction(for item: PlanTimelineItem) -> (() -> Void)? {
        if let id = item.templateID,
           let template = store.recurringTemplates.first(where: { $0.id == id }) {
            return { templateToEdit = template }
        }
        if let id = item.eventID,
           let event = store.expectedEvents.first(where: { $0.id == id }) {
            return { eventToEdit = event }
        }
        return nil
    }

    private func buildItems(now: Date) -> (items: [PlanTimelineItem], milestoneError: (any Error)?) {
        var past: [PlanTimelineItem] = pastItems(now: now)
        let assembled = futureItems(now: now)
        var future = assembled.items
        future.sort { $0.date < $1.date }
        if future.count > Self.futureLimit {
            future = Array(future.prefix(Self.futureLimit))
        }
        past.append(PlanTimelineItem(
            id: "today",
            date: now,
            titleKey: "plan.timeline.today",
            title: nil,
            amount: nil,
            sign: nil,
            style: .today,
            iconName: "record.circle"
        ))
        return (past + future, assembled.milestoneError)
    }

    private func pastItems(now: Date) -> [PlanTimelineItem] {
        store.transactions
            .filter { $0.status == .completed && $0.date <= now }
            .prefix(Self.pastLimit)
            .reversed()
            .map { record in
                PlanTimelineItem(
                    id: "past-\(record.id.uuidString)",
                    date: record.date,
                    titleKey: nil,
                    title: record.note,
                    amount: record.amount,
                    sign: record.kind == .income ? "+" : (record.kind == .expense ? "−" : nil),
                    style: .actual,
                    iconName: record.kind == .income ? "arrow.down.circle.fill"
                        : (record.kind == .expense ? "arrow.up.circle.fill" : "arrow.left.arrow.right.circle.fill")
                )
            }
    }

    private func futureItems(now: Date) -> (items: [PlanTimelineItem], milestoneError: (any Error)?) {
        var items: [PlanTimelineItem] = []
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .year, value: 1, to: now) ?? now
        let interval = DateInterval(start: now, end: horizon)
        let scheduler = RecurringScheduler(calendar: calendar)

        for template in store.recurringTemplates where template.isActive {
            if let next = scheduler.occurrences(of: template, in: interval).first {
                items.append(PlanTimelineItem(
                    id: "next-\(template.id.uuidString)",
                    date: next,
                    titleKey: nil,
                    title: template.name,
                    amount: template.amount,
                    sign: template.kind == .income ? "+" : (template.kind == .expense ? "−" : nil),
                    style: .projected,
                    iconName: "arrow.triangle.2.circlepath.circle",
                    templateID: template.id
                ))
            }
        }

        let upcoming = RecurringScheduler.expectedEventStatus(events: store.expectedEvents, now: now).upcoming
        for event in upcoming where interval.contains(event.expectedDate) {
            items.append(PlanTimelineItem(
                id: "expected-\(event.id.uuidString)",
                date: event.expectedDate,
                titleKey: nil,
                title: event.title,
                amount: event.amount,
                sign: "+",
                style: .projected,
                iconName: "questionmark.circle.dashed",
                eventID: event.id
            ))
        }

        var milestoneError: (any Error)?
        do {
            items.append(contentsOf: try milestoneItems(now: now))
        } catch {
            milestoneError = error
        }
        return (items, milestoneError)
    }

    private func milestoneItems(now: Date) throws -> [PlanTimelineItem] {
        guard let plan = try store.planBasePlan(now: now) else { return [] }
        let input = try ScenarioEngine.apply(ScenarioOverrides(), to: plan)
        let result = try ProjectionEngine.project(input)
        var items: [PlanTimelineItem] = []
        for milestone in result.standardPercentMilestones() {
            guard let date = milestone.date, date > now else { continue }
            let isCompletion = milestone.basisPoints == 10_000
            items.append(PlanTimelineItem(
                id: "milestone-\(milestone.basisPoints ?? 0)",
                date: date,
                titleKey: isCompletion ? "plan.timeline.goalCompletion" : nil,
                title: isCompletion ? nil : milestoneTitle(basisPoints: milestone.basisPoints),
                amount: milestone.threshold,
                sign: nil,
                style: .projected,
                iconName: isCompletion ? "flag.checkered.circle" : "flag.circle"
            ))
        }
        return items
    }

    private func milestoneTitle(basisPoints: Int?) -> String {
        let percent = (basisPoints ?? 0) / 100
        return String(
            format: String(localized: "plan.timeline.milestoneFormat"),
            percent.formatted(.percent) as CVarArg
        )
    }
}

struct PlanTimelineItem: Identifiable {
    enum Style {
        case actual, today, projected
    }

    let id: String
    let date: Date
    let titleKey: LocalizedStringKey?
    let title: String?
    let amount: Money?
    let sign: String?
    let style: Style
    let iconName: String
    var templateID: UUID? = nil
    var eventID: UUID? = nil
}

struct PlanTimelineRow: View {
    let item: PlanTimelineItem
    let isFirst: Bool
    let isLast: Bool
    var onEdit: (() -> Void)? = nil

    var body: some View {
        if let onEdit {
            Button(action: onEdit) {
                rowBody
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("a11y.upcoming.editHint"))
        } else {
            rowBody
        }
    }

    private var rowBody: some View {
        HStack(alignment: .top, spacing: FP.Spacing.md) {
            Image(systemName: item.iconName)
                .font(.body)
                .foregroundStyle(markerTint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 28)
                .accessibilityHidden(true)
            content
                .padding(.bottom, isLast ? 0 : FP.Spacing.xl)
            if onEdit != nil {
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .background(alignment: .topLeading) {
            if !isLast {
                connector
                    .padding(.top, 26)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var connector: some View {
        if item.style == .projected {
            PlanDashedLine()
                .stroke(Color(.separator), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .frame(width: 2)
        } else {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(.separator))
                .frame(width: 2)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: FP.Spacing.xs) {
            HStack(spacing: FP.Spacing.sm) {
                titleView
                    .font(item.style == .today ? .headline : .body)
                if item.style == .projected {
                    Text("plan.timeline.projectedBadge")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, FP.Spacing.sm)
                        .padding(.vertical, 2)
                        .overlay(
                            Capsule().strokeBorder(
                                Color.secondary,
                                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                            )
                        )
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: FP.Spacing.sm) {
                Text(item.date, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let amount = item.amount {
                    HStack(spacing: 2) {
                        if let sign = item.sign {
                            Text(verbatim: sign)
                        }
                        MoneyText(money: amount)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.style == .projected ? Color.secondary : Color.primary)
                }
            }
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if let key = item.titleKey {
            Text(key)
        } else if let title = item.title, !title.isEmpty {
            Text(verbatim: title)
        } else {
            Text("plan.timeline.untitled")
        }
    }

    private var markerTint: Color {
        switch item.style {
        case .actual: return .primary
        case .today: return .accentColor
        case .projected: return .secondary
        }
    }

    private var accessibilitySummary: String {
        let state: String
        switch item.style {
        case .actual: state = String(localized: "plan.a11y.timeline.actual")
        case .today: state = String(localized: "plan.a11y.timeline.today")
        case .projected: state = String(localized: "plan.a11y.timeline.projected")
        }
        let name = item.title ?? ""
        let date = item.date.formatted(date: .abbreviated, time: .omitted)
        return "\(state), \(name), \(date)"
    }
}

struct PlanDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

#if DEBUG
#Preview("Timeline") {
    NavigationStack { PlanTimelineSection() }
        .environment(PlanPreviewFactory.makeStore())
}
#endif
