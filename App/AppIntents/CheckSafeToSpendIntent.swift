import AppIntents
import Foundation
import FinPlanCore

struct CheckSafeToSpendIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.safeToSpend.title"
    static let description = IntentDescription("intent.safeToSpend.description")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = IntentBridge.shared.resolveStore()
        let output = try SafeToSpendSnapshot.compute(store: store)
        let result = output.result

        if let shortfall = result.shortfall {
            return .result(
                dialog: IntentDialog("intent.safeToSpend.shortfall \(shortfall.formatted())")
            )
        }
        return .result(
            dialog: IntentDialog("intent.safeToSpend.dialog \(result.available.formatted())")
        )
    }
}
