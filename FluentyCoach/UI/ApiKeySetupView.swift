import SwiftUI

struct ApiKeySetupView: View {
    @State private var apiKey: String = ""
    let onSave: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "key.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 14))
                Text("DeepL API Key")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.3)

            VStack(alignment: .leading, spacing: 8) {
                Text("Enter your free DeepL API key to enable translation.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx:fx", text: $apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(.quinary)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text("Get a free key at [deepl.com/pro#developer](https://www.deepl.com/pro#developer)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(14)

            Divider().opacity(0.3)

            HStack {
                Spacer()
                GlassActionButton(
                    title: "Save",
                    systemImage: "checkmark",
                    isDisabled: apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    UserDefaults.standard.set(trimmed, forKey: "deeplApiKey")
                    onSave(trimmed)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
    }
}
