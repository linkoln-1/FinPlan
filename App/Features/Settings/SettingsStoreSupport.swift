import Foundation
import SwiftData
import FinPlanCore

enum SettingsSupportedCurrencies {
    static let codes = ["RUB", "USD", "EUR"]

    static func codes(including extra: [String]) -> [String] {
        var result = codes
        for code in extra where !result.contains(code) {
            result.append(code)
        }
        return result
    }
}

extension FinanceStore {
    func settingsUpdateCategory(_ category: TransactionCategory, context: ModelContext) throws {
        let models = (try? context.fetch(FetchDescriptor<CategoryModel>())) ?? []
        guard let model = models.first(where: { $0.id == category.id }) else {
            throw StoreError.notFound
        }
        model.name = category.name
        model.symbolName = category.symbolName
        model.isEssential = category.isEssential
        model.isArchived = category.isArchived
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        reload()
    }

    func settingsReplaceAllData(with document: BackupService.BackupDocument, context: ModelContext) throws {
        do {
            try Self.wipeEntities(context: context)
            for account in document.accounts { context.insert(AccountModel(from: account)) }
            for category in document.categories { context.insert(CategoryModel(from: category)) }
            for tag in document.tags { context.insert(TagModel(from: tag)) }
            for record in document.transactions { context.insert(TransactionModel(from: record)) }
            for goal in document.goals { context.insert(GoalModel(from: goal)) }
            for allocation in document.allocations { context.insert(AllocationModel(from: allocation)) }
            for source in document.incomeSources { context.insert(IncomeSourceModel(from: source)) }
            for budget in document.budgets { context.insert(BudgetModel(from: budget)) }
            for template in document.recurringTemplates { context.insert(RecurringTemplateModel(from: template)) }
            for event in document.expectedEvents { context.insert(ExpectedEventModel(from: event)) }
            try context.save()
        } catch {
            context.rollback()
            reload()
            throw error
        }
        setBaseCurrency(document.baseCurrency)
        planningRates = document.planningRates
        minimumCashBuffer = Money(minor: document.minimumCashBufferMinor, currency: document.baseCurrency)
        reload()
    }

    func settingsResetAllData(context: ModelContext) throws {
        do {
            try Self.wipeEntities(context: context)
            for category in TransactionCategory.defaults() {
                context.insert(CategoryModel(from: category))
            }
            try context.save()
        } catch {
            context.rollback()
            reload()
            throw error
        }
        setBaseCurrency(.rub)
        planningRates = ManualExchangeRates()
        minimumCashBuffer = .zero(.rub)
        requireBiometrics = false
        hideBalances = false
        onboardingCompleted = false
        reload()
    }

    private static func wipeEntities(context: ModelContext) throws {
        try deleteAll(TransactionModel.self, context: context)
        try deleteAll(AllocationModel.self, context: context)
        try deleteAll(ExpectedEventModel.self, context: context)
        try deleteAll(RecurringTemplateModel.self, context: context)
        try deleteAll(BudgetModel.self, context: context)
        try deleteAll(IncomeSourceModel.self, context: context)
        try deleteAll(GoalModel.self, context: context)
        try deleteAll(TagModel.self, context: context)
        try deleteAll(CategoryModel.self, context: context)
        try deleteAll(AccountModel.self, context: context)
    }

    private static func deleteAll<M: PersistentModel>(_ type: M.Type, context: ModelContext) throws {
        for model in try context.fetch(FetchDescriptor<M>()) {
            context.delete(model)
        }
    }
}
