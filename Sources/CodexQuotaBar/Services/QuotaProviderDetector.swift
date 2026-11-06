import AppKit

enum QuotaProviderDetector {
    static func installedProviders() -> [QuotaProvider] {
        var providers: [QuotaProvider] = []
        if CodexAppServerClient.isInstalled { providers.append(.codex) }

        let grokURLs = [
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anysphere.sand"),
            URL(fileURLWithPath: "/Applications/Grok Bot.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Grok Bot.app")
        ].compactMap { $0 }
        if grokURLs.contains(where: isApplicationInstalled) { providers.append(.grok) }
        return providers
    }

    static func isApplicationInstalled(at url: URL) -> Bool {
        guard let executable = Bundle(url: url)?.executableURL else { return false }
        return FileManager.default.isExecutableFile(atPath: executable.path)
    }
}
