import SwiftUI

/// Friendly, one-time onboarding that explains the Accessibility permission and
/// links straight to System Settings. Replaces the repeated, jarring system
/// modal. Reflects the live permission state so it confirms the moment the user
/// flips the switch.
struct OnboardingView: View {
    @Bindable var permission: PermissionState
    let accessibility: AccessibilityService
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("One quick permission")
                        .font(.system(size: 16, weight: .semibold))
                    Text("So Fluenty can replace text in other apps")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            statusBanner

            VStack(alignment: .leading, spacing: 10) {
                step(1, "Click “Open Accessibility Settings” below.")
                step(2, "Turn on the switch next to Fluenty Coach.")
                step(3, "That’s it — this window updates automatically.")
            }
            .padding(.vertical, 2)

            Text("Translation and the popover work without this. The permission is only needed for the one-click Replace and for reading your selection precisely. Fluenty never sends anything anywhere except your translation engine (Cursor or DeepL).")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if permission.isTrusted {
                    Button("Done") { onDone() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Open Accessibility Settings") {
                        accessibility.openAccessibilitySettings()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Later") { onDone() }
                }
                Spacer()
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    private var statusBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: permission.isTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(permission.isTrusted ? .green : .orange)
            Text(permission.isTrusted ? "Accessibility access granted" : "Accessibility access not granted yet")
                .font(.system(size: 12, weight: .medium))
            Spacer()
        }
        .padding(10)
        .background((permission.isTrusted ? Color.green : Color.orange).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.tint))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}
