import Foundation
import FinPlanCore

enum PlanFeatureError: LocalizedError {
    case noAccountForIncome
    case scenarioStorageFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAccountForIncome:
            return String(localized: "plan.error.noAccountForIncome")
        case .scenarioStorageFailed(let details):
            return String(localized: "plan.error.scenarioStorage") + " " + details
        }
    }
}

extension FinanceStore {
    func planMarkExpectedEventReceived(_ event: ExpectedEvent, on date: Date = .now) throws {
        let fallbackAccount = accounts.first(where: { !$0.isArchived })?.id
        guard let destination = event.destinationAccountID ?? fallbackAccount else {
            throw PlanFeatureError.noAccountForIncome
        }
        let record = TransactionRecord(
            date: date,
            kind: .income,
            status: .completed,
            amount: event.amount,
            destinationAccountID: destination,
            goalID: event.goalID,
            note: event.title,
            createdAt: date
        )
        try addTransaction(record)
        var updated = event
        updated.state = .received
        try updateExpectedEvent(updated)
    }

    func planRescheduleExpectedEvent(_ event: ExpectedEvent, to date: Date) throws {
        var updated = event
        updated.expectedDate = date
        updated.state = .expected
        try updateExpectedEvent(updated)
    }

    func planCancelExpectedEvent(_ event: ExpectedEvent) throws {
        var updated = event
        updated.state = .cancelled
        try updateExpectedEvent(updated)
    }

    private var planScenariosFileURL: URL {
        get throws {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = support.appendingPathComponent("FinPlan", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent("plan-scenarios.json")
        }
    }

    func planLoadScenarios() throws -> [Scenario] {
        let url: URL
        do {
            url = try planScenariosFileURL
        } catch {
            throw PlanFeatureError.scenarioStorageFailed(error.localizedDescription)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Scenario].self, from: data)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            throw PlanFeatureError.scenarioStorageFailed(error.localizedDescription)
        }
    }

    func planSaveScenario(_ scenario: Scenario) throws {
        var scenarios = try planLoadScenarios().filter { $0.id != scenario.id }
        scenarios.append(scenario)
        try planWriteScenarios(scenarios)
    }

    func planDeleteScenario(id: UUID) throws {
        let remaining = try planLoadScenarios().filter { $0.id != id }
        try planWriteScenarios(remaining)
    }

    private func planWriteScenarios(_ scenarios: [Scenario]) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(scenarios)
            try data.write(to: planScenariosFileURL, options: .atomic)
        } catch let error as PlanFeatureError {
            throw error
        } catch {
            throw PlanFeatureError.scenarioStorageFailed(error.localizedDescription)
        }
    }

    func planPrimaryGoal() -> Goal? {
        goals
            .filter { $0.status == .active }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.startDate < rhs.startDate
            }
            .first
    }

    func planGoalBalance(_ goal: Goal, asOf date: Date) throws -> Money {
        try LedgerEngine.allocatedTotal(
            toGoal: goal.id,
            allocations: allocations,
            asOf: date,
            in: goal.targetAmount.currency,
            rates: planningRates
        )
    }

    func planBasePlan(now: Date) throws -> ScenarioBasePlan? {
        guard let goal = planPrimaryGoal() else { return nil }
        let balance = try planGoalBalance(goal, asOf: now)
        return try PlanMath.basePlan(
            goal: goal,
            balance: balance,
            templates: recurringTemplates,
            incomeSources: incomeSources,
            expectedEvents: expectedEvents,
            planningRates: planningRates,
            now: now
        )
    }
}
