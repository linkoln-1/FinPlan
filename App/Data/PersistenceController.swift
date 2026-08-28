import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    static let schema = Schema([
        AccountModel.self, CategoryModel.self, TagModel.self,
        TransactionModel.self, GoalModel.self, AllocationModel.self,
        IncomeSourceModel.self, BudgetModel.self, RecurringTemplateModel.self,
        ExpectedEventModel.self, AppSettingsModel.self,
    ])

    let container: ModelContainer

    init(inMemory: Bool = false) {
        let configuration = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: Self.schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    static func preview() -> PersistenceController {
        PersistenceController(inMemory: true)
    }
}
