import XCTest

final class MenuBarManagementViewTests: XCTestCase {
    func test菜单栏管理页使用手势整卡排序和双预览() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "MenuBarManagementView.swift"
        ])

        XCTAssertTrue(source.contains("MenuBarManagementView"))
        XCTAssertTrue(source.contains("ReorderableCredentialCardList"))
        XCTAssertTrue(source.contains("菜单栏管理"))
        XCTAssertTrue(source.contains("菜单栏预览"))
        XCTAssertTrue(source.contains("弹窗预览"))
        XCTAssertTrue(source.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(source.contains("movingDisplay"))
        XCTAssertTrue(source.contains("accessibilityLabel"))
        XCTAssertFalse(source.contains("onDrag"))
        XCTAssertFalse(source.contains("onDrop"))
        XCTAssertFalse(source.contains(".frame(height: 178)"))
    }
}
