import SwiftUI
import SwiftData
import FinPlanCore
import UniformTypeIdentifiers

struct SettingsDataSection: View {
    @Environment(FinanceStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    @State private var exportFile: SettingsExportFile?
    @State private var isImporterPresented = false
    @State private var importPreview: SettingsImportPreview?
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Button {
                exportJSON()
            } label: {
                Label("settings.export.json", systemImage: "square.and.arrow.up")
            }
            .sheet(item: $exportFile) { file in
                SettingsExportShareSheet(file: file)
            }

            Button {
                exportCSV()
            } label: {
                Label("settings.export.csv", systemImage: "tablecells")
            }

            Button {
                isImporterPresented = true
            } label: {
                Label("settings.import.json", systemImage: "square.and.arrow.down")
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.json]
            ) { result in
                handleImportSelection(result)
            }
            .sheet(item: $importPreview) { preview in
                SettingsImportPreviewSheet(preview: preview) {
                    applyImport(preview)
                }
            }
            .alert("error.title", isPresented: errorBinding) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        } header: {
            Text("settings.section.data")
        } footer: {
            Text("settings.data.footer")
        }
    }

    private func exportJSON() {
        do {
            let data = try BackupService.exportJSON(from: store)
            exportFile = try SettingsExportFile.write(data: data, fileName: "FinPlan-backup.json")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportCSV() {
        let csv = BackupService.exportCSV(from: store)
        do {
            let data = Data(csv.utf8)
            exportFile = try SettingsExportFile.write(data: data, fileName: "FinPlan-transactions.csv")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let isScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isScoped { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                let document = try BackupService.validateImport(data)
                importPreview = SettingsImportPreview(document: document)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func applyImport(_ preview: SettingsImportPreview) {
        do {
            try store.settingsReplaceAllData(with: preview.document, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

private struct SettingsExportFile: Identifiable {
    let id = UUID()
    let url: URL

    static func write(data: Data, fileName: String) throws -> SettingsExportFile {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return SettingsExportFile(url: url)
    }
}

private struct SettingsExportShareSheet: View {
    let file: SettingsExportFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: FP.Spacing.xl) {
                Image(systemName: "doc.badge.arrow.up")
                    .font(.largeTitle)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(verbatim: file.url.lastPathComponent)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("settings.export.ready")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ShareLink(item: file.url) {
                    Label("settings.export.share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(FP.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct SettingsImportPreview: Identifiable {
    let id = UUID()
    let document: BackupService.BackupDocument
}

private struct SettingsImportPreviewSheet: View {
    let preview: SettingsImportPreview
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("import.preview.baseCurrency", value: preview.document.baseCurrency.code)
                    LabeledContent("import.preview.exportedAt") {
                        Text(preview.document.exportedAt, style: .date)
                    }
                } header: {
                    Text("import.preview.header")
                }

                Section {
                    countRow("import.preview.accounts", preview.document.accounts.count)
                    countRow("import.preview.categories", preview.document.categories.count)
                    countRow("import.preview.tags", preview.document.tags.count)
                    countRow("import.preview.transactions", preview.document.transactions.count)
                    countRow("import.preview.goals", preview.document.goals.count)
                    countRow("import.preview.allocations", preview.document.allocations.count)
                    countRow("import.preview.incomeSources", preview.document.incomeSources.count)
                    countRow("import.preview.budgets", preview.document.budgets.count)
                    countRow("import.preview.recurring", preview.document.recurringTemplates.count)
                    countRow("import.preview.expectedEvents", preview.document.expectedEvents.count)
                    countRow("import.preview.rates", preview.document.planningRates.rates.count)
                } header: {
                    Text("import.preview.contents")
                }

                Section {
                    Button("import.confirmReplace", role: .destructive) {
                        dismiss()
                        onConfirm()
                    }
                } footer: {
                    Text("import.replace.warning")
                }
            }
            .navigationTitle("import.preview.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
        }
    }

    private func countRow(_ titleKey: LocalizedStringKey, _ count: Int) -> some View {
        LabeledContent {
            Text(verbatim: "\(count)")
                .monospacedDigit()
        } label: {
            Text(titleKey)
        }
    }
}

#if DEBUG
#Preview {
    let fixture = SettingsPreviewFactory.make()
    NavigationStack {
        Form {
            SettingsDataSection()
        }
    }
    .environment(fixture.store)
    .environment(PrivacyShieldModel())
    .modelContainer(fixture.controller.container)
}
#endif
