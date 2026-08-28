import Foundation
import FinPlanCore

extension LedgerError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingExchangeRate(let base, let quote):
            return String(localized: "error.core.missingRate \(base) \(quote)")
        case .unattributableExchangeFee:
            return String(localized: "error.core.unattributableFee")
        }
    }
}

extension ProjectionError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingPlanningRate(let base, let quote):
            return String(localized: "error.core.missingRate \(base) \(quote)")
        case .currencyMismatch(let expected, let actual):
            return String(localized: "error.core.currencyMismatch \(expected) \(actual)")
        case .amountOverflow:
            return String(localized: "error.core.overflow")
        case .invalidContributionDay, .invalidHorizon, .nonPositiveCycleCount, .nonPositivePlannedRate:
            return String(localized: "error.core.invalidPlanInput")
        }
    }
}

extension ScenarioError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingPlanningRate(let base, let quote):
            return String(localized: "error.core.missingRate \(base) \(quote)")
        case .currencyMismatch(let expected, let actual):
            return String(localized: "error.core.currencyMismatch \(expected) \(actual)")
        case .unknownIncomeSource, .invalidShareBasisPoints, .invalidSavingsPercent,
             .negativeSavingsAmount, .nonPositiveTarget, .invalidPlanningRateOverride,
             .zeroOneTimeEventAmount, .targetDateBeforeStart:
            return String(localized: "error.core.invalidPlanInput")
        }
    }
}

extension PurchaseImpactError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingPlanningRate(let base, let quote):
            return String(localized: "error.core.missingRate \(base) \(quote)")
        case .nonPositiveAmount:
            return String(localized: "error.core.amountNotPositive")
        }
    }
}

extension SafeToSpendError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .negativeComponent:
            return String(localized: "error.core.negativeSafeToSpendComponent")
        }
    }
}

extension MoneyError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .currencyMismatch(let expected, let actual):
            return String(localized: "error.core.currencyMismatch \(expected) \(actual)")
        case .overflow:
            return String(localized: "error.core.overflow")
        }
    }
}

extension AnalyticsError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .calendarComputationFailed:
            return String(localized: "error.core.calendar")
        }
    }
}

extension TransactionValidationError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .nonPositiveAmount:
            return String(localized: "error.core.amountNotPositive")
        case .missingSourceAccount:
            return String(localized: "error.core.missingSourceAccount")
        case .missingDestinationAccount:
            return String(localized: "error.core.missingDestinationAccount")
        case .sameAccountTransfer:
            return String(localized: "error.core.sameAccountTransfer")
        case .splitTotalMismatch:
            return String(localized: "error.core.splitTotalMismatch")
        case .splitCurrencyMismatch:
            return String(localized: "error.core.splitCurrencyMismatch")
        case .exchangeMissingCounterAmount:
            return String(localized: "error.core.exchangeMissingCounterAmount")
        case .exchangeSameCurrency:
            return String(localized: "error.core.exchangeSameCurrency")
        }
    }
}
