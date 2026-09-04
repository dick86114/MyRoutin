import XCTest

final class PopoverOrderingViewTests: XCTestCase {
    func test弹窗排序页只调用弹窗序列并显示基本信息() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "PopoverOrderingView.swift"
        ])

        XCTAssertTrue(source.contains("moving(.popover"))
        XCTAssertTrue(source.contains("visiblePopoverIDs"))
        XCTAssertTrue(source.contains("供应商"))
        XCTAssertTrue(source.contains("套餐"))
        XCTAssertTrue(source.contains("实时同步到菜单栏弹窗"))
        XCTAssertFalse(source.contains("addingToMenuBar"))
        XCTAssertFalse(source.contains("removingFromMenuBar"))
    }
}
