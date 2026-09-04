import XCTest
@testable import RoutinUsage

final class UserDefaultsMigrationTests: XCTestCase {
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

        XCTAssertEqual(current.string(forKey: "keyConfigurations"), "oldest")
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
