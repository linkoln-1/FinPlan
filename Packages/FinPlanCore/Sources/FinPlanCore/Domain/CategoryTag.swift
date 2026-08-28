import Foundation

public struct TransactionCategory: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var symbolName: String
    public var isArchived: Bool
    public var isEssential: Bool

    public init(id: UUID = UUID(), name: String, symbolName: String, isArchived: Bool = false, isEssential: Bool = false) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.isArchived = isArchived
        self.isEssential = isEssential
    }
}

public extension TransactionCategory {
    static func defaults() -> [TransactionCategory] {
        [
            TransactionCategory(name: "Food", symbolName: "fork.knife", isEssential: true),
            TransactionCategory(name: "Transport", symbolName: "car.fill", isEssential: true),
            TransactionCategory(name: "Home", symbolName: "house.fill", isEssential: true),
            TransactionCategory(name: "Shopping", symbolName: "bag.fill"),
            TransactionCategory(name: "Technology", symbolName: "laptopcomputer"),
            TransactionCategory(name: "Entertainment", symbolName: "gamecontroller.fill"),
            TransactionCategory(name: "Health", symbolName: "cross.case.fill", isEssential: true),
            TransactionCategory(name: "Education", symbolName: "book.fill"),
            TransactionCategory(name: "Gifts", symbolName: "gift.fill"),
            TransactionCategory(name: "Subscriptions", symbolName: "arrow.triangle.2.circlepath"),
            TransactionCategory(name: "Travel", symbolName: "airplane"),
            TransactionCategory(name: "Taxes", symbolName: "building.columns.fill", isEssential: true),
            TransactionCategory(name: "Other", symbolName: "ellipsis.circle.fill"),
        ]
    }
}

public struct TransactionTag: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}
