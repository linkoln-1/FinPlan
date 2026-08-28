import Foundation

public enum AccountType: String, Sendable, Codable, CaseIterable {
    case cash, checking, savings, investment, credit, other
}

public struct Account: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var currency: Currency
    public var type: AccountType
    public var openingBalance: Money
    public var includedInNetWorth: Bool
    public var includedInSafeToSpend: Bool
    public var isArchived: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        currency: Currency,
        type: AccountType,
        openingBalance: Money? = nil,
        includedInNetWorth: Bool = true,
        includedInSafeToSpend: Bool = true,
        isArchived: Bool = false,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.currency = currency
        self.type = type
        self.openingBalance = openingBalance ?? .zero(currency)
        self.includedInNetWorth = includedInNetWorth
        self.includedInSafeToSpend = includedInSafeToSpend
        self.isArchived = isArchived
        self.createdAt = createdAt
    }

    public var isLiability: Bool { type == .credit }
}
