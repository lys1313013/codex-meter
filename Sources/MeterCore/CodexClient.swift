import Foundation
import Darwin
import os

public enum MeterError: LocalizedError {
    case missingCLI, timeout, disconnected, invalidResponse, server

    var isRetryable: Bool {
        switch self {
        case .timeout, .disconnected, .server: return true
        case .missingCLI, .invalidResponse: return false
        }
    }

    var diagnosticCode: String {
        switch self {
        case .missingCLI: return "missing_cli"
        case .timeout: return "timeout"
        case .disconnected: return "disconnected"
        case .invalidResponse: return "invalid_response"
        case .server: return "server_error"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .missingCLI: return "未找到 Codex。请安装并登录 Codex，或在菜单中选择 CLI 路径。"
        case .timeout: return "读取超时，请检查网络后重试。"
        case .disconnected: return "Codex 连接中断，请确认 CLI 可以正常运行。"
        case .invalidResponse: return "无法识别额度数据，请更新 Codex 后重试。"
        case .server: return "暂时无法读取额度，请确认 Codex 已使用 ChatGPT 账号登录。"
        }
    }
}

public struct CodexClient: Sendable {
    public init() {}

    public static func executable(customPath: String? = nil) -> URL? {
        let fm = FileManager.default
        if let customPath, !customPath.isEmpty {
            let path = (customPath as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            fm.homeDirectoryForCurrentUser.path + "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        return candidates.first(where: { fm.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    public func fetch(customPath: String? = nil) async throws -> UsageResponse {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try self.fetchBlocking(customPath: customPath)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func fetchBlocking(customPath: String?) throws -> UsageResponse {
        let started = ProcessInfo.processInfo.systemUptime
        var stage = "launch"
        var outcome = "process_error"
        defer {
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            let logger = Logger(subsystem: "io.github.lys1313013.codex-meter", category: "refresh")
            // Only fixed categories and timing: never paths, credentials, stderr or raw RPC errors.
            if outcome == "success" {
                logger.info("stage=\(stage, privacy: .public) outcome=\(outcome, privacy: .public) elapsed_ms=\(elapsed)")
            } else {
                logger.error("stage=\(stage, privacy: .public) outcome=\(outcome, privacy: .public) elapsed_ms=\(elapsed)")
            }
        }
        do {
            guard let executable = Self.executable(customPath: customPath) else { throw MeterError.missingCLI }
            let process = Process()
            let input = Pipe(), output = Pipe()
            // A CLI that exits during the handshake must report an error, not kill the app via SIGPIPE.
            _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            process.executableURL = executable
            process.arguments = ["app-server"]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            // Child lifetime is bounded; no background daemon or model turn is started.
            try process.run()
            defer {
                try? input.fileHandleForWriting.close()
                if process.isRunning { process.terminate() }
                let deadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                try? output.fileHandleForReading.close()
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 20
            var pending = Data()

            func send(_ message: [String: Any]) throws {
                var data = try JSONSerialization.data(withJSONObject: message)
                data.append(10)
                try input.fileHandleForWriting.write(contentsOf: data)
            }

            func response(id: Int) throws -> Data {
                while ProcessInfo.processInfo.systemUptime < deadline {
                    while let newline = pending.firstIndex(of: 10) {
                        let line = pending[..<newline]
                        pending.removeSubrange(...newline)
                        guard let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                              let messageID = message["id"] as? Int, messageID == id else { continue }
                        // Avoid surfacing arbitrary server strings that could contain local account data.
                        if message["error"] != nil { throw MeterError.server }
                        guard let result = message["result"], JSONSerialization.isValidJSONObject(result) else {
                            throw MeterError.invalidResponse
                        }
                        return try JSONSerialization.data(withJSONObject: result)
                    }
                    var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
                    let status = poll(&descriptor, 1, 200)
                    if status < 0 { if errno == EINTR { continue }; throw MeterError.disconnected }
                    if status == 0 { continue }
                    var bytes = [UInt8](repeating: 0, count: 8192)
                    let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
                    guard count > 0 else { throw MeterError.disconnected }
                    pending.append(contentsOf: bytes.prefix(count))
                    if pending.count > 2_000_000 { throw MeterError.invalidResponse }
                }
                throw MeterError.timeout
            }

            stage = "initialize"
            try send(["id": 1, "method": "initialize", "params": [
                "clientInfo": ["name": "codex_meter", "title": "Codex Meter",
                               "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"]
            ]])
            _ = try response(id: 1)
            stage = "rate_limits"
            try send(["method": "initialized", "params": [:]])
            try send(["id": 2, "method": "account/rateLimits/read"])
            let data = try response(id: 2)
            stage = "decode"
            do {
                let result = try JSONDecoder().decode(UsageResponse.self, from: data)
                outcome = "success"
                return result
            }
            catch { throw MeterError.invalidResponse }
        } catch {
            outcome = (error as? MeterError)?.diagnosticCode ?? "process_error"
            throw error
        }
    }
}
