import Foundation

public struct SubscriptionSummary: Hashable, Sendable, Identifiable {
    public var id: UUID { templateID }
    public let templateID: UUID
    public let name: String
    public let monthlyEquivalent: Money
    public let yearlyEquivalent: Money

    public init(templateID: UUID, name: String, monthlyEquivalent: Money, yearlyEquivalent: Money) {
        self.templateID = templateID
        self.name = name
        self.monthlyEquivalent = monthlyEquivalent
        self.yearlyEquivalent = yearlyEquivalent
    }
}

public struct ExpectedEventPartition: Hashable, Sendable {
    public let upcoming: [ExpectedEvent]
    public let needsAttention: [ExpectedEvent]

    public init(upcoming: [ExpectedEvent], needsAttention: [ExpectedEvent]) {
        self.upcoming = upcoming
        self.needsAttention = needsAttention
    }
}

public struct RecurringScheduler: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public func occurrences(of template: RecurringTemplate, in interval: DateInterval) -> [Date] {
        guard template.isActive else { return [] }
        switch template.recurrence {
        case .daily:
            return steppedOccurrences(of: template, in: interval, stepDays: 1)
        case .everyNDays(let n):
            return steppedOccurrences(of: template, in: interval, stepDays: max(1, n))
        case .weekly(let weekday):
            return weeklyOccurrences(of: template, in: interval, weekday: weekday)
        case .monthly(let day):
            return monthlyOccurrences(of: template, in: interval, day: day)
        case .yearly(let month, let day):
            return yearlyOccurrences(of: template, in: interval, month: month, day: day)
        }
    }

    public func plannedRecords(
        for templates: [RecurringTemplate],
        in interval: DateInterval
    ) -> [TransactionRecord] {
        var records: [TransactionRecord] = []
        for template in templates {
            for date in occurrences(of: template, in: interval) {
                records.append(
                    TransactionRecord(
                        date: date,
                        kind: template.kind,
                        status: .planned,
                        amount: template.amount,
                        sourceAccountID: template.sourceAccountID,
                        destinationAccountID: template.destinationAccountID,
                        categoryID: template.categoryID,
                        goalID: template.goalID,
                        note: template.name,
                        recurringTemplateID: template.id,
                        createdAt: date
                    )
                )
            }
        }
        return records.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            let lhsKey = lhs.recurringTemplateID?.uuidString ?? ""
            let rhsKey = rhs.recurringTemplateID?.uuidString ?? ""
            return lhsKey < rhsKey
        }
    }

    public static func subscriptionSummary(templates: [RecurringTemplate]) -> [SubscriptionSummary] {
        templates.compactMap { template in
            guard template.isActive, template.kind == .expense else { return nil }
            let amount = template.amount
            let monthly: Money
            let yearly: Money
            switch template.recurrence {
            case .daily:
                yearly = amount.multiplied(by: 365)
                monthly = amount.multiplied(byNumerator: 365, denominator: 12)
            case .weekly:
                yearly = amount.multiplied(by: 52)
                monthly = amount.multiplied(byNumerator: 52, denominator: 12)
            case .monthly:
                yearly = amount.multiplied(by: 12)
                monthly = amount
            case .yearly:
                yearly = amount
                monthly = amount.multiplied(byNumerator: 1, denominator: 12)
            case .everyNDays(let n):
                let step = Int64(max(1, n))
                yearly = amount.multiplied(byNumerator: 365, denominator: step)
                monthly = amount.multiplied(byNumerator: 365, denominator: 12 * step)
            }
            return SubscriptionSummary(
                templateID: template.id,
                name: template.name,
                monthlyEquivalent: monthly,
                yearlyEquivalent: yearly
            )
        }
    }

    public static func expectedEventStatus(
        events: [ExpectedEvent],
        now: Date
    ) -> ExpectedEventPartition {
        var upcoming: [ExpectedEvent] = []
        var needsAttention: [ExpectedEvent] = []
        for event in events {
            switch event.state {
            case .expected:
                if event.expectedDate >= now {
                    upcoming.append(event)
                } else {
                    needsAttention.append(event)
                }
            case .overdue:
                needsAttention.append(event)
            case .received, .cancelled:
                continue
            }
        }
        let byDate: (ExpectedEvent, ExpectedEvent) -> Bool = { lhs, rhs in
            if lhs.expectedDate != rhs.expectedDate { return lhs.expectedDate < rhs.expectedDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return ExpectedEventPartition(
            upcoming: upcoming.sorted(by: byDate),
            needsAttention: needsAttention.sorted(by: byDate)
        )
    }

    private func isEligible(_ date: Date, template: RecurringTemplate, interval: DateInterval) -> Bool {
        guard date >= template.startDate, date >= interval.start, date < interval.end else { return false }
        if let end = template.endDate, date > end { return false }
        return true
    }

    private func steppedOccurrences(
        of template: RecurringTemplate,
        in interval: DateInterval,
        stepDays: Int
    ) -> [Date] {
        var current = template.startDate
        let windowStart = max(interval.start, template.startDate)
        if windowStart > current,
           let days = calendar.dateComponents([.day], from: current, to: windowStart).day {
            let steps = days / stepDays
            if steps > 0, let jumped = calendar.date(byAdding: .day, value: steps * stepDays, to: current) {
                current = jumped
            }
        }
        var result: [Date] = []
        while current < interval.end {
            if let end = template.endDate, current > end { break }
            if isEligible(current, template: template, interval: interval) {
                result.append(current)
            }
            guard let next = calendar.date(byAdding: .day, value: stepDays, to: current) else { break }
            current = next
        }
        return result
    }

    private func weeklyOccurrences(
        of template: RecurringTemplate,
        in interval: DateInterval,
        weekday: Int
    ) -> [Date] {
        let startWeekday = calendar.component(.weekday, from: template.startDate)
        let delta = ((weekday - startWeekday) % 7 + 7) % 7
        guard var current = calendar.date(byAdding: .day, value: delta, to: template.startDate) else {
            return []
        }
        let windowStart = max(interval.start, template.startDate)
        if windowStart > current,
           let days = calendar.dateComponents([.day], from: current, to: windowStart).day {
            let weeks = days / 7
            if weeks > 0, let jumped = calendar.date(byAdding: .day, value: weeks * 7, to: current) {
                current = jumped
            }
        }
        var result: [Date] = []
        while current < interval.end {
            if let end = template.endDate, current > end { break }
            if isEligible(current, template: template, interval: interval) {
                result.append(current)
            }
            guard let next = calendar.date(byAdding: .day, value: 7, to: current) else { break }
            current = next
        }
        return result
    }

    private func monthlyOccurrences(
        of template: RecurringTemplate,
        in interval: DateInterval,
        day: Int
    ) -> [Date] {
        let timeOfDay = calendar.dateComponents([.hour, .minute, .second], from: template.startDate)
        let windowStart = max(interval.start, template.startDate)
        var anchor = calendar.dateComponents([.year, .month], from: windowStart)
        var result: [Date] = []
        while true {
            guard let year = anchor.year, let month = anchor.month,
                  let occurrence = clampedDate(year: year, month: month, day: day, timeOfDay: timeOfDay)
            else { break }
            if occurrence >= interval.end { break }
            if let end = template.endDate, occurrence > end { break }
            if isEligible(occurrence, template: template, interval: interval) {
                result.append(occurrence)
            }
            anchor.month = month + 1
            anchor = normalized(anchor)
        }
        return result
    }

    private func yearlyOccurrences(
        of template: RecurringTemplate,
        in interval: DateInterval,
        month: Int,
        day: Int
    ) -> [Date] {
        let timeOfDay = calendar.dateComponents([.hour, .minute, .second], from: template.startDate)
        let windowStart = max(interval.start, template.startDate)
        var year = calendar.component(.year, from: windowStart)
        var result: [Date] = []
        while true {
            guard let occurrence = clampedDate(year: year, month: month, day: day, timeOfDay: timeOfDay)
            else { break }
            if occurrence >= interval.end { break }
            if let end = template.endDate, occurrence > end { break }
            if isEligible(occurrence, template: template, interval: interval) {
                result.append(occurrence)
            }
            year += 1
        }
        return result
    }

    private func clampedDate(year: Int, month: Int, day: Int, timeOfDay: DateComponents) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let firstOfMonth = calendar.date(from: components),
              let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else { return nil }
        components.day = min(max(1, day), dayRange.count)
        components.hour = timeOfDay.hour
        components.minute = timeOfDay.minute
        components.second = timeOfDay.second
        return calendar.date(from: components)
    }

    private func normalized(_ anchor: DateComponents) -> DateComponents {
        var components = DateComponents()
        components.year = anchor.year
        components.month = anchor.month
        components.day = 1
        guard let date = calendar.date(from: components) else { return anchor }
        return calendar.dateComponents([.year, .month], from: date)
    }
}
