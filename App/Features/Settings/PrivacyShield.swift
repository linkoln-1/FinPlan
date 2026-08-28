import SwiftUI
import Observation
import LocalAuthentication

@MainActor
@Observable
final class PrivacyShieldModel {
    var isCovered = false
    var isLocked = false
    var authenticationError: String?

    func lockIfNeeded(requireBiometrics: Bool) {
        if requireBiometrics { isLocked = true }
    }

    func unlock() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationError = error?.localizedDescription
            isLocked = false
            return
        }
        do {
            let reason = String(localized: "privacy.unlockReason")
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success {
                isLocked = false
                authenticationError = nil
            }
        } catch {
            authenticationError = error.localizedDescription
        }
    }
}

@MainActor
private final class PrivacyOverlayController {
    static let shared = PrivacyOverlayController()
    private var window: UIWindow?

    func update(shield: PrivacyShieldModel) {
        let shouldShow = shield.isCovered || shield.isLocked
        if shouldShow {
            guard window == nil else { return }
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
            else { return }
            let overlay = UIWindow(windowScene: scene)
            overlay.windowLevel = .alert + 1
            overlay.backgroundColor = .clear
            let host = UIHostingController(rootView: PrivacyShieldOverlayView(shield: shield))
            host.view.backgroundColor = .clear
            overlay.rootViewController = host
            overlay.isHidden = false
            window = overlay
        } else {
            window?.isHidden = true
            window = nil
        }
    }
}

private struct PrivacyShieldOverlayView: View {
    let shield: PrivacyShieldModel

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            if shield.isLocked {
                VStack(spacing: FP.Spacing.lg) {
                    Image(systemName: "lock.fill")
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                    Button("privacy.unlock") {
                        Task { await shield.unlock() }
                    }
                    .buttonStyle(.borderedProminent)
                    if let message = shield.authenticationError {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, FP.Spacing.xl)
                    }
                }
            }
        }
    }
}

private struct PrivacyShieldModifier: ViewModifier {
    @Environment(PrivacyShieldModel.self) private var shield
    @Environment(FinanceStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background, .inactive:
                    shield.isCovered = true
                    shield.lockIfNeeded(requireBiometrics: store.requireBiometrics)
                case .active:
                    shield.isCovered = false
                    if shield.isLocked {
                        Task { await shield.unlock() }
                    }
                @unknown default:
                    break
                }
                PrivacyOverlayController.shared.update(shield: shield)
            }
            .onChange(of: shield.isLocked) { _, _ in
                PrivacyOverlayController.shared.update(shield: shield)
            }
    }
}

extension View {
    func privacyShielded() -> some View {
        modifier(PrivacyShieldModifier())
    }
}
