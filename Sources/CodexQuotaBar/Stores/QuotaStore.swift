import Foundation
import Combine

@MainActor
final class QuotaStore: ObservableObject {
    private let client = CodexAppServerClient()

    @Published var snapshot: QuotaSnapshot = .empty
    @Published var isRefreshing = false

    init() {
        Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        do {
            snapshot = try await client.readQuota()
        } catch {
            snapshot = QuotaSnapshot(
                errorMessage: error.localizedDescription
            )
        }
    }

}
