import SwiftUI
import Charts
import FinPlanCore

struct PlanWhatIfSection: View {
    @Environment(FinanceStore.self) private var store

    var body: some View {
        switch basePlanResult() {
        case .success(nil):
            EmptyStateView(
                systemImage: "slider.horizontal.3",
                title: "plan.whatif.empty.title",
                message: "plan.whatif.empty.message"
            )
        case .success(.some(let plan)):
            PlanWhatIfForm(basePlan: plan)
        case .failure(let error):
            ScrollView {
                PlanComputationErrorCard(error: error)
                    .padding(FP.Spacing.lg)
            }
        }
    }

    private func basePlanResult() -> Result<ScenarioBasePlan?, any Error> {
        Result { try store.planBasePlan(now: .now) }
    }
}

private struct PlanWhatIfForm: View {
    let basePlan: ScenarioBasePlan

    @Environment(FinanceStore.self) private var store

    @State private var shareOverrides: [UUID: Int] = [:]
    @State private var savingsText = ""
    @State private var savingsMinor: Int64?
    @State private var rateText = ""
    @State private var rateOverride: ExchangeRate?
    @State private var rateFieldGeneration = 0
    @State private var oneTimeEnabled = false
    @State private var oneTimeText = ""
    @State private var oneTimeMinor: Int64?
    @State private var oneTimeDate = Date.now
    @State private var oneTimeIsOutflow = false
    @State private var targetText = ""
    @State private var targetMinor: Int64?

    @State private var savedScenarios: [Scenario] = []
    @State private var showSavePrompt = false
    @State private var scenarioName = ""
    @State private var errorMessage: String?

    private static let shareOptionsBps = [2_500, 5_000, 7_500, 10_000]

    private var savingsCurrency: Currency { basePlan.monthlySavings.currency }
    private var goalCurrency: Currency { basePlan.targetAmount.currency }

    var body: some View {
        Form {
            resultSection
            incomeSection
            savingsSection
            if savingsCurrency != goalCurrency {
                rateSection
            }
            oneTimeSection
            targetSection
            savedSection
        }
        .task { refreshSavedScenarios() }
        .alert("plan.whatif.savePrompt.title", isPresented: $showSavePrompt) {
            TextField("plan.whatif.savePrompt.placeholder", text: $scenarioName)
            Button("plan.common.save") { saveCurrentScenario() }
            Button("plan.common.cancel", role: .cancel) {}
        } message: {
            Text("plan.whatif.savePrompt.message")
        }
        .alert(
            "plan.alert.actionFailed.title",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("plan.common.ok", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        Section {
            switch computeOutcome() {
            case .success(let outcome):
                PlanProjectionChart(
                    basePoints: outcome.basePoints,
                    scenarioPoints: outcome.scenarioPoints,
                    target: basePlan.targetAmount
                )
                PlanComparisonGrid(comparison: outcome.comparison)
            case .failure(let error):
                Label {
                    Text(verbatim: (error as? LocalizedError)?.errorDescription ?? String(describing: error))
                        .font(.caption)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(FPStatusTint.attention)
            }
        } header: {
            Text("plan.whatif.result.header")
        }
    }

    private var incomeSection: some View {
        Section {
            if basePlan.incomeSources.isEmpty {
                Text("plan.whatif.income.none")
                    .foregroundStyle(.secondary)
            }
            ForEach(basePlan.incomeSources) { source in
                HStack {
                    VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                        Text(verbatim: source.name)
                        MoneyText(money: source.personalAmount)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("plan.whatif.income.share", selection: shareBinding(source.id)) {
                        Text("plan.whatif.income.baseShare").tag(-1)
                        ForEach(Self.shareOptionsBps, id: \.self) { bps in
                            Text(verbatim: sharePercentLabel(bps)).tag(bps)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel(String(localized: "plan.a11y.shareFor") + " " + source.name)
                }
            }
        } header: {
            Text("plan.whatif.income.header")
        } footer: {
            Text("plan.whatif.income.footer")
        }
    }

    private var savingsSection: some View {
        Section {
            MoneyField(
                titleKey: "plan.whatif.savings.field",
                currency: savingsCurrency,
                text: $savingsText,
                amountMinor: $savingsMinor
            )
            if basePlan.monthlySavings.isPositive {
                HStack(spacing: FP.Spacing.sm) {
                    ForEach(quickSavingsAmounts(), id: \.amountMinor) { amount in
                        Button {
                            savingsText = planFieldText(for: amount)
                            savingsMinor = amount.amountMinor
                        } label: {
                            MoneyText(money: amount, compact: true)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, FP.Spacing.sm)
                                .padding(.vertical, FP.Spacing.xs)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        } header: {
            Text("plan.whatif.savings.header")
        } footer: {
            HStack(spacing: FP.Spacing.xs) {
                Text("plan.whatif.savings.base")
                MoneyText(money: basePlan.monthlySavings)
            }
        }
    }

    private func quickSavingsAmounts() -> [Money] {
        let base = basePlan.monthlySavings
        return [
            base,
            base.multiplied(byNumerator: 5, denominator: 4),
            base.multiplied(byNumerator: 25, denominator: 16),
        ]
    }

    private var rateSection: some View {
        Section {
            RateEntryField(
                currencyA: savingsCurrency,
                currencyB: goalCurrency,
                sampleAmount: scenarioMonthlySavings,
                rateText: $rateText,
                onRateChange: { rateOverride = $0 }
            )
            .id("whatif-rate-\(rateFieldGeneration)")
        } header: {
            Text("plan.whatif.rate.header")
        } footer: {
            Text("plan.whatif.rate.footer")
        }
    }

    private var scenarioMonthlySavings: Money? {
        if let minor = savingsMinor, minor > 0 {
            return Money(minor: minor, currency: savingsCurrency)
        }
        return basePlan.monthlySavings.isPositive ? basePlan.monthlySavings : nil
    }

    private func displayAligned(_ rate: ExchangeRate) -> ExchangeRate? {
        let preferred = RateEntryField.preferredBase(savingsCurrency, goalCurrency)
        let other = preferred == savingsCurrency ? goalCurrency : savingsCurrency
        if rate.base == preferred, rate.quote == other { return rate }
        if rate.base == other, rate.quote == preferred { return rate.inverted }
        return nil
    }

    private var oneTimeSection: some View {
        Section {
            Toggle("plan.whatif.onetime.toggle", isOn: $oneTimeEnabled)
            if oneTimeEnabled {
                Picker("plan.whatif.onetime.direction", selection: $oneTimeIsOutflow) {
                    Text("plan.whatif.onetime.inflow").tag(false)
                    Text("plan.whatif.onetime.outflow").tag(true)
                }
                .pickerStyle(.segmented)
                MoneyField(
                    titleKey: "plan.whatif.onetime.amount",
                    currency: goalCurrency,
                    text: $oneTimeText,
                    amountMinor: $oneTimeMinor
                )
                DatePicker(
                    "plan.whatif.onetime.date",
                    selection: $oneTimeDate,
                    displayedComponents: .date
                )
            }
        } header: {
            Text("plan.whatif.onetime.header")
        }
    }

    private var targetSection: some View {
        Section {
            MoneyField(
                titleKey: "plan.whatif.target.field",
                currency: goalCurrency,
                text: $targetText,
                amountMinor: $targetMinor
            )
        } header: {
            Text("plan.whatif.target.header")
        } footer: {
            HStack(spacing: FP.Spacing.xs) {
                Text("plan.whatif.target.base")
                MoneyText(money: basePlan.targetAmount)
            }
        }
    }

    private var savedSection: some View {
        Section {
            Button {
                scenarioName = ""
                showSavePrompt = true
            } label: {
                Label("plan.whatif.saveScenario", systemImage: "square.and.arrow.down")
            }
            .disabled(!hasAnyOverride)
            Button(role: .destructive) {
                resetControls()
            } label: {
                Label("plan.whatif.reset", systemImage: "arrow.counterclockwise")
            }
            .disabled(!hasAnyOverride)
            if savedScenarios.isEmpty {
                Text("plan.whatif.saved.none")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(savedScenarios) { scenario in
                    Button {
                        load(scenario)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: FP.Spacing.xs) {
                                Text(verbatim: scenario.name)
                                    .foregroundStyle(.primary)
                                Text("plan.whatif.saved.tapToLoad")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.backward.circle")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .onDelete(perform: deleteScenarios)
                NavigationLink {
                    PlanScenarioComparisonView(basePlan: basePlan, scenarios: savedScenarios)
                } label: {
                    Label("plan.whatif.compareAll", systemImage: "chart.bar.doc.horizontal")
                }
            }
        } header: {
            Text("plan.whatif.saved.header")
        }
    }

    private var hasAnyOverride: Bool {
        !shareOverrides.isEmpty
            || (savingsMinor ?? 0) > 0
            || rateOverride != nil
            || (oneTimeEnabled && (oneTimeMinor ?? 0) > 0)
            || (targetMinor ?? 0) > 0
    }

    private func buildOverrides() -> ScenarioOverrides {
        var overrides = ScenarioOverrides()
        if !shareOverrides.isEmpty {
            overrides.incomeShareBps = shareOverrides
        }
        if let minor = savingsMinor, minor > 0 {
            overrides.monthlySavingsAmount = Money(minor: minor, currency: savingsCurrency)
        }
        if let rateOverride {
            overrides.planningRate = .rate(rateOverride)
        }
        if oneTimeEnabled, let minor = oneTimeMinor, minor > 0 {
            let amount = Money(minor: oneTimeIsOutflow ? -minor : minor, currency: goalCurrency)
            overrides.extraOneTimeEvents = [ScenarioOneTime(amount: amount, timing: .date(oneTimeDate))]
        }
        if let minor = targetMinor, minor > 0 {
            overrides.targetAmount = Money(minor: minor, currency: goalCurrency)
        }
        return overrides
    }

    private func computeOutcome() -> Result<PlanWhatIfOutcome, any Error> {
        Result {
            let overrides = buildOverrides()
            let scenario = Scenario(name: "", overrides: overrides)
            let comparison = try ScenarioEngine.compare(base: basePlan, scenario: scenario)
            let baseInput = try ScenarioEngine.apply(ScenarioOverrides(), to: basePlan)
            let scenarioInput = try ScenarioEngine.apply(overrides, to: basePlan)
            return PlanWhatIfOutcome(
                comparison: comparison,
                basePoints: try ProjectionEngine.project(baseInput).points,
                scenarioPoints: try ProjectionEngine.project(scenarioInput).points
            )
        }
    }

    private func refreshSavedScenarios() {
        do {
            savedScenarios = try store.planLoadScenarios()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func saveCurrentScenario() {
        let name = scenarioName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = String(localized: "plan.whatif.error.emptyName")
            return
        }
        do {
            try store.planSaveScenario(Scenario(name: name, overrides: buildOverrides()))
            refreshSavedScenarios()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func deleteScenarios(at offsets: IndexSet) {
        do {
            for index in offsets {
                try store.planDeleteScenario(id: savedScenarios[index].id)
            }
            refreshSavedScenarios()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func load(_ scenario: Scenario) {
        let overrides = scenario.overrides
        shareOverrides = overrides.incomeShareBps ?? [:]
        if let amount = overrides.monthlySavingsAmount {
            savingsText = planFieldText(for: amount)
            savingsMinor = amount.amountMinor
        } else {
            savingsText = ""
            savingsMinor = nil
        }
        rateFieldGeneration += 1
        let savedRate: ExchangeRate? = switch overrides.planningRate {
        case .rate(let rate): rate
        case .decimalString(let base, let quote, let value):
            ExchangeRate(base: base, quote: quote, decimalString: value)
        case nil: nil
        }
        if let aligned = savedRate.flatMap(displayAligned) {
            rateText = SettingsRateFormat.display(aligned)
            rateOverride = aligned
        } else {
            rateText = ""
            rateOverride = nil
        }
        if let event = overrides.extraOneTimeEvents?.first {
            oneTimeEnabled = true
            oneTimeIsOutflow = event.amount.isNegative
            let magnitude = event.amount.isNegative ? event.amount.negated : event.amount
            oneTimeText = planFieldText(for: magnitude)
            oneTimeMinor = magnitude.amountMinor
            if case .date(let date) = event.timing {
                oneTimeDate = date
            }
        } else {
            oneTimeEnabled = false
            oneTimeText = ""
            oneTimeMinor = nil
        }
        if let target = overrides.targetAmount {
            targetText = planFieldText(for: target)
            targetMinor = target.amountMinor
        } else {
            targetText = ""
            targetMinor = nil
        }
    }

    private func resetControls() {
        shareOverrides = [:]
        savingsText = ""
        savingsMinor = nil
        rateText = ""
        rateOverride = nil
        rateFieldGeneration += 1
        oneTimeEnabled = false
        oneTimeText = ""
        oneTimeMinor = nil
        targetText = ""
        targetMinor = nil
    }

    private func shareBinding(_ id: UUID) -> Binding<Int> {
        Binding(
            get: { shareOverrides[id] ?? -1 },
            set: { newValue in
                if newValue < 0 {
                    shareOverrides.removeValue(forKey: id)
                } else {
                    shareOverrides[id] = newValue
                }
            }
        )
    }

    private func sharePercentLabel(_ bps: Int) -> String {
        (bps / 100).formatted(.percent)
    }
}

private struct PlanWhatIfOutcome {
    let comparison: ScenarioComparison
    let basePoints: [ProjectionPoint]
    let scenarioPoints: [ProjectionPoint]
}

struct PlanProjectionChart: View {
    let basePoints: [ProjectionPoint]
    let scenarioPoints: [ProjectionPoint]
    let target: Money

    @Environment(FinanceStore.self) private var store

    private static let maxChartPoints = 96

    var body: some View {
        let baseLabel = String(localized: "plan.chart.base")
        let scenarioLabel = String(localized: "plan.chart.scenario")
        let xDomain = FPProjectionDomain.clampedDomain(
            for: basePoints.map(\.date) + scenarioPoints.map(\.date)
        )
        Chart {
            ForEach(downsampled(basePoints), id: \.cycleIndex) { point in
                LineMark(
                    x: .value("plan.chart.axis.date", point.date),
                    y: .value("plan.chart.axis.balance", planChartMajorUnits(point.balance)),
                    series: .value(baseLabel, baseLabel)
                )
                .foregroundStyle(by: .value("plan.chart.series", baseLabel))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(downsampled(scenarioPoints), id: \.cycleIndex) { point in
                LineMark(
                    x: .value("plan.chart.axis.date", point.date),
                    y: .value("plan.chart.axis.balance", planChartMajorUnits(point.balance)),
                    series: .value(scenarioLabel, scenarioLabel)
                )
                .foregroundStyle(by: .value("plan.chart.series", scenarioLabel))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            RuleMark(y: .value("plan.chart.axis.target", planChartMajorUnits(target)))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .annotation(position: .bottom, alignment: .trailing, spacing: 2) {
                    FPTargetAnnotationLabel(titleKey: "plan.chart.targetLine")
                }
        }
        .chartForegroundStyleScale([
            baseLabel: Color.blue,
            scenarioLabel: Color.orange,
        ])
        .chartXScale(domain: xDomain)
        .fpProjectionXAxis(spansYears: FPProjectionDomain.spansYears(xDomain))
        .fpMoneyYAxis(currencyCode: target.currency.code, hidden: store.hideBalances)
        .chartLegend(position: .bottom, spacing: FP.Spacing.sm)
        .frame(height: 220)
        .accessibilityLabel(String(localized: "plan.a11y.projectionChart"))
    }

    private func downsampled(_ points: [ProjectionPoint]) -> [ProjectionPoint] {
        guard points.count > Self.maxChartPoints else { return points }
        let step = max(1, points.count / Self.maxChartPoints)
        var reduced = stride(from: 0, to: points.count, by: step).map { points[$0] }
        if let last = points.last, reduced.last?.cycleIndex != last.cycleIndex {
            reduced.append(last)
        }
        return reduced
    }
}

func planChartMajorUnits(_ money: Money) -> Double {
    Double(money.amountMinor) / Double(money.currency.minorUnitsPerMajor)
}

struct PlanComparisonGrid: View {
    let comparison: ScenarioComparison

    var body: some View {
        Grid(horizontalSpacing: FP.Spacing.lg, verticalSpacing: FP.Spacing.sm) {
            GridRow {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                Text("plan.compare.baseColumn")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                Text("plan.compare.scenarioColumn")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
            }
            GridRow {
                rowLabel("plan.compare.completion")
                completionText(comparison.base)
                completionText(comparison.scenario)
            }
            GridRow {
                rowLabel("plan.compare.monthlyContribution")
                MoneyText(money: comparison.base.monthlyContribution, compact: true)
                    .font(.callout)
                MoneyText(money: comparison.scenario.monthlyContribution, compact: true)
                    .font(.callout.weight(.semibold))
            }
            GridRow {
                rowLabel("plan.compare.income")
                MoneyText(money: comparison.base.totalProjectedIncome, compact: true)
                    .font(.callout)
                MoneyText(money: comparison.scenario.totalProjectedIncome, compact: true)
                    .font(.callout)
            }
            GridRow {
                rowLabel("plan.compare.freeMonthly")
                PlanSignedMoneyText(delta: comparison.base.freeMonthly, compact: true)
                    .font(.callout)
                PlanSignedMoneyText(delta: comparison.scenario.freeMonthly, compact: true)
                    .font(.callout)
            }
        }
        .accessibilityElement(children: .contain)
        deltaSummary
    }

    private func rowLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)
    }

    @ViewBuilder
    private func completionText(_ outcome: ScenarioOutcome) -> some View {
        if let date = outcome.completionDate {
            Text(date, format: .dateTime.month(.abbreviated).year())
                .font(.callout)
                .monospacedDigit()
        } else {
            Text("plan.compare.notReached")
                .font(.caption)
                .foregroundStyle(FPStatusTint.attention)
        }
    }

    @ViewBuilder
    private var deltaSummary: some View {
        if let saved = comparison.cyclesSaved, saved != 0 {
            Label {
                HStack(spacing: FP.Spacing.xs) {
                    Text(verbatim: saved > 0 ? "−" : "+")
                    Text(abs(saved), format: .number)
                        .monospacedDigit()
                    Text("plan.compare.months")
                }
            } icon: {
                Image(systemName: saved > 0 ? "hare" : "tortoise")
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(saved > 0 ? FPStatusTint.positive : FPStatusTint.negative)
            .accessibilityLabel(
                saved > 0
                    ? String(localized: "plan.a11y.finishesEarlier")
                    : String(localized: "plan.a11y.finishesLater")
            )
        }
    }
}

struct PlanScenarioComparisonView: View {
    let basePlan: ScenarioBasePlan
    let scenarios: [Scenario]

    var body: some View {
        Group {
            if scenarios.isEmpty {
                EmptyStateView(
                    systemImage: "chart.bar.doc.horizontal",
                    title: "plan.compareAll.empty.title",
                    message: "plan.compareAll.empty.message"
                )
            } else {
                List {
                    ForEach(scenarios) { scenario in
                        Section {
                            switch comparisonResult(for: scenario) {
                            case .success(let comparison):
                                PlanComparisonGrid(comparison: comparison)
                            case .failure(let error):
                                Label {
                                    Text(verbatim: (error as? LocalizedError)?.errorDescription
                                        ?? String(describing: error))
                                        .font(.caption)
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                }
                                .foregroundStyle(FPStatusTint.attention)
                            }
                        } header: {
                            Text(verbatim: scenario.name)
                        }
                    }
                }
            }
        }
        .navigationTitle("plan.compareAll.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func comparisonResult(for scenario: Scenario) -> Result<ScenarioComparison, any Error> {
        Result { try ScenarioEngine.compare(base: basePlan, scenario: scenario) }
    }
}

func planFieldText(for money: Money) -> String {
    let perMajor = money.currency.minorUnitsPerMajor
    let magnitude = money.amountMinor.magnitude
    let whole = magnitude / UInt64(perMajor)
    let fraction = magnitude % UInt64(perMajor)
    if fraction == 0 { return "\(whole)" }
    let separator = Locale.current.decimalSeparator ?? "."
    var fractionText = String(fraction)
    while fractionText.count < money.currency.minorUnitExponent {
        fractionText = "0" + fractionText
    }
    while fractionText.hasSuffix("0") {
        fractionText.removeLast()
    }
    return "\(whole)\(separator)\(fractionText)"
}

#if DEBUG
#Preview("What if") {
    NavigationStack { PlanWhatIfSection() }
        .environment(PlanPreviewFactory.makeStore())
}
#endif
