import AppIntents
import Foundation
import FinPlanCore

struct CheckGoalProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.goalProgress.title"
    static let description = IntentDescription("intent.goalProgress.description")

    private static let fullScaleBasisPoints: Int64 = 10_000

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = IntentBridge.shared.resolveStore()
        guard let goal = IntentSupport.primaryGoal(in: store.goals) else {
            throw FinPlanIntentError.noPrimaryGoal
        }
        let currency = goal.targetAmount.currency
        let funded = try LedgerEngine.allocatedTotal(
            toGoal: goal.id,
            allocations: store.allocations,
            asOf: .now,
            in: currency,
            rates: store.planningRates
        )
        let percentBasisPoints = funded
            .multiplied(byNumerator: Self.fullScaleBasisPoints, denominator: goal.targetAmount.amountMinor)
            .amountMinor
        let percentWhole = Int(percentBasisPoints / 100)

        return .result(
            dialog: IntentDialog(
                "intent.goalProgress.dialog \(goal.title) \(funded.formatted()) \(goal.targetAmount.formatted()) \(percentWhole)"
            )
        )
    }
}
