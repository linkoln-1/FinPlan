import SwiftUI
import FinPlanCore

struct RateEntryField: View {
    let currencyA: Currency
    let currencyB: Currency
    let sampleAmount: Money?
    @Binding var rateText: String
    let onRateChange: (ExchangeRate?) -> Void

    @State private var quoteIsFirst = false

    private var displayBase: Currency {
        if swapPreferred { return quoteIsFirst ? currencyA : currencyB }
        return quoteIsFirst ? currencyB : currencyA
    }
    private var displayQuote: Currency {
        displayBase == currencyA ? currencyB : currencyA
    }
    private var swapPreferred: Bool { currencyA.code == "RUB" }

    static func preferredBase(_ a: Currency, _ b: Currency) -> Currency {
        a.code == "RUB" ? b : a
    }

    static func isSuspicious(_ rate: ExchangeRate) -> Bool {
        var scaleDivisor: Int64 = 1
        for _ in 0..<rate.scale { scaleDivisor *= 10 }
        return rate.rateScaled / scaleDivisor >= 100_000
    }

    private var parsedRate: ExchangeRate? {
        ExchangeRate(base: displayBase, quote: displayQuote, decimalString: rateText.replacingOccurrences(of: ",", with: "."))
    }

    private var looksSuspicious: Bool {
        guard let rate = parsedRate else { return false }
        return Self.isSuspicious(rate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FP.Spacing.sm) {
            HStack(spacing: FP.Spacing.sm) {
                Text(verbatim: "1 \(displayBase.code) =")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
                TextField("rate.placeholder", text: $rateText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(String(localized: "rate.a11y.value"))
                Text(verbatim: displayQuote.code)
                    .foregroundStyle(.secondary)
                Button {
                    quoteIsFirst.toggle()
                    rateText = ""
                    onRateChange(nil)
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(String(localized: "rate.a11y.swap"))
            }

            if let rate = parsedRate {
                if looksSuspicious {
                    Label("rate.suspicious", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(FPStatusTint.attention)
                }
                if let sample = sampleAmount, let preview = previewText(rate: rate, sample: sample) {
                    Label {
                        Text(verbatim: preview)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "equal.circle")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(String(localized: "rate.a11y.preview"))
                }
            } else if !rateText.isEmpty {
                Label("rate.invalid", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(FPStatusTint.attention)
            }
        }
        .onChange(of: rateText) { _, _ in
            onRateChange(parsedRate)
        }
    }

    private func previewText(rate: ExchangeRate, sample: Money) -> String? {
        let converted: Money?
        if sample.currency == rate.base {
            converted = try? rate.convert(sample)
        } else if sample.currency == rate.quote {
            converted = (rate.inverted).flatMap { try? $0.convert(sample) }
        } else {
            return nil
        }
        guard let converted else { return nil }
        return "\(sample.formatted(compact: true)) ≈ \(converted.formatted(compact: true))"
    }
}
