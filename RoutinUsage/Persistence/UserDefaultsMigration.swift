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
        for sourceDomain in sources where sourceDomain != currentDomain {
            let markerKey = "didMigratePreferencesFrom.\(sourceDomain)"
            guard !standard.bool(forKey: markerKey) else {
                continue
            }

            let sourceValues = sourceProvider(sourceDomain)?
                .persistentDomain(forName: sourceDomain) ?? [:]
            var currentValues = standard.persistentDomain(forName: currentDomain) ?? [:]

            for (key, value) in sourceValues where currentValues[key] == nil {
                currentValues[key] = value
            }
            currentValues[markerKey] = true
            standard.setPersistentDomain(currentValues, forName: currentDomain)
        }
    }

    private static func compatibilitySources(for currentDomain: String) -> [String] {
        guard let currentIndex = bundleIdentifierChain.firstIndex(of: currentDomain) else {
            return []
        }
        return Array(bundleIdentifierChain[..<currentIndex])
    }
}
