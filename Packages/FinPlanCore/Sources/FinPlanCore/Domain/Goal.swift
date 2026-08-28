import Foundation

public enum GoalStatus: String, Sendable, Codable, CaseIterable {
    case planned, active, paused, completed, archived
}

public enum GoalPriority: Int, Sendable, Codable, CaseIterable, Comparable {
    case low = 0, medium = 1, high = 2
    public static func < (lhs: GoalPriority, rhs: GoalPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct GoalAllocation: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var goalID: UUID
    public var accountID: UUID
    public var amount: Money
    public var date: Date

    public init(id: UUID = UUID(), goalID: UUID, accountID: UUID, amount: Money, date: Date) {
        self.id = id
        self.goalID = goalID
        self.accountID = accountID
        self.amount = amount
        self.date = date
    }
}

public struct Goal: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var title: String
    public var symbolName: String
    public var targetAmount: Money
    public var startDate: Date
    public var desiredCompletionDate: Date?
    public var priority: GoalPriority
    public var status: GoalStatus
    public var isEmergencyFund: Bool
    public var desiredMonthsOfExpenses: Int?

    public init(
        id: UUID = UUID(),
        title: String,
        symbolName: String = "target",
        targetAmount: Money,
        startDate: Date,
        desiredCompletionDate: Date? = nil,
        priority: GoalPriority = .medium,
        status: GoalStatus = .active,
        isEmergencyFund: Bool = false,
        desiredMonthsOfExpenses: Int? = nil
    ) {
        precondition(targetAmount.isPositive, "goal target must be positive")
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.targetAmount = targetAmount
        self.startDate = startDate
        self.desiredCompletionDate = desiredCompletionDate
        self.priority = priority
        self.status = status
        self.isEmergencyFund = isEmergencyFund
        self.desiredMonthsOfExpenses = desiredMonthsOfExpenses
    }
}

public struct GoalMilestone: Hashable, Sendable, Codable, Identifiable {
    public enum Kind: Hashable, Sendable, Codable {
        case percentBasisPoints(Int)
        case roundAmount(Money)
    }

    public var id: String {
        switch kind {
        case .percentBasisPoints(let bps): return "pct-\(bps)"
        case .roundAmount(let money): return "amt-\(money.amountMinor)"
        }
    }

    public let kind: Kind
    public let threshold: Money
    public var isReached: Bool
    public var projectedDate: Date?

    public init(kind: Kind, threshold: Money, isReached: Bool = false, projectedDate: Date? = nil) {
        self.kind = kind
        self.threshold = threshold
        self.isReached = isReached
        self.projectedDate = projectedDate
    }
}
