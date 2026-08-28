import Testing
import Foundation
@testable import FinPlanCore

@Suite("SafeToSpendEngine")
struct SafeToSpendTests {
    private func rub(_ major: Int64) -> Money {
        Money(major: major, currency: .rub)
    }

    private func breakdownSum(_ result: SafeToSpendResult) throws -> Money {
        try result.breakdown.map(\.amount).sum(in: .rub)
    }

    @Test("spec example: 300k − 100k protected − 60k upcoming − 50k buffer = 90k available")
    func specExample() throws {
        let input = SafeToSpendInput(
            liquidBalance: rub(300_000),
            goalAllocatedTotal: rub(70_000),
            emergencyReserve: rub(30_000),
            upcomingMandatory: rub(60_000),
            minimumBuffer: rub(50_000)
        )

        let result = try SafeToSpendEngine.evaluate(input)

        #expect(result.available == rub(90_000))
        #expect(result.shortfall == nil)
    }

    @Test("goal-reserved funds are excluded from spendable money")
    func goalReservedExcluded() throws {
        let input = SafeToSpendInput(
            liquidBalance: rub(200_000),
            goalAllocatedTotal: rub(80_000),
            emergencyReserve: rub(0),
            upcomingMandatory: rub(0),
            minimumBuffer: rub(0)
        )

        let result = try SafeToSpendEngine.evaluate(input)

        #expect(result.available == rub(120_000))
        #expect(result.shortfall == nil)
    }

    @Test("emergency reserve is excluded from spendable money")
    func emergencyReserveExcluded() throws {
        let input = SafeToSpendInput(
            liquidBalance: rub(200_000),
            goalAllocatedTotal: rub(0),
            emergencyReserve: rub(80_000),
            upcomingMandatory: rub(0),
            minimumBuffer: rub(0)
        )

        let result = try SafeToSpendEngine.evaluate(input)

        #expect(result.available == rub(120_000))
        #expect(result.shortfall == nil)
    }

    @Test("upcoming mandatory payments are excluded from spendable money")
    func mandatoryPaymentExcluded() throws {
        let input = SafeToSpendInput(
            liquidBalance: rub(200_000),
            goalAllocatedTotal: rub(0),
            emergencyReserve: rub(0),
            upcomingMandatory: rub(80_000),
            minimumBuffer: rub(0)
        )

        let result = try SafeToSpendEngine.evaluate(input)

        #expect(result.available == rub(120_000))
        #expect(result.shortfall == nil)
    }

    @Test("minimum buffer is excluded from spendable money")
    func minimumBufferExcluded() throws {
        let input = SafeToSpendInput(
            liquidBalance: rub(200_000),
            goalAllocatedTotal: rub(0),
            emergencyReserve: rub(0),
            upcomingMandatory: rub(0),
            minimumBuffer: rub(80_000)
        )

        let result = try SafeToSpendEngine.evaluate(input)

        #expect(result.available == rub(120_000))
        #expect(result.shortfall == nil)
    }

    @Test("underwater: available clamps to zero, shortfall carries the gap")
    func negativeClampsToZeroWithShortfall() throws {
        let input = SafeToSpendInput(
            liquidBalance: rub(100_000),
            reservedTotal: rub(150_000),
            upcomingMandatory: rub(0),
            minimumBuffer: rub(0)
        )

        let result = try SafeToSpendEngine.evaluate(input)

        #expect(result.available == rub(0))
        #expect(result.shortfall == rub(50_000))
    }

    @Test("breakdown lines sum back to the raw result (positive case)")
    func breakdownSumsToRawPositive() throws {
        let input = SafeToSpendInput(
            liquidBalance: rub(300_000),
            goalAllocatedTotal: rub(70_000),
            emergencyReserve: rub(30_000),
            upcomingMandatory: rub(60_000),
            minimumBuffer: rub(50_000)
        )

        let result = try SafeToSpendEngine.evaluate(input)

        #expect(try breakdownSum(result) == result.available)
        #expect(result.breakdown.map(\.label) == [
            .liquidBalance, .goalReserved, .emergencyReserve, .upcomingMandatory, .minimumBuffer,
        ])
    }

    @Test("breakdown lines sum back to the raw result (negative case)")
    func breakdownSumsToRawNegative() throws {
        let input = SafeToSpendInput(
            liquidBalance: rub(100_000),
            reservedTotal: rub(150_000),
            upcomingMandatory: rub(0),
            minimumBuffer: rub(0)
        )

        let result = try SafeToSpendEngine.evaluate(input)

        let shortfall = try #require(result.shortfall)
        #expect(try breakdownSum(result) == shortfall.negated)
    }

    @Test("all-zero input yields zero available and no shortfall")
    func allZeros() throws {
        let input = SafeToSpendInput(
            liquidBalance: rub(0),
            goalAllocatedTotal: rub(0),
            emergencyReserve: rub(0),
            upcomingMandatory: rub(0),
            minimumBuffer: rub(0)
        )

        let result = try SafeToSpendEngine.evaluate(input)

        #expect(result.available == rub(0))
        #expect(result.available.isZero)
        #expect(result.shortfall == nil)
        #expect(try breakdownSum(result) == rub(0))
    }

    @Test("reservedTotal convenience path matches the split path")
    func reservedTotalPathEquivalence() throws {
        let split = SafeToSpendInput(
            liquidBalance: rub(300_000),
            goalAllocatedTotal: rub(70_000),
            emergencyReserve: rub(30_000),
            upcomingMandatory: rub(60_000),
            minimumBuffer: rub(50_000)
        )
        let aggregated = SafeToSpendInput(
            liquidBalance: rub(300_000),
            reservedTotal: rub(100_000),
            upcomingMandatory: rub(60_000),
            minimumBuffer: rub(50_000)
        )

        let splitResult = try SafeToSpendEngine.evaluate(split)
        let aggregatedResult = try SafeToSpendEngine.evaluate(aggregated)

        #expect(splitResult.available == aggregatedResult.available)
        #expect(splitResult.shortfall == aggregatedResult.shortfall)
        #expect(try split.reservedTotal() == rub(100_000))
        #expect(try aggregated.reservedTotal() == rub(100_000))
    }

    @Test("negative liquid balance (overdraft) is allowed and produces a shortfall")
    func negativeLiquidBalance() throws {
        let input = SafeToSpendInput(
            liquidBalance: rub(-10_000),
            reservedTotal: rub(0),
            upcomingMandatory: rub(0),
            minimumBuffer: rub(0)
        )

        let result = try SafeToSpendEngine.evaluate(input)

        #expect(result.available == rub(0))
        #expect(result.shortfall == rub(10_000))
    }

    @Test("negative deduction is rejected — it would inflate spendable money")
    func negativeDeductionThrows() {
        let input = SafeToSpendInput(
            liquidBalance: rub(100_000),
            goalAllocatedTotal: rub(-1),
            emergencyReserve: rub(0),
            upcomingMandatory: rub(0),
            minimumBuffer: rub(0)
        )

        #expect(throws: SafeToSpendError.negativeComponent(.goalReserved)) {
            _ = try SafeToSpendEngine.evaluate(input)
        }
    }

    @Test("currency mismatch between fields throws instead of producing a wrong number")
    func currencyMismatchThrows() {
        let input = SafeToSpendInput(
            liquidBalance: rub(100_000),
            goalAllocatedTotal: Money(major: 500, currency: .usd),
            emergencyReserve: rub(0),
            upcomingMandatory: rub(0),
            minimumBuffer: rub(0)
        )

        #expect(throws: MoneyError.currencyMismatch("RUB", "USD")) {
            _ = try SafeToSpendEngine.evaluate(input)
        }
    }

    @Test("exact boundary: protections equal liquid → zero available, no shortfall")
    func exactBoundaryIsNotShortfall() throws {
        let input = SafeToSpendInput(
            liquidBalance: rub(150_000),
            goalAllocatedTotal: rub(100_000),
            emergencyReserve: rub(0),
            upcomingMandatory: rub(30_000),
            minimumBuffer: rub(20_000)
        )

        let result = try SafeToSpendEngine.evaluate(input)

        #expect(result.available == rub(0))
        #expect(result.shortfall == nil)
    }

    @Test("minor units survive intact — no rounding anywhere in the pipeline")
    func minorUnitPrecision() throws {
        let input = SafeToSpendInput(
            liquidBalance: Money(minor: 123_456, currency: .rub),
            goalAllocatedTotal: Money(minor: 23_450, currency: .rub),
            emergencyReserve: Money(minor: 5, currency: .rub),
            upcomingMandatory: Money(minor: 1, currency: .rub),
            minimumBuffer: Money(minor: 0, currency: .rub)
        )

        let result = try SafeToSpendEngine.evaluate(input)

        #expect(result.available == Money(minor: 100_000, currency: .rub))
        #expect(result.shortfall == nil)
    }
}
