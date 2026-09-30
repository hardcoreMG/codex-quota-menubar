import XCTest
@testable import CodexQuotaBar

final class AppServerClientTests: XCTestCase {
    private func run(_ script: String, startup: TimeInterval = 1, quota: TimeInterval = 1) throws -> [JSONRPCResponse] {
        try runAppServerRequests(executableURL: URL(fileURLWithPath: "/bin/sh"),
                                arguments: ["-c", script],
                                initializationTimeout: startup, quotaTimeout: quota)
    }

    func testHandshakePrecedesQuotaAndHandlesFragmentedResponse() throws {
        let responses = try run(#"""
        read -r request
        printf '%s\n' '{"id":1,"result":{}}'
        read -r notification
        case "$notification" in *'"id"'*) exit 2;; esac
        case "$notification" in *'"method":"initialized"'*) ;; *) exit 3;; esac
        read -r request
        case "$request" in *'account'*'rateLimits'*'read'*) ;; *) exit 4;; esac
        printf '%s' '{"id":2,"res'
        sleep 0.05
        printf '%s\n' 'ult":{}}'
        """#)
        XCTAssertEqual(responses.compactMap(\.id), [1, 2])
    }

    func testInitializationErrorIsReportedImmediately() {
        XCTAssertThrowsError(try run(#"""
        read -r request
        printf '%s\n' '{"id":1,"error":{"message":"Initialization rejected"}}'
        """#)) { error in
            XCTAssertEqual(error.localizedDescription, "Initialization rejected")
        }
    }

    func testEarlyExitIsNotReportedAsTimeout() {
        XCTAssertThrowsError(try run("read -r request; exit 7")) { error in
            guard case CodexAppServerError.processFailed = error else {
                return XCTFail("Expected process failure, got \(error)")
            }
        }
    }

    func testStartupTimeoutIdentifiesStage() {
        XCTAssertThrowsError(try run("read -r request; read -r next", startup: 0.1)) { error in
            XCTAssertTrue(error.localizedDescription.contains("timed out during initialize"))
        }
    }

    func testQuotaTimeoutIdentifiesStage() {
        XCTAssertThrowsError(try run(#"""
        read -r request
        printf '%s\n' '{"id":1,"result":{}}'
        read -r notification
        read -r request
        read -r next
        """#, quota: 0.1)) { error in
            XCTAssertTrue(error.localizedDescription.contains("timed out during account/rateLimits/read"))
        }
    }

    func testQuotaDeadlineStartsAfterInitialization() throws {
        let responses = try run(#"""
        read -r request
        sleep 0.2
        printf '%s\n' '{"id":1,"result":{}}'
        read -r notification
        read -r request
        sleep 0.1
        printf '%s\n' '{"id":2,"result":{}}'
        """#, quota: 0.25)
        XCTAssertEqual(responses.count, 2)
    }
}
