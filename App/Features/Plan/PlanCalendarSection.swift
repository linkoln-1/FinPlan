import SwiftUI
import FinPlanCore

struct PlanCalendarSection: View {
    @Environment(FinanceStore.self) private var store
    @State private var eventToReschedule: ExpectedEvent?
    @State private var eventToCancel: ExpectedEvent?
    @State private var templateToEdit: RecurringTemplate?
    @State private var eventToEdit: ExpectedEvent?
    @State private var errorMessage: String?

    private static let horizonMonths = 3

    var body: some View {
        let now = Date.now
        let partition = RecurringScheduler.expectedEventStatus(events: store.expectedEvents, now: now)
        let months = agendaMonths(now: now, upcoming: partition.upcoming)

        if partition.needsAttention.isEmpty && months.allSatisfy(\.entries.isEmpty) {
            EmptyStateView(
                systemImage: "calendar.badge.clock",
                title: "plan.calendar.empty.title",
                message: "plan.calendar.empty.message"
            )
        } else {
            List {
                if !partition.needsAttention.isEmpty {
                    Section {
                        ForEach(partition.needsAttention) { event in
                            overdueRow(event)
                        }
                    } header: {
                        Label("plan.calendar.attention", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(FPStatusTint.attention)
                    }
                }
                ForEach(months) { month in
                    if !month.entries.isEmpty {
                        Section {
                            ForEach(month.entries) { entry in
                                Button {
                                    edit(entry)
                                } label: {
                                    PlanCalendarRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(Text("a11y.upcoming.editHint"))
                            }
                        } header: {
                            Text(month.start, format: .dateTime.month(.wide).year())
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .sheet(item: $eventToReschedule) { event in
                PlanRescheduleSheet(event: event) { newDate in
                    perform { try store.planRescheduleExpectedEvent(event, to: newDate) }
                }
            }
            .sheet(item: $templateToEdit) { template in
                RecurringTemplateEditorView(template: template)
            }
            .sheet(item: $eventToEdit) { event in
                ExpectedEventEditorView(event: event)
            }
            .confirmationDialog(
                "plan.calendar.cancelConfirm.title",
                isPresented: Binding(
                    get: { eventToCancel != nil },
                    set: { if !$0 { eventToCancel = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("plan.calendar.action.cancelEvent", role: .destructive) {
                    if let event = eventToCancel {
                        perform { try store.planCancelExpectedEvent(event) }
                    }
                    eventToCancel = nil
                }
                Button("plan.common.keep", role: .cancel) { eventToCancel = nil }
            }
            .alert(
                "plan.alert.actionFailed.title",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("plan.common.ok", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func overdueRow(_ event: ExpectedEvent) -> some View {
        HStack(spacing: FP.Spacing.md) {
            Button {
                eventToEdit = event
            } label: {
                HStack(spacing: FP.Spacing.md) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(FPStatusTint.attention)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                        Text(verbatim: event.title)
                            .font(.body)
                        HStack(spacing: FP.Spacing.xs) {
                            Text("plan.calendar.overdueBadge")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, FP.Spacing.sm)
                                .padding(.vertical, 2)
                                .background(FPStatusTint.attention.opacity(0.18), in: Capsule())
                                .foregroundStyle(FPStatusTint.attention)
                            Text(event.expectedDate, format: .dateTime.day().month())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        Text(verbatim: "+")
                        MoneyText(money: event.amount)
                    }
                    .font(.callout.weight(.semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("a11y.upcoming.editHint"))
            Menu {
                Button {
                    eventToEdit = event
                } label: {
                    Label("plan.calendar.action.edit", systemImage: "pencil")
                }
                Button {
                    perform { try store.planMarkExpectedEventReceived(event) }
                } label: {
                    Label("plan.calendar.action.markReceived", systemImage: "checkmark.circle")
                }
                Button {
                    eventToReschedule = event
                } label: {
                    Label("plan.calendar.action.updateDate", systemImage: "calendar.badge.clock")
                }
                Button(role: .destructive) {
                    eventToCancel = event
                } label: {
                    Label("plan.calendar.action.cancelEvent", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .accessibilityLabel(String(localized: "plan.a11y.overdueActions"))
        }
        .padding(.vertical, FP.Spacing.xs)
    }

    private func edit(_ entry: PlanCalendarEntry) {
        if let id = entry.templateID,
           let template = store.recurringTemplates.first(where: { $0.id == id }) {
            templateToEdit = template
        } else if let id = entry.eventID,
                  let event = store.expectedEvents.first(where: { $0.id == id }) {
            eventToEdit = event
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func agendaMonths(now: Date, upcoming: [ExpectedEvent]) -> [PlanAgendaMonth] {
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .month, value: Self.horizonMonths, to: now) else {
            return []
        }
        let interval = DateInterval(start: now, end: end)
        let scheduler = RecurringScheduler(calendar: calendar)
        let planned = scheduler
            .plannedRecords(for: store.recurringTemplates, in: interval)
            .map(PlanCalendarEntry.planned)
        let expected = upcoming
            .filter { interval.contains($0.expectedDate) }
            .map(PlanCalendarEntry.expected)

        let all = (planned + expected).sorted { $0.date < $1.date }
        let grouped = Dictionary(grouping: all) { entry in
            calendar.dateInterval(of: .month, for: entry.date)?.start ?? entry.date
        }
        return grouped
            .map { PlanAgendaMonth(start: $0.key, entries: $0.value) }
            .sorted { $0.start < $1.start }
    }
}

private struct PlanAgendaMonth: Identifiable {
    let start: Date
    let entries: [PlanCalendarEntry]
    var id: Date { start }
}

struct PlanCalendarEntry: Identifiable {
    enum Kind {
        case planned(TransactionKind)
        case expected
    }

    let id: String
    let date: Date
    let title: String?
    let amount: Money
    let kind: Kind
    var templateID: UUID? = nil
    var eventID: UUID? = nil

    static func planned(_ record: TransactionRecord) -> PlanCalendarEntry {
        PlanCalendarEntry(
            id: "planned-\(record.recurringTemplateID?.uuidString ?? record.id.uuidString)-\(record.date.timeIntervalSinceReferenceDate)",
            date: record.date,
            title: record.note,
            amount: record.amount,
            kind: .planned(record.kind),
            templateID: record.recurringTemplateID
        )
    }

    static func expected(_ event: ExpectedEvent) -> PlanCalendarEntry {
        PlanCalendarEntry(
            id: "expected-\(event.id.uuidString)",
            date: event.expectedDate,
            title: event.title,
            amount: event.amount,
            kind: .expected,
            eventID: event.id
        )
    }
}

struct PlanCalendarRow: View {
    let entry: PlanCalendarEntry

    var body: some View {
        HStack(spacing: FP.Spacing.md) {
            Image(systemName: iconName)
                .foregroundStyle(iconTint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                if let title = entry.title, !title.isEmpty {
                    Text(verbatim: title)
                        .font(.body)
                } else {
                    Text(fallbackTitleKey)
                        .font(.body)
                }
                HStack(spacing: FP.Spacing.xs) {
                    badge
                    Text(entry.date, format: .dateTime.day().month())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 2) {
                if let sign {
                    Text(verbatim: sign)
                }
                MoneyText(money: entry.amount)
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(amountTint)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, FP.Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badge: some View {
        switch entry.kind {
        case .planned:
            Text("plan.calendar.plannedBadge")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, FP.Spacing.sm)
                .padding(.vertical, 2)
                .background(Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(.secondary)
        case .expected:
            Text("plan.calendar.expectedBadge")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, FP.Spacing.sm)
                .padding(.vertical, 2)
                .overlay(
                    Capsule().strokeBorder(
                        FPStatusTint.attention,
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
                )
                .foregroundStyle(FPStatusTint.attention)
        }
    }

    private var fallbackTitleKey: LocalizedStringKey {
        switch entry.kind {
        case .planned(.income): return "plan.calendar.kind.income"
        case .planned(.expense): return "plan.calendar.kind.expense"
        case .planned(.transfer): return "plan.calendar.kind.transfer"
        case .planned(.currencyExchange): return "plan.calendar.kind.exchange"
        case .planned(.adjustment): return "plan.calendar.kind.adjustment"
        case .expected: return "plan.calendar.kind.expected"
        }
    }

    private var iconName: String {
        switch entry.kind {
        case .planned(.income): return "arrow.down.circle"
        case .planned(.expense): return "arrow.up.circle"
        case .planned(.transfer): return "arrow.left.arrow.right.circle"
        case .planned(.currencyExchange): return "dollarsign.arrow.circlepath"
        case .planned(.adjustment): return "slider.horizontal.3"
        case .expected: return "questionmark.circle.dashed"
        }
    }

    private var iconTint: Color {
        switch entry.kind {
        case .planned(.income): return FPStatusTint.positive
        case .planned(.expense): return FPStatusTint.negative
        case .planned(.transfer), .planned(.currencyExchange), .planned(.adjustment):
            return FPStatusTint.neutral
        case .expected: return FPStatusTint.attention
        }
    }

    private var sign: String? {
        switch entry.kind {
        case .planned(.income), .expected: return "+"
        case .planned(.expense): return "−"
        case .planned(.transfer), .planned(.currencyExchange), .planned(.adjustment): return nil
        }
    }

    private var amountTint: Color {
        switch entry.kind {
        case .planned(.income): return FPStatusTint.positive
        case .planned(.expense): return FPStatusTint.negative
        case .expected: return FPStatusTint.attention
        case .planned(.transfer), .planned(.currencyExchange), .planned(.adjustment): return .primary
        }
    }
}

struct PlanRescheduleSheet: View {
    let event: ExpectedEvent
    let onSave: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newDate: Date

    init(event: ExpectedEvent, onSave: @escaping (Date) -> Void) {
        self.event = event
        self.onSave = onSave
        _newDate = State(initialValue: max(event.expectedDate, .now))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: event.title)
                        .font(.headline)
                    HStack {
                        Text("plan.reschedule.amount")
                            .foregroundStyle(.secondary)
                        Spacer()
                        MoneyText(money: event.amount)
                    }
                } header: {
                    Text("plan.reschedule.eventHeader")
                }
                Section {
                    DatePicker(
                        "plan.reschedule.newDate",
                        selection: $newDate,
                        displayedComponents: .date
                    )
                }
            }
            .navigationTitle("plan.reschedule.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("plan.common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("plan.common.save") {
                        onSave(newDate)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#if DEBUG
#Preview("Calendar") {
    NavigationStack { PlanCalendarSection() }
        .environment(PlanPreviewFactory.makeStore())
}
#endif
