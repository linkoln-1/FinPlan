import Foundation
import Observation
import FinPlanCore

enum TransactionsFeeSide: String, CaseIterable, Hashable {
    case source, destination
}

enum TransactionsAdjustmentDirection: String, CaseIterable, Hashable {
    case increase, decrease
}

struct TransactionsSplitDraft: Identifiable {
    let id = UUID()
    var categoryID: UUID?
    var amountText: String = ""
    var amountMinor: Int64?
}

@MainActor
@Observable
final class TransactionsEditorModel {
    let original: TransactionRecord?

    var kind: TransactionKind
    var status: TransactionStatus
    var date: Date
    var amountText: String
    var amountMinor: Int64?
    var sourceAccountID: UUID?
    var destinationAccountID: UUID?
    var counterText: String
    var counterMinor: Int64?
    var feeText: String
    var feeMinor: Int64?
    var feeSide: TransactionsFeeSide
    var categoryID: UUID?
    var goalID: UUID?
    var note: String
    var tagIDs: Set<UUID>
    var adjustmentDirection: TransactionsAdjustmentDirection
    var splitsEnabled: Bool
    var splits: [TransactionsSplitDraft]

    init(record: TransactionRecord?, defaultKind: TransactionKind) {
        original = record
        if let record {
            kind = record.kind
            status = record.status
            date = record.date
            amountText = Self.editText(for: record.amount)
            amountMinor = record.amount.amountMinor
            sourceAccountID = record.kind == .adjustment
                ? (record.sourceAccountID ?? record.destinationAccountID)
                : record.sourceAccountID
            destinationAccountID = record.destinationAccountID
            counterText = record.counterAmount.map { Self.editText(for: $0) } ?? ""
            counterMinor = record.counterAmount?.amountMinor
            feeText = record.fee.map { Self.editText(for: $0) } ?? ""
            feeMinor = record.fee?.amountMinor
            feeSide = record.fee != nil && record.fee?.currency == record.counterAmount?.currency
                ? .destination
                : .source
            categoryID = record.categoryID
            goalID = record.goalID
            note = record.note ?? ""
            tagIDs = Set(record.tagIDs)
            adjustmentDirection = record.kind == .adjustment && record.sourceAccountID != nil
                ? .decrease
                : .increase
            splitsEnabled = !record.splits.isEmpty
            splits = record.splits.map {
                TransactionsSplitDraft(
                    categoryID: $0.categoryID,
                    amountText: Self.editText(for: $0.amount),
                    amountMinor: $0.amount.amountMinor
                )
            }
        } else {
            kind = defaultKind
            status = .completed
            date = Date()
            amountText = ""
            amountMinor = nil
            sourceAccountID = nil
            destinationAccountID = nil
            counterText = ""
            counterMinor = nil
            feeText = ""
            feeMinor = nil
            feeSide = .source
            categoryID = nil
            goalID = nil
            note = ""
            tagIDs = []
            adjustmentDirection = .increase
            splitsEnabled = false
            splits = []
        }
    }

    var availableKinds: [TransactionKind] {
        if original?.kind == .adjustment {
            return [.expense, .income, .transfer, .currencyExchange, .adjustment]
        }
        return [.expense, .income, .transfer, .currencyExchange]
    }

    func selectableAccounts(in accounts: [Account]) -> [Account] {
        accounts.filter {
            !$0.isArchived
                || $0.id == original?.sourceAccountID
                || $0.id == original?.destinationAccountID
        }
    }

    func account(_ id: UUID?, in accounts: [Account]) -> Account? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    func transferDestinationCandidates(accounts: [Account]) -> [Account] {
        guard let source = account(sourceAccountID, in: accounts) else { return [] }
        return selectableAccounts(in: accounts).filter {
            $0.id != source.id && $0.currency == source.currency
        }
    }

    func exchangeDestinationCandidates(accounts: [Account]) -> [Account] {
        guard let source = account(sourceAccountID, in: accounts) else { return [] }
        return selectableAccounts(in: accounts).filter {
            $0.id != source.id && $0.currency != source.currency
        }
    }

    func ensureValidSelections(accounts: [Account]) {
        let selectable = selectableAccounts(in: accounts)
        if account(sourceAccountID, in: selectable) == nil {
            sourceAccountID = selectable.first?.id
        }
        switch kind {
        case .income:
            if account(destinationAccountID, in: selectable) == nil {
                destinationAccountID = selectable.first?.id
            }
        case .transfer:
            let candidates = transferDestinationCandidates(accounts: accounts)
            if !candidates.contains(where: { $0.id == destinationAccountID }) {
                destinationAccountID = candidates.first?.id
            }
        case .currencyExchange:
            let candidates = exchangeDestinationCandidates(accounts: accounts)
            if !candidates.contains(where: { $0.id == destinationAccountID }) {
                destinationAccountID = candidates.first?.id
            }
        case .expense, .adjustment:
            break
        }
    }

    func amountCurrency(accounts: [Account]) -> Currency? {
        switch kind {
        case .income:
            return account(destinationAccountID, in: accounts)?.currency
        case .expense, .transfer, .currencyExchange, .adjustment:
            return account(sourceAccountID, in: accounts)?.currency
        }
    }

    func counterCurrency(accounts: [Account]) -> Currency? {
        account(destinationAccountID, in: accounts)?.currency
    }

    func feeCurrency(accounts: [Account]) -> Currency? {
        switch feeSide {
        case .source: amountCurrency(accounts: accounts)
        case .destination: counterCurrency(accounts: accounts)
        }
    }

    func reparse(accounts: [Account], fallback: Currency) {
        let currency = amountCurrency(accounts: accounts) ?? fallback
        amountMinor = MoneyParser.minorUnits(from: amountText, currency: currency)
        let counter = counterCurrency(accounts: accounts) ?? fallback
        counterMinor = MoneyParser.minorUnits(from: counterText, currency: counter)
        let fee = feeCurrency(accounts: accounts) ?? fallback
        feeMinor = MoneyParser.minorUnits(from: feeText, currency: fee)
        for index in splits.indices {
            splits[index].amountMinor = MoneyParser.minorUnits(from: splits[index].amountText, currency: currency)
        }
    }

    func splitRemainder(accounts: [Account], fallback: Currency) -> Money? {
        let currency = amountCurrency(accounts: accounts) ?? fallback
        let parent = Money(minor: amountMinor ?? 0, currency: currency)
        do {
            var total = Money.zero(currency)
            for row in splits {
                total = try total.adding(Money(minor: row.amountMinor ?? 0, currency: currency))
            }
            return try parent.subtracting(total)
        } catch {
            return nil
        }
    }

    private func splitsAreValid(accounts: [Account], fallback: Currency) -> Bool {
        guard !splits.isEmpty else { return false }
        guard splits.allSatisfy({ ($0.amountMinor ?? 0) > 0 }) else { return false }
        guard let remainder = splitRemainder(accounts: accounts, fallback: fallback) else { return false }
        return remainder.isZero
    }

    func canSave(accounts: [Account], fallback: Currency) -> Bool {
        guard let amount = amountMinor, amount > 0 else { return false }
        switch kind {
        case .expense:
            guard sourceAccountID != nil else { return false }
            if splitsEnabled {
                guard splitsAreValid(accounts: accounts, fallback: fallback) else { return false }
            }
        case .income:
            guard destinationAccountID != nil else { return false }
        case .transfer:
            guard let source = sourceAccountID,
                  let destination = destinationAccountID,
                  source != destination else { return false }
        case .currencyExchange:
            guard let source = account(sourceAccountID, in: accounts),
                  let destination = account(destinationAccountID, in: accounts),
                  source.currency != destination.currency,
                  let counter = counterMinor, counter > 0 else { return false }
            if !feeText.isEmpty, feeMinor == nil { return false }
            if let fee = feeMinor, fee < 0 { return false }
        case .adjustment:
            guard sourceAccountID != nil else { return false }
        }
        return true
    }

    func buildRecord(accounts: [Account]) -> TransactionRecord? {
        guard let currency = amountCurrency(accounts: accounts),
              let amountMinor, amountMinor > 0 else { return nil }
        let amount = Money(minor: amountMinor, currency: currency)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        var source: UUID?
        var destination: UUID?
        var counter: Money?
        var fee: Money?
        var category: UUID?
        var goal: UUID? = original?.goalID
        var recordSplits: [TransactionSplit] = []

        switch kind {
        case .expense:
            source = sourceAccountID
            if splitsEnabled, !splits.isEmpty {
                recordSplits = splits.compactMap { row in
                    guard let minor = row.amountMinor else { return nil }
                    return TransactionSplit(categoryID: row.categoryID, amount: Money(minor: minor, currency: currency))
                }
                guard recordSplits.count == splits.count else { return nil }
            } else {
                category = categoryID
            }
        case .income:
            destination = destinationAccountID
            category = categoryID
        case .transfer:
            source = sourceAccountID
            destination = destinationAccountID
            goal = goalID
            fee = original?.fee
        case .currencyExchange:
            source = sourceAccountID
            destination = destinationAccountID
            guard let counterCurrency = counterCurrency(accounts: accounts),
                  let counterMinor, counterMinor > 0 else { return nil }
            counter = Money(minor: counterMinor, currency: counterCurrency)
            if let feeMinor, feeMinor > 0, let feeCurrency = feeCurrency(accounts: accounts) {
                fee = Money(minor: feeMinor, currency: feeCurrency)
            }
        case .adjustment:
            switch adjustmentDirection {
            case .increase: destination = sourceAccountID
            case .decrease: source = sourceAccountID
            }
        }

        return TransactionRecord(
            id: original?.id ?? UUID(),
            date: date,
            kind: kind,
            status: status,
            amount: amount,
            sourceAccountID: source,
            destinationAccountID: destination,
            counterAmount: counter,
            fee: fee,
            categoryID: category,
            goalID: goal,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            tagIDs: Array(tagIDs),
            splits: recordSplits,
            recurringTemplateID: original?.recurringTemplateID,
            attachments: original?.attachments ?? [],
            createdAt: original?.createdAt ?? Date()
        )
    }

    func derivedRate(accounts: [Account]) -> ExchangeRate? {
        guard kind == .currencyExchange,
              let source = account(sourceAccountID, in: accounts),
              let destination = account(destinationAccountID, in: accounts),
              source.currency != destination.currency,
              let amountMinor, amountMinor > 0,
              let counterMinor, counterMinor > 0 else { return nil }
        let scale = 6
        var numerator = Int128(counterMinor)
        var denominator = Int128(amountMinor)
        let shift = scale + source.currency.minorUnitExponent - destination.currency.minorUnitExponent
        if shift >= 0 {
            for _ in 0..<shift { numerator *= 10 }
        } else {
            for _ in 0..<(-shift) { denominator *= 10 }
        }
        let quotient = numerator / denominator
        let remainder = numerator % denominator
        let rounded = remainder * 2 >= denominator ? quotient + 1 : quotient
        guard let scaled = Int64(exactly: rounded), scaled > 0 else { return nil }
        return ExchangeRate(base: source.currency, quote: destination.currency, rateScaled: scaled, scale: scale)
    }

    static func rateDisplay(_ rate: ExchangeRate) -> String {
        var divisor = Decimal(1)
        for _ in 0..<rate.scale { divisor *= 10 }
        let value = (Decimal(rate.rateScaled) / divisor)
            .formatted(.number.precision(.fractionLength(0...rate.scale)))
        return "1 \(rate.base.code) ≈ \(value) \(rate.quote.code)"
    }

    static func orderedCategories(
        all: [TransactionCategory],
        recentTransactions: [TransactionRecord]
    ) -> [TransactionCategory] {
        let active = all.filter { !$0.isArchived }
        var recentIDs: [UUID] = []
        for record in recentTransactions.prefix(20) {
            if let id = record.categoryID { recentIDs.append(id) }
            for split in record.splits {
                if let id = split.categoryID { recentIDs.append(id) }
            }
        }
        var seen = Set<UUID>()
        var ordered: [TransactionCategory] = []
        for id in recentIDs where !seen.contains(id) {
            if let category = active.first(where: { $0.id == id }) {
                seen.insert(id)
                ordered.append(category)
            }
        }
        return ordered + active.filter { !seen.contains($0.id) }
    }

    private static func editText(for money: Money) -> String {
        var divisor = Decimal(1)
        for _ in 0..<money.currency.minorUnitExponent { divisor *= 10 }
        return (Decimal(money.amountMinor) / divisor)
            .formatted(.number.grouping(.never).precision(.fractionLength(0...money.currency.minorUnitExponent)))
    }
}
