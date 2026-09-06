import XCTest
@testable import RoutinUsage

final class KeychainMigrationTests: XCTestCase {
    func test旧Routin密钥迁移成功后删除旧值() throws {
        let id = UUID()
        let old = TestSecretStore(values: [id: "plan-secret-1234"])
        let new = TestSecretStore()

        try KeychainMigration.migrate(
            ids: [id],
            from: old,
            to: new
        )

        XCTAssertNil(try old.read(for: id))
        XCTAssertEqual(try new.read(for: id), "plan-secret-1234")
    }

    func test新存储失败时保留旧值() {
        let id = UUID()
        let old = TestSecretStore(values: [id: "plan-secret-1234"])
        let new = TestSecretStore(failingOnSave: true)

        XCTAssertThrowsError(
            try KeychainMigration.migrate(ids: [id], from: old, to: new)
        )
        XCTAssertEqual(try? old.read(for: id), "plan-secret-1234")
        XCTAssertNil(try? new.read(for: id))
    }

    func test回迁到App存储成功后删除旧Keychain值() throws {
        let id = UUID()
        let keychain = TestSecretStore(values: [id: "sk-existing"])
        let app = TestSecretStore()

        try KeychainMigration.restore(ids: [id], from: keychain, to: app)

        XCTAssertEqual(try app.read(for: id), "sk-existing")
        XCTAssertNil(try keychain.read(for: id))
    }

    func testApp已有值时回迁保留双方值() throws {
        let id = UUID()
        let keychain = TestSecretStore(values: [id: "keychain-value"])
        let app = TestSecretStore(values: [id: "app-value"])

        try KeychainMigration.restore(ids: [id], from: keychain, to: app)

        XCTAssertEqual(try app.read(for: id), "app-value")
        XCTAssertEqual(try keychain.read(for: id), "keychain-value")
    }

    func test回迁保存失败时保留Keychain值且App无值() {
        let id = UUID()
        let keychain = TestSecretStore(values: [id: "keychain-value"])
        let app = TestSecretStore(failingOnSave: true)

        XCTAssertThrowsError(try KeychainMigration.restore(ids: [id], from: keychain, to: app))
        XCTAssertEqual(try? keychain.read(for: id), "keychain-value")
        XCTAssertNil(try? app.read(for: id))
    }

    func test回迁缺少ID时不改变任何存储() throws {
        let storedID = UUID()
        let missingID = UUID()
        let keychain = TestSecretStore(values: [storedID: "keychain-value"])
        let app = TestSecretStore(values: [storedID: "app-value"])

        try KeychainMigration.restore(ids: [missingID], from: keychain, to: app)

        XCTAssertEqual(try keychain.read(for: storedID), "keychain-value")
        XCTAssertEqual(try app.read(for: storedID), "app-value")
        XCTAssertNil(try keychain.read(for: missingID))
        XCTAssertNil(try app.read(for: missingID))
    }
}

private final class TestSecretStore: CredentialStoring, @unchecked Sendable {
    private var values: [UUID: String]
    private let failingOnSave: Bool

    init(values: [UUID: String] = [:], failingOnSave: Bool = false) {
        self.values = values
        self.failingOnSave = failingOnSave
    }

    func save(_ secret: String, for id: UUID) throws {
        if failingOnSave {
            throw TestSecretStoreError.saveFailed
        }
        values[id] = secret
    }

    func read(for id: UUID) throws -> String? { values[id] }

    func delete(for id: UUID) throws { values.removeValue(forKey: id) }
}

private enum TestSecretStoreError: Error {
    case saveFailed
}
