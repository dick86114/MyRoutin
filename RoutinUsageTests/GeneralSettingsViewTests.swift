import XCTest

final class GeneralSettingsViewTests: XCTestCase {
    func test通用页只保留刷新启动和通知总开关() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "GeneralSettingsView.swift"
        ])

        XCTAssertTrue(source.contains("刷新"))
        XCTAssertTrue(source.contains("登录时启动"))
        XCTAssertTrue(source.contains("notificationsEnabled"))
        XCTAssertTrue(source.contains("settingSection"))
        XCTAssertTrue(source.contains(".liquidGlassSurface(cornerRadius: 16)"))
        XCTAssertFalse(source.contains("Form {"))
        XCTAssertFalse(source.contains(".formStyle(.grouped)"))
        XCTAssertFalse(source.contains("displayDimension"))
        XCTAssertFalse(source.contains("thresholds"))
    }
}
