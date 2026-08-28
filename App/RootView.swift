import SwiftUI
import SwiftData
import FinPlanCore

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store: FinanceStore?
    @State private var privacyShield = PrivacyShieldModel()
    @State private var router = AppRouter()
    @AppStorage("appearanceOverride") private var appearanceRaw = SettingsAppearance.system.rawValue

    var body: some View {
        Group {
            if let store {
                if store.onboardingCompleted {
                    MainTabView()
                        .environment(store)
                } else {
                    OnboardingFlowView()
                        .environment(store)
                }
            } else {
                ProgressView()
            }
        }
        .environment(privacyShield)
        .environment(router)
        .preferredColorScheme((SettingsAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
        .task {
            if store == nil {
                let created = FinanceStore(context: modelContext)
                #if DEBUG
                DemoSeed.seedIfRequested(store: created)
                DemoSeed.applyNavigation(router: router, store: created)
                #endif
                store = created
            }
            if let store {
                IntentBridge.shared.register(router: router, store: store)
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "finplan" else { return }
        switch url.host() {
        case "dashboard":
            router.open(.dashboard)
        case "goals":
            if let id = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:)) {
                router.open(.goal(id))
            } else {
                router.selectedTab = 1
            }
        case "transactions":
            router.open(.transactions)
        case "plan":
            router.open(.plan)
        case "analytics":
            router.open(.analytics)
        default:
            break
        }
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("tab.home", systemImage: "house.fill", value: 0) {
                DashboardView()
            }
            Tab("tab.goals", systemImage: "target", value: 1) {
                GoalsView()
            }
            Tab("tab.transactions", systemImage: "list.bullet.rectangle.fill", value: 2) {
                TransactionsView()
            }
            Tab("tab.plan", systemImage: "calendar", value: 3) {
                PlanView()
            }
            Tab("tab.analytics", systemImage: "chart.bar.xaxis", value: 4) {
                AnalyticsView()
            }
        }
        .privacyShielded()
    }
}
