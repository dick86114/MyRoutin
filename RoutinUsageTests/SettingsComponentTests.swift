import AppKit
import UniformTypeIdentifiers
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

    func test拖拽使用专属凭证类型() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "Components", "CredentialDropDelegate.swift"
        ])

        XCTAssertTrue(source.contains("static let credentialID"))
        XCTAssertTrue(source.contains("ai.routin.mytoken.credential"))
    }
}
