import Foundation

public enum LedgerError: Error, Equatable, Sendable {
    case missingExchangeRate(base: String, quote: String)
    case unattributableExchangeFee(transactionID: UUID)
}

public struct PeriodSummary: Hashable, Sendable {
    public let income: Money
    public let expenses: Money
    public let savingsAllocated: Money
    public let fees: Money
    public let freeCashFlow: Money

    public init(income: Money, expenses: Money, savingsAllocated: Money, fees: Money, freeCashFlow: Money) {
        self.income = income
        self.expenses = expenses
        self.savingsAllocated = savingsAllocated
        self.fees = fees
        self.freeCashFlow = freeCashFlow
    }
}

public struct LedgerEngine: Sendable {
    public init() {}

    public static func balance(
        of account: Account,
        transactions: [TransactionRecord],
        asOf date: Date
    ) throws -> Money {
        var result = account.openingBalance
        for transaction in transactions
        where transaction.status.affectsActualBalance && transaction.date <= date {
            result = try applying(transaction, to: result, accountID: account.id)
        }
        return result
    }

    public static func netWorth(
        accounts: [Account],
        transactions: [TransactionRecord],
        asOf date: Date,
        in baseCurrency: Currency,
        rates: any ExchangeRateProvider
    ) throws -> Money {
        var total = Money.zero(baseCurrency)
        for account in accounts where account.includedInNetWorth && !account.isArchived {
            let accountBalance = try balance(of: account, transactions: transactions, asOf: date)
            let converted = try converted(accountBalance, to: baseCurrency, rates: rates)
            if account.isLiability {
                total = try total.subtracting(converted)
            } else {
                total = try total.adding(converted)
            }
        }
        return total
    }

    public static func periodSummary(
        transactions: [TransactionRecord],
        in interval: DateInterval,
        currency: Currency,
        rates: any ExchangeRateProvider
    ) throws -> PeriodSummary {
        var income = Money.zero(currency)
        var expenses = Money.zero(currency)
        var savings = Money.zero(currency)
        var fees = Money.zero(currency)

        for transaction in transactions
        where transaction.status.affectsActualBalance && transaction.date >= interval.start && transaction.date < interval.end {
            switch transaction.kind {
            case .income:
                income = try income.adding(converted(transaction.amount, to: currency, rates: rates))
            case .expense:
                if transaction.goalID != nil {
                    savings = try savings.adding(converted(transaction.amount, to: currency, rates: rates))
                } else {
                    expenses = try expenses.adding(converted(transaction.amount, to: currency, rates: rates))
                }
            case .transfer:
                if transaction.goalID != nil {
                    savings = try savings.adding(converted(transaction.amount, to: currency, rates: rates))
                }
                if let fee = transaction.fee {
                    fees = try fees.adding(converted(fee, to: currency, rates: rates))
                }
            case .currencyExchange:
                if let fee = transaction.fee {
                    guard fee.currency == transaction.amount.currency
                        || fee.currency == transaction.counterAmount?.currency else {
                        throw LedgerError.unattributableExchangeFee(transactionID: transaction.id)
                    }
                    fees = try fees.adding(converted(fee, to: currency, rates: rates))
                }
            case .adjustment:
                break
            }
        }

        let freeCashFlow = try income.subtracting(expenses).subtracting(savings)
        return PeriodSummary(
            income: income,
            expenses: expenses,
            savingsAllocated: savings,
            fees: fees,
            freeCashFlow: freeCashFlow
        )
    }

    public static func incomeTotal(
        transactions: [TransactionRecord],
        in interval: DateInterval,
        currency: Currency,
        rates: any ExchangeRateProvider
    ) throws -> Money {
        try periodSummary(transactions: transactions, in: interval, currency: currency, rates: rates).income
    }

    public static func expenseTotal(
        transactions: [TransactionRecord],
        in interval: DateInterval,
        currency: Currency,
        rates: any ExchangeRateProvider
    ) throws -> Money {
        try periodSummary(transactions: transactions, in: interval, currency: currency, rates: rates).expenses
    }

    public static func savingsAllocated(
        transactions: [TransactionRecord],
        in interval: DateInterval,
        currency: Currency,
        rates: any ExchangeRateProvider
    ) throws -> Money {
        try periodSummary(transactions: transactions, in: interval, currency: currency, rates: rates).savingsAllocated
    }

    public static func freeCashFlow(
        transactions: [TransactionRecord],
        in interval: DateInterval,
        currency: Currency,
        rates: any ExchangeRateProvider
    ) throws -> Money {
        try periodSummary(transactions: transactions, in: interval, currency: currency, rates: rates).freeCashFlow
    }

    public static func categoryBreakdown(
        transactions: [TransactionRecord],
        in interval: DateInterval,
        currency: Currency,
        rates: any ExchangeRateProvider
    ) throws -> [UUID?: Money] {
        var result: [UUID?: Money] = [:]
        for transaction in transactions
        where transaction.status.affectsActualBalance
            && transaction.date >= interval.start && transaction.date < interval.end
            && transaction.kind == .expense
            && transaction.goalID == nil {
            if transaction.splits.isEmpty {
                let amount = try converted(transaction.amount, to: currency, rates: rates)
                result[transaction.categoryID] = try (result[transaction.categoryID] ?? .zero(currency)).adding(amount)
            } else {
                for split in transaction.splits {
                    let amount = try converted(split.amount, to: currency, rates: rates)
                    result[split.categoryID] = try (result[split.categoryID] ?? .zero(currency)).adding(amount)
                }
            }
        }
        return result
    }

    public static func allocatedTotal(
        toGoal goalID: UUID,
        allocations: [GoalAllocation],
        asOf date: Date,
        in currency: Currency,
        rates: any ExchangeRateProvider
    ) throws -> Money {
        var total = Money.zero(currency)
        for allocation in allocations where allocation.goalID == goalID && allocation.date <= date {
            total = try total.adding(converted(allocation.amount, to: currency, rates: rates))
        }
        return total
    }

    private static func applying(
        _ transaction: TransactionRecord,
        to balance: Money,
        accountID: UUID
    ) throws -> Money {
        var result = balance
        switch transaction.kind {
        case .income:
            if transaction.destinationAccountID == accountID {
                result = try result.adding(transaction.amount)
            }
        case .expense:
            if transaction.sourceAccountID == accountID {
                result = try result.subtracting(transaction.amount)
            }
        case .transfer:
            if transaction.sourceAccountID == accountID {
                result = try result.subtracting(transaction.amount)
                if let fee = transaction.fee {
                    result = try result.subtracting(fee)
                }
            }
            if transaction.destinationAccountID == accountID {
                result = try result.adding(transaction.amount)
            }
        case .currencyExchange:
            result = try applyingExchange(transaction, to: result, accountID: accountID)
        case .adjustment:
            if transaction.destinationAccountID == accountID {
                result = try result.adding(transaction.amount)
            }
            if transaction.sourceAccountID == accountID {
                result = try result.subtracting(transaction.amount)
            }
        }
        return result
    }

    private static func applyingExchange(
        _ transaction: TransactionRecord,
        to balance: Money,
        accountID: UUID
    ) throws -> Money {
        let isSource = transaction.sourceAccountID == accountID
        let isDestination = transaction.destinationAccountID == accountID
        guard isSource || isDestination else { return balance }

        var result = balance
        if isSource {
            result = try result.subtracting(transaction.amount)
        }
        if isDestination, let counter = transaction.counterAmount {
            result = try result.adding(counter)
        }
        if let fee = transaction.fee {
            if fee.currency == transaction.amount.currency {
                if isSource {
                    result = try result.subtracting(fee)
                }
            } else if fee.currency == transaction.counterAmount?.currency {
                if isDestination {
                    result = try result.subtracting(fee)
                }
            } else {
                throw LedgerError.unattributableExchangeFee(transactionID: transaction.id)
            }
        }
        return result
    }

    private static func converted(
        _ money: Money,
        to currency: Currency,
        rates: any ExchangeRateProvider
    ) throws -> Money {
        if money.currency == currency { return money }
        guard let rate = rates.rate(from: money.currency, to: currency) else {
            throw LedgerError.missingExchangeRate(base: money.currency.code, quote: currency.code)
        }
        return try rate.convert(money)
    }
}
