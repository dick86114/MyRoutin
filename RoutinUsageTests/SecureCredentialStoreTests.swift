import Foundation
import XCTest
@testable import RoutinUsage

final class SecureCredentialStoreTests: XCTestCase {
    func testSecureCredentialStore保存读取删除凭证() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let id = UUID()
        let secret = "secure-contract-secret"

        let store: any CredentialStoring = context.store
        try store.save(secret, for: id)
        XCTAssertTrue(try store.read(for: id) == secret)

        try store.delete(for: id)
        XCTAssertNil(try store.read(for: id))
    }

    func testSecureCredentialStore读取不存在的ID为空() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let store: any CredentialStoring = context.store
        XCTAssertNil(try store.read(for: UUID()))
    }

    func testSecureCredentialStore覆盖已有凭证() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let id = UUID()
        let store: any CredentialStoring = context.store

        try store.save("secure-contract-old", for: id)
        try store.save("secure-contract-new", for: id)

        XCTAssertTrue(try store.read(for: id) == "secure-contract-new")
    }

    func testKeychainSecretStore执行安全存储契约() throws {
        let id = UUID()
        let store: any SecureCredentialStoring = KeychainSecretStore(
            service: "ai.routin.usage-monitor.tests.\(UUID().uuidString)"
        )
        defer { try? store.delete(for: id) }

        try store.save("keychain-contract-secret", for: id)
        XCTAssertTrue(try store.read(for: id) == "keychain-contract-secret")

        try store.delete(for: id)
        XCTAssertNil(try store.read(for: id))
    }

    private struct TestContext {
        let suiteName: String
        let store: LocalKeyStore
        let defaults: UserDefaults

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeContext() throws -> TestContext {
        let suiteName = "ai.routin.usage-monitor.secure-credential-store-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return TestContext(
            suiteName: suiteName,
            store: LocalKeyStore(defaults: defaults),
            defaults: defaults
        )
    }
}
