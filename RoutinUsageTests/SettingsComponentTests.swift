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
        XCTAssertTrue(source.contains("let dimension: DisplayDimension"))
        XCTAssertTrue(source.contains("static func =="))
        XCTAssertFalse(source.contains("@Bindable var environment"))
    }

    func test排序控件使用本地拖拽手势() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "Components", "ReorderableCredentialCardList.swift"
        ])

        XCTAssertTrue(source.contains("struct ReorderableCredentialCardList"))
        XCTAssertTrue(source.contains("DragGesture(minimumDistance: 5"))
        XCTAssertTrue(source.contains("interactiveSpring"))
        XCTAssertTrue(source.contains("let move: (ID, Int) -> Bool"))
        XCTAssertTrue(source.contains("@State private var workingIDs"))
        XCTAssertTrue(source.contains("commitMove"))
        XCTAssertTrue(source.contains(".coordinateSpace(name: reorderableCardCoordinateSpace)"))
        XCTAssertTrue(source.contains("DragGesture(minimumDistance: 5, coordinateSpace: .named(reorderableCardCoordinateSpace))"))
        XCTAssertTrue(source.contains(".transaction { transaction in"))
        XCTAssertTrue(source.contains("transaction.animation = nil"))
        XCTAssertFalse(source.contains("CardFramePreferenceKey"))
        XCTAssertFalse(source.contains("onPreferenceChange"))
    }
}
