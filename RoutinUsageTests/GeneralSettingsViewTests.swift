import XCTest

final class GeneralSettingsViewTests: XCTestCase {
    func test通用页保留刷新启动显示和通知设置() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "GeneralSettingsView.swift"
        ])

        XCTAssertTrue(source.contains("刷新"))
        XCTAssertTrue(source.contains("登录时启动"))
        XCTAssertTrue(source.contains("displayDimension"))
        XCTAssertTrue(source.contains("notificationsEnabled"))
        XCTAssertTrue(source.contains("thresholds"))
    }
}
