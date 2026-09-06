import Foundation
import Combine

@MainActor
final class QuotaStore: ObservableObject {
    private static let lowQuotaAlertKey = "lowQuotaAlertEnabled"
    private let client = CodexAppServerClient()

    @Published var snapshot: QuotaSnapshot = .empty
    @Published var isRefreshing = false
    @Published var lowQuotaAlertEnabled: Bool {
        didSet {
            UserDefaults.standard.set(lowQuotaAlertEnabled, forKey: Self.lowQuotaAlertKey)
        }
    }

    init() {
        lowQuotaAlertEnabled = UserDefaults.standard.bool(forKey: Self.lowQuotaAlertKey)

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

    func setLowQuotaAlertEnabled(_ isEnabled: Bool) {
        lowQuotaAlertEnabled = isEnabled
    }
}
