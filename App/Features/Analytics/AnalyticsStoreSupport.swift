import Foundation
import SwiftData
import FinPlanCore

extension FinanceStore {
    func updateBudget(_ budget: Budget, context: ModelContext) throws {
        let all = (try? context.fetch(FetchDescriptor<BudgetModel>())) ?? []
        guard let model = all.first(where: { $0.id == budget.id }) else {
            throw StoreError.notFound
        }
        context.delete(model)
        context.insert(BudgetModel(from: budget))
        try context.save()
        reload()
    }

    func deleteBudget(id: UUID, context: ModelContext) throws {
        let all = (try? context.fetch(FetchDescriptor<BudgetModel>())) ?? []
        guard let model = all.first(where: { $0.id == id }) else {
            throw StoreError.notFound
        }
        context.delete(model)
        try context.save()
        reload()
    }

    func updateCategory(_ category: TransactionCategory, context: ModelContext) throws {
        let all = (try? context.fetch(FetchDescriptor<CategoryModel>())) ?? []
        guard let model = all.first(where: { $0.id == category.id }) else {
            throw StoreError.notFound
        }
        context.delete(model)
        context.insert(CategoryModel(from: category))
        try context.save()
        reload()
    }
}
