import SwiftUI
import FinPlanCore

@MainActor
struct AnalyticsAchievementsSection: View {
    let achievements: [Achievement]

    var body: some View {
        VStack(alignment: .leading, spacing: FP.Spacing.sm) {
            Text("analytics.achievements")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FP.Spacing.md) {
                    ForEach(achievements) { achievement in
                        AnalyticsAchievementCard(achievement: achievement)
                    }
                }
            }
        }
    }
}

@MainActor
private struct AnalyticsAchievementCard: View {
    let achievement: Achievement

    var body: some View {
        VStack(spacing: FP.Spacing.xs) {
            Image(systemName: achievement.symbolName)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(achievement.titleKey))
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
            if let date = achievement.achievedDate {
                Text(date, format: .dateTime.month(.abbreviated).year())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(FP.Spacing.md)
        .frame(width: 132)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: FP.Radius.card)
        )
        .accessibilityElement(children: .combine)
    }
}
