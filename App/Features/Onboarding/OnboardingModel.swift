import Foundation
import Observation
import SwiftUI
import FinPlanCore

enum OnboardingStep: Int, CaseIterable, Hashable {
    case baseCurrency
    case account
    case goal
    case income
    case savings
    case expectedEvents
    case recurringExpenses
    case security

    var titleKey: LocalizedStringKey {
        switch self {
        case .baseCurrency: "onboarding.currency.title"
        case .account: "onboarding.account.title"
        case .goal: "onboarding.goal.title"
        case .income: "onboarding.income.title"
        case .savings: "onboarding.savings.title"
        case .expectedEvents: "onboarding.events.title"
        case .recurringExpenses: "onboarding.expenses.title"
        case .security: "onboarding.security.title"
        }
    }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .baseCurrency: "onboarding.currency.subtitle"
        case .account: "onboarding.account.subtitle"
        case .goal: "onboarding.goal.subtitle"
        case .income: "onboarding.income.subtitle"
        case .savings: "onboarding.savings.subtitle"
        case .expectedEvents: "onboarding.events.subtitle"
        case .recurringExpenses: "onboarding.expenses.subtitle"
        case .security: "onboarding.security.subtitle"
        }
    }

    var isSkippable: Bool { self == .expectedEvents || self == .recurringExpenses }
}

struct OnboardingIncomeDraft: Identifiable, Hashable {
    enum SharePreset: Int, CaseIterable, Hashable {
        case full, threeQuarters, half, quarter, custom

        var basisPoints: Int? {
            switch self {
            case .full: 10_000
            case .threeQuarters: 7_500
            case .half: 5_000
            case .quarter: 2_500
            case .custom: nil
            }
        }
    }

    let id = UUID()
    var name = ""
    var amountText = ""
    var amountMinor: Int64?
    var currency: Currency = .rub
    var sharePreset: SharePreset = .full
    var customBasisPoints: Int = 5_000

    var effectiveBasisPoints: Int { sharePreset.basisPoints ?? customBasisPoints }

    var isValid: Bool {
        !name.fpTrimmed.isEmpty && (amountMinor ?? 0) > 0 && effectiveBasisPoints > 0
    }

    var personalAmount: Money? {
        guard let amountMinor, amountMinor > 0 else { return nil }
        let gross = Money(minor: amountMinor, currency: currency)
        return PersonalShare.percentageBasisPoints(effectiveBasisPoints).personalAmount(of: gross)
    }
}

struct OnboardingEventDraft: Identifiable, Hashable {
    let id = UUID()
    var title = ""
    var amountText = ""
    var amountMinor: Int64?
    var date: Date = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now

    var isValid: Bool { !title.fpTrimmed.isEmpty && (amountMinor ?? 0) > 0 }
}

struct OnboardingExpenseDraft: Identifiable, Hashable {
    let id = UUID()
    var name = ""
    var amountText = ""
    var amountMinor: Int64?
    var day = 1

    var isValid: Bool { !name.fpTrimmed.isEmpty && (amountMinor ?? 0) > 0 && (1...31).contains(day) }
}

enum OnboardingIncomeSummary: Hashable {
    case empty
    case total(Money)
    case subtotals([Money])
}

@MainActor
@Observable
final class OnboardingModel {
    static let supportedCurrencies: [Currency] = [.rub, .usd, .eur]
    static let savingsContributionDay = 7

    var step: OnboardingStep = .baseCurrency

    var baseCurrency: Currency = .rub

    var accountName: String = String(localized: "onboarding.mainAccount")
    var balanceText = ""
    var balanceMinor: Int64?

    var goalTitle = ""
    var goalTargetText = ""
    var goalTargetMinor: Int64?
    var hasDesiredDate = false
    var desiredDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    var allocateOpeningToGoal = true

    var incomeDrafts: [OnboardingIncomeDraft] = []

    var savingsAmountText = ""
    var savingsAmountMinor: Int64?
    var savingsCurrency: Currency = .rub
    var savingsRateText = ""
    var enteredPlanningRate: ExchangeRate?

    var eventDrafts: [OnboardingEventDraft] = []

    var expenseDrafts: [OnboardingExpenseDraft] = []

    var enableBiometrics = false

    var isAccountValid: Bool {
        !accountName.fpTrimmed.isEmpty && (balanceMinor ?? 0) > 0
    }

    var isGoalValid: Bool {
        !goalTitle.fpTrimmed.isEmpty && (goalTargetMinor ?? 0) > 0
    }

    var needsPlanningRate: Bool { savingsCurrency != baseCurrency }

    var savingsSampleAmount: Money? {
        guard let savingsAmountMinor, savingsAmountMinor > 0 else { return nil }
        return Money(minor: savingsAmountMinor, currency: savingsCurrency)
    }

    var isPlanningRateSuspicious: Bool {
        guard let enteredPlanningRate else { return false }
        return RateEntryField.isSuspicious(enteredPlanningRate)
    }

    private func planningRateCoversPair(_ rate: ExchangeRate) -> Bool {
        ManualExchangeRates(rates: [rate]).rate(from: savingsCurrency, to: baseCurrency) != nil
    }

    var isSavingsValid: Bool {
        guard (savingsAmountMinor ?? 0) > 0 else { return false }
        guard needsPlanningRate else { return true }
        guard let rate = enteredPlanningRate, planningRateCoversPair(rate) else { return false }
        return !RateEntryField.isSuspicious(rate)
    }

    func resetPlanningRateEntry() {
        savingsRateText = ""
        enteredPlanningRate = nil
    }

    var canAdvance: Bool {
        switch step {
        case .baseCurrency: true
        case .account: isAccountValid
        case .goal: isGoalValid
        case .income: incomeDrafts.allSatisfy(\.isValid)
        case .savings: isSavingsValid
        case .expectedEvents: eventDrafts.allSatisfy(\.isValid)
        case .recurringExpenses: expenseDrafts.allSatisfy(\.isValid)
        case .security: true
        }
    }

    var showsSkipLabel: Bool {
        switch step {
        case .expectedEvents: eventDrafts.isEmpty
        case .recurringExpenses: expenseDrafts.isEmpty
        default: false
        }
    }

    func advance() {
        if step == .baseCurrency { reparseBaseCurrencyAmounts() }
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func reparseBaseCurrencyAmounts() {
        if !needsPlanningRate {
            resetPlanningRateEntry()
        } else if let rate = enteredPlanningRate, !planningRateCoversPair(rate) {
            resetPlanningRateEntry()
        }
        balanceMinor = MoneyParser.minorUnits(from: balanceText, currency: baseCurrency)
        goalTargetMinor = MoneyParser.minorUnits(from: goalTargetText, currency: baseCurrency)
        eventDrafts = eventDrafts.map { draft in
            var copy = draft
            copy.amountMinor = MoneyParser.minorUnits(from: draft.amountText, currency: baseCurrency)
            return copy
        }
        expenseDrafts = expenseDrafts.map { draft in
            var copy = draft
            copy.amountMinor = MoneyParser.minorUnits(from: draft.amountText, currency: baseCurrency)
            return copy
        }
    }

    func addIncomeDraft() {
        incomeDrafts = incomeDrafts + [OnboardingIncomeDraft(currency: baseCurrency)]
    }

    func removeIncomeDraft(id: UUID) {
        incomeDrafts = incomeDrafts.filter { $0.id != id }
    }

    func addEventDraft() {
        eventDrafts = eventDrafts + [OnboardingEventDraft()]
    }

    func removeEventDraft(id: UUID) {
        eventDrafts = eventDrafts.filter { $0.id != id }
    }

    func addExpenseDraft() {
        expenseDrafts = expenseDrafts + [OnboardingExpenseDraft()]
    }

    func removeExpenseDraft(id: UUID) {
        expenseDrafts = expenseDrafts.filter { $0.id != id }
    }

    var incomeSummary: OnboardingIncomeSummary {
        let personals = incomeDrafts.compactMap(\.personalAmount)
        guard !personals.isEmpty else { return .empty }
        var order: [Currency] = []
        var grouped: [Currency: Money] = [:]
        do {
            for amount in personals {
                if let existing = grouped[amount.currency] {
                    grouped[amount.currency] = try existing.adding(amount)
                } else {
                    order.append(amount.currency)
                    grouped[amount.currency] = amount
                }
            }
            let subtotals = order.compactMap { grouped[$0] }
            let rates = ManualExchangeRates(rates: enteredPlanningRate.map { [$0] } ?? [])
            var total = Money.zero(baseCurrency)
            for subtotal in subtotals {
                guard let rate = rates.rate(from: subtotal.currency, to: baseCurrency) else {
                    return .subtotals(subtotals)
                }
                total = try total.adding(rate.convert(subtotal))
            }
            return .total(total)
        } catch {
            return .subtotals(order.compactMap { grouped[$0] })
        }
    }

    func finish(with store: FinanceStore) {
        store.lastError = nil
        guard let balanceMinor, let goalTargetMinor else { return }
        do {
            try store.performAtomically {
                try commitAll(store: store, balanceMinor: balanceMinor, goalTargetMinor: goalTargetMinor)
            }
        } catch {
            store.lastError = error.localizedDescription
            return
        }
        guard store.lastError == nil else { return }
        store.requireBiometrics = enableBiometrics
        store.onboardingCompleted = true
    }

    private func commitAll(store: FinanceStore, balanceMinor: Int64, goalTargetMinor: Int64) throws {
        let now = Date()

        store.setBaseCurrency(baseCurrency)
        let opening = Money(minor: balanceMinor, currency: baseCurrency)
        let account = Account(
            name: accountName.fpTrimmed,
            currency: baseCurrency,
            type: .checking,
            openingBalance: opening,
            createdAt: now
        )
        store.addAccount(account)

        let goal = Goal(
            title: goalTitle.fpTrimmed,
            targetAmount: Money(minor: goalTargetMinor, currency: baseCurrency),
            startDate: now,
            desiredCompletionDate: hasDesiredDate ? desiredDate : nil
        )
        store.addGoal(goal)

        if allocateOpeningToGoal {
            store.addAllocation(GoalAllocation(goalID: goal.id, accountID: account.id, amount: opening, date: now))
        }

        for draft in incomeDrafts where draft.isValid {
            guard let minor = draft.amountMinor else { continue }
            store.addIncomeSource(IncomeSource(
                name: draft.name.fpTrimmed,
                grossAmount: Money(minor: minor, currency: draft.currency),
                share: .percentageBasisPoints(draft.effectiveBasisPoints),
                destinationAccountID: account.id
            ))
        }

        if needsPlanningRate, let rate = enteredPlanningRate {
            store.upsertPlanningRate(rate)
        }

        if let savingsMinor = savingsAmountMinor, savingsMinor > 0 {
            store.addRecurringTemplate(RecurringTemplate(
                name: String(localized: "onboarding.savings.templateName"),
                kind: .transfer,
                amount: Money(minor: savingsMinor, currency: savingsCurrency),
                recurrence: .monthly(day: Self.savingsContributionDay),
                sourceAccountID: account.id,
                goalID: goal.id,
                startDate: Self.savingsStartDate(after: now)
            ))
        }

        for draft in eventDrafts where draft.isValid {
            guard let minor = draft.amountMinor else { continue }
            store.addExpectedEvent(ExpectedEvent(
                title: draft.title.fpTrimmed,
                amount: Money(minor: minor, currency: baseCurrency),
                expectedDate: draft.date,
                destinationAccountID: account.id,
                goalID: goal.id
            ))
        }

        for draft in expenseDrafts where draft.isValid {
            guard let minor = draft.amountMinor else { continue }
            store.addRecurringTemplate(RecurringTemplate(
                name: draft.name.fpTrimmed,
                kind: .expense,
                amount: Money(minor: minor, currency: baseCurrency),
                recurrence: .monthly(day: draft.day),
                sourceAccountID: account.id,
                startDate: now
            ))
        }
    }

    static func savingsStartDate(after date: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month], from: date)
        components.month = (components.month ?? 1) + 1
        components.day = savingsContributionDay
        return calendar.date(from: components) ?? date
    }
}

fileprivate extension String {
    var fpTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
