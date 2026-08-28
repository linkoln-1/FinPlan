import SwiftUI
import SwiftData
import FinPlanCore
import LocalAuthentication
import UserNotifications
import UIKit

enum SettingsAppearance: String, CaseIterable {
    case system, light, dark

    var labelKey: LocalizedStringKey {
        switch self {
        case .system: return "settings.appearance.system"
        case .light: return "settings.appearance.light"
        case .dark: return "settings.appearance.dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(PrivacyShieldModel.self) private var shield
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearanceOverride") private var appearanceRaw = SettingsAppearance.system.rawValue

    @State private var isBiometryAvailable = false
    @State private var bufferText = ""
    @State private var bufferMinor: Int64?
    @State private var isResetDialogPresented = false
    @State private var isResetFinalAlertPresented = false
    @State private var localErrorMessage: String?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                generalSection
                privacySection(store: $store)
                SettingsNotificationsSection()
                planningSection
                accountsSection
                categoriesSection
                SettingsDataSection()
                dangerSection
                aboutSection
            }
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .alert("error.title", isPresented: storeErrorBinding) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(store.lastError ?? "")
            }
        }
        .alert("error.title", isPresented: localErrorBinding) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(localErrorMessage ?? "")
        }
        .sheet(item: $missingRatesPrompt) { prompt in
            SettingsMissingRatesSheet(currencies: prompt.currencies) {
                missingRatesPrompt = nil
            }
            .environment(store)
        }
        .onAppear {
            refreshBiometryAvailability()
            prefillBuffer()
        }
    }

    private var generalSection: some View {
        Section {
            Picker("settings.baseCurrency", selection: baseCurrencyBinding) {
                ForEach(baseCurrencyOptions, id: \.self) { code in
                    Text(verbatim: code).tag(code)
                }
            }
            Picker("settings.appearance", selection: $appearanceRaw) {
                ForEach(SettingsAppearance.allCases, id: \.rawValue) { appearance in
                    Text(appearance.labelKey).tag(appearance.rawValue)
                }
            }
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: settingsURL) {
                    HStack {
                        Text("settings.language")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel(String(localized: "a11y.settings.openLanguage"))
            }
        } header: {
            Text("settings.section.general")
        } footer: {
            Text("settings.baseCurrency.footer")
        }
    }

    @State private var missingRatesPrompt: MissingRatesPrompt?

    private var baseCurrencyOptions: [String] {
        SettingsSupportedCurrencies.codes(including: [store.baseCurrency.code])
    }

    private var baseCurrencyBinding: Binding<String> {
        Binding(
            get: { store.baseCurrency.code },
            set: { newCode in
                store.setBaseCurrency(Currency.known(code: newCode))
                prefillBuffer()
                Task { @MainActor in
                    promptForMissingRates()
                }
            }
        )
    }

    private func promptForMissingRates() {
        let base = store.baseCurrency
        var codes = Set<String>()
        codes.formUnion(store.accounts.filter { !$0.isArchived }.map(\.currency.code))
        codes.formUnion(store.incomeSources.filter(\.isActive).map(\.grossAmount.currency.code))
        codes.formUnion(store.goals.map(\.targetAmount.currency.code))
        codes.formUnion(store.recurringTemplates.filter(\.isActive).map(\.amount.currency.code))
        codes.remove(base.code)
        let missing = codes
            .map { Currency.known(code: $0) }
            .filter { store.planningRates.rate(from: $0, to: base) == nil }
            .sorted { $0.code < $1.code }
        if !missing.isEmpty {
            missingRatesPrompt = MissingRatesPrompt(currencies: missing)
        }
    }

    private func privacySection(store: Bindable<FinanceStore>) -> some View {
        Section {
            Toggle("settings.faceID", isOn: store.requireBiometrics)
                .disabled(!isBiometryAvailable && !store.wrappedValue.requireBiometrics)
            Toggle("settings.hideBalances", isOn: store.hideBalances)
        } header: {
            Text("settings.section.privacy")
        } footer: {
            if isBiometryAvailable {
                Text("settings.faceID.footer")
            } else {
                Text("settings.faceID.unavailable")
            }
        }
    }

    private var planningSection: some View {
        Section {
            NavigationLink {
                SettingsRatesView()
            } label: {
                HStack {
                    Text("settings.rates")
                    Spacer()
                    Text(verbatim: "\(store.planningRates.rates.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            LabeledContent("settings.buffer.current") {
                MoneyText(money: store.minimumCashBuffer)
            }
            MoneyField(
                titleKey: "settings.buffer.amount",
                currency: store.baseCurrency,
                text: $bufferText,
                amountMinor: $bufferMinor
            )
            HStack {
                Button("settings.buffer.save") { saveBuffer() }
                    .disabled(!isBufferSaveEnabled)
                Spacer()
                if store.minimumCashBuffer.isPositive {
                    Button("settings.buffer.clear", role: .destructive) { clearBuffer() }
                }
            }
        } header: {
            Text("settings.section.planning")
        } footer: {
            Text("settings.buffer.footer")
        }
    }

    private var isBufferSaveEnabled: Bool {
        guard let minor = bufferMinor, minor > 0 else { return false }
        return minor != store.minimumCashBuffer.amountMinor
    }

    private func saveBuffer() {
        guard let minor = bufferMinor, minor > 0 else { return }
        store.minimumCashBuffer = Money(minor: minor, currency: store.baseCurrency)
        prefillBuffer()
    }

    private func clearBuffer() {
        store.minimumCashBuffer = .zero(store.baseCurrency)
        prefillBuffer()
    }

    private func prefillBuffer() {
        let current = store.minimumCashBuffer
        if current.isPositive {
            bufferText = BackupService.decimalString(current)
            bufferMinor = current.amountMinor
        } else {
            bufferText = ""
            bufferMinor = nil
        }
    }

    private var accountsSection: some View {
        Section {
            NavigationLink {
                SettingsAccountsView()
            } label: {
                HStack {
                    Label("settings.accounts", systemImage: "creditcard")
                    Spacer()
                    Text(verbatim: "\(store.accounts.filter { !$0.isArchived }.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("settings.section.accounts")
        }
    }

    private var categoriesSection: some View {
        Section {
            NavigationLink {
                SettingsCategoriesView()
            } label: {
                HStack {
                    Label("settings.categories", systemImage: "tag")
                    Spacer()
                    Text(verbatim: "\(store.categories.filter { !$0.isArchived }.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("settings.section.categories")
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                isResetDialogPresented = true
            } label: {
                Label("settings.reset", systemImage: "trash")
            }
            .confirmationDialog(
                "settings.reset.confirmTitle",
                isPresented: $isResetDialogPresented,
                titleVisibility: .visible
            ) {
                Button("settings.reset.confirmAction", role: .destructive) {
                    isResetFinalAlertPresented = true
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("settings.reset.confirmMessage")
            }
            .alert("settings.reset.finalTitle", isPresented: $isResetFinalAlertPresented) {
                Button("settings.reset.finalAction", role: .destructive) {
                    Task { await performReset() }
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("settings.reset.consequence")
            }
        } header: {
            Text("settings.section.danger")
        } footer: {
            Text("settings.reset.footer")
        }
    }

    private func performReset() async {
        if store.requireBiometrics {
            shield.lockIfNeeded(requireBiometrics: true)
            if shield.isLocked {
                await shield.unlock()
            }
            guard !shield.isLocked else { return }
        }
        do {
            try store.settingsResetAllData(context: modelContext)
            prefillBuffer()
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("settings.about.version", value: appVersion)
            Label("settings.about.localFirst", systemImage: "internaldrive")
            Label("settings.about.noTracking", systemImage: "hand.raised")
            Label("settings.about.exportAnytime", systemImage: "square.and.arrow.up")
        } header: {
            Text("settings.section.about")
        } footer: {
            Text("settings.about.footer")
        }
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }

    private func refreshBiometryAvailability() {
        var evaluationError: NSError?
        isBiometryAvailable = LAContext().canEvaluatePolicy(
            .deviceOwnerAuthentication, error: &evaluationError
        )
    }

    private var storeErrorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }

    private var localErrorBinding: Binding<Bool> {
        Binding(
            get: { localErrorMessage != nil },
            set: { if !$0 { localErrorMessage = nil } }
        )
    }
}

private struct SettingsNotificationsSection: View {
    @Environment(FinanceStore.self) private var store
    @AppStorage(NotificationPreference.master) private var isMasterEnabled = false
    @AppStorage(NotificationPreference.expectedIncome) private var isExpectedIncomeEnabled = true
    @AppStorage(NotificationPreference.savingsContribution) private var isSavingsContributionEnabled = true
    @AppStorage(NotificationPreference.largePayment) private var isLargePaymentEnabled = true
    @AppStorage(NotificationPreference.overdue) private var isOverdueEnabled = true
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var isDenied: Bool { authorizationStatus == .denied }

    var body: some View {
        Section {
            Toggle("settings.notifications.master", isOn: $isMasterEnabled)
                .disabled(isDenied && !isMasterEnabled)
            if isMasterEnabled {
                Toggle("settings.notifications.expectedIncome", isOn: $isExpectedIncomeEnabled)
                    .disabled(isDenied)
                Toggle("settings.notifications.savingsContribution", isOn: $isSavingsContributionEnabled)
                    .disabled(isDenied)
                Toggle("settings.notifications.largePayment", isOn: $isLargePaymentEnabled)
                    .disabled(isDenied)
                Toggle("settings.notifications.overdue", isOn: $isOverdueEnabled)
                    .disabled(isDenied)
                if isDenied, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: settingsURL) {
                        HStack {
                            Text("settings.notifications.openSettings")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(String(localized: "a11y.settings.openNotificationSettings"))
                }
            }
        } header: {
            Text("settings.notifications")
        } footer: {
            if isDenied {
                Text("settings.notifications.denied")
            } else if let issue = NotificationService.shared.lastScheduleIssue {
                Text(verbatim: issue)
            } else {
                Text("settings.notifications.footer")
            }
        }
        .onChange(of: isMasterEnabled) { _, enabled in
            Task {
                if enabled {
                    _ = await NotificationService.shared.requestAuthorization()
                    authorizationStatus = await NotificationService.shared.authorizationStatus()
                }
                NotificationService.shared.scheduleRefresh(from: store)
            }
        }
        .onChange(of: isExpectedIncomeEnabled) { reschedule() }
        .onChange(of: isSavingsContributionEnabled) { reschedule() }
        .onChange(of: isLargePaymentEnabled) { reschedule() }
        .onChange(of: isOverdueEnabled) { reschedule() }
        .task {
            authorizationStatus = await NotificationService.shared.authorizationStatus()
        }
    }

    private func reschedule() {
        NotificationService.shared.scheduleRefresh(from: store)
    }
}

#if DEBUG
#Preview {
    let fixture = SettingsPreviewFactory.make()
    SettingsView()
        .environment(fixture.store)
        .environment(PrivacyShieldModel())
        .modelContainer(fixture.controller.container)
}
#endif
