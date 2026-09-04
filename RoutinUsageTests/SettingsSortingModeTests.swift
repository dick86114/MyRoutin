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
    func test菜单栏排序页使用共享凭证拖拽协议() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "MenuBarOrderingView.swift"
        ])

        XCTAssertTrue(source.contains("CredentialDropDelegate"))
        XCTAssertTrue(source.contains("UTType.credentialID"))
        XCTAssertFalse(source.contains("isReorderingMenuBarIndicators"))
        XCTAssertFalse(source.contains("isReorderingAvailableIndicators"))
    }
}
