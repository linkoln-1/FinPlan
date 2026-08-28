import AppIntents
import Foundation
import FinPlanCore

struct AccountEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "intent.entity.account")
    static let defaultQuery = AccountEntityQuery()

    let id: UUID
    let name: String
    let currencyCode: String

    init(account: Account) {
        self.id = account.id
        self.name = account.name
        self.currencyCode = account.currency.code
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(currencyCode)")
    }
}

struct AccountEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        IntentBridge.shared.resolveStore().accounts
            .filter { identifiers.contains($0.id) }
            .map(AccountEntity.init(account:))
    }

    @MainActor
    func suggestedEntities() async throws -> [AccountEntity] {
        IntentBridge.shared.resolveStore().accounts
            .filter { !$0.isArchived }
            .map(AccountEntity.init(account:))
    }
}

struct CategoryEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "intent.entity.category")
    static let defaultQuery = CategoryEntityQuery()

    let id: UUID
    let name: String

    init(category: TransactionCategory) {
        self.id = category.id
        self.name = category.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CategoryEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        IntentBridge.shared.resolveStore().categories
            .filter { identifiers.contains($0.id) }
            .map(CategoryEntity.init(category:))
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        IntentBridge.shared.resolveStore().categories
            .filter { !$0.isArchived }
            .map(CategoryEntity.init(category:))
    }
}

struct AccountCurrencyOptionsProvider: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [String] {
        var seen = Set<String>()
        return IntentBridge.shared.resolveStore().accounts
            .filter { !$0.isArchived }
            .compactMap { seen.insert($0.currency.code).inserted ? $0.currency.code : nil }
    }
}

enum FinPlanIntentError: Error, CustomLocalizedStringResourceConvertible {
    case invalidAmount
    case accountNotFound
    case currencyMismatch
    case noPrimaryGoal

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidAmount: "intent.error.invalidAmount"
        case .accountNotFound: "intent.error.accountNotFound"
        case .currencyMismatch: "intent.error.currencyMismatch"
        case .noPrimaryGoal: "intent.error.noPrimaryGoal"
        }
    }
}

@MainActor
enum IntentSupport {
    static func primaryGoal(in goals: [Goal]) -> Goal? {
        goals
            .filter { $0.status == .active && !$0.isEmergencyFund }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first
    }

    static func parseAmount(
        text: String,
        currencyCode: String,
        account: Account
    ) throws -> Money {
        guard account.currency.code == currencyCode.uppercased() else {
            throw FinPlanIntentError.currencyMismatch
        }
        let currency = account.currency
        guard let minor = MoneyParser.minorUnits(from: text, currency: currency), minor > 0 else {
            throw FinPlanIntentError.invalidAmount
        }
        return Money(minor: minor, currency: currency)
    }

    static func account(for entity: AccountEntity, in store: FinanceStore) throws -> Account {
        guard let account = store.accounts.first(where: { $0.id == entity.id }), !account.isArchived else {
            throw FinPlanIntentError.accountNotFound
        }
        return account
    }

    static func categoryID(for entity: CategoryEntity?, in store: FinanceStore) -> UUID? {
        guard let entity else { return nil }
        return store.categories.first(where: { $0.id == entity.id })?.id
    }

    static func normalizedNote(_ note: String?) -> String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}
