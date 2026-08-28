import Foundation
import Observation
import UserNotifications
import FinPlanCore

enum NotificationPreference {
    static let master = "notifications.enabled"
    static let expectedIncome = "notifications.expectedIncome"
    static let savingsContribution = "notifications.savingsContribution"
    static let largePayment = "notifications.largePayment"
    static let overdue = "notifications.overdue"
}

@MainActor
@Observable
final class NotificationService {
    static let shared = NotificationService()

    static let largePaymentThresholdMajor: Int64 = 10_000

    private static let deliveryHour = 10
    private static let identifierPrefix = "finplan.notification."
    private static let horizonDays = 60
    private static let maxScheduledRequests = 24

    private(set) var lastScheduleIssue: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            lastScheduleIssue = error.localizedDescription
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func scheduleRefresh(
        expectedEvents: [ExpectedEvent],
        recurringTemplates: [RecurringTemplate],
        baseCurrency: Currency,
        planningRates: ManualExchangeRates
    ) {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            await self?.rebuild(
                expectedEvents: expectedEvents,
                recurringTemplates: recurringTemplates,
                baseCurrency: baseCurrency,
                planningRates: planningRates
            )
        }
    }

    func scheduleRefresh(from store: FinanceStore) {
        scheduleRefresh(
            expectedEvents: store.expectedEvents,
            recurringTemplates: store.recurringTemplates,
            baseCurrency: store.baseCurrency,
            planningRates: store.planningRates
        )
    }

    private func rebuild(
        expectedEvents: [ExpectedEvent],
        recurringTemplates: [RecurringTemplate],
        baseCurrency: Currency,
        planningRates: ManualExchangeRates
    ) async {
        let center = UNUserNotificationCenter.current()

        let ourIdentifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ourIdentifiers)

        guard defaults.bool(forKey: NotificationPreference.master) else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        guard !Task.isCancelled else { return }

        var issues: [String] = []
        let planned = plannedNotifications(
            expectedEvents: expectedEvents,
            recurringTemplates: recurringTemplates,
            baseCurrency: baseCurrency,
            planningRates: planningRates,
            now: Date(),
            calendar: .current,
            issues: &issues
        )

        for item in planned.sorted(by: { $0.fireDate < $1.fireDate }).prefix(Self.maxScheduledRequests) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: item.fireDate
            )
            let request = UNNotificationRequest(
                identifier: item.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            do {
                try await center.add(request)
            } catch {
                issues.append(error.localizedDescription)
            }
        }
        lastScheduleIssue = issues.first
    }

    private struct PlannedNotification {
        let identifier: String
        let title: String
        let body: String
        let fireDate: Date
    }

    private func plannedNotifications(
        expectedEvents: [ExpectedEvent],
        recurringTemplates: [RecurringTemplate],
        baseCurrency: Currency,
        planningRates: ManualExchangeRates,
        now: Date,
        calendar: Calendar,
        issues: inout [String]
    ) -> [PlannedNotification] {
        var result: [PlannedNotification] = []
        guard let horizonEnd = calendar.date(byAdding: .day, value: Self.horizonDays, to: now) else {
            return result
        }
        let horizon = DateInterval(start: now, end: horizonEnd)
        let scheduler = RecurringScheduler(calendar: calendar)

        let expectedIncomeOn = isTypeEnabled(NotificationPreference.expectedIncome)
        let overdueOn = isTypeEnabled(NotificationPreference.overdue)
        for event in expectedEvents where event.state == .expected {
            if expectedIncomeOn,
               let fire = delivery(on: event.expectedDate, calendar: calendar), fire > now {
                result.append(PlannedNotification(
                    identifier: Self.identifierPrefix + "expectedIncome." + event.id.uuidString,
                    title: String(localized: "notification.expectedIncome.title"),
                    body: event.title,
                    fireDate: fire
                ))
            }
            if overdueOn,
               let dayAfter = calendar.date(byAdding: .day, value: 1, to: event.expectedDate),
               let fire = delivery(on: dayAfter, calendar: calendar), fire > now {
                result.append(PlannedNotification(
                    identifier: Self.identifierPrefix + "expectedOverdue." + event.id.uuidString,
                    title: String(localized: "notification.expectedOverdue.title"),
                    body: event.title,
                    fireDate: fire
                ))
            }
        }

        if isTypeEnabled(NotificationPreference.savingsContribution) {
            for template in recurringTemplates where template.isActive && template.goalID != nil {
                guard
                    let next = scheduler.occurrences(of: template, in: horizon).first,
                    let fire = delivery(on: next, calendar: calendar), fire > now
                else { continue }
                result.append(PlannedNotification(
                    identifier: Self.identifierPrefix + "savings." + template.id.uuidString,
                    title: String(localized: "notification.savingsContribution.title"),
                    body: template.name,
                    fireDate: fire
                ))
            }
        }

        if isTypeEnabled(NotificationPreference.largePayment) {
            let threshold = Money(major: Self.largePaymentThresholdMajor, currency: baseCurrency)
            for template in recurringTemplates where template.isActive && template.kind == .expense {
                guard let amountInBase = convertForComparison(
                    template.amount, to: baseCurrency, rates: planningRates,
                    templateName: template.name, issues: &issues
                ) else { continue }
                guard let comparison = try? amountInBase.comparing(threshold), comparison >= 0 else {
                    continue
                }
                for occurrence in scheduler.occurrences(of: template, in: horizon) {
                    guard
                        let dayBefore = calendar.date(byAdding: .day, value: -1, to: occurrence),
                        let fire = delivery(on: dayBefore, calendar: calendar), fire > now
                    else { continue }
                    let occurrenceStamp = Int(occurrence.timeIntervalSince1970)
                    result.append(PlannedNotification(
                        identifier: Self.identifierPrefix
                            + "largePayment.\(template.id.uuidString).\(occurrenceStamp)",
                        title: String(localized: "notification.largePayment.title"),
                        body: template.name,
                        fireDate: fire
                    ))
                }
            }
        }
        return result
    }

    private func convertForComparison(
        _ money: Money,
        to currency: Currency,
        rates: ManualExchangeRates,
        templateName: String,
        issues: inout [String]
    ) -> Money? {
        if money.currency == currency { return money }
        guard let rate = rates.rate(from: money.currency, to: currency) else {
            issues.append(String(localized: "notification.issue.missingRate \(money.currency.code) \(currency.code) \(templateName)"))
            return nil
        }
        do {
            return try rate.convert(money)
        } catch {
            issues.append(error.localizedDescription)
            return nil
        }
    }

    private func delivery(on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: Self.deliveryHour, minute: 0, second: 0, of: day)
    }

    private func isTypeEnabled(_ key: String) -> Bool {
        defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }
}
