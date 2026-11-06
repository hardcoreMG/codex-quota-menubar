import XCTest
@testable import CodexQuotaBar

final class QuotaStoreTests: XCTestCase {
    @MainActor
    func testOnlyInstalledProvidersAreDisplayedAndRead() async {
        let combinations: [[QuotaProvider]] = [[], [.codex], [.grok], [.codex, .grok]]
        for providers in combinations {
            var codexReads = 0
            var grokReads = 0
            let store = QuotaStore(automaticallyRefresh: false, detectProviders: { providers },
                                  readCodex: {
                codexReads += 1
                return QuotaSnapshot(weeklyUsedPercent: 10)
            }, readGrok: {
                grokReads += 1
                return GrokQuotaSnapshot(usedPercent: 20)
            })
            XCTAssertEqual(store.installedProviders, providers)
            await store.refresh()
            XCTAssertEqual(codexReads, providers.contains(.codex) ? 1 : 0)
            XCTAssertEqual(grokReads, providers.contains(.grok) ? 1 : 0)
            XCTAssertEqual(store.snapshot.weeklyRemainingPercent, providers.contains(.codex) ? 90 : nil)
            XCTAssertEqual(store.grokSnapshot.remainingPercent, providers.contains(.grok) ? 80 : nil)
        }
    }

    @MainActor
    func testRefreshDetectsInstallationChangesAndClearsRemovedQuota() async {
        var providers: [QuotaProvider] = [.codex]
        let store = QuotaStore(automaticallyRefresh: false, detectProviders: { providers },
                              readCodex: { QuotaSnapshot(weeklyUsedPercent: 5) },
                              readGrok: { GrokQuotaSnapshot(usedPercent: 10) })
        await store.refresh()
        providers = [.grok]
        await store.refresh()
        XCTAssertEqual(store.installedProviders, [.grok])
        XCTAssertNil(store.snapshot.weeklyRemainingPercent)
        XCTAssertEqual(store.grokSnapshot.remainingPercent, 90)
        providers = []
        await store.refresh()
        XCTAssertEqual(store.installedProviders, [])
        XCTAssertNil(store.grokSnapshot.remainingPercent)
    }

    @MainActor
    func testInFlightReadCannotRestoreAnUninstalledProvider() async {
        var providers: [QuotaProvider] = [.codex, .grok]
        var resumeCodex: CheckedContinuation<QuotaSnapshot, Never>?
        let started = expectation(description: "Codex waiting")
        let store = QuotaStore(automaticallyRefresh: false, detectProviders: { providers },
                              readCodex: {
            await withCheckedContinuation { continuation in
                resumeCodex = continuation
                started.fulfill()
            }
        }, readGrok: { GrokQuotaSnapshot(usedPercent: 10) })
        let firstRefresh = Task { await store.refresh() }
        await fulfillment(of: [started], timeout: 2)
        providers = [.grok]
        await store.refresh()
        resumeCodex?.resume(returning: QuotaSnapshot(weeklyUsedPercent: 3))
        await firstRefresh.value
        XCTAssertEqual(store.installedProviders, [.grok])
        XCTAssertNil(store.snapshot.weeklyRemainingPercent)
        XCTAssertEqual(store.grokSnapshot.remainingPercent, 90)
    }

    @MainActor
    func testCodexFailureDoesNotHideGrokQuota() async {
        let store = QuotaStore(automaticallyRefresh: false,
                              detectProviders: { [.codex, .grok] },
                              readCodex: { throw CodexAppServerError.timeout(nil) },
                              readGrok: { GrokQuotaSnapshot(usedPercent: 12) })
        await store.refresh()
        XCTAssertNotNil(store.snapshot.errorMessage)
        XCTAssertEqual(store.grokSnapshot.remainingPercent, 88)
    }

    @MainActor
    func testGrokFailureClearsItsOldQuotaAndPreservesCodex() async {
        let store = QuotaStore(automaticallyRefresh: false,
                              detectProviders: { [.codex, .grok] },
                              readCodex: { QuotaSnapshot(weeklyUsedPercent: 5) },
                              readGrok: { throw GrokQuotaCacheError.expired })
        store.grokSnapshot = GrokQuotaSnapshot(usedPercent: 20)
        await store.refresh()
        XCTAssertEqual(store.snapshot.weeklyRemainingPercent, 95)
        XCTAssertNil(store.grokSnapshot.remainingPercent)
        XCTAssertNotNil(store.grokSnapshot.errorMessage)
    }

    @MainActor
    func testGrokPublishesWhileCodexIsStillWaiting() async {
        var resumeCodex: CheckedContinuation<QuotaSnapshot, Never>?
        let codexStarted = expectation(description: "Codex read started")
        let grokPublished = expectation(description: "Grok published")
        let store = QuotaStore(automaticallyRefresh: false,
                              detectProviders: { [.codex, .grok] },
                              readCodex: {
            await withCheckedContinuation { continuation in
                resumeCodex = continuation
                codexStarted.fulfill()
            }
        }, readGrok: { GrokQuotaSnapshot(usedPercent: 10) })
        let subscription = store.$grokSnapshot.dropFirst().sink { snapshot in
            if snapshot.remainingPercent == 90 { grokPublished.fulfill() }
        }
        let refresh = Task { await store.refresh() }
        await fulfillment(of: [codexStarted, grokPublished], timeout: 2)
        XCTAssertNil(store.snapshot.weeklyUsedPercent)
        resumeCodex?.resume(returning: QuotaSnapshot(weeklyUsedPercent: 3))
        await refresh.value
        subscription.cancel()
        XCTAssertEqual(store.snapshot.weeklyRemainingPercent, 97)
    }
}
