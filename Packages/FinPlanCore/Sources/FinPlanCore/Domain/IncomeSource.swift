import Foundation

public enum Recurrence: Hashable, Sendable, Codable {
    case daily
    case weekly(weekday: Int)
    case monthly(day: Int)
    case yearly(month: Int, day: Int)
    case everyNDays(Int)

    public var isValid: Bool {
        switch self {
        case .daily: return true
        case .weekly(let weekday): return (1...7).contains(weekday)
        case .monthly(let day): return (1...31).contains(day)
        case .yearly(let month, let day): return (1...12).contains(month) && (1...31).contains(day)
        case .everyNDays(let n): return n >= 1
        }
    }
}

public enum PersonalShare: Hashable, Sendable, Codable {
    case percentageBasisPoints(Int)
    case fixedAmount(Money)

    public func personalAmount(of gross: Money) -> Money {
        switch self {
        case .percentageBasisPoints(let bps):
            return gross.multiplied(byNumerator: Int64(bps), denominator: 10_000)
        case .fixedAmount(let fixed):
            return fixed
        }
    }
}

public struct IncomeSource: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var grossAmount: Money
    public var share: PersonalShare
    public var recurrence: Recurrence
    public var destinationAccountID: UUID?
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        grossAmount: Money,
        share: PersonalShare = .percentageBasisPoints(10_000),
        recurrence: Recurrence = .monthly(day: 5),
        destinationAccountID: UUID? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.grossAmount = grossAmount
        self.share = share
        self.recurrence = recurrence
        self.destinationAccountID = destinationAccountID
        self.isActive = isActive
    }

    public var personalAmount: Money { share.personalAmount(of: grossAmount) }
}
