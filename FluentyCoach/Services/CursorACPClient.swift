import Foundation

@MainActor
final class CursorACPClient {
    var onSessionUpdate: ((_ sessionId: String, _ update: [String: Any]) -> Void)?
    /// Fires once when the process ends on its own. A caller-initiated `terminate()`
    /// stays silent.
    var onExit: (() -> Void)?

    private var isRunning = true
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let errorLines = LineBuffer()
    private let pidFile: URL
    private let timeout: TimeInterval
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var lastRequestID = 0

    private static let ignoreSIGPIPE: Void = { _ = signal(SIGPIPE, SIG_IGN) }()

    init(executable: URL, environment: [String: String], workingDirectory: URL,
         pidFile: URL, timeout: TimeInterval) throws {
        Self.ignoreSIGPIPE
        self.pidFile = pidFile
        self.timeout = timeout
        process.executableURL = executable
        process.arguments = ["acp"]
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        // Stderr and stdout can lag the exit signal by a few ms, so the exit is
        // finalized after a short grace period to keep the last stderr line.
        let scheduleFinish: @Sendable () -> Void = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                MainActor.assumeIsolated { self?.finish() }
            }
        }

        let stdoutLines = LineBuffer()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                scheduleFinish()
                return
            }
            let lines = stdoutLines.append(chunk)
            guard !lines.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(lines) }
            }
        }

        let stderrLines = errorLines
        errors.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            _ = stderrLines.append(chunk)
        }

        process.terminationHandler = { _ in scheduleFinish() }

        try process.run()
        try? String(process.processIdentifier).write(to: pidFile, atomically: true, encoding: .utf8)
    }

    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        guard isRunning else { throw AITranslationError(message: stopMessage) }
        lastRequestID += 1
        let id = lastRequestID

        let timer = Task { [weak self, timeout] in
            guard (try? await Task.sleep(for: .seconds(timeout))) != nil else { return }
            self?.pending.removeValue(forKey: id)?.resume(throwing: AITranslationError(message: "Timed out."))
        }
        defer { timer.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        }
    }

    func notify(_ method: String, _ params: [String: Any]) {
        send(["jsonrpc": "2.0", "method": method, "params": params])
    }

    func terminate() {
        guard isRunning else { return }
        isRunning = false
        onExit = nil
        onSessionUpdate = nil
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        process.terminate()
        try? FileManager.default.removeItem(at: pidFile)
        failPending(AITranslationError(message: "cursor-agent stopped"))
    }

    /// Once authenticated, `cursor-agent acp` keeps running after its parent dies,
    /// so a crashed or force-quit app would leak it. The pid recorded at spawn lets
    /// the next launch stop that orphan, after checking it really is one.
    static func reapOrphan(pidFile: URL) {
        guard let recorded = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = pid_t(recorded.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return }
        try? FileManager.default.removeItem(at: pidFile)

        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "ppid=,command=", "-p", String(pid)]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()

        let line = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = line.split(separator: " ", maxSplits: 1)
        guard fields.count == 2, fields[0] == "1",
              fields[1].contains("cursor-agent"), fields[1].hasSuffix(" acp") else { return }
        kill(pid, SIGTERM)
    }

    private enum Incoming {
        case response(id: Int, outcome: Result<[String: Any], Error>)
        case notification(method: String, params: [String: Any])
        case agentRequest(id: Any, method: String)

        init?(_ object: [String: Any]) {
            let method = object["method"] as? String
            let id = object["id"]
            switch (method, id) {
            case let (method?, id?):
                self = .agentRequest(id: id, method: method)
            case let (method?, nil):
                self = .notification(method: method, params: object["params"] as? [String: Any] ?? [:])
            case let (nil, id as Int):
                if let error = object["error"] as? [String: Any] {
                    let detail = (error["data"] as? [String: Any])?["message"] as? String
                    let message = detail ?? error["message"] as? String ?? "cursor-agent request failed."
                    self = .response(id: id, outcome: .failure(AITranslationError(message: message)))
                } else {
                    self = .response(id: id, outcome: .success(object["result"] as? [String: Any] ?? [:]))
                }
            default:
                return nil
            }
        }
    }

    private func receive(_ lines: [Data]) {
        for line in lines {
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let message = Incoming(object) else { continue }
            switch message {
            case let .response(id, outcome):
                pending.removeValue(forKey: id)?.resume(with: outcome)
            case let .notification(method, params):
                if method == "session/update",
                   let sessionId = params["sessionId"] as? String,
                   let update = params["update"] as? [String: Any] {
                    onSessionUpdate?(sessionId, update)
                }
            case let .agentRequest(id, method):
                if method == "session/request_permission" {
                    send(["jsonrpc": "2.0", "id": id, "result": ["outcome": ["outcome": "cancelled"]]])
                } else {
                    send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]])
                }
            }
        }
    }

    private func send(_ object: [String: Any]) {
        guard isRunning, var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    private var stopMessage: String {
        errorLines.lastLine ?? "cursor-agent stopped"
    }

    private func finish() {
        guard isRunning else { return }
        isRunning = false
        try? FileManager.default.removeItem(at: pidFile)
        failPending(AITranslationError(message: stopMessage))
        onExit?()
    }

    private func failPending(_ error: Error) {
        let waiting = pending
        pending = [:]
        for continuation in waiting.values {
            continuation.resume(throwing: error)
        }
    }
}

private final class LineBuffer: @unchecked Sendable {
    private var partial = Data()
    private var lastNonEmpty: Data?
    private let lock = NSLock()

    var lastLine: String? {
        lock.lock()
        defer { lock.unlock() }
        let text = lastNonEmpty.map { String(decoding: $0, as: UTF8.self) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    func append(_ chunk: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        partial.append(chunk)
        var lines: [Data] = []
        while let newline = partial.firstIndex(of: 0x0A) {
            lines.append(Data(partial[partial.startIndex..<newline]))
            partial.removeSubrange(partial.startIndex...newline)
        }
        if partial.count > 1_048_576 { partial.removeAll() }
        if let last = lines.last(where: { !$0.isEmpty }) { lastNonEmpty = last }
        return lines
    }
}
