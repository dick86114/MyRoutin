import XCTest
@testable import RoutinUsage

@MainActor
final class CredentialOrderingControllerTests: XCTestCase {
    func test删除凭证成功时同步清理独立顺序() throws {
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

        let outcome = try controller.delete(id)

        XCTAssertEqual(outcome, .deleted)
        XCTAssertFalse(settings.displayOrder.menuBarCredentialIDs.contains(id))
        XCTAssertFalse(settings.displayOrder.popoverCredentialIDs.contains(id))
        XCTAssertEqual(deletedIDs, [id])
    }

    func test删除缓存失败时仍清理顺序并返回专门结果() throws {
        let suiteName = "credential-order-controller.cache-failure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = LocalKeyStore(defaults: defaults)
        let repository = KeyRepository(defaults: defaults, localStore: keychain)
        let key = try repository.add(name: "缓存失败", secret: "plan-cache-failure-0001")
        let settings = AppSettings(defaults: defaults)
        settings.displayOrder.menuBarCredentialIDs = [key.id]
        settings.displayOrder.popoverCredentialIDs = [key.id]
        let store = UsageStore(
            keyRepository: repository,
            localStore: keychain,
            apiClient: ScriptedUsageFetcher(responses: [:]),
            cache: DeleteFailingUsageCache(),
            alertEvaluator: AlertEvaluator(defaults: defaults),
            notificationSender: NotificationSenderFake(),
            defaults: defaults
        )
        let codexRepository = CodexGroupDetectionRepository(defaults: defaults)
        try codexRepository.save(Self.makeDetectionRecord(keyID: key.id))
        let codexDetection = CodexGroupDetectionService(
            webSession: NoopRoutinGroupDetectionWebSession(),
            probeClient: NoopCodexGroupProbeClient(),
            repository: codexRepository
        )
        let environment = AppEnvironment(
            settings: settings,
            store: store,
            refreshScheduler: RefreshScheduler(),
            loginItemManager: LoginItemManager(),
            keyRepository: repository,
            apiClient: ScriptedUsageFetcher(responses: [:]),
            notificationSender: NotificationSenderFake(),
            codexGroupDetection: codexDetection
        )
        let controller = CredentialOrderingController(
            settings: settings,
            addCredential: { _ in
                CredentialAddOutcome(saveResult: .saved, addedCredentialID: nil)
            },
            setKeyEnabled: { _, _ in },
            delete: { try environment.deleteKey($0) }
        )

        let outcome = try controller.delete(key.id)

        XCTAssertEqual(outcome, .cacheCleanupFailed)
        XCTAssertNil(store.state(for: key.id))
        XCTAssertNil(codexDetection.record(for: key.id))
        XCTAssertFalse(settings.displayOrder.menuBarCredentialIDs.contains(key.id))
        XCTAssertFalse(settings.displayOrder.popoverCredentialIDs.contains(key.id))
    }

    private static func makeDetectionRecord(keyID: UUID) -> CodexGroupDetectionRecord {
        CodexGroupDetectionRecord(
            keyID: keyID,
            accountFingerprint: "fingerprint",
            accountDisplayName: "测试账号",
            groupName: "测试分组",
            detectedAt: Date(timeIntervalSince1970: 10_000)
        )
    }
}

private actor NoopRoutinGroupDetectionWebSession: RoutinGroupDetectionWebSessionManaging {
    func hasAuthenticatedSession() async -> Bool { false }
    func prepareLogin() async {}
    func readCurrentAccountIdentity() async throws -> RoutinAccountIdentity {
        throw RoutinGroupDetectionWebError.accountUnavailable
    }
    func findGroupName(marker _: CodexGroupProbeRequestMarker) async throws -> String {
        throw RoutinGroupDetectionWebError.pageChanged
    }
}

private actor NoopCodexGroupProbeClient: CodexGroupProbing {
    func probe(apiKey _: String, marker _: CodexGroupProbeRequestMarker) async throws {
        throw CodexGroupProbeError.network
    }
}
