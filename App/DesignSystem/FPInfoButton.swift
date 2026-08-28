import SwiftUI

struct FPInfoButton: View {
    let titleKey: LocalizedStringKey
    let bodyKey: LocalizedStringKey
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "a11y.info"))
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: FP.Spacing.md) {
                Text(titleKey)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(bodyKey)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(FP.Spacing.lg)
            .frame(minWidth: 260, maxWidth: 320, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }
}

struct FPExplainedHeader: View {
    let titleKey: LocalizedStringKey
    let infoTitleKey: LocalizedStringKey
    let infoBodyKey: LocalizedStringKey

    var body: some View {
        HStack(spacing: FP.Spacing.sm) {
            Text(titleKey).font(.headline)
            FPInfoButton(titleKey: infoTitleKey, bodyKey: infoBodyKey)
            Spacer(minLength: 0)
        }
    }
}
