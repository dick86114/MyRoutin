import AppKit
import XCTest
@testable import RoutinUsage

final class SettingsComponentTests: XCTestCase {
    func test菜单栏预览复用真实图标渲染器() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "Components", "MenuBarIndicatorPreview.swift"
        ])

        XCTAssertTrue(source.contains("MenuBarIndicatorModel.make("))
        XCTAssertTrue(source.contains("MenuBarMultiUsageIcon.image("))
    }

    func test排序控件使用本地拖拽手势() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "Components", "ReorderableCredentialCardList.swift"
        ])

        XCTAssertTrue(source.contains("struct ReorderableCredentialCardList"))
        XCTAssertTrue(source.contains("DragGesture(minimumDistance: 5"))
        XCTAssertTrue(source.contains("interactiveSpring"))
    }
}
