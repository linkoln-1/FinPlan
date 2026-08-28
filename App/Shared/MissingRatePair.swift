import Foundation
import FinPlanCore

struct MissingRatePair: Hashable, Sendable {
    let base: Currency
    let quote: Currency

    init(base: Currency, quote: Currency) {
        self.base = base
        self.quote = quote
    }

    init?(error: Error) {
        switch error {
        case LedgerError.missingExchangeRate(let base, let quote),
             ProjectionError.missingPlanningRate(let base, let quote),
             ScenarioError.missingPlanningRate(let base, let quote),
             PurchaseImpactError.missingPlanningRate(let base, let quote):
            self.init(base: Currency.known(code: base), quote: Currency.known(code: quote))
        default:
            return nil
        }
    }
}

struct MissingRatesPrompt: Identifiable {
    let id = UUID()
    let currencies: [Currency]
}
