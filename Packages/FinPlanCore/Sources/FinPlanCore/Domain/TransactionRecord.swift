import Foundation

public enum TransactionKind: String, Sendable, Codable, CaseIterable {
    case income, expense, transfer, currencyExchange, adjustment
}

public enum TransactionStatus: String, Sendable, Codable, CaseIterable {
    case planned, expected, completed, skipped, cancelled

    public var affectsActualBalance: Bool { self == .completed }
}

public struct TransactionSplit: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var categoryID: UUID?
    public var amount: Money
    public var note: String?

    public init(id: UUID = UUID(), categoryID: UUID?, amount: Money, note: String? = nil) {
        self.id = id
        self.categoryID = categoryID
        self.amount = amount
        self.note = note
    }
}

public struct AttachmentReference: Hashable, Sendable, Codable {
    public let id: UUID
    public var fileName: String
    public var uti: String

    public init(id: UUID = UUID(), fileName: String, uti: String) {
        self.id = id
        self.fileName = fileName
        self.uti = uti
    }
}

public enum TransactionValidationError: Error, Equatable, Sendable {
    case nonPositiveAmount
    case missingSourceAccount
    case missingDestinationAccount
    case sameAccountTransfer
    case splitTotalMismatch(expected: Int64, actual: Int64)
    case splitCurrencyMismatch
    case exchangeMissingCounterAmount
    case exchangeSameCurrency
}

public struct TransactionRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var date: Date
    public var kind: TransactionKind
    public var status: TransactionStatus
    public var amount: Money
    public var sourceAccountID: UUID?
    public var destinationAccountID: UUID?
    public var counterAmount: Money?
    public var fee: Money?
    public var categoryID: UUID?
    public var goalID: UUID?
    public var note: String?
    public var tagIDs: [UUID]
    public var splits: [TransactionSplit]
    public var recurringTemplateID: UUID?
    public var attachments: [AttachmentReference]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        date: Date,
        kind: TransactionKind,
        status: TransactionStatus = .completed,
        amount: Money,
        sourceAccountID: UUID? = nil,
        destinationAccountID: UUID? = nil,
        counterAmount: Money? = nil,
        fee: Money? = nil,
        categoryID: UUID? = nil,
        goalID: UUID? = nil,
        note: String? = nil,
        tagIDs: [UUID] = [],
        splits: [TransactionSplit] = [],
        recurringTemplateID: UUID? = nil,
        attachments: [AttachmentReference] = [],
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.status = status
        self.amount = amount
        self.sourceAccountID = sourceAccountID
        self.destinationAccountID = destinationAccountID
        self.counterAmount = counterAmount
        self.fee = fee
        self.categoryID = categoryID
        self.goalID = goalID
        self.note = note
        self.tagIDs = tagIDs
        self.splits = splits
        self.recurringTemplateID = recurringTemplateID
        self.attachments = attachments
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public func validate() throws(TransactionValidationError) {
        switch kind {
        case .income:
            guard amount.isPositive else { throw .nonPositiveAmount }
            guard destinationAccountID != nil else { throw .missingDestinationAccount }
        case .expense:
            guard amount.isPositive else { throw .nonPositiveAmount }
            guard sourceAccountID != nil else { throw .missingSourceAccount }
        case .transfer:
            guard amount.isPositive else { throw .nonPositiveAmount }
            guard let source = sourceAccountID else { throw .missingSourceAccount }
            guard let destination = destinationAccountID else { throw .missingDestinationAccount }
            guard source != destination else { throw .sameAccountTransfer }
        case .currencyExchange:
            guard amount.isPositive else { throw .nonPositiveAmount }
            guard sourceAccountID != nil else { throw .missingSourceAccount }
            guard destinationAccountID != nil else { throw .missingDestinationAccount }
            guard let counter = counterAmount, counter.isPositive else { throw .exchangeMissingCounterAmount }
            guard counter.currency != amount.currency else { throw .exchangeSameCurrency }
        case .adjustment:
            guard sourceAccountID != nil || destinationAccountID != nil else { throw .missingSourceAccount }
        }
        if !splits.isEmpty {
            guard splits.allSatisfy({ $0.amount.currency == amount.currency }) else {
                throw .splitCurrencyMismatch
            }
            let total = splits.reduce(Int64(0)) { $0 + $1.amount.amountMinor }
            guard total == amount.amountMinor else {
                throw .splitTotalMismatch(expected: amount.amountMinor, actual: total)
            }
        }
    }
}
