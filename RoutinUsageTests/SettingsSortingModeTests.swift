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
    func test菜单栏管理页使用手势整卡排序() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "MenuBarManagementView.swift"
        ])

        XCTAssertTrue(source.contains("ReorderableCredentialCardList"))
        XCTAssertTrue(source.contains("movingDisplay"))
        XCTAssertFalse(source.contains("isReorderingMenuBarIndicators"))
        XCTAssertFalse(source.contains("isReorderingAvailableIndicators"))
    }
}
