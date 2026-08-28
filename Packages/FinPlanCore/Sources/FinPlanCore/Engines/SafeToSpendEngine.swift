import Foundation

public enum SafeToSpendError: Error, Equatable, Sendable {
    case negativeComponent(SafeToSpendComponent)
}

public enum SafeToSpendComponent: String, Sendable, Codable, CaseIterable {
    case liquidBalance
    case goalReserved
    case emergencyReserve
    case upcomingMandatory
    case minimumBuffer
}

public struct SafeToSpendBreakdownItem: Hashable, Sendable, Codable {
    public let label: SafeToSpendComponent
    public let amount: Money

    public init(label: SafeToSpendComponent, amount: Money) {
        self.label = label
        self.amount = amount
    }
}

public struct SafeToSpendInput: Hashable, Sendable, Codable {
    public let liquidBalance: Money
    public let goalAllocatedTotal: Money
    public let emergencyReserve: Money
    public let upcomingMandatory: Money
    public let minimumBuffer: Money

    public init(
        liquidBalance: Money,
        goalAllocatedTotal: Money,
        emergencyReserve: Money,
        upcomingMandatory: Money,
        minimumBuffer: Money
    ) {
        self.liquidBalance = liquidBalance
        self.goalAllocatedTotal = goalAllocatedTotal
        self.emergencyReserve = emergencyReserve
        self.upcomingMandatory = upcomingMandatory
        self.minimumBuffer = minimumBuffer
    }

    public init(
        liquidBalance: Money,
        reservedTotal: Money,
        upcomingMandatory: Money,
        minimumBuffer: Money
    ) {
        self.init(
            liquidBalance: liquidBalance,
            goalAllocatedTotal: reservedTotal,
            emergencyReserve: .zero(reservedTotal.currency),
            upcomingMandatory: upcomingMandatory,
            minimumBuffer: minimumBuffer
        )
    }

    public func reservedTotal() throws -> Money {
        try goalAllocatedTotal.adding(emergencyReserve)
    }
}

public struct SafeToSpendResult: Hashable, Sendable, Codable {
    public let available: Money
    public let shortfall: Money?
    public let breakdown: [SafeToSpendBreakdownItem]

    public init(available: Money, shortfall: Money?, breakdown: [SafeToSpendBreakdownItem]) {
        self.available = available
        self.shortfall = shortfall
        self.breakdown = breakdown
    }
}

public enum SafeToSpendEngine {
    public static func evaluate(_ input: SafeToSpendInput) throws -> SafeToSpendResult {
        try validateDeductions(of: input)

        let raw = try input.liquidBalance
            .subtracting(input.goalAllocatedTotal)
            .subtracting(input.emergencyReserve)
            .subtracting(input.upcomingMandatory)
            .subtracting(input.minimumBuffer)

        let currency = raw.currency
        let available = raw.isNegative ? Money.zero(currency) : raw
        let shortfall = raw.isNegative ? raw.negated : nil

        let breakdown: [SafeToSpendBreakdownItem] = [
            SafeToSpendBreakdownItem(label: .liquidBalance, amount: input.liquidBalance),
            SafeToSpendBreakdownItem(label: .goalReserved, amount: input.goalAllocatedTotal.negated),
            SafeToSpendBreakdownItem(label: .emergencyReserve, amount: input.emergencyReserve.negated),
            SafeToSpendBreakdownItem(label: .upcomingMandatory, amount: input.upcomingMandatory.negated),
            SafeToSpendBreakdownItem(label: .minimumBuffer, amount: input.minimumBuffer.negated),
        ]

        return SafeToSpendResult(available: available, shortfall: shortfall, breakdown: breakdown)
    }

    private static func validateDeductions(of input: SafeToSpendInput) throws {
        let deductions: [(SafeToSpendComponent, Money)] = [
            (.goalReserved, input.goalAllocatedTotal),
            (.emergencyReserve, input.emergencyReserve),
            (.upcomingMandatory, input.upcomingMandatory),
            (.minimumBuffer, input.minimumBuffer),
        ]
        for (component, amount) in deductions where amount.isNegative {
            throw SafeToSpendError.negativeComponent(component)
        }
    }
}
