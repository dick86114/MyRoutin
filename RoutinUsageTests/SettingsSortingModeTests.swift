import XCTest

enum TestSourceReader {
    static func read(_ pathComponents: [String]) throws -> String {
        let fileName = pathComponents.last!
        if let bundledURL = Bundle(for: SettingsSortingModeTests.self)
            .url(forResource: fileName, withExtension: "txt") {
            return try String(contentsOf: bundledURL, encoding: .utf8)
        }

        var url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for pathComponent in pathComponents {
            url.appendPathComponent(pathComponent)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

final class SettingsSortingModeTests: XCTestCase {
    func test排序仅在显示与刷新页的菜单栏指标中启用() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage",
            "Views",
            "SettingsView.swift"
        ])

        XCTAssertTrue(source.contains("MenuBarIndicatorCardDropDelegate"))
        XCTAssertTrue(source.contains("MenuBarIndicatorCardDragControl"))
        XCTAssertTrue(source.contains(".onDrag"))
        XCTAssertTrue(source.contains("DropDelegate"))
        XCTAssertTrue(source.contains("draggingIndicatorID"))
        XCTAssertTrue(source.contains("withAnimation(.spring(response: 0.32, dampingFraction: 0.82)"))
        XCTAssertTrue(source.contains("scaleEffect(draggingIndicatorID == configuration.id ? 1.02 : 1)"))
        XCTAssertTrue(source.contains("shadow(color: .black.opacity(draggingIndicatorID == configuration.id ? 0.18 : 0)"))
        XCTAssertFalse(source.contains(".onMove(perform: settings.moveSelectedCredential)"))
        XCTAssertFalse(source.contains("chevron.up"))
        XCTAssertFalse(source.contains("chevron.down"))
        XCTAssertFalse(source.contains("private struct CredentialSortInteraction"))
        XCTAssertFalse(source.contains("兼容选项"))
        XCTAssertFalse(source.contains("额度通知"))
    }

    func test卡片拖拽保持原始拖拽ID并避免目标卡片闪烁() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage",
            "Views",
            "SettingsView.swift"
        ])
        let delegateStart = try XCTUnwrap(source.range(of: "struct MenuBarIndicatorCardDropDelegate"))
        let delegateEnd = try XCTUnwrap(source.range(of: "struct MenuBarIndicatorCardDragControl"))
        let delegate = String(source[delegateStart.lowerBound..<delegateEnd.lowerBound])
        let rowStart = try XCTUnwrap(source.range(of: "func menuBarIndicatorRow"))
        let availableStart = try XCTUnwrap(source.range(of: "func availableMenuBarIndicatorRow"))
        let row = String(source[rowStart.lowerBound..<availableStart.lowerBound])
        let availableStart2 = try XCTUnwrap(source.range(of: "func availableMenuBarIndicatorRow"))
        let providerStart = try XCTUnwrap(source.range(of: "func providerIdentity"))
        let availableRow = String(source[availableStart2.lowerBound..<providerStart.lowerBound])

        XCTAssertTrue(delegate.contains("move(draggedID, targetID)"))
        XCTAssertFalse(delegate.contains("self.draggedID = targetID"))
        XCTAssertFalse(row.contains(".onDrag {"))
        XCTAssertTrue(row.contains("scaleEffect(draggingIndicatorID == configuration.id ? 1.02 : 1)"))
        XCTAssertTrue(source.contains(".contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))"))
        XCTAssertTrue(source.contains("indicatorDragProvider("))
        XCTAssertTrue(availableRow.contains("scaleEffect(draggingIndicatorID == configuration.id ? 1.02 : 1)"))
    }

    func test可添加指标使用独立的菜单栏排序交互() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage",
            "Views",
            "SettingsView.swift"
        ])

        XCTAssertTrue(source.contains("@State private var isReorderingAvailableIndicators = false"))
        XCTAssertTrue(source.contains("toggleAvailableIndicatorReordering()"))
        XCTAssertTrue(source.contains("isActive: isReorderingAvailableIndicators && availableMenuBarConfigurations.count > 1"))
        XCTAssertFalse(source.contains("toggleAvailableIndicatorReordering() {\n        isReorderingAvailableIndicators.toggle()\n    }\n\n    func toggleMenuBarReordering()"))
    }
}
