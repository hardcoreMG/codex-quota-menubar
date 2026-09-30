import AppKit
import Foundation
import OSLog

struct CodexAppServerClient {
    private let decoder = JSONDecoder()

    func readQuota() async throws -> QuotaSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let responses: [JSONRPCResponse]
            do {
                responses = try runAppServerRequests()
            } catch CodexAppServerError.timeout {
                // Retry one read after a transient network timeout with a fresh server.
                try await Task.sleep(for: .seconds(1))
                responses = try runAppServerRequests()
            }
            let rateLimits: CodexRateLimitResponse = try decodeResult(id: 2, from: responses)

            let codexLimit = rateLimits.codexLimit
            let fiveHourWindow = codexLimit.fiveHourWindow
            let weeklyWindow = codexLimit.weeklyWindow

            return QuotaSnapshot(
                fiveHourUsedPercent: fiveHourWindow?.usedPercent,
                fiveHourResetAt: fiveHourWindow?.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                weeklyUsedPercent: weeklyWindow?.usedPercent,
                weeklyResetAt: weeklyWindow?.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                bankResets: rateLimits.rateLimitResetCredits,
                errorMessage: nil
            )
        }.value
    }

    private func decodeResult<T: Decodable>(id: Int, from responses: [JSONRPCResponse]) throws -> T {
        guard let response = responses.first(where: { $0.id == id }) else {
            throw CodexAppServerError.missingResponse(id)
        }

        if let message = response.error?.message {
            throw CodexAppServerError.server(message)
        }

        guard let result = response.result else {
            throw CodexAppServerError.missingResult(id)
        }

        return try decoder.decode(T.self, from: result)
    }
}

// Separate startup from the network-backed quota request so slow startup does not
// consume the quota request's deadline. Injectable process settings support regression tests.
func runAppServerRequests(
    executableURL: URL? = nil,
    arguments: [String] = ["app-server", "--stdio", "--disable", "remote_control"],
    initializationTimeout: TimeInterval = 15,
    quotaTimeout: TimeInterval = 30
) throws -> [JSONRPCResponse] {
    let process = Process()
    process.executableURL = try executableURL ?? codexExecutableURL()
    process.arguments = arguments
    process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr

    let state = AppServerOutput()
    let logger = Logger(subsystem: "com.kevinchin.CodexQuotaBar", category: "app-server")
    stdout.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        state.condition.lock()
        defer { state.condition.unlock() }
        if data.isEmpty {
            state.outputClosed = true
            handle.readabilityHandler = nil
        } else {
            state.buffer.append(data)
            while let newline = state.buffer.firstIndex(of: 0x0A) {
                let line = state.buffer[..<newline]
                if let response = try? JSONDecoder().decode(JSONRPCResponse.self, from: line) {
                    state.responses.append(response)
                }
                state.buffer.removeSubrange(...newline)
            }
        }
        state.condition.broadcast()
    }
    stderr.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        state.condition.lock()
        defer { state.condition.unlock() }
        if data.isEmpty {
            handle.readabilityHandler = nil
        } else {
            // Bound diagnostics even if a server repeatedly logs while waiting.
            state.stderrData.append(data)
            state.stderrData = Data(state.stderrData.suffix(4096))
        }
    }

    defer {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        try? stdin.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        // Bound shutdown too: an unresponsive child must not accumulate per refresh.
        if process.isRunning {
            let deadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        try? stdout.fileHandleForReading.close()
        try? stderr.fileHandleForReading.close()
    }
    try process.run()

    func send(_ request: JSONRPCRequest) throws {
        var data = try JSONEncoder().encode(request)
        data.append(0x0A)
        try stdin.fileHandleForWriting.write(contentsOf: data)
    }

    func waitForResponse(id: Int, stage: String, timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        state.condition.lock()
        defer { state.condition.unlock() }
        while true {
            if let response = state.responses.first(where: { $0.id == id }) {
                if let error = response.error { throw CodexAppServerError.server(error.message) }
                guard response.result != nil else { throw CodexAppServerError.missingResult(id) }
                return
            }
            if state.outputClosed {
                let diagnostics = String(decoding: state.stderrData, as: UTF8.self)
                logger.error("App-server exited during \(stage, privacy: .public): \(diagnostics, privacy: .private)")
                throw CodexAppServerError.processFailed("Codex app-server exited during \(stage)")
            }
            if Date() >= deadline {
                let diagnostics = String(decoding: state.stderrData, as: UTF8.self)
                logger.error("App-server timed out during \(stage, privacy: .public): \(diagnostics, privacy: .private)")
                throw CodexAppServerError.timeout("Codex app-server timed out during \(stage) (\(Int(timeout))s)")
            }
            _ = state.condition.wait(until: deadline)
        }
    }

    try send(JSONRPCRequest(
        id: 1,
        method: "initialize",
        params: [
            "clientInfo": .object([
                "name": .string("codex-quota-menubar"),
                "version": .string("0.1.5")
            ]),
            "capabilities": .object(["experimentalApi": .bool(true)])
        ]
    ))
    try waitForResponse(id: 1, stage: "initialize", timeout: initializationTimeout)
    try send(JSONRPCRequest(id: nil, method: "initialized", params: [:]))
    try send(JSONRPCRequest(id: 2, method: "account/rateLimits/read", params: [:]))
    try waitForResponse(id: 2, stage: "account/rateLimits/read", timeout: quotaTimeout)

    state.condition.lock()
    defer { state.condition.unlock() }
    return state.responses
}

private final class AppServerOutput {
    let condition = NSCondition()
    var buffer = Data()
    var responses: [JSONRPCResponse] = []
    var stderrData = Data()
    var outputClosed = false
}

private func codexExecutableURL() throws -> URL {
    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
        let bundledCodex = appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("codex")

        if FileManager.default.isExecutableFile(atPath: bundledCodex.path) {
            return bundledCodex
        }
    }

    let candidates = [
        "/Applications/Codex.app/Contents/Resources/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex"
    ]

    if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
        return URL(fileURLWithPath: path)
    }

    throw CodexAppServerError.codexExecutableNotFound
}

private struct JSONRPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int?
    let method: String
    let params: [String: JSONValue]
}

struct JSONRPCResponse: Decodable {
    let id: Int?
    let result: Data?
    let error: JSONRPCError?

    private enum CodingKeys: CodingKey {
        case id
        case result
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        error = try container.decodeIfPresent(JSONRPCError.self, forKey: .error)

        if container.contains(.result) {
            let value = try container.decode(JSONValue.self, forKey: .result)
            result = try JSONEncoder().encode(value)
        } else {
            result = nil
        }
    }
}

struct JSONRPCError: Decodable {
    let message: String
}

private enum JSONValue: Codable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

enum CodexAppServerError: LocalizedError {
    case codexExecutableNotFound
    case timeout(String?)
    case processFailed(String)
    case missingResponse(Int)
    case missingResult(Int)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .codexExecutableNotFound:
            return "Codex executable not found"
        case let .timeout(message):
            return message ?? "Codex app-server timed out"
        case let .processFailed(message):
            return message
        case let .missingResponse(id):
            return "Missing response \(id)"
        case let .missingResult(id):
            return "Missing result \(id)"
        case let .server(message):
            return message
        }
    }
}
