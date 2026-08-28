import Foundation
import FinPlanCore

extension FinanceStore {
    var dashboardDataRevision: Int {
        var hasher = Hasher()
        hasher.combine(accounts)
        hasher.combine(transactions)
        hasher.combine(goals)
        hasher.combine(allocations)
        hasher.combine(recurringTemplates)
        hasher.combine(expectedEvents)
        hasher.combine(incomeSources)
        hasher.combine(baseCurrency)
        hasher.combine(planningRates)
        hasher.combine(minimumCashBuffer)
        return hasher.finalize()
    }
}
