import XCTest

final class StatusBarVisibilityTests: XCTestCase {
    func test状态栏控制器由应用级强引用并显式保持状态项可见() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage",
            "App",
            "RoutinUsageApp.swift"
        ])
        let controller = try TestSourceReader.read([
            "RoutinUsage",
            "App",
            "StatusBarController.swift"
        ])

        XCTAssertTrue(source.contains("retainedStatusBarController"))
        XCTAssertTrue(controller.contains("statusItem.isVisible = true"))
        XCTAssertFalse(controller.contains("autosaveName"))
        XCTAssertTrue(controller.contains("statusItem.length = imageWidth + 8"))
    }
}
