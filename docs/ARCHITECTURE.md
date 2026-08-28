# Architecture

FinPlan is organised as a pure Swift domain package plus a SwiftUI application and a WidgetKit extension that consume it. Dependencies point in one direction only: the app and the widgets depend on `FinPlanCore`; the package knows nothing about SwiftUI, SwiftData, WidgetKit or the app.

```
┌──────────────────────────────────────────────────────────────────┐
│  App (SwiftUI)                                                   │
│                                                                  │
│  Features/        Onboarding · Dashboard · Goals · Transactions  │
│                   Plan · Analytics · Settings                    │
│        │  read domain values, build engine inputs, render        │
│        ▼                                                         │
│  Data/FinanceStore   single @Observable store (domain arrays)    │
│        │  maps ⇄ SwiftData models, saves, republishes snapshots  │
│        ▼                                                         │
│  Data/PersistenceModels + PersistenceController  (SwiftData)     │
│                                                                  │
│  Services/  notifications, achievements     AppIntents/  Siri    │
│  Data/WidgetSnapshotWriter ──── JSON in App Group ───┐           │
└──────────────────────────────────────────────────────┼───────────┘
                          │ depends on                 │ reads
                          ▼                            ▼
┌──────────────────────────────────┐   ┌──────────────────────────┐
│  Packages/FinPlanCore (pure)     │   │  Widgets (WidgetKit)     │
│  Money/   Domain/   Engines/     │   │  Goal · SafeToSpend ·    │
│  no UI, no persistence, no I/O   │   │  Month                   │
└──────────────────────────────────┘   └──────────────────────────┘
```

## Guiding rule

**Views are not financial calculation authorities.** Every number shown to the user is produced by a deterministic function in `FinPlanCore`. Feature code is allowed to gather inputs (accounts, transactions, rates), call an engine and format the result. It is not allowed to add, subtract or convert money on its own, and it never works with floating-point amounts.

## FinPlanCore

Location: `Packages/FinPlanCore`. A Swift Package with one library target and one test target, buildable on iOS 18 and macOS 15 so the domain tests run with `swift test` without a simulator.

### Money/

- `Money` — an amount in integer minor units (`Int64`) plus a `Currency`. Arithmetic is currency-checked and overflow-aware; multiplication by a fraction uses `Int128` intermediates and half-away-from-zero rounding.
- `Currency` — ISO code plus minor-unit exponent (0…6). Known exponents are built in for common currencies; unknown codes default to 2.
- `ExchangeRate` — a scaled integer rate (`rateScaled / 10^scale`) between a base and a quote currency, parsed from decimal strings without floating point. `ManualExchangeRates` is the only rate provider: identity for equal currencies, a direct rate if present, otherwise the inverted reverse rate.

### Domain/

Value types that describe the user's finances: `Account`, `TransactionRecord` (with kinds, statuses, splits, fee, counter-amount, goal tag, attachments), `TransactionCategory`, `TransactionTag`, `Goal`, `GoalAllocation`, `GoalMilestone`, `IncomeSource` with a `PersonalShare`, `Budget`, `RecurringTemplate`, `ExpectedEvent`, `PlanSettings`. All are `Sendable`, `Hashable` and `Codable`; identity is a `UUID`.

### Engines/

Stateless engines (enums or structs with static functions) that take domain values and return results:

| Engine | Responsibility |
| --- | --- |
| `LedgerEngine` | Account balances, net worth, period summaries (income / expenses / savings / fees / free cash flow), category breakdowns, goal allocation totals |
| `ProjectionEngine` | Month-by-month goal projection, completion cycle and date, milestones, required monthly contribution, plan status, recovery plan |
| `ScenarioEngine` | Applies What-If overrides to a base plan and compares outcomes |
| `SafeToSpendEngine` | Liquid minus reserves, upcoming mandatory payments and buffer, with breakdown and shortfall |
| `PurchaseImpactEngine` | Verdict and goal delay for a candidate purchase |
| `BudgetEngine` | Spending against a category budget, pace, rollover |
| `RecurringScheduler` | Occurrences of recurring templates, planned transaction records, subscription equivalents, expected event partitioning |
| `AnalyticsEngine` | Monthly summaries, trends, net-worth history, runway, monthly close |
| `InsightEngine` | Rule-based insights (behind plan, overspending, low runway, …) from a snapshot context |

Engines throw typed errors (for example `LedgerError.missingExchangeRate`) instead of silently degrading; the app surfaces those errors to the user.

The exact rules the engines implement are documented in [FINANCIAL_MODEL.md](FINANCIAL_MODEL.md).

## App

### Data layer

- `PersistenceModels.swift` — one SwiftData `@Model` class per domain type (`AccountModel`, `TransactionModel`, `GoalModel`, `AllocationModel`, `IncomeSourceModel`, `BudgetModel`, `RecurringTemplateModel`, `ExpectedEventModel`, `CategoryModel`, `TagModel`, `AppSettingsModel`). Each model converts to and from its domain value (`toDomain()` / `apply(from:)`); complex enums are stored as encoded blobs.
- `PersistenceController` — owns the `ModelContainer` for the schema above with the default on-device configuration. Because the app declares an App Group, SwiftData places that store inside the group container; the widget extension does not open it and only reads the separate snapshot file. An in-memory configuration is used for previews and tests.
- `FinanceStore` — a `@MainActor @Observable` class and the single source of truth for feature code. It holds plain domain arrays (`accounts`, `transactions`, `goals`, `allocations`, …) and the app settings (base currency, planning rates, minimum cash buffer, privacy toggles). Mutations go through explicit methods (`addTransaction`, `updateGoal`, …) that validate, write to SwiftData, save and then `reload()`. `performAtomically` groups several mutations into one save so a failure rolls back the whole change set. After every reload the store republishes the widget snapshot and reschedules local notifications.
- Feature-specific store extensions (`DashboardModel`, `GoalsStoreSupport`, `PlanStoreSupport`, `AnalyticsStoreSupport`, `SettingsStoreSupport`, …) assemble engine inputs from the store's arrays. They are the only place where raw store data is turned into `SafeToSpendInput`, `ProjectionInput`, `ScenarioBasePlan` and friends.
- `BackupService` — JSON export/import of the whole store as a schema-versioned document with consistency validation, and CSV export of transactions.
- `WidgetSnapshotWriter` — computes a compact `WidgetSnapshot` (primary goal progress, safe to spend, current-month figures) with the core engines and writes it as JSON into the App Group container.

### Features

Each tab is a folder under `App/Features` and follows the same shape: a view (`*View.swift`), a model or store-support extension that talks to `FinanceStore`, and supporting sections and sheets. Views hold only UI state; anything derived from finances is recomputed from the store through an engine.

- **Onboarding** — base currency, first account, first goal, income, savings, expected events, recurring expenses, security. Committed atomically at the end.
- **Dashboard** — primary goal hero card with plan status, Safe to Spend with breakdown, current month, upcoming items, insight banner.
- **Goals** — list, detail (progress, forecast chart, contributions, milestones, allocations, events, history), editor, allocation sheet, purchase impact sheet.
- **Transactions** — searchable and filterable list, editor with splits, fees and exchange counter-amounts, filter sheet.
- **Plan** — monthly plan vs. actual, What-If sandbox with saved scenarios, timeline, calendar of planned and expected items, subscriptions.
- **Analytics** — summary, charts, budgets, runway, insights, achievements.
- **Settings** — general, privacy (Face ID, hide balances), notifications, planning rates, accounts, categories, data export/import, danger zone, about. Also hosts the `PrivacyShield` overlay window used for app lock and the app-switcher cover.

### Services and system integration

- `NotificationService` — schedules local notifications (expected income, savings contribution, large payment, overdue) from the store and rebuilds them idempotently on every refresh.
- `AchievementsEvaluator` — derives achievements from allocations and transaction history.
- `AppIntents/` — five intents (`AddExpenseIntent`, `AddIncomeIntent`, `CheckGoalProgressIntent`, `CheckSafeToSpendIntent`, `OpenPrimaryGoalIntent`), an `AppShortcutsProvider`, account and category entities, and an `IntentBridge` that hands the running `FinanceStore` and `AppRouter` to intents.
- `AppRouter` — tab selection plus a pending route consumed by the destination tab; used by deep links (`finplan://…`), widgets and intents.

### Design system

`App/DesignSystem` contains the card container, money text with privacy masking, locale-aware money input, an exchange-rate entry field that makes the quotation direction explicit, chart axis formatting for money, and spacing / radius tokens.

## Widgets

`Widgets/` is a WidgetKit extension with three widgets (goal progress, safe to spend, month summary). It does not open the database. It reads `widget-snapshot.json` from the App Group container, renders it and refreshes on a timeline every few hours; tapping a widget opens the app through a `finplan://` URL.

## State flow

```
user action ──▶ Feature view ──▶ FinanceStore mutation ──▶ SwiftData save
                                                              │
                     ┌────────────────────────────────────────┘
                     ▼
              FinanceStore.reload()
                     │  domain arrays change (@Observable)
                     ├──▶ views recompute via engines and re-render
                     ├──▶ WidgetSnapshotWriter.publish
                     └──▶ NotificationService.scheduleRefresh
```

## Testing strategy

- `Packages/FinPlanCore/Tests` — Swift Testing suites per engine (Money foundation, exchange rates, transaction invariants, Ledger, Projection, Scenario, SafeToSpend, PurchaseImpact, Budget and Recurring, Analytics, Insight, regression guards). They run on macOS with `swift test` and are the primary guard for financial correctness, including two synthetic end-to-end regression scenarios.
- `AppTests` — smoke tests for the app layer against an in-memory SwiftData container: store CRUD, ledger accounting through the store, onboarding commit, backup round-trip, privacy shield behaviour.
- CI runs both on every pull request (see `.github/workflows/ci.yml` and `scripts/ci.sh`).

## Conventions

- Swift 6 language mode with strict concurrency; store and UI code is `@MainActor`, domain types are `Sendable`.
- Money never leaves `Money`; no `Double`, `Decimal` or `NSDecimalNumber` in calculation paths.
- Debug-only code (`#Preview`, demo seed, preview fixtures) is wrapped in `#if DEBUG` so release builds do not compile it.
- User-facing strings are keys in the String Catalogs; no hard-coded UI text.
