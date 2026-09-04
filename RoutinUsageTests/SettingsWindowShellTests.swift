import XCTest

final class SettingsWindowShellTests: XCTestCase {
    func test新设置窗口包含五个现代导航分类() throws {
        let shell = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "SettingsWindowView.swift"
        ])
        let credentialPage = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "CredentialManagementView.swift"
        ])

        XCTAssertTrue(shell.contains("enum SettingsSection"))
        XCTAssertTrue(shell.contains("case credentials"))
        XCTAssertTrue(shell.contains("case menuBar"))
        XCTAssertTrue(shell.contains("case popover"))
        XCTAssertTrue(shell.contains("case general"))
        XCTAssertTrue(shell.contains("case help"))
        XCTAssertTrue(shell.contains("liquidGlassWindowBackground()"))
        XCTAssertTrue(credentialPage.contains("SettingsPageHeader"))
        XCTAssertFalse(shell.contains("Routin 签到"))
    }
}
