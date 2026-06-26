import AppKit
import Foundation

struct CodexAppServerClient {
    private let decoder = JSONDecoder()

    func readQuota() async throws -> QuotaSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let responses = try runAppServerRequests()
            let rateLimits: CodexRateLimitResponse = try decodeResult(id: 2, from: responses)
            let usage: CodexUsageResponse? = try? decodeResult(id: 3, from: responses)

            let codexLimit = rateLimits.codexLimit
            let primary = codexLimit.primary
            let secondary = codexLimit.secondary

            return QuotaSnapshot(
                fiveHourUsedPercent: primary?.usedPercent,
                fiveHourResetAt: primary?.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                weeklyUsedPercent: secondary?.usedPercent,
                weeklyResetAt: secondary?.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                resetCredits: rateLimits.rateLimitResetCredits?.availableCount,
                lifetimeTokens: usage?.summary.lifetimeTokens,
                updatedAt: Date(),
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

private func runAppServerRequests() throws -> [JSONRPCResponse] {
    let process = Process()
    process.executableURL = try codexExecutableURL()
    process.arguments = ["app-server", "--stdio", "--disable", "remote_control"]
    process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()

    let lock = NSLock()
    let semaphore = DispatchSemaphore(value: 0)
    var outputBuffer = ""
    var responses: [JSONRPCResponse] = []
    var stderrText = ""

    stdout.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty else {
            return
        }

        let chunk = String(data: data, encoding: .utf8) ?? ""

        lock.lock()
        outputBuffer += chunk

        while let newline = outputBuffer.firstIndex(of: "\n") {
            let line = String(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)

            if let data = line.data(using: .utf8),
               let response = try? JSONDecoder().decode(JSONRPCResponse.self, from: data) {
                responses.append(response)
            }
        }

        let hasRateLimits = responses.contains { $0.id == 2 }
        let hasUsage = responses.contains { $0.id == 3 }
        lock.unlock()

        if hasRateLimits && hasUsage {
            semaphore.signal()
        }
    }

    stderr.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty else {
            return
        }

        lock.lock()
        stderrText += String(data: data, encoding: .utf8) ?? ""
        lock.unlock()
    }

    let requests = [
        JSONRPCRequest(
            id: 1,
            method: "initialize",
            params: [
                "clientInfo": .object([
                    "name": .string("codex-quota-menubar"),
                    "version": .string("0.1.0")
                ]),
                "capabilities": .object([
                    "experimentalApi": .bool(true)
                ])
            ]
        ),
        JSONRPCRequest(id: 2, method: "account/rateLimits/read", params: [:]),
        JSONRPCRequest(id: 3, method: "account/usage/read", params: [:])
    ]

    for request in requests {
        let data = try JSONEncoder().encode(request)
        stdin.fileHandleForWriting.write(data)
        stdin.fileHandleForWriting.write(Data([0x0A]))
    }

    let result = semaphore.wait(timeout: .now() + 15)

    stdout.fileHandleForReading.readabilityHandler = nil
    stderr.fileHandleForReading.readabilityHandler = nil
    stdin.fileHandleForWriting.closeFile()

    if process.isRunning {
        process.terminate()
    }

    if result == .timedOut {
        let message = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        throw CodexAppServerError.timeout(message.isEmpty ? nil : message)
    }

    lock.lock()
    let finalResponses = responses
    lock.unlock()

    return finalResponses
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
    let id: Int
    let method: String
    let params: [String: JSONValue]
}

private struct JSONRPCResponse: Decodable {
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

private struct JSONRPCError: Decodable {
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
