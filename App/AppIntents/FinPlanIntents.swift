import AppIntents

struct FinPlanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense in \(.applicationName)",
                "Log spending in \(.applicationName)",
            ],
            shortTitle: "shortcut.addExpense.title",
            systemImageName: "minus.circle"
        )
        AppShortcut(
            intent: AddIncomeIntent(),
            phrases: [
                "Add income in \(.applicationName)",
                "Log income in \(.applicationName)",
            ],
            shortTitle: "shortcut.addIncome.title",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: CheckGoalProgressIntent(),
            phrases: [
                "Check my goal in \(.applicationName)",
                "How is my goal doing in \(.applicationName)",
            ],
            shortTitle: "shortcut.goalProgress.title",
            systemImageName: "target"
        )
        AppShortcut(
            intent: CheckSafeToSpendIntent(),
            phrases: [
                "How much can I spend in \(.applicationName)",
                "Check safe to spend in \(.applicationName)",
            ],
            shortTitle: "shortcut.safeToSpend.title",
            systemImageName: "banknote"
        )
        AppShortcut(
            intent: OpenPrimaryGoalIntent(),
            phrases: [
                "Open my goal in \(.applicationName)",
                "Show my goal in \(.applicationName)",
            ],
            shortTitle: "shortcut.openGoal.title",
            systemImageName: "arrow.up.forward.app"
        )
    }
}
