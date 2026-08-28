import SwiftUI
import SwiftData

@main
struct FinPlanApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(PersistenceController.shared.container)
    }
}
