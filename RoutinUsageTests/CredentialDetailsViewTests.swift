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

    func test火山详情显示动态订阅信息且官网地址右对齐() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage",
            "Views",
            "Settings",
            "CredentialDetailsView.swift"
        ])

        XCTAssertTrue(source.contains("state.configuration.providerID == .volcengine"))
        XCTAssertTrue(source.contains("订阅与周期"))
        XCTAssertTrue(source.contains("subscriptionStartAt"))
        XCTAssertTrue(source.contains("subscriptionEndAt"))
        XCTAssertTrue(source.contains("statusText"))
        XCTAssertTrue(source.contains("billingMode"))
        XCTAssertTrue(source.contains("接口未返回"))
        XCTAssertTrue(source.contains("multilineTextAlignment(.trailing)"))
    }

    func testGLM和DeepSeek详情显示动态模型清单() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage",
            "Views",
            "Settings",
            "CredentialDetailsView.swift"
        ])

        XCTAssertTrue(source.contains("providerID == .glm || state.configuration.providerID == .deepseek"))
        XCTAssertTrue(source.contains("modelDetails"))
        XCTAssertTrue(source.contains("allowedModels"))
    }

    func test模型清单使用多色胶囊并支持点击复制() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage",
            "Views",
            "Settings",
            "CredentialDetailsView.swift"
        ])
        let chipSource = try TestSourceReader.read([
            "RoutinUsage",
            "Views",
            "Settings",
            "Components",
            "ModelIDChipFlow.swift"
        ])

        XCTAssertTrue(source.contains("ModelIDChipFlow(models:"))
        XCTAssertTrue(source.contains("copyModelID"))
        XCTAssertFalse(source.contains("allowedModels.joined(separator: \"、\")"))
        XCTAssertTrue(chipSource.contains("WrappingModelChips"))
        XCTAssertTrue(chipSource.contains("Capsule()"))
        XCTAssertTrue(chipSource.contains("NSPasteboard.general.setString(modelID, forType: .string)"))
        XCTAssertTrue(chipSource.contains("已复制模型 ID"))
        XCTAssertTrue(chipSource.contains("复制模型 ID"))
    }
}
