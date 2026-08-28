import Foundation

@MainActor
final class IntentBridge {
    static let shared = IntentBridge()

    private(set) weak var router: AppRouter?
    private(set) weak var store: FinanceStore?
    private var stashedRoute: AppRoute?

    private init() {}

    func register(router: AppRouter, store: FinanceStore) {
        self.router = router
        self.store = store
        if let route = stashedRoute {
            stashedRoute = nil
            router.open(route)
        }
    }

    func open(_ route: AppRoute) {
        if let router {
            router.open(route)
        } else {
            stashedRoute = route
        }
    }

    func resolveStore() -> FinanceStore {
        if let store { return store }
        return FinanceStore(context: PersistenceController.shared.container.mainContext)
    }
}
