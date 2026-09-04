import XCTest

final class MenuBarOrderingViewTests: XCTestCase {
    func test菜单栏页包含模拟条展示区待选区和上限提示() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "MenuBarOrderingView.swift"
        ])

        XCTAssertTrue(source.contains("MenuBarIndicatorPreview"))
        XCTAssertTrue(source.contains("展示区"))
        XCTAssertTrue(source.contains("待选区"))
        XCTAssertTrue(source.contains("maximumMenuBarCount"))
        XCTAssertTrue(source.contains("addingToMenuBar"))
        XCTAssertTrue(source.contains("removingFromMenuBar"))
        XCTAssertTrue(source.contains("UTType.text"))
        XCTAssertTrue(source.contains(".onDrag"))
        XCTAssertFalse(source.contains("chevron.up"))
        XCTAssertFalse(source.contains("chevron.down"))
        XCTAssertFalse(source.contains("moveUp"))
        XCTAssertFalse(source.contains("moveDown"))
    }
}
