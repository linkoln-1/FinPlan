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
            FPInfoPopoverContent(titleKey: titleKey, bodyKey: bodyKey)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct FPInfoPopoverContent: View {
    let titleKey: LocalizedStringKey
    let bodyKey: LocalizedStringKey
    @State private var contentHeight: CGFloat?

    private static let width: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: FP.Spacing.md) {
            Text(titleKey)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(bodyKey)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: Self.width - FP.Spacing.lg * 2, alignment: .leading)
        .padding(FP.Spacing.lg)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            contentHeight = height
        }
        .frame(width: Self.width, height: contentHeight, alignment: .topLeading)
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
