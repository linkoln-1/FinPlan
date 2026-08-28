import Foundation
import Observation
import SwiftUI
import FinPlanCore

struct TransactionsFilter: Equatable {
    var accountID: UUID?
    var kind: TransactionKind?
    var categoryID: UUID?
    var tagID: UUID?
    var status: TransactionStatus?
    var startDate: Date?
    var endDate: Date?
    var currencyCode: String?

    var isActive: Bool {
        accountID != nil || kind != nil || categoryID != nil || tagID != nil
            || status != nil || startDate != nil || endDate != nil || currencyCode != nil
    }
}

struct TransactionsRowItem: Identifiable {
    let record: TransactionRecord
    let categoryName: String?
    let categorySymbol: String?
    let subtitle: String?
    var id: UUID { record.id }
}

enum TransactionsDayKind: Hashable {
    case today
    case yesterday
    case other
}

struct TransactionsDaySection: Identifiable {
    let day: Date
    let kind: TransactionsDayKind
    let rows: [TransactionsRowItem]
    var id: Date { day }
}

enum TransactionsLabels {
    static func kindKey(_ kind: TransactionKind) -> LocalizedStringKey {
        switch kind {
        case .expense: "transactions.kind.expense"
        case .income: "transactions.kind.income"
        case .transfer: "transactions.kind.transfer"
        case .currencyExchange: "transactions.kind.exchange"
        case .adjustment: "transactions.kind.adjustment"
        }
    }

    static func statusKey(_ status: TransactionStatus) -> LocalizedStringKey {
        switch status {
        case .planned: "transactions.status.planned"
        case .expected: "transactions.status.expected"
        case .completed: "transactions.status.completed"
        case .skipped: "transactions.status.skipped"
        case .cancelled: "transactions.status.cancelled"
        }
    }
}

@MainActor
@Observable
final class TransactionsListModel {
    var filter = TransactionsFilter() { didSet { rebuild() } }
    var searchText = "" { didSet { rebuild() } }

    private(set) var sections: [TransactionsDaySection] = []
    private(set) var hasAnyTransactions = false
    private(set) var currencyCodes: [String] = []

    private var transactions: [TransactionRecord] = []
    private var categoriesByID: [UUID: TransactionCategory] = [:]
    private var tagsByID: [UUID: TransactionTag] = [:]
    private var accountsByID: [UUID: Account] = [:]
    private let calendar = Calendar.current

    func update(
        transactions: [TransactionRecord],
        categories: [TransactionCategory],
        tags: [TransactionTag],
        accounts: [Account]
    ) {
        self.transactions = transactions
        categoriesByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        tagsByID = Dictionary(tags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        accountsByID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        currencyCodes = Set(accounts.map(\.currency.code))
            .union(transactions.map(\.amount.currency.code))
            .sorted()
        rebuild()
    }

    private func rebuild() {
        hasAnyTransactions = !transactions.isEmpty
        let filtered = transactions.filter { matches($0) }
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        sections = grouped.keys.sorted(by: >).map { day in
            let rows = (grouped[day] ?? [])
                .sorted { $0.date > $1.date }
                .map { rowItem(for: $0) }
            return TransactionsDaySection(day: day, kind: dayKind(day), rows: rows)
        }
    }

    private func dayKind(_ day: Date) -> TransactionsDayKind {
        if calendar.isDateInToday(day) { return .today }
        if calendar.isDateInYesterday(day) { return .yesterday }
        return .other
    }

    private func rowItem(for record: TransactionRecord) -> TransactionsRowItem {
        let categoryName: String?
        let categorySymbol: String?
        if record.splits.isEmpty {
            let category = record.categoryID.flatMap { categoriesByID[$0] }
            categoryName = category?.name
            categorySymbol = category?.symbolName
        } else {
            let names = record.splits.compactMap { split in
                split.categoryID.flatMap { categoriesByID[$0]?.name }
            }
            categoryName = names.isEmpty ? nil : names.joined(separator: " + ")
            categorySymbol = "square.split.2x1"
        }

        var pieces: [String] = []
        switch record.kind {
        case .transfer, .currencyExchange, .adjustment:
            if let route = accountRoute(for: record) { pieces.append(route) }
            if let note = record.note, !note.isEmpty { pieces.append(note) }
        case .expense, .income:
            if let note = record.note, !note.isEmpty { pieces.append(note) }
        }
        let tagNames = record.tagIDs.compactMap { tagsByID[$0]?.name }
        if !tagNames.isEmpty {
            pieces.append(tagNames.map { "#\($0)" }.joined(separator: " "))
        }

        return TransactionsRowItem(
            record: record,
            categoryName: categoryName,
            categorySymbol: categorySymbol,
            subtitle: pieces.isEmpty ? nil : pieces.joined(separator: " · ")
        )
    }

    private func accountRoute(for record: TransactionRecord) -> String? {
        let source = record.sourceAccountID.flatMap { accountsByID[$0]?.name }
        let destination = record.destinationAccountID.flatMap { accountsByID[$0]?.name }
        switch (source, destination) {
        case (let source?, let destination?): return "\(source) → \(destination)"
        case (let source?, nil): return source
        case (nil, let destination?): return destination
        case (nil, nil): return nil
        }
    }

    private func matches(_ record: TransactionRecord) -> Bool {
        if let accountID = filter.accountID,
           record.sourceAccountID != accountID, record.destinationAccountID != accountID {
            return false
        }
        if let kind = filter.kind, record.kind != kind { return false }
        if let categoryID = filter.categoryID,
           record.categoryID != categoryID,
           !record.splits.contains(where: { $0.categoryID == categoryID }) {
            return false
        }
        if let tagID = filter.tagID, !record.tagIDs.contains(tagID) { return false }
        if let status = filter.status, record.status != status { return false }
        if let start = filter.startDate, record.date < calendar.startOfDay(for: start) { return false }
        if let end = filter.endDate {
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
            if record.date >= endOfDay { return false }
        }
        if let code = filter.currencyCode,
           record.amount.currency.code != code, record.counterAmount?.currency.code != code {
            return false
        }
        if !searchText.isEmpty, !matchesSearch(record) { return false }
        return true
    }

    private func matchesSearch(_ record: TransactionRecord) -> Bool {
        let query = searchText
        if let note = record.note, note.localizedStandardContains(query) { return true }
        if let categoryID = record.categoryID,
           let name = categoriesByID[categoryID]?.name,
           name.localizedStandardContains(query) {
            return true
        }
        for split in record.splits {
            if let id = split.categoryID,
               let name = categoriesByID[id]?.name,
               name.localizedStandardContains(query) {
                return true
            }
        }
        for tagID in record.tagIDs {
            if let name = tagsByID[tagID]?.name, name.localizedStandardContains(query) {
                return true
            }
        }
        return false
    }
}
