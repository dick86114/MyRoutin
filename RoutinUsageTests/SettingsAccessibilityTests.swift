import XCTest

final class SettingsAccessibilityTests: XCTestCase {
    func test设置页统一使用玻璃扩展并支持减少动态效果() throws {
        let files = [
            "SettingsWindowView",
            "CredentialManagementView",
            "MenuBarManagementView",
            "GeneralSettingsView",
            "HelpUpdateView"
        ]

        for file in files {
            let source = try TestSourceReader.read([
                "RoutinUsage", "Views", "Settings", "\(file).swift"
            ])
            XCTAssertFalse(
                source.contains("glassEffect("),
                "\(file) 必须通过 LiquidGlassSurface 使用玻璃效果"
            )
        }

        let ordering = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "MenuBarManagementView.swift"
        ])
        XCTAssertTrue(ordering.contains("accessibilityAction"))
        XCTAssertTrue(ordering.contains("accessibilityLabel"))
        XCTAssertTrue(ordering.contains("reduceMotion"))
    }
}
