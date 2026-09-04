import Foundation

enum UserDefaultsMigration {
    static let legacyBundleIdentifier = "ai.routin.usage-monitor"
    static let currentBundleIdentifier = "ai.routin.myroutin"
    static let debugBundleIdentifier = "ai.routin.mytoken.debug"
    static let debugV2BundleIdentifier = "ai.routin.mytoken.debug.v2"
    static let bundleIdentifierChain = [
        legacyBundleIdentifier,
        currentBundleIdentifier,
        debugBundleIdentifier,
        debugV2BundleIdentifier,
    ]

    static func migrateCompatiblePreferences(
        standard: UserDefaults = .standard,
        currentDomain: String = Bundle.main.bundleIdentifier ?? currentBundleIdentifier,
        sourceDomains: [String]? = nil,
        sourceProvider: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) }
    ) {
        let sources = sourceDomains ?? compatibilitySources(for: currentDomain)
        var currentValues = standard.persistentDomain(forName: currentDomain) ?? [:]
        var migratedKeys = Set<String>()
        var changed = false
        for sourceDomain in sources.reversed() where sourceDomain != currentDomain {
            let markerKey = "didMigratePreferencesFrom.\(sourceDomain)"
            guard currentValues[markerKey] == nil else {
                continue
            }

            let sourceValues = sourceProvider(sourceDomain)?
                .persistentDomain(forName: sourceDomain) ?? [:]
            for (key, value) in sourceValues where migratedKeys.insert(key).inserted {
                if currentValues[key] == nil {
                    currentValues[key] = value
                }
            }
            currentValues[markerKey] = true
            changed = true
        }

        if changed {
            for (key, value) in currentValues {
                standard.set(value, forKey: key)
            }
        }
    }

    private static func compatibilitySources(for currentDomain: String) -> [String] {
        guard let currentIndex = bundleIdentifierChain.firstIndex(of: currentDomain) else {
            return []
        }
        return Array(bundleIdentifierChain[..<currentIndex])
    }
}
