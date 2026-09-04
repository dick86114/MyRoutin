import XCTest

final class CredentialManagementViewTests: XCTestCase {
    func test凭证管理页包含分组筛选搜索和危险删除确认() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "CredentialManagementView.swift"
        ])

        XCTAssertTrue(source.contains("struct CredentialFilter"))
        XCTAssertTrue(source.contains("ProviderID.allCases"))
        XCTAssertTrue(source.contains("searchText"))
        XCTAssertTrue(source.contains("confirmationDialog"))
        XCTAssertTrue(source.contains("将同时删除本地保存的密钥和用量缓存"))
        XCTAssertTrue(source.contains("CredentialSummaryRow"))
    }
}
