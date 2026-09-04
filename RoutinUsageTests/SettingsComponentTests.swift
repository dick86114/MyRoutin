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

    func test拖拽代理按移动语义处理投放() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "Components", "CredentialDropDelegate.swift"
        ])

        XCTAssertTrue(source.contains("struct CredentialDropDelegate: DropDelegate"))
        XCTAssertTrue(source.contains("DropProposal(operation: .move)"))
        XCTAssertTrue(source.contains("move(draggedID)"))
    }
}
