import Foundation

public enum BudgetPeriod: String, Sendable, Codable, CaseIterable {
    case monthly, weekly
}

public enum BudgetRolloverPolicy: String, Sendable, Codable, CaseIterable {
    case expires, rollsOver, toGoal, toFreeCash
}

public struct Budget: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var categoryID: UUID
    public var amount: Money
    public var period: BudgetPeriod
    public var rollover: BudgetRolloverPolicy
    public var carriedOverMinor: Int64

    public init(
        id: UUID = UUID(),
        categoryID: UUID,
        amount: Money,
        period: BudgetPeriod = .monthly,
        rollover: BudgetRolloverPolicy = .expires,
        carriedOverMinor: Int64 = 0
    ) {
        precondition(amount.isPositive, "budget amount must be positive")
        self.id = id
        self.categoryID = categoryID
        self.amount = amount
        self.period = period
        self.rollover = rollover
        self.carriedOverMinor = carriedOverMinor
    }
}

public struct RecurringTemplate: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var kind: TransactionKind
    public var amount: Money
    public var recurrence: Recurrence
    public var sourceAccountID: UUID?
    public var destinationAccountID: UUID?
    public var categoryID: UUID?
    public var goalID: UUID?
    public var isActive: Bool
    public var startDate: Date
    public var endDate: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: TransactionKind,
        amount: Money,
        recurrence: Recurrence,
        sourceAccountID: UUID? = nil,
        destinationAccountID: UUID? = nil,
        categoryID: UUID? = nil,
        goalID: UUID? = nil,
        isActive: Bool = true,
        startDate: Date,
        endDate: Date? = nil
    ) {
        precondition(amount.isPositive, "recurring amount must be positive")
        precondition(recurrence.isValid, "invalid recurrence")
        self.id = id
        self.name = name
        self.kind = kind
        self.amount = amount
        self.recurrence = recurrence
        self.sourceAccountID = sourceAccountID
        self.destinationAccountID = destinationAccountID
        self.categoryID = categoryID
        self.goalID = goalID
        self.isActive = isActive
        self.startDate = startDate
        self.endDate = endDate
    }
}

public enum ExpectedEventState: String, Sendable, Codable {
    case expected
    case received
    case overdue
    case cancelled
}

public struct ExpectedEvent: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var title: String
    public var amount: Money
    public var expectedDate: Date
    public var state: ExpectedEventState
    public var destinationAccountID: UUID?
    public var goalID: UUID?

    public init(
        id: UUID = UUID(),
        title: String,
        amount: Money,
        expectedDate: Date,
        state: ExpectedEventState = .expected,
        destinationAccountID: UUID? = nil,
        goalID: UUID? = nil
    ) {
        precondition(amount.isPositive, "expected amount must be positive")
        self.id = id
        self.title = title
        self.amount = amount
        self.expectedDate = expectedDate
        self.state = state
        self.destinationAccountID = destinationAccountID
        self.goalID = goalID
    }
}

public struct PlanSettings: Hashable, Sendable, Codable {
    public var baseCurrency: Currency
    public var planningRates: ManualExchangeRates
    public var minimumCashBufferMinor: Int64

    public init(
        baseCurrency: Currency = .rub,
        planningRates: ManualExchangeRates = ManualExchangeRates(),
        minimumCashBufferMinor: Int64 = 0
    ) {
        self.baseCurrency = baseCurrency
        self.planningRates = planningRates
        self.minimumCashBufferMinor = minimumCashBufferMinor
    }
}
