import XCTest
@testable import RoutinUsage

final class UserDefaultsMigrationTests: XCTestCase {
    func test新正式身份只从旧正式身份迁移而不读取调试数据() {
        XCTAssertEqual(UserDefaultsMigration.currentBundleIdentifier, "cc.idickies.mytoken")
        XCTAssertEqual(
            UserDefaultsMigration.compatibilitySources(for: "cc.idickies.mytoken"),
            ["ai.routin.usage-monitor", "ai.routin.myroutin"]
        )
    }

    func test迁移保留凭证但不复制系统显示状态且不会重复导入() throws {
        let targetName = "migration-target-\(UUID().uuidString)"
        let sourceName = "migration-source-\(UUID().uuidString)"
        let target = try XCTUnwrap(UserDefaults(suiteName: targetName))
        let source = try XCTUnwrap(UserDefaults(suiteName: sourceName))
        defer {
            target.removePersistentDomain(forName: targetName)
            source.removePersistentDomain(forName: sourceName)
        }
        let stateKeys = [
            "NSStatusItem Preferred Position Item-0",
            "NSStatusItem VisibleCC ai.routin.myroutin",
            "NSWindow Frame settings",
            "NSSplitView Subview Frames settings",
        ]
        source.set("测试凭证", forKey: "planKey.test")
        source.set(Data([1, 2, 3]), forKey: "keyConfigurations")
        for key in stateKeys { source.set(false, forKey: key) }
        UserDefaultsMigration.migrateCompatiblePreferences(
            standard: target, currentDomain: targetName, sourceDomains: [sourceName]
        )
        XCTAssertEqual(target.string(forKey: "planKey.test"), "测试凭证")
        XCTAssertEqual(target.data(forKey: "keyConfigurations"), Data([1, 2, 3]))
        for key in stateKeys { XCTAssertNil(target.object(forKey: key)) }
        target.removeObject(forKey: "planKey.test")
        UserDefaultsMigration.migrateCompatiblePreferences(
            standard: target, currentDomain: targetName, sourceDomains: [sourceName]
        )
        XCTAssertNil(target.object(forKey: "planKey.test"))
        XCTAssertEqual(source.string(forKey: "planKey.test"), "测试凭证")
    }

    func test兼容链偏好只补齐当前身份缺失的键() throws {
        let currentSuite = "migration-current-\(UUID().uuidString)"
        let sourceSuites = (0..<3).map { _ in "migration-source-\(UUID().uuidString)" }
        let current = try XCTUnwrap(UserDefaults(suiteName: currentSuite))
        let sources = try sourceSuites.map { suite in
            try XCTUnwrap(UserDefaults(suiteName: suite))
        }
        defer {
            current.removePersistentDomain(forName: currentSuite)
            for suite in sourceSuites {
                UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            }
        }

        sources[0].setPersistentDomain(
            ["keyConfigurations": "oldest", "shared": "source-zero"],
            forName: sourceSuites[0]
        )
        sources[1].setPersistentDomain(
            ["keyConfigurations": "newer", "shared": "source-one"],
            forName: sourceSuites[1]
        )
        sources[2].setPersistentDomain(
            ["shared": "source-two"],
            forName: sourceSuites[2]
        )
        current.setPersistentDomain(["shared": "already-set"], forName: currentSuite)

        UserDefaultsMigration.migrateCompatiblePreferences(
            standard: current,
            currentDomain: currentSuite,
            sourceDomains: sourceSuites
        )

        XCTAssertEqual(current.string(forKey: "keyConfigurations"), "newer")
        XCTAssertEqual(current.string(forKey: "shared"), "already-set")
        XCTAssertEqual(
            current.bool(forKey: "didMigratePreferencesFrom.\(sourceSuites[0])"),
            true
        )
        XCTAssertEqual(
            current.bool(forKey: "didMigratePreferencesFrom.\(sourceSuites[1])"),
            true
        )
        XCTAssertEqual(
            current.bool(forKey: "didMigratePreferencesFrom.\(sourceSuites[2])"),
            true
        )
    }

    func test未知身份默认不迁移兼容链数据() throws {
        let currentSuite = "migration-current-\(UUID().uuidString)"
        let current = try XCTUnwrap(UserDefaults(suiteName: currentSuite))
        defer {
            current.removePersistentDomain(forName: currentSuite)
        }

        UserDefaultsMigration.migrateCompatiblePreferences(
            standard: current,
            currentDomain: currentSuite
        )

        XCTAssertNil(current.persistentDomain(forName: currentSuite)?["keyConfigurations"])
    }
}
