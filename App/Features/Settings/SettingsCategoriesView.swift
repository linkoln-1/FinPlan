import SwiftUI
import SwiftData
import FinPlanCore

struct SettingsCategoriesView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @State private var editorContext: SettingsCategoryEditorContext?
    @State private var errorMessage: String?

    private var activeCategories: [TransactionCategory] { store.categories.filter { !$0.isArchived } }
    private var archivedCategories: [TransactionCategory] { store.categories.filter(\.isArchived) }

    var body: some View {
        Group {
            if store.categories.isEmpty {
                EmptyStateView(
                    systemImage: "tag",
                    title: "settings.categories.empty.title",
                    message: "settings.categories.empty.message"
                )
            } else {
                List {
                    if !activeCategories.isEmpty {
                        Section {
                            ForEach(activeCategories) { category in
                                categoryRow(category)
                            }
                        } header: {
                            Text("settings.categories.active")
                        } footer: {
                            Text("settings.categories.essential.footer")
                        }
                    }
                    if !archivedCategories.isEmpty {
                        Section {
                            ForEach(archivedCategories) { category in
                                categoryRow(category)
                            }
                        } header: {
                            Text("settings.categories.archived")
                        } footer: {
                            Text("settings.categories.archived.footer")
                        }
                    }
                }
            }
        }
        .navigationTitle("settings.categories.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorContext = .add
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "a11y.settings.addCategory"))
            }
        }
        .sheet(item: $editorContext) { context in
            SettingsCategoryEditorSheet(context: context)
        }
        .alert("error.title", isPresented: errorBinding) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func categoryRow(_ category: TransactionCategory) -> some View {
        Button {
            editorContext = .edit(category)
        } label: {
            HStack {
                Label {
                    Text(verbatim: category.name)
                } icon: {
                    Image(systemName: category.symbolName)
                        .foregroundStyle(category.isArchived ? FPStatusTint.neutral : Color.accentColor)
                }
                Spacer()
                if category.isEssential {
                    Image(systemName: "staroflife.fill")
                        .font(.caption)
                        .foregroundStyle(FPStatusTint.attention)
                        .accessibilityLabel(String(localized: "a11y.settings.essentialCategory"))
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                toggleArchive(category)
            } label: {
                if category.isArchived {
                    Label("settings.categories.unarchive", systemImage: "tray.and.arrow.up")
                } else {
                    Label("settings.categories.archive", systemImage: "archivebox")
                }
            }
            .tint(FPStatusTint.attention)
        }
    }

    private func toggleArchive(_ category: TransactionCategory) {
        var updated = category
        updated.isArchived.toggle()
        do {
            try store.settingsUpdateCategory(updated, context: modelContext)
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

private enum SettingsCategoryEditorContext: Identifiable {
    case add
    case edit(TransactionCategory)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let category): return category.id.uuidString
        }
    }
}

private struct SettingsCategoryEditorSheet: View {
    let context: SettingsCategoryEditorContext
    @Environment(FinanceStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var symbolName = "tag"
    @State private var isEssential = false
    @State private var errorMessage: String?

    private static let symbolPalette = [
        "tag", "fork.knife", "car.fill", "house.fill", "bag.fill",
        "laptopcomputer", "gamecontroller.fill", "cross.case.fill",
        "book.fill", "gift.fill", "arrow.triangle.2.circlepath",
        "airplane", "building.columns.fill", "pawprint.fill",
        "tshirt.fill", "dumbbell.fill", "cup.and.saucer.fill",
        "wifi", "phone.fill", "banknote", "scissors", "leaf.fill",
        "music.note", "ellipsis.circle.fill",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("settings.categories.name", text: $name)
                    Toggle("settings.categories.essential", isOn: $isEssential)
                } footer: {
                    Text("settings.categories.essential.footer")
                }

                Section {
                    symbolGrid
                } header: {
                    Text("settings.categories.symbol")
                }
            }
            .navigationTitle(isEditing ? "settings.categories.editTitle" : "settings.categories.addTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(!isSaveEnabled)
                }
            }
            .onAppear { prefill() }
            .alert("error.title", isPresented: errorBinding) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: FP.Spacing.sm)], spacing: FP.Spacing.sm) {
            ForEach(symbolOptions, id: \.self) { symbol in
                Button {
                    symbolName = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: FP.Radius.control)
                                .fill(symbol == symbolName ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: FP.Radius.control)
                                .strokeBorder(symbol == symbolName ? Color.accentColor : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: symbol))
                .accessibilityAddTraits(symbol == symbolName ? .isSelected : [])
            }
        }
        .padding(.vertical, FP.Spacing.xs)
    }

    private var symbolOptions: [String] {
        if Self.symbolPalette.contains(symbolName) {
            return Self.symbolPalette
        }
        return [symbolName] + Self.symbolPalette
    }

    private var isEditing: Bool {
        if case .edit = context { return true }
        return false
    }

    private var isSaveEnabled: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func prefill() {
        guard case .edit(let category) = context else { return }
        name = category.name
        symbolName = category.symbolName
        isEssential = category.isEssential
    }

    private func save() {
        guard isSaveEnabled else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch context {
        case .add:
            store.addCategory(
                TransactionCategory(name: trimmedName, symbolName: symbolName, isEssential: isEssential)
            )
            dismiss()
        case .edit(let existing):
            let updated = TransactionCategory(
                id: existing.id,
                name: trimmedName,
                symbolName: symbolName,
                isArchived: existing.isArchived,
                isEssential: isEssential
            )
            do {
                try store.settingsUpdateCategory(updated, context: modelContext)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

#if DEBUG
#Preview {
    let fixture = SettingsPreviewFactory.make()
    NavigationStack {
        SettingsCategoriesView()
    }
    .environment(fixture.store)
    .environment(PrivacyShieldModel())
    .modelContainer(fixture.controller.container)
}
#endif
