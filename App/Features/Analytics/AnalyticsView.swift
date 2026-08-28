import SwiftUI
import FinPlanCore

@MainActor
struct AnalyticsView: View {
    @Environment(FinanceStore.self) private var store
    @State private var model = AnalyticsModel()
    @State private var activeError: String?
    @State private var ratePrompt: MissingRatesPrompt?

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = model.snapshot {
                    if snapshot.hasFacts {
                        content(snapshot)
                    } else {
                        emptyState
                    }
                } else if model.computeError != nil {
                    emptyState
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("analytics.title")
            .background(Color(.systemGroupedBackground))
        }
        .task(id: computeKey) {
            model.recompute(store: store)
        }
        .onChange(of: store.lastError) { _, newValue in
            if let newValue { activeError = newValue }
        }
        .onChange(of: model.computeError) { _, newValue in
            if let newValue { activeError = newValue }
        }
        .alert("analytics.error.title", isPresented: errorPresented) {
            if let pair = model.missingRate, pair.quote == store.baseCurrency {
                Button("error.addRate") {
                    ratePrompt = MissingRatesPrompt(currencies: [pair.base])
                }
            }
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: activeError ?? "")
        }
        .sheet(item: $ratePrompt) { prompt in
            SettingsMissingRatesSheet(currencies: prompt.currencies) {
                ratePrompt = nil
            }
            .environment(store)
        }
    }

    private func content(_ snapshot: AnalyticsSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FP.Spacing.lg) {
                periodPicker
                AnalyticsSummarySection(summary: snapshot.summary)
                AnalyticsChartsSection(snapshot: snapshot)
                AnalyticsBudgetsSection(rows: snapshot.budgetRows, issue: snapshot.budgetIssue)
                AnalyticsRunwayCard(runwayTenths: snapshot.runwayTenths)
                if let closeInfo = snapshot.monthlyClose {
                    AnalyticsMonthlyCloseCard(info: closeInfo)
                }
                AnalyticsInsightsSection(insights: snapshot.insights)
                if !snapshot.achievements.isEmpty {
                    AnalyticsAchievementsSection(achievements: snapshot.achievements)
                }
            }
            .padding(.horizontal, FP.Spacing.lg)
            .padding(.bottom, FP.Spacing.xxl)
        }
    }

    private var periodPicker: some View {
        @Bindable var model = model
        return Picker("analytics.period.title", selection: $model.period) {
            Text("analytics.period.currentMonth").tag(AnalyticsPeriod.currentMonth)
            Text("analytics.period.threeMonths").tag(AnalyticsPeriod.threeMonths)
            Text("analytics.period.sixMonths").tag(AnalyticsPeriod.sixMonths)
            Text("analytics.period.twelveMonths").tag(AnalyticsPeriod.twelveMonths)
            Text("analytics.period.all").tag(AnalyticsPeriod.all)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(Text("analytics.period.title"))
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "chart.bar",
            title: "analytics.empty.title",
            message: "analytics.empty.message"
        )
    }

    private struct ComputeKey: Hashable {
        let period: AnalyticsPeriod
        let dataHash: Int
    }

    private var computeKey: ComputeKey {
        ComputeKey(period: model.period, dataHash: AnalyticsModel.dataFingerprint(of: store))
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { activeError != nil },
            set: { if !$0 { activeError = nil } }
        )
    }
}

@MainActor
struct AnalyticsSummarySection: View {
    let summary: MonthlySummary

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: FP.Spacing.sm) {
            LazyVGrid(columns: columns, spacing: FP.Spacing.md) {
                AnalyticsSummaryCard(titleKey: "analytics.summary.income") {
                    MoneyText(money: summary.income, compact: true)
                }
                AnalyticsSummaryCard(titleKey: "analytics.summary.expenses") {
                    MoneyText(money: summary.expenses, compact: true)
                }
                AnalyticsSummaryCard(titleKey: "analytics.summary.savings") {
                    MoneyText(money: summary.savingsAllocated, compact: true)
                }
                AnalyticsSummaryCard(titleKey: "analytics.summary.netCashFlow") {
                    HStack(spacing: FP.Spacing.xs) {
                        Image(systemName: summary.netCashFlow.isNegative ? "arrow.down.right" : "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(summary.netCashFlow.isNegative ? FPStatusTint.negative : FPStatusTint.positive)
                            .accessibilityHidden(true)
                        MoneyText(money: summary.netCashFlow, compact: true)
                    }
                }
                AnalyticsSummaryCard(titleKey: "analytics.summary.savingsRate") {
                    if let basisPoints = summary.savingsRateBasisPoints {
                        Text(verbatim: AnalyticsFormat.percent(basisPoints: basisPoints))
                            .monospacedDigit()
                    } else {
                        Text("analytics.savingsRate.noIncome")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("analytics.savingsRate.formula")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
private struct AnalyticsSummaryCard<Value: View>: View {
    let titleKey: LocalizedStringKey
    @ViewBuilder var value: Value

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                Text(titleKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                value
                    .font(.headline)
            }
        }
    }
}

#if DEBUG
#Preview("Seeded") {
    let controller = PersistenceController.preview()
    let store = FinanceStore(context: controller.container.mainContext)
    AnalyticsPreviewData.seed(store)
    return AnalyticsView()
        .environment(store)
        .modelContainer(controller.container)
}
#endif

#if DEBUG
#Preview("Empty") {
    let controller = PersistenceController.preview()
    let store = FinanceStore(context: controller.container.mainContext)
    return AnalyticsView()
        .environment(store)
        .modelContainer(controller.container)
}
#endif
