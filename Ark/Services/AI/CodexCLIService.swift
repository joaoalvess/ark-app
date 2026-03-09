import Foundation
import Observation

@MainActor @Observable
final class CodexCLIService {
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
            return (true, "Codex CLI instalado com sucesso")
        } else {
            return (false, result.stderr.isEmpty ? "Falha na instalacao" : "Falha na instalacao: \(result.stderr)")
        }
    }

    func checkAuth() async -> Bool {
        guard let command = await resolvedCommand() else { return false }
        let result = await runShellCommand("\(command) login status", timeout: 15)
        return result.exitCode == 0
    }

    func login() async -> (success: Bool, message: String) {
        guard let command = await resolvedCommand() else {
            return (false, "Codex CLI nao encontrado no sistema")
        }
        let result = await runShellCommand("\(command) login", timeout: 120)
        if result.exitCode == 0 {
            isAuthenticated = await checkAuth()
            return (isAuthenticated, isAuthenticated ? "Login realizado com sucesso" : "Login completou mas autenticacao nao confirmada")
        } else {
            return (false, result.stderr.isEmpty ? "Falha no login" : "Falha no login: \(result.stderr)")
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
        let prompt = "\(systemPrompt)\n\n\(userMessage)"

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

        var fullResponse = ""
        var byteBuffer = Data()

        let handle = stdoutPipe.fileHandleForReading
        for try await byte in handle.bytes {
            if byte == UInt8(ascii: "\n") {
                if let line = String(data: byteBuffer, encoding: .utf8),
                   let text = extractAgentMessage(from: line) {
                    fullResponse += text
                    onChunk(text)
                }
                byteBuffer.removeAll()
            } else {
                byteBuffer.append(byte)
            }
        }

        // Handle remaining buffer
        if !byteBuffer.isEmpty {
            if let line = String(data: byteBuffer, encoding: .utf8),
               let text = extractAgentMessage(from: line) {
                fullResponse += text
                onChunk(text)
            }
        }

        process.waitUntilExit()

        if fullResponse.isEmpty {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: data, encoding: .utf8) ?? ""
            if process.terminationStatus != 0 {
                throw CodexError.failed(exit: Int(process.terminationStatus), stderr: stderr)
            }
        }

        return fullResponse
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

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        return (stdout, Int(process.terminationStatus))
    }

    private func parseResponse(from stdout: String) -> String {
        let lines = stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n")
        for line in lines.reversed() {
            if let text = extractAgentMessage(from: String(line)) {
                return text
            }
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractAgentMessage(from line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Codex exec --json: item.type == "agent_message" -> item.text
        if let item = json["item"] as? [String: Any],
           let type = item["type"] as? String, type == "agent_message",
           let text = item["text"] as? String {
            return text
        }

        // Fallbacks
        if let output = json["output"] as? String { return output }
        if let result = json["result"] as? String { return result }
        if let text = json["text"] as? String { return text }

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
                "Codex CLI falhou (exit \(exit))\(stderr.isEmpty ? "" : ": \(stderr)")"
            case .notAvailable:
                "Codex CLI nao encontrado. Instale com: npm install -g @openai/codex"
            }
        }
    }
}

private struct ShellResult: Sendable {
    let exitCode: Int
    let stdout: String
    let stderr: String
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
                continuation.resume(returning: ShellResult(exitCode: -1, stdout: "", stderr: "Timeout apos \(Int(timeout))s"))
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
