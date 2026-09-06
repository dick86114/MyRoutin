import XCTest
@testable import RoutinUsage

final class UsagePopoverLayoutTests: XCTestCase {
    func test弹窗定位优先跟随状态按钮所在屏幕() {
        let origin = PopoverWindowPlacement.origin(
            popoverSize: NSSize(width: 240, height: 180),
            anchorRect: NSRect(x: 150, y: 940, width: 30, height: 24),
            visibleFrame: NSRect(x: 0, y: 0, width: 800, height: 920)
        )

        XCTAssertEqual(origin.x, 45, accuracy: 0.01)
        XCTAssertEqual(origin.y, 740, accuracy: 0.01)
    }

    func test弹窗定位超出当前屏幕时保持可见() {
        let origin = PopoverWindowPlacement.origin(
            popoverSize: NSSize(width: 240, height: 180),
            anchorRect: NSRect(x: 790, y: 940, width: 30, height: 24),
            visibleFrame: NSRect(x: 0, y: 0, width: 800, height: 920)
        )

        XCTAssertEqual(origin.x, 560, accuracy: 0.01)
        XCTAssertEqual(origin.y, 740, accuracy: 0.01)
    }

    func test弹窗按内容展示并在超过屏幕时滚动() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage",
            "Views",
            "UsagePopoverView.swift"
        ])

        XCTAssertTrue(source.contains("ScrollView(.vertical, showsIndicators: false)"))
        XCTAssertTrue(source.contains("ThinVerticalScrollIndicator"))
        XCTAssertTrue(source.contains(".frame(width: 440)"))
        XCTAssertTrue(source.contains(".frame(maxHeight: maxPopoverHeight)"))
        XCTAssertTrue(source.contains("visibleHeight * 0.9"))

        let controller = try TestSourceReader.read([
            "RoutinUsage",
            "App",
            "StatusBarController.swift"
        ])
        XCTAssertTrue(controller.contains("popover.contentSize = contentSize"))
        XCTAssertTrue(controller.contains("window.setContentSize(contentSize)"))
        XCTAssertTrue(controller.contains("screenHeight * 0.9"))
        XCTAssertTrue(controller.contains("view.fittingSize"))
        XCTAssertTrue(controller.contains("min(max(idealSize.height, 1), maximumHeight)"))
    }

    func test弹窗设置按钮复用右键菜单激活逻辑() throws {
        let popover = try TestSourceReader.read([
            "RoutinUsage",
            "Views",
            "UsagePopoverView.swift"
        ])
        let controller = try TestSourceReader.read([
            "RoutinUsage",
            "App",
            "StatusBarController.swift"
        ])

        XCTAssertTrue(popover.contains("openSettings()"))
        XCTAssertTrue(popover.contains("let openSettings: @MainActor () -> Void"))
        XCTAssertTrue(controller.contains("openSettings: { [weak self] in"))
        XCTAssertTrue(controller.contains("self?.openSettingsWindow()"))
    }
}
