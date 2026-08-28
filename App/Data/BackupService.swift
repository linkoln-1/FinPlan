import Foundation
import FinPlanCore

struct BackupService {
    static let currentSchemaVersion = 1

    struct BackupDocument: Codable {
        var schemaVersion: Int
        var exportedAt: Date
        var baseCurrency: Currency
        var planningRates: ManualExchangeRates
        var minimumCashBufferMinor: Int64
        var accounts: [Account]
        var categories: [TransactionCategory]
        var tags: [TransactionTag]
        var transactions: [TransactionRecord]
        var goals: [Goal]
        var allocations: [GoalAllocation]
        var incomeSources: [IncomeSource]
        var budgets: [Budget]
        var recurringTemplates: [RecurringTemplate]
        var expectedEvents: [ExpectedEvent]
    }

    enum ImportError: LocalizedError, Equatable {
        case unreadable
        case unsupportedSchema(Int)
        case inconsistent(String)

        var errorDescription: String? {
            switch self {
            case .unreadable: return String(localized: "import.error.unreadable")
            case .unsupportedSchema(let version): return String(localized: "import.error.schema \(version)")
            case .inconsistent(let reason): return String(localized: "import.error.inconsistent \(reason)")
            }
        }
    }

    @MainActor
    static func exportJSON(from store: FinanceStore) throws -> Data {
        let document = BackupDocument(
            schemaVersion: currentSchemaVersion,
            exportedAt: Date(),
            baseCurrency: store.baseCurrency,
            planningRates: store.planningRates,
            minimumCashBufferMinor: store.minimumCashBuffer.amountMinor,
            accounts: store.accounts,
            categories: store.categories,
            tags: store.tags,
            transactions: store.transactions,
            goals: store.goals,
            allocations: store.allocations,
            incomeSources: store.incomeSources,
            budgets: store.budgets,
            recurringTemplates: store.recurringTemplates,
            expectedEvents: store.expectedEvents
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    @MainActor
    static func exportCSV(from store: FinanceStore) -> String {
        var lines = ["id,date,kind,status,amount,currency,source_account,destination_account,category,note"]
        let formatter = ISO8601DateFormatter()
        let accountNames = Dictionary(uniqueKeysWithValues: store.accounts.map { ($0.id, $0.name) })
        let categoryNames = Dictionary(uniqueKeysWithValues: store.categories.map { ($0.id, $0.name) })
        for record in store.transactions {
            let fields = [
                record.id.uuidString,
                formatter.string(from: record.date),
                record.kind.rawValue,
                record.status.rawValue,
                decimalString(record.amount),
                record.amount.currency.code,
                record.sourceAccountID.flatMap { accountNames[$0] } ?? "",
                record.destinationAccountID.flatMap { accountNames[$0] } ?? "",
                record.categoryID.flatMap { categoryNames[$0] } ?? "",
                record.note ?? "",
            ]
            lines.append(fields.map(escapeCSV).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func decimalString(_ money: Money) -> String {
        let perMajor = money.currency.minorUnitsPerMajor
        let major = money.amountMinor / perMajor
        let minor = abs(money.amountMinor % perMajor)
        guard money.currency.minorUnitExponent > 0 else { return "\(major)" }
        let sign = money.amountMinor < 0 && major == 0 ? "-" : ""
        let minorDigits = String(minor).leftPadded(to: money.currency.minorUnitExponent)
        return "\(sign)\(major).\(minorDigits)"
    }

    private static func escapeCSV(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    static func validateImport(_ data: Data) throws -> BackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(BackupDocument.self, from: data) else {
            throw ImportError.unreadable
        }
        guard document.schemaVersion <= currentSchemaVersion else {
            throw ImportError.unsupportedSchema(document.schemaVersion)
        }
        let accountIDs = Set(document.accounts.map(\.id))
        let goalIDs = Set(document.goals.map(\.id))
        for record in document.transactions {
            for reference in [record.sourceAccountID, record.destinationAccountID].compactMap({ $0 }) {
                guard accountIDs.contains(reference) else {
                    throw ImportError.inconsistent("transaction \(record.id) references unknown account")
                }
            }
            do { try record.validate() } catch {
                throw ImportError.inconsistent("transaction \(record.id) invalid: \(error)")
            }
        }
        for allocation in document.allocations {
            guard goalIDs.contains(allocation.goalID), accountIDs.contains(allocation.accountID) else {
                throw ImportError.inconsistent("allocation \(allocation.id) references unknown goal/account")
            }
        }
        return document
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
