import AppKit
import XCTest
@testable import RoutinUsage

final class SettingsWindowShellTests: XCTestCase {
    func test新设置窗口包含四个现代导航分类() throws {
        let shell = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "SettingsWindowView.swift"
        ])
        let credentialPage = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "CredentialManagementView.swift"
        ])

        XCTAssertTrue(shell.contains("enum SettingsSection"))
        XCTAssertTrue(shell.contains("case credentials"))
        XCTAssertTrue(shell.contains("case menuBar"))
        XCTAssertTrue(shell.contains("case general"))
        XCTAssertTrue(shell.contains("case help"))
        XCTAssertTrue(shell.contains("liquidGlassWindowBackground()"))
        XCTAssertTrue(credentialPage.contains("SettingsPageHeader"))
        XCTAssertFalse(shell.contains("Routin 签到"))
    }

    @MainActor
    func test显示设置窗口时切换前台形态并激活应用() {
        var appliedPolicies: [NSApplication.ActivationPolicy] = []
        var activationCount = 0

        SettingsWindowActivationPolicy.apply(
            hasSettingsWindow: true,
            setActivationPolicy: { policy in
                appliedPolicies.append(policy)
                return true
            },
            activate: { activationCount += 1 }
        )

        XCTAssertEqual(appliedPolicies, [.regular])
        XCTAssertEqual(activationCount, 1)
    }

    @MainActor
    func test关闭设置窗口时恢复菜单栏形态且不强制激活() {
        var appliedPolicies: [NSApplication.ActivationPolicy] = []
        var activationCount = 0

        SettingsWindowActivationPolicy.apply(
            hasSettingsWindow: false,
            setActivationPolicy: { policy in
                appliedPolicies.append(policy)
                return true
            },
            activate: { activationCount += 1 }
        )

        XCTAssertEqual(appliedPolicies, [.accessory])
        XCTAssertEqual(activationCount, 0)
    }
}
