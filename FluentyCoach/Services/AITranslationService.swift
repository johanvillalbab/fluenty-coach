import Foundation
import AppKit

struct AITranslationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct CursorModel: Identifiable, Equatable {
    let id: String
    let name: String

    /// ACP ids carry parameters (`composer-2.5[fast=true]`) that a stored model
    /// from older builds (`composer-2.5`) lacks.
    var baseID: Substring { id.prefix(while: { $0 != "[" }) }

    static func match(_ stored: String, in models: [CursorModel]) -> CursorModel? {
        models.first { $0.id == stored }
            ?? models.first { $0.baseID == stored }
            ?? models.first { $0.name == stored }
    }
}

/// One AI translation result: the text plus what the model detected/used, so the
/// popover can reflect the real direction (same contract DeepL gives us).
struct AITranslation {
    let text: String
    let detectedSource: Language?
    let usedTarget: Language
}

@MainActor
final class AITranslationService {
    private struct PreparedSession {
        let id: String
        let model: String
        let client: CursorACPClient
    }

    private struct Launch: Equatable {
        let cliPath: String
        let apiKey: String
    }

    private let style: TranslationStyleStore
    private var client: CursorACPClient?
    private var launch: Launch?
    private var startup: Task<CursorACPClient, Error>?
    private var next: (model: String, task: Task<PreparedSession, Error>)?
    private var models: [CursorModel] = []
    private var active: (session: PreparedSession, continuation: CheckedContinuation<String, Error>, text: String)?
    private var cancelCount = 0

    static let defaultModel = "composer-2.5"
    static let modelKey = "translationModel"
    static let cliPathKey = "cursorAgentPath"
    static let apiKeyKey = "cursorApiKey"
    static let timeoutSeconds: TimeInterval = 60

    init(style: TranslationStyleStore) {
        self.style = style
    }

    // MARK: - Settings

    static var defaultCLIPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/cursor-agent")
    }

    var cliPath: String {
        let stored = UserDefaults.standard.string(forKey: Self.cliPathKey) ?? ""
        return stored.isEmpty ? Self.defaultCLIPath : (stored as NSString).expandingTildeInPath
    }

    var model: String {
        let stored = UserDefaults.standard.string(forKey: Self.modelKey) ?? ""
        return stored.isEmpty ? Self.defaultModel : stored
    }

    var isCLIAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: cliPath)
    }

    /// Optional Cursor API key (`crsr_…`). When set, it is passed as
    /// `CURSOR_API_KEY` so GUI launches (which don't inherit the shell env)
    /// can authenticate without an interactive `cursor-agent login`.
    var apiKey: String {
        (UserDefaults.standard.string(forKey: Self.apiKeyKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentLaunch: Launch { Launch(cliPath: cliPath, apiKey: apiKey) }

    private static let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FluentyCoach", isDirectory: true)

    private static func supportSubdir(_ name: String) -> URL {
        let dir = supportDir.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let workspaceDir = supportSubdir("workspace")
    /// cursor-agent otherwise loads the owner's global ~/.cursor setup (MCP servers,
    /// skills, hooks that see every prompt) into each translation.
    private static let configDir = supportSubdir("cursor-config")
    private static let pidFile = supportDir.appendingPathComponent("cursor-agent.pid")

    // MARK: - Translation

    func applySettings() {
        guard TranslationEngine.current == .ai else { return shutdown() }
        if let launch, launch != currentLaunch { shutdown() }
        if let next, next.model == model { return }
        next?.task.cancel()
        let wanted = model
        let task = Task { try await self.prepareSession(for: wanted) }
        next = (wanted, task)
        Task {
            if case .failure = await task.result, next?.task == task {
                next = nil
            }
        }
    }

    func shutdown() {
        if let turn = active {
            resolve(turn.session.id, .failure(AITranslationError(message: "Translation stopped because the AI settings changed.")))
        }
        client?.terminate()
        forgetClient()
    }

    /// Cancels the in-flight run, if any. The pending `translate` call throws a
    /// CancellationError instead of returning text.
    func cancel() {
        cancelCount += 1
        abortActive()
    }

    /// Translates in a single model call. When `source` is .auto and the text is
    /// already in `target`, the model translates to `flipTarget` instead (same
    /// auto-swap behavior the DeepL path implements with a second request).
    func translate(
        _ text: String,
        source: Language,
        target: Language,
        flipTarget: Language,
        context: String?
    ) async throws -> AITranslation {
        let fullPrompt = buildFullPrompt(
            text: text,
            source: source,
            target: target,
            flipTarget: flipTarget,
            context: context
        )

        let cancelCountAtStart = cancelCount
        let session = try await takePreparedSession()
        // Preparing the next session while this prompt streams would compete with
        // it inside the same agent process, so it waits until this turn is over.
        defer { applySettings() }
        guard cancelCountAtStart == cancelCount else { throw CancellationError() }

        let raw = try await prompt(fullPrompt, in: session)

        let cleaned = Self.sanitize(raw)
        guard !cleaned.isEmpty else {
            throw AITranslationError(message: "The model returned no text.")
        }
        return Self.parse(cleaned, requestedTarget: target)
    }

    // MARK: - Prompt assembly

    private func buildFullPrompt(
        text: String,
        source: Language,
        target: Language,
        flipTarget: Language,
        context: String?
    ) -> String {
        var parts: [String] = [style.text]

        if source == .auto {
            parts.append("""
            TAREA: detecta el idioma del texto y tradúcelo a \(target.displayName). \
            Si el texto YA está en \(target.displayName), tradúcelo a \(flipTarget.displayName) en su lugar.
            """)
        } else {
            parts.append("TAREA: traduce el texto de \(source.displayName) a \(target.displayName).")
        }

        if let ctx = context, !ctx.isEmpty {
            parts.append("""
            CONTEXTO CIRCUNDANTE (texto alrededor de la selección en la app de origen; \
            úsalo solo para resolver referencias y elegir el registro — NO lo traduzcas ni lo incluyas en la salida):
            \"\"\"
            \(ctx)
            \"\"\"
            """)
        }

        parts.append("""
        TEXTO A TRADUCIR:
        \"\"\"
        \(text)
        \"\"\"
        """)

        parts.append("""
        Responde ÚNICAMENTE con un objeto JSON válido en una sola línea, sin fences de código ni texto extra, con esta forma exacta:
        {"detected_source":"<código ISO-639-1 del idioma origen>","target_used":"<código ISO-639-1 del idioma al que tradujiste>","translation":"<la traducción>"}
        """)

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Output parsing

    /// Strip a wrapping markdown fence if the model added one despite instructions.
    static func sanitize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            var lines = text.components(separatedBy: "\n")
            lines.removeFirst()
            if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                lines.removeLast()
            }
            text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private struct AIResponse: Decodable {
        let detectedSource: String?
        let targetUsed: String?
        let translation: String

        enum CodingKeys: String, CodingKey {
            case detectedSource = "detected_source"
            case targetUsed = "target_used"
            case translation
        }
    }

    private static func decodeResponse(_ raw: String) -> AIResponse? {
        guard let data = sanitize(raw).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIResponse.self, from: data)
    }

    /// Decode the JSON contract; if the model ignored it and answered with plain
    /// text, fall back to using the whole output as the translation.
    static func parse(_ cleaned: String, requestedTarget: Language) -> AITranslation {
        if let decoded = decodeResponse(cleaned) {
            let detected = decoded.detectedSource.map { Language(deeplDetected: $0) }
            let used = decoded.targetUsed.map { Language(deeplDetected: $0) } ?? requestedTarget
            return AITranslation(
                text: decoded.translation.trimmingCharacters(in: .whitespacesAndNewlines),
                detectedSource: detected == .auto ? nil : detected,
                usedTarget: used == .auto ? requestedTarget : used
            )
        }
        return AITranslation(text: cleaned, detectedSource: nil, usedTarget: requestedTarget)
    }

    private func resolve(_ sessionId: String, _ result: Result<String, Error>) {
        guard let turn = active, turn.session.id == sessionId else { return }
        active = nil
        turn.continuation.resume(with: result)
    }

    private func abortActive() {
        guard let turn = active else { return }
        cancelTurn(in: turn.session)
        resolve(turn.session.id, .failure(CancellationError()))
    }

    private func cancelTurn(in session: PreparedSession) {
        session.client.notify("session/cancel", ["sessionId": session.id])
    }

    private func prompt(_ text: String, in session: PreparedSession) async throws -> String {
        abortActive()
        return try await withCheckedThrowingContinuation { continuation in
            active = (session, continuation, "")
            Task {
                do {
                    _ = try await session.client.request("session/prompt", [
                        "sessionId": session.id,
                        "prompt": [["type": "text", "text": text]]
                    ])
                    if let turn = active, turn.session.id == session.id {
                        resolve(session.id, .success(turn.text))
                    }
                } catch {
                    cancelTurn(in: session)
                    resolve(session.id, .failure(error))
                }
            }
        }
    }

    /// The translation JSON is complete in the stream slightly before the turn
    /// formally ends, so the turn resolves as soon as the text decodes.
    private func handleUpdate(_ sessionId: String, _ update: [String: Any]) {
        guard active?.session.id == sessionId,
              update["sessionUpdate"] as? String == "agent_message_chunk",
              let chunk = (update["content"] as? [String: Any])?["text"] as? String else { return }
        active?.text += chunk
        guard let text = active?.text, Self.decodeResponse(text) != nil else { return }
        resolve(sessionId, .success(text))
    }

    private func takePreparedSession() async throws -> PreparedSession {
        applySettings()
        guard let task = next?.task else {
            throw AITranslationError(message: "The AI engine is turned off in Settings.")
        }
        next = nil
        return try await task.value
    }

    private func prepareSession(for wanted: String) async throws -> PreparedSession {
        try Task.checkCancellation()
        let client = try await ensureClient()
        let created = try await client.request("session/new", ["cwd": Self.workspaceDir.path, "mcpServers": [Any]()])
        guard let sessionId = created["sessionId"] as? String else {
            throw AITranslationError(message: "cursor-agent returned no session.")
        }

        let modelState = created["models"] as? [String: Any]
        let listed = (modelState?["availableModels"] as? [[String: Any]] ?? []).compactMap { entry -> CursorModel? in
            guard let id = entry["modelId"] as? String else { return nil }
            return CursorModel(id: id, name: entry["name"] as? String ?? id)
        }
        models = listed

        // New sessions start in agent mode with full tool access. set_model only
        // accepts ids the session listed, so the stored model is matched first.
        async let readOnly = client.request("session/set_mode", ["sessionId": sessionId, "modeId": "ask"])
        if let match = CursorModel.match(wanted, in: listed), match.id != modelState?["currentModelId"] as? String {
            _ = try await client.request("session/set_model", ["sessionId": sessionId, "modelId": match.id])
        }
        _ = try await readOnly

        return PreparedSession(id: sessionId, model: wanted, client: client)
    }

    private func ensureClient() async throws -> CursorACPClient {
        let task: Task<CursorACPClient, Error>
        if let startup {
            task = startup
        } else {
            launch = currentLaunch
            task = Task { try await self.startClient() }
            startup = task
        }
        do {
            return try await task.value
        } catch {
            if startup == task {
                startup = nil
                launch = nil
            }
            throw error
        }
    }

    private func startClient() async throws -> CursorACPClient {
        try Task.checkCancellation()
        let path = cliPath
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw AITranslationError(message: "cursor-agent not found at \(path). Set the path in Settings.")
        }

        CursorACPClient.reapOrphan(pidFile: Self.pidFile)
        // The agent stores every session on disk (~200-300 KB each) and none is
        // ever resumed, so the previous agent's sessions are dropped before spawning.
        try? FileManager.default.removeItem(at: Self.configDir.appendingPathComponent("acp-sessions"))
        let spawned: CursorACPClient
        do {
            spawned = try CursorACPClient(
                executable: URL(fileURLWithPath: path),
                environment: processEnvironment(),
                workingDirectory: Self.workspaceDir,
                pidFile: Self.pidFile,
                timeout: Self.timeoutSeconds
            )
        } catch {
            throw AITranslationError(message: "Could not launch cursor-agent: \(error.localizedDescription)")
        }
        client = spawned
        spawned.onSessionUpdate = { [weak self] sessionId, update in
            self?.handleUpdate(sessionId, update)
        }
        spawned.onExit = { [weak self, weak spawned] in
            guard let self, self.client === spawned else { return }
            forgetClient()
        }

        do {
            let initialized = try await spawned.request("initialize", [
                "protocolVersion": 1,
                "clientCapabilities": [
                    "fs": ["readTextFile": false, "writeTextFile": false],
                    "terminal": false
                ]
            ])
            let methods = initialized["authMethods"] as? [[String: Any]]
            if let methodId = methods?.first?["id"] as? String {
                _ = try await spawned.request("authenticate", ["methodId": methodId])
            }
        } catch {
            spawned.terminate()
            if client === spawned { client = nil }
            throw error
        }
        return spawned
    }

    private func forgetClient() {
        startup?.cancel()
        next?.task.cancel()
        client = nil
        launch = nil
        startup = nil
        next = nil
        models = []
    }

    /// GUI apps launch with a minimal environment; cursor-agent (a bash
    /// script that locates its versioned binary) needs HOME and a sane PATH.
    /// `CURSOR_API_KEY` is injected from Settings so Finder/menu-bar launches
    /// don't depend on a shell profile.
    private func processEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extraPaths = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        env["PATH"] = (extraPaths + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        env["CURSOR_CONFIG_DIR"] = Self.configDir.path
        let key = apiKey
        if !key.isEmpty {
            env["CURSOR_API_KEY"] = key
        }
        return env
    }

    func listModels() async -> [CursorModel] {
        applySettings()
        _ = try? await next?.task.value
        return models
    }
}
