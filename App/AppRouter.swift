import Foundation
import Observation

enum AppRoute: Hashable {
    case dashboard
    case goal(UUID)
    case transactions
    case addExpense
    case plan
    case analytics
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: Int = 0
    var pendingRoute: AppRoute?

    func open(_ route: AppRoute) {
        switch route {
        case .dashboard:
            selectedTab = 0
        case .goal:
            pendingRoute = route
            selectedTab = 1
        case .transactions, .addExpense:
            pendingRoute = route
            selectedTab = 2
        case .plan:
            selectedTab = 3
        case .analytics:
            selectedTab = 4
        }
    }
}
