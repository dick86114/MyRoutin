import XCTest

final class CredentialDetailsViewTests: XCTestCase {
    func testRoutin详情显示套餐订阅和模型信息() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage",
            "Views",
            "Settings",
            "CredentialDetailsView.swift"
        ])

        XCTAssertTrue(source.contains("套餐状态"))
        XCTAssertTrue(source.contains("订阅与周期"))
        XCTAssertTrue(source.contains("账户与模型"))
        XCTAssertTrue(source.contains("5 小时结束"))
        XCTAssertTrue(source.contains("分组倍率"))
        XCTAssertTrue(source.contains("allowedModels"))
        XCTAssertTrue(source.contains("subscriptionStatus(snapshot.status)"))
        XCTAssertTrue(source.contains("关闭凭证详情"))
        XCTAssertTrue(source.contains("var onClose: (() -> Void)? = nil"))
        XCTAssertTrue(source.contains("case \"planType\": \"计划类型\""))
        XCTAssertTrue(source.contains("case \"websiteURL\": \"官网地址\""))
        XCTAssertTrue(source.contains("detailLinkRow(metadataLabel(for: key), url)"))
    }
}
