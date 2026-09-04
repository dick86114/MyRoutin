import XCTest
@testable import RoutinUsage

@MainActor
final class CredentialOrderingControllerTests: XCTestCase {
    func test删除凭证时同步清理独立顺序() throws {
        let suiteName = "credential-order-controller.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        var deletedIDs: [UUID] = []
        let id = UUID()
        settings.appendCredential(id)
        settings.displayOrder.menuBarCredentialIDs = [id]
        let controller = CredentialOrderingController(
            settings: settings,
            addCredential: { _ in
                CredentialAddOutcome(saveResult: .saved, addedCredentialID: nil)
            },
            setKeyEnabled: { _, _ in },
            delete: { id in
                deletedIDs.append(id)
            }
        )

        try controller.delete(id)

        XCTAssertFalse(settings.displayOrder.menuBarCredentialIDs.contains(id))
        XCTAssertFalse(settings.displayOrder.popoverCredentialIDs.contains(id))
        XCTAssertEqual(deletedIDs, [id])
    }
}
