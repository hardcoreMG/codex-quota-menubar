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

    var menuTitle: String {
        snapshot.menuTitle
    }

    var statusLine: String {
        isRefreshing ? "正在刷新..." : snapshot.updatedLine
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
                updatedAt: Date(),
                errorMessage: error.localizedDescription
            )
        }
    }

    func toggleLowQuotaAlert() {
        lowQuotaAlertEnabled.toggle()
    }

    func setLowQuotaAlertEnabled(_ isEnabled: Bool) {
        lowQuotaAlertEnabled = isEnabled
    }
}
