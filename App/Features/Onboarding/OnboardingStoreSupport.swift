import FinPlanCore

extension FinanceStore {
    func upsertPlanningRate(_ rate: ExchangeRate) {
        let remaining = planningRates.rates.filter { existing in
            let samePair = existing.base == rate.base && existing.quote == rate.quote
            let invertedPair = existing.base == rate.quote && existing.quote == rate.base
            return !samePair && !invertedPair
        }
        planningRates = ManualExchangeRates(rates: remaining + [rate])
    }
}
