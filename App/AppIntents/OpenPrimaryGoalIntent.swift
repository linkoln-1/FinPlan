import AppIntents
import Foundation
import FinPlanCore

struct OpenPrimaryGoalIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.openGoal.title"
    static let description = IntentDescription("intent.openGoal.description")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = IntentBridge.shared.resolveStore()
        guard let goal = IntentSupport.primaryGoal(in: store.goals) else {
            throw FinPlanIntentError.noPrimaryGoal
        }
        IntentBridge.shared.open(.goal(goal.id))
        return .result()
    }
}
