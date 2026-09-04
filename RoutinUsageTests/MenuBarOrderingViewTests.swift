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
        XCTAssertTrue(source.contains("UTType.credentialID"))
        XCTAssertTrue(source.contains("chevron.up"))
        XCTAssertTrue(source.contains("chevron.down"))
    }
}
