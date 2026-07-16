import Foundation
import AppKit

struct AITranslationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct CursorModel: Identifiable, Equatable {
    let id: String
    let name: String
}

/// One AI translation result: the text plus what the model detected/used, so the
/// popover can reflect the real direction (same contract DeepL gives us).
struct AITranslation {
    let text: String
    let detectedSource: Language?
    let usedTarget: Language
}

/// Runs translation through the Cursor CLI in headless mode (same solution as
/// BestPrompt's PromptImprovementService):
///   cursor-agent -p <prompt> --output-format text --mode ask --model <model>
/// The CLI reuses the user's Cursor login (or CURSOR_API_KEY); `--mode ask` keeps
/// the agent read-only, and `--workspace` points at an empty directory so it never
/// indexes or touches project files.
@MainActor
final class AITranslationService {
    private let style: TranslationStyleStore
    private var currentProcess: Process?
    private var jobID = 0

    static let defaultModel = "composer-2.5"
    static let modelKey = "translationModel"
    static let cliPathKey = "cursorAgentPath"
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

    /// Empty directory handed to --workspace so cursor-agent never scans real projects.
    private static let workspaceDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluentyCoach/workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Translation

    /// Cancels the in-flight run, if any. The pending `translate` call throws a
    /// CancellationError (a stale-job guard) instead of returning text.
    func cancel() {
        jobID += 1
        currentProcess?.terminate()
        currentProcess = nil
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
        jobID += 1
        let myJob = jobID

        let fullPrompt = buildFullPrompt(
            text: text,
            source: source,
            target: target,
            flipTarget: flipTarget,
            context: context
        )
        let raw = try await runCLI(fullPrompt: fullPrompt)

        guard myJob == jobID else { throw CancellationError() }

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

    /// Decode the JSON contract; if the model ignored it and answered with plain
    /// text, fall back to using the whole output as the translation.
    static func parse(_ cleaned: String, requestedTarget: Language) -> AITranslation {
        if let data = cleaned.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(AIResponse.self, from: data) {
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

    // MARK: - CLI plumbing

    private func runCLI(fullPrompt: String) async throws -> String {
        let path = cliPath
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw AITranslationError(message: "cursor-agent not found at \(path). Set the path in Settings.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [
            "-p", fullPrompt,
            "--output-format", "text",
            "--mode", "ask",
            "--model", model,
            "--workspace", Self.workspaceDir.path,
            "--trust"
        ]

        // GUI apps launch with a minimal environment; cursor-agent (a bash script
        // that locates its versioned binary) needs HOME and a sane PATH.
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extraPaths = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        env["PATH"] = (extraPaths + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        process.environment = env
        process.currentDirectoryURL = Self.workspaceDir

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        // Accumulate output incrementally so a large response can never fill the
        // pipe buffer and deadlock the child against readDataToEndOfFile.
        let stdoutBuffer = PipeBuffer()
        let stderrBuffer = PipeBuffer()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }

        currentProcess = process

        // Kill runs that hang (network issues, auth prompts…).
        let timeoutTask = Task.detached {
            try? await Task.sleep(for: .seconds(Self.timeoutSeconds))
            if !Task.isCancelled, process.isRunning {
                process.terminate()
            }
        }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { p in
                continuation.resume(returning: p.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: AITranslationError(message: "Could not launch cursor-agent: \(error.localizedDescription)"))
            }
        }

        timeoutTask.cancel()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        // Drain anything still buffered in the pipes after termination.
        stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

        if currentProcess === process { currentProcess = nil }

        let stdout = stdoutBuffer.string()
        let stderr = stderrBuffer.string()

        guard status == 0 else {
            if status == SIGTERM || status == -SIGTERM {
                throw AITranslationError(message: "Cancelled or timed out.")
            }
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = detail.components(separatedBy: "\n").first ?? ""
            throw AITranslationError(message: firstLine.isEmpty ? "cursor-agent failed (code \(status))." : firstLine)
        }

        return stdout
    }

    // MARK: - Models

    /// Parses `cursor-agent --list-models` ("id - Display Name" lines) for Settings.
    func listModels() async -> [CursorModel] {
        let path = cliPath
        guard FileManager.default.isExecutableFile(atPath: path) else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--list-models"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let buffer = PipeBuffer()
        pipe.fileHandleForReading.readabilityHandler = { buffer.append($0.availableData) }

        let launched: Bool = await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume(returning: true) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: false)
            }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        buffer.append(pipe.fileHandleForReading.readDataToEndOfFile())
        guard launched else { return [] }

        return buffer.string()
            .components(separatedBy: "\n")
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let sepRange = trimmed.range(of: " - ") else { return nil }
                let id = String(trimmed[..<sepRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let name = String(trimmed[sepRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard !id.isEmpty, !name.isEmpty, !id.contains(" ") else { return nil }
                return CursorModel(id: id, name: name)
            }
    }
}

/// Thread-safe accumulator for pipe readability handlers (they fire on a
/// background queue while we await on the main actor).
private final class PipeBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
