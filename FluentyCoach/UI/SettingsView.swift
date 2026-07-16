import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var permission: PermissionState
    let accessibility: AccessibilityService
    let ai: AITranslationService
    let style: TranslationStyleStore

    @State private var engine = TranslationEngine.current
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "deeplApiKey") ?? ""
    @State private var saved = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    @State private var models: [CursorModel] = []
    @State private var selectedModel = ""
    @State private var cliPath = ""
    @State private var cliAvailable = false
    @State private var isLoadingModels = false
    @State private var styleText = ""

    var body: some View {
        Form {
            Section("Translation Engine") {
                Picker("Engine", selection: $engine) {
                    ForEach(TranslationEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: engine) { _, newValue in
                    TranslationEngine.current = newValue
                }
                Text(engine == .ai
                     ? "Translations run through your Cursor account via cursor-agent in headless mode — no API key needed."
                     : "Translations use the DeepL REST API with your API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if engine == .ai {
                aiEngineSection
                styleSection
            } else {
                deeplSection
            }

            Section("Permissions") {
                HStack(spacing: 8) {
                    Image(systemName: permission.isTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(permission.isTrusted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Accessibility")
                            .font(.system(size: 12, weight: .medium))
                        Text(permission.isTrusted ? "Granted — Replace is ready" : "Needed for one-click Replace")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !permission.isTrusted {
                        Button("Open Settings") { accessibility.openAccessibilitySettings() }
                            .font(.system(size: 12))
                    }
                }
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        toggleLaunchAtLogin(enabled)
                    }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 640)
        .onAppear {
            permission.refresh()
            selectedModel = ai.model
            cliPath = ai.cliPath
            cliAvailable = ai.isCLIAvailable
            styleText = style.text
            loadModels()
        }
    }

    // MARK: - AI engine (cursor-agent)

    private var aiEngineSection: some View {
        Section("Cursor CLI") {
            HStack(spacing: 8) {
                Circle()
                    .fill(cliAvailable ? Color.green : Color.red)
                    .frame(width: 9, height: 9)
                TextField("cursor-agent path", text: $cliPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { saveCLIPath() }
                Button("Save") { saveCLIPath() }
            }

            HStack(spacing: 8) {
                Picker("Model", selection: $selectedModel) {
                    if models.isEmpty {
                        Text(selectedModel).tag(selectedModel)
                    } else {
                        ForEach(models) { model in
                            Text("\(model.name)  (\(model.id))").tag(model.id)
                        }
                    }
                }
                .onChange(of: selectedModel) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: AITranslationService.modelKey)
                }
                if isLoadingModels {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        loadModels()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reload models from cursor-agent --list-models")
                }
            }
            Text("composer-2.5 is the fastest — ideal for the popover. Thinking models translate slightly better but take longer.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var styleSection: some View {
        Section {
            TextEditor(text: $styleText)
                .font(.system(size: 11.5, design: .monospaced))
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.25))
                )
                .onChange(of: styleText) { _, newValue in
                    style.text = newValue
                }
            Text("These rules are sent to the model ahead of every translation. Edit freely; the default stays saved.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            HStack {
                Text("Translation Style")
                Spacer()
                if style.isCustomized {
                    Button("Reset to default") {
                        style.resetToDefault()
                        styleText = style.text
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - DeepL

    private var deeplSection: some View {
        Section("DeepL API Key") {
            VStack(alignment: .leading, spacing: 6) {
                SecureField("Paste your DeepL API key here", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Text("Get a free key at deepl.com/pro#developer (500k chars/month free)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
        }
    }

    // MARK: - Actions

    private func saveCLIPath() {
        let trimmed = cliPath.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == AITranslationService.defaultCLIPath {
            UserDefaults.standard.removeObject(forKey: AITranslationService.cliPathKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: AITranslationService.cliPathKey)
        }
        cliPath = ai.cliPath
        cliAvailable = ai.isCLIAvailable
        loadModels()
    }

    private func loadModels() {
        guard ai.isCLIAvailable else {
            cliAvailable = false
            return
        }
        cliAvailable = true
        isLoadingModels = true
        Task { @MainActor in
            let found = await ai.listModels()
            if !found.isEmpty {
                models = found
                if !found.contains(where: { $0.id == selectedModel }) {
                    // Keep the stored model even if not listed (e.g. parameterized ids).
                    models.insert(CursorModel(id: selectedModel, name: selectedModel), at: 0)
                }
            }
            isLoadingModels = false
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert the toggle if the system rejected the change.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
