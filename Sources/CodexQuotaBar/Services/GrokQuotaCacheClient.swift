import CryptoKit
import Foundation

/// Reads only Grok Bot's active-account marker and weekly quota cache (schemas 2 and 3).
/// Authentication, network requests and cache updates remain owned by Grok Bot.
struct GrokQuotaCacheClient {
    let userDataURL: URL

    init(userDataURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Grok Bot")) {
        self.userDataURL = userDataURL
    }

    func readQuota(at now: Date = Date()) throws -> GrokQuotaSnapshot {
        guard FileManager.default.fileExists(atPath: userDataURL.path) else {
            throw GrokQuotaCacheError.notFound
        }
        do {
            let statusURL = userDataURL.appendingPathComponent("desktop-status.json")
            if FileManager.default.fileExists(atPath: statusURL.path) {
                let status = try JSONDecoder().decode(DesktopStatus.self, from: Data(contentsOf: statusURL))
                guard status.signedIn else { throw GrokQuotaCacheError.signedOut }
            }

            let accountKey = "sand.client.slice.client-meta.account-slot"
            let account: Envelope<String?> = try read(accountKey)
            guard account.schemaVersion == 1 else { throw GrokQuotaCacheError.unsupportedFormat }
            guard let slot = account.value, !slot.isEmpty else { throw GrokQuotaCacheError.signedOut }
            // Grok Bot scopes this key with JavaScript's encodeURIComponent.
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
            let encodedSlot = slot.addingPercentEncoding(withAllowedCharacters: allowed)!
            let cache: Envelope<WeeklyCache> = try read("sand.client.slice.account.\(encodedSlot).weekly-usage.cache")
            guard [2, 3].contains(cache.schemaVersion) else { throw GrokQuotaCacheError.unsupportedFormat }
            guard cache.value.kind == "present", let reading = cache.value.reading else {
                throw GrokQuotaCacheError.unavailable
            }
            // An account switch can replace the marker while these files are read.
            let currentAccount: Envelope<String?> = try read(accountKey)
            guard currentAccount.value == slot else { throw GrokQuotaCacheError.accountChanged }

            let usage = reading.usage
            guard usage.percentUsed.isFinite, usage.percentUsed >= 0,
                  reading.readAtMs.isFinite, reading.readAtMs > 0,
                  cache.value.expiresAtMs.isFinite else {
                throw GrokQuotaCacheError.unsupportedFormat
            }
            let resetAt = usage.nextResetMs.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
            let updatedAt = Date(timeIntervalSince1970: reading.readAtMs / 1000)
            let expiresAt = min(Date(timeIntervalSince1970: cache.value.expiresAtMs / 1000),
                                updatedAt.addingTimeInterval(86_400), resetAt ?? .distantFuture)
            guard expiresAt > now else { throw GrokQuotaCacheError.expired }
            return GrokQuotaSnapshot(
                usedPercent: usage.percentUsed,
                resetAt: resetAt,
                updatedAt: updatedAt,
                isTrial: usage.isSandTrial
            )
        } catch let error as GrokQuotaCacheError {
            throw error
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw GrokQuotaCacheError.unavailable
        } catch is DecodingError {
            throw GrokQuotaCacheError.unsupportedFormat
        }
    }

    private func read<T: Decodable>(_ key: String) throws -> T {
        let name = Self.blobName(for: key)
        let url = userDataURL.appendingPathComponent("sand-client-persistence").appendingPathComponent(name)
        var data = try Data(contentsOf: url)
        // Long keys are stored as a JSON key line followed by the envelope.
        if name.hasSuffix(".kblob") {
            guard let newline = data.firstIndex(of: 0x0A),
                  try JSONDecoder().decode(String.self, from: data[..<newline]) == key else {
                throw GrokQuotaCacheError.unsupportedFormat
            }
            data = data.subdata(in: (newline + 1)..<data.endIndex)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func blobName(for key: String) -> String {
        let bytes = Data(key.utf8)
        let encoded = base32(bytes) + ".blob"
        return encoded.utf8.count <= 240 ? encoded : base32(Data(SHA256.hash(data: bytes))) + ".kblob"
    }

    private static func base32(_ data: Data) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567".utf8)
        var result: [UInt8] = []
        var buffer: UInt16 = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | UInt16(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                result.append(alphabet[Int((buffer >> bits) & 31)])
            }
        }
        if bits > 0 { result.append(alphabet[Int((buffer << (5 - bits)) & 31)]) }
        return String(decoding: result, as: UTF8.self)
    }
}

private struct Envelope<Value: Decodable>: Decodable {
    let schemaVersion: Int
    let value: Value
}

private struct DesktopStatus: Decodable {
    let signedIn: Bool
}

private struct WeeklyCache: Decodable {
    let kind: String
    let reading: Reading?
    let expiresAtMs: Double

    struct Reading: Decodable {
        let usage: Usage
        let readAtMs: Double
    }

    struct Usage: Decodable {
        let percentUsed: Double
        let nextResetMs: Double?
        let isSandTrial: Bool
    }
}

enum GrokQuotaCacheError: LocalizedError {
    case notFound, signedOut, unavailable, expired, unsupportedFormat, accountChanged

    var errorDescription: String? {
        switch self {
        case .notFound: return "请先安装并登录 Grok Bot"
        case .signedOut: return "请先登录 Grok Bot"
        case .unavailable: return "暂无额度数据，请在 Grok Bot 中打开用量菜单"
        case .expired: return "额度缓存已过期，请在 Grok Bot 中打开用量菜单更新"
        case .unsupportedFormat: return "Grok Bot 额度缓存格式不受支持"
        case .accountChanged: return "Grok Bot 正在切换账号，请稍后刷新"
        }
    }
}
