import Foundation
import SwiftData
import FinPlanCore
import Observation

@MainActor
@Observable
final class FinanceStore {
    private let context: ModelContext

    private(set) var accounts: [Account] = []
    private(set) var categories: [TransactionCategory] = []
    private(set) var tags: [TransactionTag] = []
    private(set) var transactions: [TransactionRecord] = []
    private(set) var goals: [Goal] = []
    private(set) var allocations: [GoalAllocation] = []
    private(set) var incomeSources: [IncomeSource] = []
    private(set) var budgets: [Budget] = []
    private(set) var recurringTemplates: [RecurringTemplate] = []
    private(set) var expectedEvents: [ExpectedEvent] = []

    var baseCurrency: Currency { settingsModel.baseCurrency }
    var planningRates: ManualExchangeRates {
        get { settingsModel.planningRates }
        set { settingsModel.planningRates = newValue; save() }
    }
    var minimumCashBuffer: Money {
        get { Money(minor: settingsModel.minimumCashBufferMinor, currency: baseCurrency) }
        set { settingsModel.minimumCashBufferMinor = newValue.amountMinor; save() }
    }
    var requireBiometrics: Bool {
        get { settingsModel.requireBiometrics }
        set { settingsModel.requireBiometrics = newValue; save() }
    }
    var hideBalances: Bool {
        get { settingsModel.hideBalances }
        set { settingsModel.hideBalances = newValue; save() }
    }
    var onboardingCompleted: Bool {
        get { settingsModel.onboardingCompleted }
        set { settingsModel.onboardingCompleted = newValue; save() }
    }

    private var settingsModel: AppSettingsModel

    init(context: ModelContext) {
        self.context = context
        if let existing = (try? context.fetch(FetchDescriptor<AppSettingsModel>()))?.first {
            settingsModel = existing
        } else {
            let created = AppSettingsModel()
            context.insert(created)
            settingsModel = created
        }
        seedDefaultCategoriesIfNeeded()
        reload()
    }

    func setBaseCurrency(_ currency: Currency) {
        settingsModel.baseCurrency = currency
        save()
    }

    func reload() {
        accounts = fetchMapped(AccountModel.self) { $0.toDomain() }
        categories = fetchMapped(CategoryModel.self) { $0.toDomain() }
        tags = fetchMapped(TagModel.self) { $0.toDomain() }
        transactions = fetchMapped(TransactionModel.self) { $0.toDomain() }
            .sorted { $0.date > $1.date }
        goals = fetchMapped(GoalModel.self) { $0.toDomain() }
        allocations = fetchMapped(AllocationModel.self) { $0.toDomain() }
        incomeSources = fetchMapped(IncomeSourceModel.self) { $0.toDomain() }
        budgets = fetchMapped(BudgetModel.self) { $0.toDomain() }
        recurringTemplates = fetchMapped(RecurringTemplateModel.self) { $0.toDomain() }
        expectedEvents = fetchMapped(ExpectedEventModel.self) { $0.toDomain() }
        #if canImport(WidgetKit)
        WidgetSnapshotWriter.publish(from: self)
        #endif
        NotificationService.shared.scheduleRefresh(from: self)
    }

    private func fetchMapped<M: PersistentModel, D>(_ type: M.Type, _ transform: (M) -> D) -> [D] {
        ((try? context.fetch(FetchDescriptor<M>())) ?? []).map(transform)
    }

    enum StoreError: LocalizedError {
        case validationFailed(String)
        case notFound

        var errorDescription: String? {
            switch self {
            case .validationFailed(let reason): return reason
            case .notFound: return String(localized: "error.notFound")
            }
        }
    }

    func addAccount(_ account: Account) {
        context.insert(AccountModel(from: account))
        save()
        reload()
    }

    func updateAccount(_ account: Account) throws {
        let model = try fetchOne(AccountModel.self, id: account.id)
        context.delete(model)
        context.insert(AccountModel(from: account))
        save()
        reload()
    }

    func addTransaction(_ record: TransactionRecord) throws {
        do {
            try record.validate()
        } catch {
            throw StoreError.validationFailed(String(describing: error))
        }
        context.insert(TransactionModel(from: record))
        save()
        reload()
    }

    func updateTransaction(_ record: TransactionRecord) throws {
        do {
            try record.validate()
        } catch {
            throw StoreError.validationFailed(String(describing: error))
        }
        let model = try fetchOne(TransactionModel.self, id: record.id)
        context.delete(model)
        var updated = record
        updated.updatedAt = Date()
        context.insert(TransactionModel(from: updated))
        save()
        reload()
    }

    func deleteTransaction(id: UUID) throws {
        let model = try fetchOne(TransactionModel.self, id: id)
        context.delete(model)
        save()
        reload()
    }

    func addGoal(_ goal: Goal) {
        context.insert(GoalModel(from: goal))
        save()
        reload()
    }

    func updateGoal(_ goal: Goal) throws {
        let model = try fetchOne(GoalModel.self, id: goal.id)
        context.delete(model)
        context.insert(GoalModel(from: goal))
        save()
        reload()
    }

    func addAllocation(_ allocation: GoalAllocation) {
        context.insert(AllocationModel(from: allocation))
        save()
        reload()
    }

    func addIncomeSource(_ source: IncomeSource) {
        context.insert(IncomeSourceModel(from: source))
        save()
        reload()
    }

    func updateIncomeSource(_ source: IncomeSource) throws {
        let model = try fetchOne(IncomeSourceModel.self, id: source.id)
        context.delete(model)
        context.insert(IncomeSourceModel(from: source))
        save()
        reload()
    }

    func addCategory(_ category: TransactionCategory) {
        context.insert(CategoryModel(from: category))
        save()
        reload()
    }

    func addTag(_ tag: TransactionTag) {
        context.insert(TagModel(from: tag))
        save()
        reload()
    }

    func addBudget(_ budget: Budget) {
        context.insert(BudgetModel(from: budget))
        save()
        reload()
    }

    func addRecurringTemplate(_ template: RecurringTemplate) {
        context.insert(RecurringTemplateModel(from: template))
        save()
        reload()
    }

    func updateRecurringTemplate(_ template: RecurringTemplate) throws {
        guard template.amount.isPositive else {
            throw StoreError.validationFailed(String(localized: "error.recurring.amountNotPositive"))
        }
        guard template.recurrence.isValid else {
            throw StoreError.validationFailed(String(localized: "error.recurring.invalidRecurrence"))
        }
        let model = try fetchOne(RecurringTemplateModel.self, id: template.id)
        context.delete(model)
        context.insert(RecurringTemplateModel(from: template))
        save()
        reload()
    }

    func deleteRecurringTemplate(id: UUID) throws {
        let model = try fetchOne(RecurringTemplateModel.self, id: id)
        context.delete(model)
        save()
        reload()
    }

    func addExpectedEvent(_ event: ExpectedEvent) {
        context.insert(ExpectedEventModel(from: event))
        save()
        reload()
    }

    func updateExpectedEvent(_ event: ExpectedEvent) throws {
        let model = try fetchOne(ExpectedEventModel.self, id: event.id)
        context.delete(model)
        context.insert(ExpectedEventModel(from: event))
        save()
        reload()
    }

    private func fetchOne<M: PersistentModel & Identifiable>(_ type: M.Type, id: UUID) throws -> M where M.ID == UUID {
        let all = (try? context.fetch(FetchDescriptor<M>())) ?? []
        guard let model = all.first(where: { $0.id == id }) else { throw StoreError.notFound }
        return model
    }

    func performAtomically(_ body: () throws -> Void) throws {
        suspendsSave = true
        defer { suspendsSave = false }
        do {
            try body()
        } catch {
            context.rollback()
            reload()
            throw error
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            reload()
            throw error
        }
        reload()
    }

    private var suspendsSave = false

    private func save() {
        guard !suspendsSave else { return }
        do {
            try context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    var lastError: String?

    private func seedDefaultCategoriesIfNeeded() {
        let existing = (try? context.fetch(FetchDescriptor<CategoryModel>())) ?? []
        guard existing.isEmpty else { return }
        for category in TransactionCategory.defaults() {
            context.insert(CategoryModel(from: category))
        }
        save()
    }
}
