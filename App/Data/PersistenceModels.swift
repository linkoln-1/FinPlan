import Foundation
import SwiftData
import FinPlanCore

@Model
final class AccountModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var currencyCode: String
    var currencyExponent: Int
    var typeRaw: String
    var openingBalanceMinor: Int64
    var includedInNetWorth: Bool
    var includedInSafeToSpend: Bool
    var isArchived: Bool
    var createdAt: Date

    init(from domain: Account) {
        self.id = domain.id
        self.name = domain.name
        self.currencyCode = domain.currency.code
        self.currencyExponent = domain.currency.minorUnitExponent
        self.typeRaw = domain.type.rawValue
        self.openingBalanceMinor = domain.openingBalance.amountMinor
        self.includedInNetWorth = domain.includedInNetWorth
        self.includedInSafeToSpend = domain.includedInSafeToSpend
        self.isArchived = domain.isArchived
        self.createdAt = domain.createdAt
    }

    var currency: Currency { Currency(code: currencyCode, minorUnitExponent: currencyExponent) }

    func toDomain() -> Account {
        Account(
            id: id, name: name, currency: currency,
            type: AccountType(rawValue: typeRaw) ?? .other,
            openingBalance: Money(minor: openingBalanceMinor, currency: currency),
            includedInNetWorth: includedInNetWorth,
            includedInSafeToSpend: includedInSafeToSpend,
            isArchived: isArchived, createdAt: createdAt
        )
    }
}

@Model
final class CategoryModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var symbolName: String
    var isArchived: Bool
    var isEssential: Bool

    init(from domain: TransactionCategory) {
        self.id = domain.id
        self.name = domain.name
        self.symbolName = domain.symbolName
        self.isArchived = domain.isArchived
        self.isEssential = domain.isEssential
    }

    func toDomain() -> TransactionCategory {
        TransactionCategory(id: id, name: name, symbolName: symbolName, isArchived: isArchived, isEssential: isEssential)
    }
}

@Model
final class TagModel {
    @Attribute(.unique) var id: UUID
    var name: String

    init(from domain: TransactionTag) {
        self.id = domain.id
        self.name = domain.name
    }

    func toDomain() -> TransactionTag { TransactionTag(id: id, name: name) }
}

@Model
final class TransactionModel {
    @Attribute(.unique) var id: UUID
    var date: Date
    var kindRaw: String
    var statusRaw: String
    var amountMinor: Int64
    var currencyCode: String
    var currencyExponent: Int
    var sourceAccountID: UUID?
    var destinationAccountID: UUID?
    var counterAmountMinor: Int64?
    var counterCurrencyCode: String?
    var counterCurrencyExponent: Int?
    var feeMinor: Int64?
    var feeCurrencyCode: String?
    var feeCurrencyExponent: Int?
    var categoryID: UUID?
    var goalID: UUID?
    var note: String?
    var tagIDsBlob: Data?
    var splitsBlob: Data?
    var attachmentsBlob: Data?
    var recurringTemplateID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(from domain: TransactionRecord) {
        self.id = domain.id
        self.date = domain.date
        self.kindRaw = domain.kind.rawValue
        self.statusRaw = domain.status.rawValue
        self.amountMinor = domain.amount.amountMinor
        self.currencyCode = domain.amount.currency.code
        self.currencyExponent = domain.amount.currency.minorUnitExponent
        self.sourceAccountID = domain.sourceAccountID
        self.destinationAccountID = domain.destinationAccountID
        self.counterAmountMinor = domain.counterAmount?.amountMinor
        self.counterCurrencyCode = domain.counterAmount?.currency.code
        self.counterCurrencyExponent = domain.counterAmount?.currency.minorUnitExponent
        self.feeMinor = domain.fee?.amountMinor
        self.feeCurrencyCode = domain.fee?.currency.code
        self.feeCurrencyExponent = domain.fee?.currency.minorUnitExponent
        self.categoryID = domain.categoryID
        self.goalID = domain.goalID
        self.note = domain.note
        self.tagIDsBlob = try? JSONEncoder().encode(domain.tagIDs)
        self.splitsBlob = try? JSONEncoder().encode(domain.splits)
        self.attachmentsBlob = try? JSONEncoder().encode(domain.attachments)
        self.recurringTemplateID = domain.recurringTemplateID
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
    }

    func toDomain() -> TransactionRecord {
        let currency = Currency(code: currencyCode, minorUnitExponent: currencyExponent)
        var counter: Money?
        if let minor = counterAmountMinor, let code = counterCurrencyCode {
            counter = Money(minor: minor, currency: Currency(code: code, minorUnitExponent: counterCurrencyExponent ?? 2))
        }
        var fee: Money?
        if let minor = feeMinor, let code = feeCurrencyCode {
            fee = Money(minor: minor, currency: Currency(code: code, minorUnitExponent: feeCurrencyExponent ?? 2))
        }
        let decoder = JSONDecoder()
        return TransactionRecord(
            id: id, date: date,
            kind: TransactionKind(rawValue: kindRaw) ?? .expense,
            status: TransactionStatus(rawValue: statusRaw) ?? .completed,
            amount: Money(minor: amountMinor, currency: currency),
            sourceAccountID: sourceAccountID,
            destinationAccountID: destinationAccountID,
            counterAmount: counter,
            fee: fee,
            categoryID: categoryID,
            goalID: goalID,
            note: note,
            tagIDs: (try? decoder.decode([UUID].self, from: tagIDsBlob ?? Data())) ?? [],
            splits: (try? decoder.decode([TransactionSplit].self, from: splitsBlob ?? Data())) ?? [],
            recurringTemplateID: recurringTemplateID,
            attachments: (try? decoder.decode([AttachmentReference].self, from: attachmentsBlob ?? Data())) ?? [],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class GoalModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var symbolName: String
    var targetMinor: Int64
    var currencyCode: String
    var currencyExponent: Int
    var startDate: Date
    var desiredCompletionDate: Date?
    var priorityRaw: Int
    var statusRaw: String
    var isEmergencyFund: Bool
    var desiredMonthsOfExpenses: Int?

    init(from domain: Goal) {
        self.id = domain.id
        self.title = domain.title
        self.symbolName = domain.symbolName
        self.targetMinor = domain.targetAmount.amountMinor
        self.currencyCode = domain.targetAmount.currency.code
        self.currencyExponent = domain.targetAmount.currency.minorUnitExponent
        self.startDate = domain.startDate
        self.desiredCompletionDate = domain.desiredCompletionDate
        self.priorityRaw = domain.priority.rawValue
        self.statusRaw = domain.status.rawValue
        self.isEmergencyFund = domain.isEmergencyFund
        self.desiredMonthsOfExpenses = domain.desiredMonthsOfExpenses
    }

    func toDomain() -> Goal {
        let currency = Currency(code: currencyCode, minorUnitExponent: currencyExponent)
        return Goal(
            id: id, title: title, symbolName: symbolName,
            targetAmount: Money(minor: targetMinor, currency: currency),
            startDate: startDate,
            desiredCompletionDate: desiredCompletionDate,
            priority: GoalPriority(rawValue: priorityRaw) ?? .medium,
            status: GoalStatus(rawValue: statusRaw) ?? .active,
            isEmergencyFund: isEmergencyFund,
            desiredMonthsOfExpenses: desiredMonthsOfExpenses
        )
    }
}

@Model
final class AllocationModel {
    @Attribute(.unique) var id: UUID
    var goalID: UUID
    var accountID: UUID
    var amountMinor: Int64
    var currencyCode: String
    var currencyExponent: Int
    var date: Date

    init(from domain: GoalAllocation) {
        self.id = domain.id
        self.goalID = domain.goalID
        self.accountID = domain.accountID
        self.amountMinor = domain.amount.amountMinor
        self.currencyCode = domain.amount.currency.code
        self.currencyExponent = domain.amount.currency.minorUnitExponent
        self.date = domain.date
    }

    func toDomain() -> GoalAllocation {
        GoalAllocation(
            id: id, goalID: goalID, accountID: accountID,
            amount: Money(minor: amountMinor, currency: Currency(code: currencyCode, minorUnitExponent: currencyExponent)),
            date: date
        )
    }
}

@Model
final class IncomeSourceModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var grossMinor: Int64
    var currencyCode: String
    var currencyExponent: Int
    var shareBlob: Data?
    var recurrenceBlob: Data?
    var destinationAccountID: UUID?
    var isActive: Bool

    init(from domain: IncomeSource) {
        self.id = domain.id
        self.name = domain.name
        self.grossMinor = domain.grossAmount.amountMinor
        self.currencyCode = domain.grossAmount.currency.code
        self.currencyExponent = domain.grossAmount.currency.minorUnitExponent
        self.shareBlob = try? JSONEncoder().encode(domain.share)
        self.recurrenceBlob = try? JSONEncoder().encode(domain.recurrence)
        self.destinationAccountID = domain.destinationAccountID
        self.isActive = domain.isActive
    }

    func toDomain() -> IncomeSource {
        let currency = Currency(code: currencyCode, minorUnitExponent: currencyExponent)
        let decoder = JSONDecoder()
        return IncomeSource(
            id: id, name: name,
            grossAmount: Money(minor: grossMinor, currency: currency),
            share: (try? decoder.decode(PersonalShare.self, from: shareBlob ?? Data())) ?? .percentageBasisPoints(10_000),
            recurrence: (try? decoder.decode(Recurrence.self, from: recurrenceBlob ?? Data())) ?? .monthly(day: 5),
            destinationAccountID: destinationAccountID,
            isActive: isActive
        )
    }
}

@Model
final class BudgetModel {
    @Attribute(.unique) var id: UUID
    var categoryID: UUID
    var amountMinor: Int64
    var currencyCode: String
    var currencyExponent: Int
    var periodRaw: String
    var rolloverRaw: String
    var carriedOverMinor: Int64

    init(from domain: Budget) {
        self.id = domain.id
        self.categoryID = domain.categoryID
        self.amountMinor = domain.amount.amountMinor
        self.currencyCode = domain.amount.currency.code
        self.currencyExponent = domain.amount.currency.minorUnitExponent
        self.periodRaw = domain.period.rawValue
        self.rolloverRaw = domain.rollover.rawValue
        self.carriedOverMinor = domain.carriedOverMinor
    }

    func toDomain() -> Budget {
        Budget(
            id: id, categoryID: categoryID,
            amount: Money(minor: amountMinor, currency: Currency(code: currencyCode, minorUnitExponent: currencyExponent)),
            period: BudgetPeriod(rawValue: periodRaw) ?? .monthly,
            rollover: BudgetRolloverPolicy(rawValue: rolloverRaw) ?? .expires,
            carriedOverMinor: carriedOverMinor
        )
    }
}

@Model
final class RecurringTemplateModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var amountMinor: Int64
    var currencyCode: String
    var currencyExponent: Int
    var recurrenceBlob: Data?
    var sourceAccountID: UUID?
    var destinationAccountID: UUID?
    var categoryID: UUID?
    var goalID: UUID?
    var isActive: Bool
    var startDate: Date
    var endDate: Date?

    init(from domain: RecurringTemplate) {
        self.id = domain.id
        self.name = domain.name
        self.kindRaw = domain.kind.rawValue
        self.amountMinor = domain.amount.amountMinor
        self.currencyCode = domain.amount.currency.code
        self.currencyExponent = domain.amount.currency.minorUnitExponent
        self.recurrenceBlob = try? JSONEncoder().encode(domain.recurrence)
        self.sourceAccountID = domain.sourceAccountID
        self.destinationAccountID = domain.destinationAccountID
        self.categoryID = domain.categoryID
        self.goalID = domain.goalID
        self.isActive = domain.isActive
        self.startDate = domain.startDate
        self.endDate = domain.endDate
    }

    func toDomain() -> RecurringTemplate {
        RecurringTemplate(
            id: id, name: name,
            kind: TransactionKind(rawValue: kindRaw) ?? .expense,
            amount: Money(minor: amountMinor, currency: Currency(code: currencyCode, minorUnitExponent: currencyExponent)),
            recurrence: (try? JSONDecoder().decode(Recurrence.self, from: recurrenceBlob ?? Data())) ?? .monthly(day: 1),
            sourceAccountID: sourceAccountID,
            destinationAccountID: destinationAccountID,
            categoryID: categoryID,
            goalID: goalID,
            isActive: isActive,
            startDate: startDate,
            endDate: endDate
        )
    }
}

@Model
final class ExpectedEventModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var amountMinor: Int64
    var currencyCode: String
    var currencyExponent: Int
    var expectedDate: Date
    var stateRaw: String
    var destinationAccountID: UUID?
    var goalID: UUID?

    init(from domain: ExpectedEvent) {
        self.id = domain.id
        self.title = domain.title
        self.amountMinor = domain.amount.amountMinor
        self.currencyCode = domain.amount.currency.code
        self.currencyExponent = domain.amount.currency.minorUnitExponent
        self.expectedDate = domain.expectedDate
        self.stateRaw = domain.state.rawValue
        self.destinationAccountID = domain.destinationAccountID
        self.goalID = domain.goalID
    }

    func toDomain() -> ExpectedEvent {
        ExpectedEvent(
            id: id, title: title,
            amount: Money(minor: amountMinor, currency: Currency(code: currencyCode, minorUnitExponent: currencyExponent)),
            expectedDate: expectedDate,
            state: ExpectedEventState(rawValue: stateRaw) ?? .expected,
            destinationAccountID: destinationAccountID,
            goalID: goalID
        )
    }
}

@Model
final class AppSettingsModel {
    @Attribute(.unique) var id: UUID
    var baseCurrencyCode: String
    var baseCurrencyExponent: Int
    var planningRatesBlob: Data?
    var minimumCashBufferMinor: Int64
    var requireBiometrics: Bool
    var hideBalances: Bool
    var onboardingCompleted: Bool

    init() {
        self.id = UUID()
        self.baseCurrencyCode = "RUB"
        self.baseCurrencyExponent = 2
        self.planningRatesBlob = nil
        self.minimumCashBufferMinor = 0
        self.requireBiometrics = false
        self.hideBalances = false
        self.onboardingCompleted = false
    }

    var baseCurrency: Currency {
        get { Currency(code: baseCurrencyCode, minorUnitExponent: baseCurrencyExponent) }
        set { baseCurrencyCode = newValue.code; baseCurrencyExponent = newValue.minorUnitExponent }
    }

    var planningRates: ManualExchangeRates {
        get { (try? JSONDecoder().decode(ManualExchangeRates.self, from: planningRatesBlob ?? Data())) ?? ManualExchangeRates() }
        set { planningRatesBlob = try? JSONEncoder().encode(newValue) }
    }
}
