import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "deeplApiKey") ?? ""
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DeepL API Key")
                        .font(.headline)

                    SecureField("Paste your DeepL API key here", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    Text("Get a free key at deepl.com/pro#developer (500k chars/month free)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                if saved {
                    Label("Saved!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                        .transition(.opacity)
                }
                Button("Save") {
                    let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
                    UserDefaults.standard.set(trimmed, forKey: "deeplApiKey")
                    withAnimation { saved = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { saved = false }
                    }
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 360, height: 180)
    }
}
