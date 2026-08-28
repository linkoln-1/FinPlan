import SwiftUI
import FinPlanCore

struct PlanSubscriptionsCard: View {
    @Environment(FinanceStore.self) private var store

    private static let billingLookaheadYears = 1

    var body: some View {
        let rows = subscriptionRows(now: Date.now)
        if !rows.isEmpty {
            FPCard {
                VStack(alignment: .leading, spacing: FP.Spacing.md) {
                    Text("plan.subscriptions.title")
                        .font(.headline)

                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                            HStack(spacing: FP.Spacing.sm) {
                                Label {
                                    Text(verbatim: row.summary.name)
                                        .lineLimit(1)
                                } icon: {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline.weight(.medium))
                                Spacer(minLength: FP.Spacing.sm)
                                HStack(spacing: FP.Spacing.xs) {
                                    MoneyText(money: row.summary.monthlyEquivalent)
                                        .font(.subheadline.weight(.semibold))
                                    Text("plan.subscriptions.perMonth")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            HStack(spacing: FP.Spacing.sm) {
                                if let next = row.nextBillingDate {
                                    Label {
                                        Text(next, format: .dateTime.day().month().year())
                                    } icon: {
                                        Image(systemName: "calendar")
                                    }
                                } else {
                                    Label("plan.subscriptions.noUpcoming", systemImage: "calendar.badge.exclamationmark")
                                }
                                Spacer(minLength: FP.Spacing.sm)
                                HStack(spacing: FP.Spacing.xs) {
                                    MoneyText(money: row.summary.yearlyEquivalent)
                                    Text("plan.subscriptions.perYear")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        if row.id != rows.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private struct PlanSubscriptionRow: Identifiable {
        let summary: SubscriptionSummary
        let nextBillingDate: Date?
        var id: UUID { summary.id }
    }

    private func subscriptionRows(now: Date) -> [PlanSubscriptionRow] {
        let summaries = RecurringScheduler.subscriptionSummary(templates: store.recurringTemplates)
        guard !summaries.isEmpty else { return [] }
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .year, value: Self.billingLookaheadYears, to: now) ?? now
        let interval = DateInterval(start: now, end: horizon)
        let scheduler = RecurringScheduler(calendar: calendar)
        return summaries.map { summary in
            let template = store.recurringTemplates.first { $0.id == summary.templateID }
            let next = template.flatMap { scheduler.occurrences(of: $0, in: interval).first }
            return PlanSubscriptionRow(summary: summary, nextBillingDate: next)
        }
    }
}

#if DEBUG
#Preview("Subscriptions") {
    ScrollView {
        PlanSubscriptionsCard()
            .padding()
    }
    .environment(PlanPreviewFactory.makeStore())
}
#endif
