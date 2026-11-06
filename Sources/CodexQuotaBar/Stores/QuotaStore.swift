import Foundation
import Combine

@MainActor
final class QuotaStore: ObservableObject {
    private let readCodex: () async throws -> QuotaSnapshot
    private let readGrok: () async throws -> GrokQuotaSnapshot
    private let detectProviders: () -> [QuotaProvider]

    @Published private(set) var installedProviders: [QuotaProvider]
    @Published var snapshot: QuotaSnapshot = .empty
    @Published var grokSnapshot: GrokQuotaSnapshot = .empty
    private var isRefreshingCodex = false
    private var isRefreshingGrok = false

    init(
        automaticallyRefresh: Bool = true,
        detectProviders: @escaping () -> [QuotaProvider] = QuotaProviderDetector.installedProviders,
        readCodex: @escaping () async throws -> QuotaSnapshot = { try await CodexAppServerClient().readQuota() },
        readGrok: @escaping () async throws -> GrokQuotaSnapshot = {
            try await Task.detached { try GrokQuotaCacheClient().readQuota() }.value
        }
    ) {
        self.readCodex = readCodex
        self.readGrok = readGrok
        self.detectProviders = detectProviders
        installedProviders = detectProviders()
        guard automaticallyRefresh else { return }
        Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func refresh() async {
        let providers = detectProviders()
        if providers != installedProviders {
            installedProviders = providers
            if !providers.contains(.codex) { snapshot = .empty }
            if !providers.contains(.grok) { grokSnapshot = .empty }
        }
        async let codex: Void = refreshCodex()
        async let grok: Void = refreshGrok()
        _ = await (codex, grok)
    }

    private func refreshCodex() async {
        guard installedProviders.contains(.codex), !isRefreshingCodex else {
            return
        }

        isRefreshingCodex = true
        defer {
            isRefreshingCodex = false
        }

        do {
            let result = try await readCodex()
            guard installedProviders.contains(.codex) else { return }
            snapshot = result
        } catch {
            guard installedProviders.contains(.codex) else { return }
            snapshot = QuotaSnapshot(
                errorMessage: error.localizedDescription
            )
        }
    }

    private func refreshGrok() async {
        guard installedProviders.contains(.grok), !isRefreshingGrok else { return }
        isRefreshingGrok = true
        defer { isRefreshingGrok = false }
        do {
            let result = try await readGrok()
            guard installedProviders.contains(.grok) else { return }
            grokSnapshot = result
        } catch {
            guard installedProviders.contains(.grok) else { return }
            grokSnapshot = GrokQuotaSnapshot(errorMessage: error.localizedDescription)
        }
    }
}
