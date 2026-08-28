import SwiftUI
import FinPlanCore

@MainActor
struct AnalyticsRunwayCard: View {
    let runwayTenths: Int?
    @State private var isEditingEssentials = false

    var body: some View {
        FPCard {
            VStack(alignment: .leading, spacing: FP.Spacing.sm) {
                Label("analytics.runway.title", systemImage: "gauge.with.needle")
                    .font(.headline)

                if let runwayTenths {
                    Text("analytics.runway.months \(AnalyticsFormat.monthsTenths(runwayTenths))")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                } else {
                    Text("analytics.runway.insufficientData")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("analytics.runway.explanation")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    isEditingEssentials = true
                } label: {
                    Label("analytics.runway.editEssential", systemImage: "checklist")
                        .font(.callout)
                }
            }
        }
        .sheet(isPresented: $isEditingEssentials) {
            AnalyticsEssentialCategoriesEditor()
        }
    }
}

@MainActor
struct AnalyticsEssentialCategoriesEditor: View {
    @Environment(FinanceStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if activeCategories.isEmpty {
                    EmptyStateView(
                        systemImage: "folder",
                        title: "analytics.essential.empty.title",
                        message: "analytics.essential.empty.message"
                    )
                } else {
                    List {
                        Section {
                            ForEach(activeCategories) { category in
                                Toggle(isOn: binding(for: category)) {
                                    Label {
                                        Text(verbatim: category.name)
                                    } icon: {
                                        Image(systemName: category.symbolName)
                                    }
                                }
                            }
                        } footer: {
                            Text("analytics.essential.footnote")
                        }
                    }
                }
            }
            .navigationTitle("analytics.essential.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
            .alert("analytics.error.title", isPresented: errorPresented) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(verbatim: errorMessage ?? "")
            }
        }
    }

    private var activeCategories: [TransactionCategory] {
        store.categories
            .filter { !$0.isArchived }
            .sorted { $0.name < $1.name }
    }

    private func binding(for category: TransactionCategory) -> Binding<Bool> {
        Binding(
            get: {
                store.categories.first(where: { $0.id == category.id })?.isEssential
                    ?? category.isEssential
            },
            set: { newValue in
                var updated = category
                updated.isEssential = newValue
                do {
                    try store.updateCategory(updated, context: modelContext)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
