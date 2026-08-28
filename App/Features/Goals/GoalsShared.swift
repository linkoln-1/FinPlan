import SwiftUI
import FinPlanCore

struct GoalsPriorityBadge: View {
    let priority: GoalPriority

    var body: some View {
        Text(titleKey)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, FP.Spacing.sm)
            .padding(.vertical, FP.Spacing.xs)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private var titleKey: LocalizedStringKey {
        switch priority {
        case .low: return "goals.priority.low"
        case .medium: return "goals.priority.medium"
        case .high: return "goals.priority.high"
        }
    }

    private var tint: Color {
        switch priority {
        case .low: return FPStatusTint.neutral
        case .medium: return .accentColor
        case .high: return FPStatusTint.attention
        }
    }
}

struct GoalsEmergencyBadge: View {
    var body: some View {
        Label("goals.badge.emergencyFund", systemImage: "shield.lefthalf.filled")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, FP.Spacing.sm)
            .padding(.vertical, FP.Spacing.xs)
            .background(FPStatusTint.positive.opacity(0.15), in: Capsule())
            .foregroundStyle(FPStatusTint.positive)
    }
}

struct GoalsStatusBadge: View {
    let status: GoalStatus

    var body: some View {
        Text(titleKey)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, FP.Spacing.sm)
            .padding(.vertical, FP.Spacing.xs)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var titleKey: LocalizedStringKey {
        switch status {
        case .planned: return "goals.status.planned"
        case .active: return "goals.status.active"
        case .paused: return "goals.status.paused"
        case .completed: return "goals.status.completed"
        case .archived: return "goals.status.archived"
        }
    }
}

enum GoalsDisplay {
    static func percentText(basisPoints: Int) -> String {
        (Double(basisPoints) / 10_000)
            .formatted(.percent.precision(.fractionLength(0...1)))
    }

    static func progressFraction(basisPoints: Int) -> Double {
        Double(basisPoints) / 10_000
    }

    static func editableText(for money: Money, locale: Locale = .current) -> String {
        let perMajor = money.currency.minorUnitsPerMajor
        guard perMajor > 1 else { return "\(money.amountMinor)" }
        let whole = money.amountMinor / perMajor
        let fraction = abs(money.amountMinor % perMajor)
        if fraction == 0 { return "\(whole)" }
        let separator = locale.decimalSeparator ?? "."
        let width = money.currency.minorUnitExponent
        let padded = String(String("\(fraction)".reversed()).padding(toLength: width, withPad: "0", startingAt: 0).reversed())
        return "\(whole)\(separator)\(padded)"
    }
}

enum GoalsSymbolCatalog {
    static let symbols: [String] = [
        "target", "house.fill", "car.fill", "airplane", "graduationcap.fill",
        "heart.fill", "gift.fill", "laptopcomputer", "iphone", "briefcase.fill",
        "shield.lefthalf.filled", "banknote", "stroller.fill", "pawprint.fill",
        "book.fill", "cross.case.fill", "bicycle", "sailboat.fill",
        "tent.fill", "guitars.fill",
    ]
}
