import SwiftUI
import FinPlanCore

enum MoneyParser {
    static func minorUnits(from text: String, currency: Currency, locale: Locale = .current) -> Int64? {
        _ = locale
        var normalized = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: "")
        let lastComma = normalized.range(of: ",", options: .backwards)?.lowerBound
        let lastDot = normalized.range(of: ".", options: .backwards)?.lowerBound
        if let comma = lastComma, let dot = lastDot {
            let decimal = max(comma, dot)
            let grouping: Character = normalized[decimal] == "," ? "." : ","
            normalized.removeAll { $0 == grouping }
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        } else {
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        }
        guard !normalized.isEmpty, normalized != "." else { return nil }
        let parts = normalized.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count <= 2,
              !parts[0].isEmpty || parts.count == 2,
              parts[0].allSatisfy(\.isNumber),
              let whole = Int64(parts[0].isEmpty ? "0" : String(parts[0])) else { return nil }
        var fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= currency.minorUnitExponent, fraction.allSatisfy(\.isNumber) else { return nil }
        while fraction.count < currency.minorUnitExponent { fraction.append("0") }
        let fractionValue = Int64(fraction.isEmpty ? "0" : fraction) ?? 0
        let (scaled, overflow1) = whole.multipliedReportingOverflow(by: currency.minorUnitsPerMajor)
        guard !overflow1 else { return nil }
        let (result, overflow2) = scaled.addingReportingOverflow(fractionValue)
        guard !overflow2 else { return nil }
        return result
    }
}

struct MoneyField: View {
    let titleKey: LocalizedStringKey
    let currency: Currency
    @Binding var text: String
    @Binding var amountMinor: Int64?

    var body: some View {
        HStack {
            TextField(titleKey, text: $text)
                .keyboardType(.decimalPad)
                .onChange(of: text) { _, newValue in
                    amountMinor = MoneyParser.minorUnits(from: newValue, currency: currency)
                }
            Text(currency.code)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}
