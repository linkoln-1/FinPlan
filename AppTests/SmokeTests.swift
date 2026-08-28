import Foundation
import Testing
import SwiftData
import FinPlanCore
@testable import FinPlan

@MainActor
private struct StoreFixture {
    let controller: PersistenceController
    let store: FinanceStore

    init() {
        controller = PersistenceController(inMemory: true)
        store = FinanceStore(context: controller.container.mainContext)
    }
}

private let parsingLocale = Locale(identifier: "en_US")

private func minor(_ text: String, _ currency: Currency) -> Int64? {
    MoneyParser.minorUnits(from: text, currency: currency, locale: parsingLocale)
}

private struct TestFailure: Error {}

@Suite("Onboarding commit")
@MainActor
struct OnboardingCommitTests {
    private let fixture = StoreFixture()

    @Test("full happy path lands complete state in the store")
    func onboardingCompletes() throws {
        let store = fixture.store
        let model = OnboardingModel()

        model.baseCurrency = .rub
        model.advance()

        model.accountName = "Main account"
        model.balanceText = "850000"
        model.balanceMinor = minor(model.balanceText, model.baseCurrency)
        #expect(model.isAccountValid)
        model.advance()

        model.goalTitle = "Apartment"
        model.goalTargetText = "6000000"
        model.goalTargetMinor = minor(model.goalTargetText, model.baseCurrency)
        #expect(model.isGoalValid)
        #expect(model.allocateOpeningToGoal)
        model.advance()

        model.addIncomeDraft()
        model.incomeDrafts[0].name = "Salary"
        model.incomeDrafts[0].currency = .usd
        model.incomeDrafts[0].sharePreset = .half
        model.incomeDrafts[0].amountText = "3750"
        model.incomeDrafts[0].amountMinor = minor("3750", .usd)
        model.addIncomeDraft()
        model.incomeDrafts[1].name = "Contract"
        model.incomeDrafts[1].currency = .usd
        model.incomeDrafts[1].sharePreset = .full
        model.incomeDrafts[1].amountText = "2500"
        model.incomeDrafts[1].amountMinor = minor("2500", .usd)
        let incomeDraftsValid = model.incomeDrafts.allSatisfy { $0.isValid }
        #expect(incomeDraftsValid)
        model.advance()

        model.savingsCurrency = .usd
        model.savingsAmountText = "4000"
        model.savingsAmountMinor = minor("4000", .usd)
        model.savingsRateText = "84.282"
        model.enteredPlanningRate = ExchangeRate(base: .usd, quote: .rub, decimalString: "84.282")
        #expect(model.needsPlanningRate)
        #expect(model.isSavingsValid)
        model.advance()

        model.addEventDraft()
        model.eventDrafts[0].title = "Bonus payout"
        model.eventDrafts[0].amountText = "1695000"
        model.eventDrafts[0].amountMinor = minor("1695000", .rub)
        let eventDraftsValid = model.eventDrafts.allSatisfy { $0.isValid }
        #expect(eventDraftsValid)
        model.advance()

        model.advance()
        #expect(model.step == .security)

        model.finish(with: store)

        #expect(store.lastError == nil)
        #expect(store.onboardingCompleted)

        #expect(store.accounts.count == 1)
        let account = try #require(store.accounts.first)
        #expect(account.openingBalance.amountMinor == 85_000_000)
        #expect(account.currency == .rub)
        #expect(store.baseCurrency == .rub)

        #expect(store.goals.count == 1)
        let goal = try #require(store.goals.first)
        #expect(goal.targetAmount.amountMinor == 600_000_000)
        #expect(store.allocations.count == 1)
        let allocation = try #require(store.allocations.first)
        #expect(allocation.amount.amountMinor == 85_000_000)
        #expect(allocation.goalID == goal.id)
        #expect(allocation.accountID == account.id)

        #expect(store.incomeSources.count == 2)
        let shares = Set(store.incomeSources.map { source -> Int64 in
            source.share.personalAmount(of: source.grossAmount).amountMinor
        })
        #expect(shares == [187_500, 250_000])

        #expect(store.recurringTemplates.count == 1)
        let template = try #require(store.recurringTemplates.first)
        #expect(template.kind == .transfer)
        #expect(template.goalID == goal.id)
        #expect(template.sourceAccountID == account.id)
        #expect(template.amount == Money(minor: 400_000, currency: .usd))

        let rate = try #require(store.planningRates.rate(from: .usd, to: .rub))
        #expect(rate.rateScaled == 84_282_000)
        #expect(rate.scale == 6)

        #expect(store.expectedEvents.count == 1)
        let event = try #require(store.expectedEvents.first)
        #expect(event.amount.amountMinor == 169_500_000)
        #expect(event.destinationAccountID == account.id)
        #expect(event.goalID == store.goals.first?.id)

        #expect(store.transactions.isEmpty)
    }

    @Test("atomic commit rolls back every write when the block throws")
    func onboardingAtomicity() {
        let store = fixture.store
        let thrown = #expect(throws: TestFailure.self) {
            try store.performAtomically {
                store.addAccount(Account(
                    name: "Doomed",
                    currency: .rub,
                    type: .checking,
                    openingBalance: Money(minor: 1_000, currency: .rub),
                    createdAt: Date()
                ))
                store.addGoal(Goal(
                    title: "Doomed goal",
                    targetAmount: Money(minor: 1_000, currency: .rub),
                    startDate: Date()
                ))
                throw TestFailure()
            }
        }
        #expect(thrown != nil)
        #expect(store.accounts.isEmpty)
        #expect(store.goals.isEmpty)
    }
}

@Suite("Store CRUD")
@MainActor
struct StoreCRUDTests {
    private let fixture = StoreFixture()

    @Test("goal + transactions round-trip; invalid writes throw")
    func crudSmoke() throws {
        let store = fixture.store
        let now = Date()

        let checking = Account(name: "Checking", currency: .rub, type: .checking,
                               openingBalance: Money(minor: 500_000, currency: .rub), createdAt: now)
        let savings = Account(name: "Savings", currency: .rub, type: .savings, createdAt: now)
        store.addAccount(checking)
        store.addAccount(savings)
        #expect(store.accounts.count == 2)

        store.addGoal(Goal(title: "Cushion", targetAmount: Money(minor: 10_000_000, currency: .rub), startDate: now))
        #expect(store.goals.count == 1)

        try store.addTransaction(TransactionRecord(
            date: now, kind: .income, status: .completed,
            amount: Money(minor: 250_000, currency: .rub),
            destinationAccountID: checking.id, createdAt: now
        ))
        try store.addTransaction(TransactionRecord(
            date: now, kind: .expense, status: .completed,
            amount: Money(minor: 40_000, currency: .rub),
            sourceAccountID: checking.id, createdAt: now
        ))
        let transfer = TransactionRecord(
            date: now, kind: .transfer, status: .completed,
            amount: Money(minor: 100_000, currency: .rub),
            sourceAccountID: checking.id, destinationAccountID: savings.id, createdAt: now
        )
        try store.addTransaction(transfer)
        #expect(store.transactions.count == 3)

        let invalid = TransactionRecord(
            date: now, kind: .transfer, status: .completed,
            amount: Money(minor: 100, currency: .rub),
            sourceAccountID: checking.id, destinationAccountID: checking.id, createdAt: now
        )
        let error = #expect(throws: FinanceStore.StoreError.self) {
            try store.addTransaction(invalid)
        }
        guard case .validationFailed = error else {
            Issue.record("expected validationFailed, got \(String(describing: error))")
            return
        }
        #expect(store.transactions.count == 3)

        try store.deleteTransaction(id: transfer.id)
        #expect(store.transactions.count == 2)
        #expect(store.transactions.allSatisfy { $0.id != transfer.id })
        let missing = #expect(throws: FinanceStore.StoreError.self) {
            try store.deleteTransaction(id: UUID())
        }
        guard case .notFound = missing else {
            Issue.record("expected notFound, got \(String(describing: missing))")
            return
        }
    }
}

@Suite("Ledger accounting via store")
@MainActor
struct LedgerAccountingTests {
    private let fixture = StoreFixture()

    @Test("goal-tagged transfer is savings, never expense")
    func periodSummaryThroughStore() throws {
        let store = fixture.store
        let now = Date()

        let card = Account(name: "Card", currency: .usd, type: .checking, createdAt: now)
        let vault = Account(name: "Vault", currency: .usd, type: .savings, createdAt: now)
        store.addAccount(card)
        store.addAccount(vault)
        let goal = Goal(title: "Reserve", targetAmount: Money(minor: 1_000_000, currency: .usd), startDate: now)
        store.addGoal(goal)

        try store.addTransaction(TransactionRecord(
            date: now, kind: .income, status: .completed,
            amount: Money(minor: 437_500, currency: .usd),
            destinationAccountID: card.id, createdAt: now
        ))
        try store.addTransaction(TransactionRecord(
            date: now, kind: .transfer, status: .completed,
            amount: Money(minor: 400_000, currency: .usd),
            sourceAccountID: card.id, destinationAccountID: vault.id,
            goalID: goal.id, createdAt: now
        ))

        let interval = DateInterval(start: now.addingTimeInterval(-3_600), duration: 7_200)
        let summary = try LedgerEngine.periodSummary(
            transactions: store.transactions,
            in: interval,
            currency: .usd,
            rates: ManualExchangeRates()
        )
        #expect(summary.income.amountMinor == 437_500)
        #expect(summary.expenses.isZero)
        #expect(summary.savingsAllocated.amountMinor == 400_000)
        #expect(summary.fees.isZero)
        #expect(summary.freeCashFlow.amountMinor == 37_500)
    }
}

@Suite("Backup round-trip")
@MainActor
struct BackupTests {
    private let fixture = StoreFixture()

    @Test("export → validateImport preserves every entity count")
    func jsonRoundTrip() throws {
        let store = fixture.store
        let now = Date()

        let account = Account(name: "Main", currency: .rub, type: .checking,
                              openingBalance: Money(minor: 1_000_000, currency: .rub), createdAt: now)
        store.addAccount(account)
        let goal = Goal(title: "Trip", targetAmount: Money(minor: 5_000_000, currency: .rub), startDate: now)
        store.addGoal(goal)
        store.addAllocation(GoalAllocation(goalID: goal.id, accountID: account.id,
                                           amount: Money(minor: 200_000, currency: .rub), date: now))
        store.addIncomeSource(IncomeSource(name: "Job", grossAmount: Money(minor: 9_000_000, currency: .rub),
                                           destinationAccountID: account.id))
        try store.addTransaction(TransactionRecord(
            date: now, kind: .expense, status: .completed,
            amount: Money(minor: 12_345, currency: .rub),
            sourceAccountID: account.id, createdAt: now
        ))

        let data = try BackupService.exportJSON(from: store)
        let document = try BackupService.validateImport(data)

        #expect(document.schemaVersion == BackupService.currentSchemaVersion)
        #expect(document.baseCurrency == store.baseCurrency)
        #expect(document.accounts.count == store.accounts.count)
        #expect(document.categories.count == store.categories.count)
        #expect(document.transactions.count == store.transactions.count)
        #expect(document.goals.count == store.goals.count)
        #expect(document.allocations.count == store.allocations.count)
        #expect(document.incomeSources.count == store.incomeSources.count)
    }

    @Test("corrupt payload is rejected as unreadable")
    func corruptImport() {
        let garbage = Data("definitely { not json".utf8)
        #expect(throws: BackupService.ImportError.unreadable) {
            _ = try BackupService.validateImport(garbage)
        }
    }

    @Test("transaction referencing an unknown account is inconsistent")
    func inconsistentImport() throws {
        let now = Date()
        let account = Account(name: "Known", currency: .rub, type: .checking, createdAt: now)
        let orphan = TransactionRecord(
            date: now, kind: .income, status: .completed,
            amount: Money(minor: 1_000, currency: .rub),
            destinationAccountID: UUID(),
            createdAt: now
        )
        let document = BackupService.BackupDocument(
            schemaVersion: BackupService.currentSchemaVersion,
            exportedAt: now,
            baseCurrency: .rub,
            planningRates: ManualExchangeRates(),
            minimumCashBufferMinor: 0,
            accounts: [account],
            categories: [], tags: [],
            transactions: [orphan],
            goals: [], allocations: [], incomeSources: [],
            budgets: [], recurringTemplates: [], expectedEvents: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)

        let error = #expect(throws: BackupService.ImportError.self) {
            _ = try BackupService.validateImport(data)
        }
        guard case .inconsistent = error else {
            Issue.record("expected inconsistent, got \(String(describing: error))")
            return
        }
    }

    @Test("CSV export writes exact decimal amounts")
    func csvExport() throws {
        let store = fixture.store
        let now = Date()
        let card = Account(name: "Card", currency: .usd, type: .checking, createdAt: now)
        store.addAccount(card)
        try store.addTransaction(TransactionRecord(
            date: now, kind: .expense, status: .completed,
            amount: Money(minor: 10_025, currency: .usd),
            sourceAccountID: card.id, createdAt: now
        ))

        let csv = BackupService.exportCSV(from: store)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 2)
        #expect(lines[0] == "id,date,kind,status,amount,currency,source_account,destination_account,category,note")
        let fields = lines[1].split(separator: ",", omittingEmptySubsequences: false)
        #expect(fields.count == 10)
        #expect(fields[2] == "expense")
        #expect(fields[3] == "completed")
        #expect(fields[4] == "100.25")
        #expect(fields[5] == "USD")
        #expect(fields[6] == "Card")
    }
}

@Suite("Privacy shield")
@MainActor
struct PrivacyShieldTests {
    @Test("lockIfNeeded honors the biometrics toggle")
    func lockRespectsSetting() {
        let shield = PrivacyShieldModel()
        #expect(!shield.isLocked)

        shield.lockIfNeeded(requireBiometrics: false)
        #expect(!shield.isLocked)

        shield.lockIfNeeded(requireBiometrics: true)
        #expect(shield.isLocked)
    }
}
