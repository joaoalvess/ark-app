import Foundation
import Observation

@MainActor
protocol SuggestionCodexClient: AnyObject {
    func chatStream(
        systemPrompt: String,
        userMessage: String,
        model: String?,
        reasoningLevel: String?,
        requestID: UUID,
        onChunk: @escaping @Sendable (UUID, String) -> Void
    ) async throws -> String
}

@MainActor @Observable
final class CodexCLIService: SuggestionCodexClient {
    private(set) var isAvailable = false
    private(set) var isAuthenticated = false
    private var codexPath: String?

    nonisolated static let userShell: String = {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }
        return "/bin/zsh"
    }()

    nonisolated private static var shellConfigSource: String? {
        if userShell.hasSuffix("/fish") {
            return "source ~/.config/fish/config.fish 2>/dev/null; "
        } else if userShell.hasSuffix("/zsh") {
            return "source ~/.zshrc 2>/dev/null; "
        } else if userShell.hasSuffix("/bash") {
            return "source ~/.bashrc 2>/dev/null; "
        }
        return nil
    }

    func checkAvailability() async {
        let path = await resolveCodexPath()
        codexPath = path
        isAvailable = path != nil
        if isAvailable {
            isAuthenticated = await checkAuth()
        } else {
            isAuthenticated = false
        }
    }

    func installCodex() async -> (success: Bool, message: String) {
        let sourcePrefix = Self.shellConfigSource ?? ""
        let result = await runShellCommand("\(sourcePrefix)npm install -g @openai/codex", timeout: 300)
        if result.exitCode == 0 {
            await checkAvailability()
            return (true, "Codex CLI installed successfully")
        } else {
            return (false, result.stderr.isEmpty ? "Installation failed" : "Installation failed: \(result.stderr)")
        }
    }

    func checkAuth() async -> Bool {
        guard let command = await resolvedCommand() else { return false }
        let result = await runShellCommand("\(command) login status", timeout: 15)
        return result.exitCode == 0
    }

    func login() async -> (success: Bool, message: String) {
        guard let command = await resolvedCommand() else {
            return (false, "Codex CLI not found on this system")
        }
        let result = await runShellCommand("\(command) login", timeout: 120)
        if result.exitCode == 0 {
            isAuthenticated = await checkAuth()
            return (isAuthenticated, isAuthenticated ? "Login completed successfully" : "Login completed, but authentication was not confirmed")
        } else {
            return (false, result.stderr.isEmpty ? "Login failed" : "Login failed: \(result.stderr)")
        }
    }

    func chat(systemPrompt: String, userMessage: String, model: String? = nil, reasoningLevel: String? = nil) async throws -> String {
        let prompt = "\(systemPrompt)\n\n\(userMessage)"
        let (stdout, _) = try await runCodex(prompt: prompt, model: model, reasoningLevel: reasoningLevel)
        return parseResponse(from: stdout)
    }

    func chatStream(
        systemPrompt: String,
        userMessage: String,
        model: String? = nil,
        reasoningLevel: String? = nil,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await chatStream(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            model: model,
            reasoningLevel: reasoningLevel,
            requestID: UUID()
        ) { _, chunk in
            onChunk(chunk)
        }
    }

    func chatStream(
        systemPrompt: String,
        userMessage: String,
        model: String? = nil,
        reasoningLevel: String? = nil,
        requestID: UUID,
        onChunk: @escaping @Sendable (UUID, String) -> Void
    ) async throws -> String {
        let prompt = "\(systemPrompt)\n\n\(userMessage)"
        let cancellationBox = StreamCancellationBox()

        return try await withTaskCancellationHandler(operation: {
            guard let command = await resolvedCommand() else {
                throw CodexError.notAvailable
            }

            let processInstance = Process()
            let stdoutPipeInstance = Pipe()
            let stderrPipeInstance = Pipe()
            cancellationBox.process = processInstance
            cancellationBox.stdoutPipe = stdoutPipeInstance
            cancellationBox.stderrPipe = stderrPipeInstance

            let escapedPrompt = prompt.replacingOccurrences(of: "'", with: "'\\''")
            let modelFlag = model.map { " --model \($0)" } ?? ""
            let reasoningFlag = reasoningLevel.map { " -c model_reasoning_effort=\"\($0)\"" } ?? ""
            processInstance.executableURL = URL(fileURLWithPath: Self.userShell)
            processInstance.arguments = ["-l", "-c", "\(command) exec --json\(modelFlag)\(reasoningFlag) '\(escapedPrompt)' --skip-git-repo-check"]
            processInstance.standardOutput = stdoutPipeInstance
            processInstance.standardError = stderrPipeInstance

            try processInstance.run()

            let stderrHandle = stderrPipeInstance.fileHandleForReading
            let stderrCollector = Task.detached { () -> String in
                let data = stderrHandle.readDataToEndOfFile()
                return String(data: data, encoding: .utf8) ?? ""
            }

            let streamResult: String = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { [self] in
                    var fullResponse = ""
                    var byteBuffer = Data()

                    let handle = stdoutPipeInstance.fileHandleForReading
                    for try await byte in handle.bytes {
                        try Task.checkCancellation()
                        if byte == UInt8(ascii: "\n") {
                            if let line = String(data: byteBuffer, encoding: .utf8),
                               let text = self.extractAgentMessage(from: line) {
                                fullResponse += text
                                onChunk(requestID, text)
                            }
                            byteBuffer.removeAll()
                        } else {
                            byteBuffer.append(byte)
                        }
                    }

                    if !byteBuffer.isEmpty {
                        if let line = String(data: byteBuffer, encoding: .utf8),
                           let text = self.extractAgentMessage(from: line) {
                            fullResponse += text
                            onChunk(requestID, text)
                        }
                    }

                    return fullResponse
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: 120_000_000_000)
                    throw CodexError.failed(exit: -1, stderr: "Timeout: response took longer than 120s")
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }

            try Task.checkCancellation()
            processInstance.waitUntilExit()
            let stderr = await stderrCollector.value

            #if DEBUG
            if !stderr.isEmpty {
                print("[CodexCLI] stderr: \(stderr.prefix(500))")
            }
            #endif

            if streamResult.isEmpty {
                if processInstance.terminationStatus != 0 {
                    throw CodexError.failed(exit: Int(processInstance.terminationStatus), stderr: stderr)
                }
                if !stderr.isEmpty {
                    throw CodexError.failed(exit: 0, stderr: "No model response. stderr: \(stderr)")
                }
            }

            return streamResult
        }, onCancel: {
            if let process = cancellationBox.process, process.isRunning {
                process.terminate()
            }
            cancellationBox.stdoutPipe?.fileHandleForReading.closeFile()
            cancellationBox.stderrPipe?.fileHandleForReading.closeFile()
        })
    }
    func testConnection() async -> Bool {
        do {
            let (_, exitCode) = try await runCodexRaw(prompt: "respond ok")
            return exitCode == 0
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func resolvedCommand() async -> String? {
        if let path = codexPath { return path }
        let path = await resolveCodexPath()
        codexPath = path
        return path
    }

    private func runCodex(prompt: String, model: String? = nil, reasoningLevel: String? = nil) async throws -> (stdout: String, stderr: String) {
        let (stdout, exitCode) = try await runCodexRaw(prompt: prompt, model: model, reasoningLevel: reasoningLevel)
        if exitCode != 0 {
            throw CodexError.failed(exit: exitCode, stderr: "")
        }
        return (stdout, "")
    }

    private func runCodexRaw(prompt: String, model: String? = nil, reasoningLevel: String? = nil) async throws -> (stdout: String, exitCode: Int) {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        guard let command = await resolvedCommand() else {
            throw CodexError.notAvailable
        }
        let escapedPrompt = prompt.replacingOccurrences(of: "'", with: "'\\''")
        let modelFlag = model.map { " --model \($0)" } ?? ""
        let reasoningFlag = reasoningLevel.map { " -c model_reasoning_effort=\"\($0)\"" } ?? ""
        process.executableURL = URL(fileURLWithPath: Self.userShell)
        process.arguments = ["-l", "-c", "\(command) exec --json\(modelFlag)\(reasoningFlag) '\(escapedPrompt)' --skip-git-repo-check"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let result: (String, Int) = try await withThrowingTaskGroup(of: (String, Int).self) { group in
            group.addTask {
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                return (stdout, Int(process.terminationStatus))
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 120_000_000_000)
                throw CodexError.failed(exit: -1, stderr: "Timeout: response took longer than 120s")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        return result
    }

    nonisolated private func parseResponse(from stdout: String) -> String {
        let lines = stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n")
        // First pass: look for structured JSON agent_message
        for line in lines.reversed() {
            let lineStr = String(line)
            guard let data = lineStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let item = json["item"] as? [String: Any],
                  let type = item["type"] as? String, type == "agent_message",
                  let text = item["text"] as? String else { continue }
            return text
        }
        // Second pass: try full extractAgentMessage (with fallbacks)
        for line in lines.reversed() {
            if let text = extractAgentMessage(from: String(line)) {
                return text
            }
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private func extractAgentMessage(from line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Not JSON — CLI banners/spinners, discard
            #if DEBUG
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                print("[CodexCLI] Skipping non-JSON line: \(trimmed.prefix(100))")
            }
            #endif
            return nil
        }

        // Codex exec --json: {"type":"item.completed","item":{"type":"agent_message","text":"..."}}
        if let item = json["item"] as? [String: Any],
           let type = item["type"] as? String, type == "agent_message",
           let text = item["text"] as? String {
            return text
        }

        // Streaming delta events: {"type":"agent_message.delta","delta":"..."}
        if let type = json["type"] as? String, type.contains("delta"),
           let delta = json["delta"] as? String {
            return delta
        }

        // OpenAI-style content array: {"item":{"content":[{"type":"text","text":"..."}]}}
        if let item = json["item"] as? [String: Any],
           let content = item["content"] as? [[String: Any]],
           let first = content.first,
           let text = first["text"] as? String {
            return text
        }

        // Fallbacks for alternative formats
        if let output = json["output"] as? String { return output }
        if let result = json["result"] as? String { return result }
        if let text = json["text"] as? String { return text }
        if let content = json["content"] as? String { return content }
        if let message = json["message"] as? String { return message }

        // Skip known control events silently
        if let type = json["type"] as? String,
           ["thread.started", "turn.started", "turn.completed", "item.completed"].contains(type) {
            // item.completed without agent_message (e.g. reasoning) — skip
            return nil
        }

        #if DEBUG
        print("[CodexCLI] Unrecognized JSON line: \(line.prefix(200))")
        #endif
        return nil
    }

    private func resolveCodexPath() async -> String? {
        // Strategy 1: login shell (-l -c)
        if let path = await shellWhichCodex(args: ["-l", "-c"]) { return path }
        // Strategy 2: source shell config explicitly (fish, zsh, bash)
        if let sourcePrefix = Self.shellConfigSource,
           let path = await shellWhichCodex(args: ["-c"], prefix: sourcePrefix) { return path }
        // Strategy 3: check common paths directly on filesystem
        return findCodexInCommonPaths()
    }

    private func shellWhichCodex(args: [String], prefix: String = "") async -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: Self.userShell)
        process.arguments = args + ["\(prefix)which codex 2>/dev/null"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            let path = output.components(separatedBy: .newlines)
                .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
                .trimmingCharacters(in: .whitespaces)
            guard let path, path.hasPrefix("/") else { return nil }
            return path
        } catch {
            return nil
        }
    }

    private func findCodexInCommonPaths() -> String? {
        let home = NSHomeDirectory()
        var candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.npm-global/bin/codex",
        ]
        let nvmDir = "\(home)/.nvm/versions/node"
        if let nodes = try? FileManager.default.contentsOfDirectory(atPath: nvmDir),
           let latest = nodes.sorted().last {
            candidates.insert("\(nvmDir)/\(latest)/bin/codex", at: 0)
        }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    enum CodexError: LocalizedError {
        case failed(exit: Int, stderr: String)
        case notAvailable

        var errorDescription: String? {
            switch self {
            case .failed(let exit, let stderr):
                "Codex CLI failed (exit \(exit))\(stderr.isEmpty ? "" : ": \(stderr)")"
            case .notAvailable:
                "Codex CLI not found. Install it with: npm install -g @openai/codex"
            }
        }
    }
}

private struct ShellResult: Sendable {
    let exitCode: Int
    let stdout: String
    let stderr: String
}

private final class StreamCancellationBox: @unchecked Sendable {
    var process: Process?
    var stdoutPipe: Pipe?
    var stderrPipe: Pipe?
}

private func runShellCommand(_ command: String, timeout: TimeInterval) async -> ShellResult {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: CodexCLIService.userShell)
            process.arguments = ["-l", "-c", command]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ShellResult(exitCode: -1, stdout: "", stderr: error.localizedDescription))
                return
            }

            let semaphore = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in semaphore.signal() }
            let finished = semaphore.wait(timeout: .now() + timeout)

            if finished == .timedOut {
                process.terminate()
                continuation.resume(returning: ShellResult(exitCode: -1, stdout: "", stderr: "Timeout after \(Int(timeout))s"))
                return
            }

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            continuation.resume(returning: ShellResult(
                exitCode: Int(process.terminationStatus),
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            ))
        }
    }
}
