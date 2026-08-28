import SwiftUI
import SwiftData
import FinPlanCore

struct DashboardView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var model = DashboardModel()
    @State private var isSettingsPresented = false
    @State private var ratePrompt: MissingRatesPrompt?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FP.Spacing.lg) {
                    if let insight = model.topInsight {
                        DashboardInsightBanner(insight: insight)
                    }
                    if let hero = model.hero {
                        DashboardHeroCard(data: hero)
                    } else {
                        DashboardFirstGoalCard()
                    }
                    if let result = model.safeToSpend {
                        DashboardSafeToSpendCard(result: result, details: model.safeToSpendDetails)
                    }
                    if let month = model.month {
                        DashboardMonthCard(data: month)
                    }
                    if let chart = model.chart {
                        DashboardChartCard(data: chart)
                    }
                    DashboardUpcomingCard(items: model.upcoming)
                }
                .padding(FP.Spacing.lg)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("dashboard.title")
            .toolbar { toolbarContent }
        }
        .onChange(of: store.dashboardDataRevision, initial: true) {
            model.recompute(store: store)
        }
        .sensoryFeedback(.success, trigger: celebrationTrigger) { _, newValue in
            newValue != nil
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .alert("dashboard.error.title", isPresented: isErrorPresented) {
            if let pair = model.missingRate, pair.quote == store.baseCurrency {
                Button("error.addRate") {
                    ratePrompt = MissingRatesPrompt(currencies: [pair.base])
                }
            }
            Button("dashboard.error.dismiss", role: .cancel) {}
        } message: {
            Text(verbatim: model.errorMessage ?? store.lastError ?? "")
        }
        .sheet(item: $ratePrompt) { prompt in
            SettingsMissingRatesSheet(currencies: prompt.currencies) {
                ratePrompt = nil
            }
            .environment(store)
        }
    }

    private var celebrationTrigger: Int? {
        guard let insight = model.topInsight,
              insight.type == .goalReached || insight.type == .milestoneReached
        else { return nil }
        return insight.hashValue
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil || store.lastError != nil },
            set: { presented in
                if !presented {
                    model.errorMessage = nil
                    store.lastError = nil
                }
            }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                store.hideBalances.toggle()
            } label: {
                Image(systemName: store.hideBalances ? "eye.slash" : "eye")
            }
            .accessibilityLabel(
                store.hideBalances
                    ? String(localized: "a11y.dashboard.showBalances")
                    : String(localized: "a11y.dashboard.hideBalances")
            )
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel(String(localized: "settings.title"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("dashboard.quickAdd.expense", systemImage: "cart.badge.minus") {
                    router.open(.addExpense)
                }
                Button("dashboard.quickAdd.transactions", systemImage: "list.bullet.rectangle") {
                    router.open(.transactions)
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(String(localized: "a11y.dashboard.quickAdd"))
        }
    }
}

#if DEBUG
#Preview("Seeded") {
    let controller = PersistenceController.preview()
    let store = FinanceStore(context: controller.container.mainContext)
    let _ = dashboardSeedPreviewData(into: store)
    DashboardView()
        .environment(store)
        .environment(AppRouter())
        .modelContainer(controller.container)
}
#endif

#if DEBUG
#Preview("Empty") {
    let controller = PersistenceController.preview()
    let store = FinanceStore(context: controller.container.mainContext)
    DashboardView()
        .environment(store)
        .environment(AppRouter())
        .modelContainer(controller.container)
}
#endif

@MainActor
private func dashboardSeedPreviewData(into store: FinanceStore) {
    let calendar = Calendar.current
    let now = Date()
    let rub = Currency.rub
    let usd = Currency.usd

    func daysFromNow(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: now) ?? now
    }
    func monthsFromNow(_ months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: now) ?? now
    }

    if let usdRub = ExchangeRate(base: usd, quote: rub, decimalString: "84.282") {
        store.planningRates = ManualExchangeRates(rates: [usdRub])
    }
    store.minimumCashBuffer = Money(major: 100_000, currency: rub)

    let card = Account(
        name: "Card", currency: rub, type: .checking,
        openingBalance: Money(major: 1_450_000, currency: rub), createdAt: monthsFromNow(-12)
    )
    let savings = Account(
        name: "Savings", currency: rub, type: .savings,
        openingBalance: Money(major: 850_000, currency: rub), createdAt: monthsFromNow(-12)
    )
    store.addAccount(card)
    store.addAccount(savings)

    let goalStart = monthsFromNow(-8)
    let goal = Goal(
        title: "Apartment", symbolName: "house.fill",
        targetAmount: Money(major: 6_000_000, currency: rub),
        startDate: goalStart, desiredCompletionDate: monthsFromNow(16),
        priority: .high, status: .active
    )
    let emergency = Goal(
        title: "Emergency fund", symbolName: "shield.fill",
        targetAmount: Money(major: 600_000, currency: rub),
        startDate: goalStart, priority: .medium, status: .active,
        isEmergencyFund: true, desiredMonthsOfExpenses: 6
    )
    store.addGoal(goal)
    store.addGoal(emergency)

    let monthlyMajor: [Int64] = [100_000, 100_000, 110_000, 100_000, 110_000, 110_000, 120_000, 100_000]
    for (offset, major) in monthlyMajor.enumerated() {
        let date = calendar.date(byAdding: .month, value: offset, to: goalStart) ?? goalStart
        store.addAllocation(
            GoalAllocation(goalID: goal.id, accountID: savings.id, amount: Money(major: major, currency: rub), date: date)
        )
    }
    store.addAllocation(
        GoalAllocation(goalID: emergency.id, accountID: card.id, amount: Money(major: 300_000, currency: rub), date: goalStart)
    )

    store.addRecurringTemplate(
        RecurringTemplate(
            name: "Salary", kind: .income, amount: Money(major: 420_000, currency: rub),
            recurrence: .monthly(day: 5), destinationAccountID: card.id, startDate: goalStart
        )
    )
    store.addRecurringTemplate(
        RecurringTemplate(
            name: "Goal contribution", kind: .transfer, amount: Money(major: 4_000, currency: usd),
            recurrence: .monthly(day: 6), sourceAccountID: card.id, destinationAccountID: savings.id,
            goalID: goal.id, startDate: goalStart
        )
    )
    store.addRecurringTemplate(
        RecurringTemplate(
            name: "Rent", kind: .expense, amount: Money(major: 90_000, currency: rub),
            recurrence: .monthly(day: 1), sourceAccountID: card.id, startDate: goalStart
        )
    )
    store.addRecurringTemplate(
        RecurringTemplate(
            name: "Music subscription", kind: .expense, amount: Money(major: 1_500, currency: rub),
            recurrence: .monthly(day: 20), sourceAccountID: card.id, startDate: goalStart
        )
    )

    let foodCategoryID = store.categories.first { $0.name == "Food" }?.id
    let seedTransactions = [
        TransactionRecord(
            date: daysFromNow(-6), kind: .income, amount: Money(major: 420_000, currency: rub),
            destinationAccountID: card.id, createdAt: daysFromNow(-6)
        ),
        TransactionRecord(
            date: daysFromNow(-4), kind: .transfer, amount: Money(major: 100_000, currency: rub),
            sourceAccountID: card.id, destinationAccountID: savings.id, goalID: goal.id,
            createdAt: daysFromNow(-4)
        ),
        TransactionRecord(
            date: daysFromNow(-2), kind: .expense, amount: Money(major: 12_450, currency: rub),
            sourceAccountID: card.id, categoryID: foodCategoryID, createdAt: daysFromNow(-2)
        ),
        TransactionRecord(
            date: daysFromNow(-1), kind: .expense, amount: Money(major: 3_200, currency: rub),
            sourceAccountID: card.id, createdAt: daysFromNow(-1)
        ),
    ]
    for record in seedTransactions {
        do {
            try store.addTransaction(record)
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    store.addExpectedEvent(
        ExpectedEvent(
            title: "Annual bonus", amount: Money(major: 300_000, currency: rub),
            expectedDate: daysFromNow(18), destinationAccountID: savings.id, goalID: goal.id
        )
    )
}
