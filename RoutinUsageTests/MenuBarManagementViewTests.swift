import XCTest

final class MenuBarManagementViewTests: XCTestCase {
    func test菜单栏管理页使用手势整卡排序和合并预览() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "MenuBarManagementView.swift"
        ])

        XCTAssertTrue(source.contains("MenuBarManagementView"))
        XCTAssertTrue(source.contains("ReorderableCredentialCardList"))
        XCTAssertTrue(source.contains("菜单栏管理"))
        XCTAssertTrue(source.contains("previewPanel(title: \"预览\""))
        XCTAssertFalse(source.contains("previewPanel(title: \"菜单栏预览\""))
        XCTAssertFalse(source.contains("previewPanel(title: \"弹窗预览\""))
        XCTAssertTrue(source.contains("HStack(alignment: .top, spacing: 20)"))
        XCTAssertTrue(source.contains("VStack(alignment: .leading, spacing: 16)"))
        XCTAssertTrue(source.contains(".frame(width: 440)"))
        XCTAssertTrue(source.contains(".frame(minWidth: 360, maxWidth: .infinity)"))
        XCTAssertTrue(source.contains("SystemPopoverArrow"))
        XCTAssertTrue(source.contains("PopoverColorBrandLogo"))
        XCTAssertTrue(source.contains("RoundedRectangle(cornerRadius: 10, style: .continuous)"))
        XCTAssertTrue(source.contains("strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)"))
        XCTAssertFalse(source.contains("arrowtriangle.up.fill"))
        XCTAssertFalse(source.contains(".padding(.trailing, 62)"))
        XCTAssertTrue(source.contains(".lineLimit(1)"))
        XCTAssertTrue(source.contains("ProviderTheme.background(for:"))
        XCTAssertFalse(source.contains("CredentialSummaryRow("))
        XCTAssertTrue(source.contains("movingDisplay"))
        XCTAssertTrue(source.contains("Menu {"))
        XCTAssertTrue(source.contains("菜单栏指标"))
        XCTAssertTrue(source.contains("MenuBarMetricResolver.options"))
        XCTAssertTrue(source.contains("setUsagePreferences"))
        XCTAssertTrue(source.contains("accessibilityLabel"))
        XCTAssertFalse(source.contains("unifiedStates.prefix(3)"))
        XCTAssertFalse(source.contains("onDrag"))
        XCTAssertFalse(source.contains("onDrop"))
        XCTAssertFalse(source.contains(".frame(height: 178)"))
    }
}
