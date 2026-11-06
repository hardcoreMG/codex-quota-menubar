import XCTest
@testable import CodexQuotaBar

final class QuotaProviderDetectorTests: XCTestCase {
    func testApplicationRequiresAnInstalledExecutable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Grok Bot.app")
        XCTAssertFalse(QuotaProviderDetector.isApplicationInstalled(at: app))

        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info = ["CFBundleExecutable": "Grok Bot", "CFBundleIdentifier": "test.quota.grok",
                    "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        XCTAssertFalse(QuotaProviderDetector.isApplicationInstalled(at: app))

        let executable = macOS.appendingPathComponent("Grok Bot")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        XCTAssertTrue(QuotaProviderDetector.isApplicationInstalled(at: app))

        try FileManager.default.removeItem(at: executable)
        XCTAssertFalse(QuotaProviderDetector.isApplicationInstalled(at: app))
    }
}
