import Foundation
import Observation

struct AlertThresholds: Equatable, Sendable {
    let low: Int
    let high: Int

    init(low: Int = 80, high: Int = 95) {
        precondition(Self.isValid(low: low, high: high), "通知阈值必须位于 1...100，且低阈值小于高阈值")
        self.low = low
        self.high = high
    }

    static func isValid(low: Int, high: Int) -> Bool {
        (1...100).contains(low) && (1...100).contains(high) && low < high
    }
}

enum UpdateChannel: String, Equatable, Sendable, CaseIterable {
    case direct
    case cdn
}

@Observable
final class AppSettings {
    static let allowedRefreshMinutes = [1, 5, 15, 30]
    static let cdnBases = ["https://ghfast.top", "https://gh-proxy.com", "https://ghproxy.net"]

    @ObservationIgnored private let defaults: UserDefaults
    private var credentialUsagePreferences: [String: CredentialUsagePreferences]
    @ObservationIgnored private var migratedUsagePreferenceIDs: Set<String>

    var refreshMinutes: Int {
        didSet {
            guard Self.allowedRefreshMinutes.contains(refreshMinutes) else {
                refreshMinutes = oldValue
                return
            }
            defaults.set(refreshMinutes, forKey: Keys.refreshMinutes)
        }
    }

    var displayDimension: DisplayDimension {
        didSet {
            defaults.set(displayDimension.rawValue, forKey: Keys.displayDimension)
        }
    }

    var displayOrder: CredentialDisplayOrder {
        didSet {
            persistDisplayOrder()
        }
    }

    var menuBarStyle: MenuBarStyle {
        didSet {
            defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle)
        }
    }

    var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }

    var thresholds: AlertThresholds {
        didSet {
            defaults.set(thresholds.low, forKey: Keys.lowThreshold)
            defaults.set(thresholds.high, forKey: Keys.highThreshold)
        }
    }

    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    var updateChannel: UpdateChannel {
        didSet {
            guard updateChannel != oldValue || defaults.string(forKey: Keys.updateChannel) != updateChannel.rawValue else {
                return
            }
            defaults.set(updateChannel.rawValue, forKey: Keys.updateChannel)
            if updateChannel == .cdn, updateCDNBase.isEmpty {
                updateCDNBase = Self.cdnBases[0]
            }
            syncUpdateMirrorBase()
        }
    }

    var updateCDNBase: String {
        didSet {
            let trimmed = updateCDNBase
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            defaults.set(trimmed, forKey: Keys.updateCDNBase)
            if trimmed != updateCDNBase {
                updateCDNBase = trimmed
            }
            syncUpdateMirrorBase()
        }
    }

    /// nil = 直连 GitHub；非空 = 走该镜像前缀下载和检测。
    var updateMirrorBase: String? {
        updateChannel == .cdn && !updateCDNBase.isEmpty ? updateCDNBase : nil
    }

    private func syncUpdateMirrorBase() {
        if let mirror = updateMirrorBase {
            defaults.set(mirror, forKey: "updateMirrorBase")
        } else {
            defaults.removeObject(forKey: "updateMirrorBase")
        }
    }

    var hasPersistedDisplayOrder: Bool {
        defaults.data(forKey: Self.displayOrderKey) != nil
    }

    func importLegacyDisplayOrder(allIDs: [UUID]) {
        guard !hasPersistedDisplayOrder else { return }
        let selected = (defaults.stringArray(forKey: Keys.selectedCredentialIDs) ?? [])
            .compactMap(UUID.init(uuidString:))
        let available = (defaults.stringArray(forKey: Keys.availableCredentialIDs) ?? [])
            .compactMap(UUID.init(uuidString:))
        displayOrder = CredentialDisplayOrder.migrated(
            selected: selected,
            available: available,
            allIDs: allIDs
        )
    }

    func appendCredential(_ id: UUID) {
        var order = displayOrder
        order.popoverCredentialIDs.append(id)
        displayOrder = order
    }

    func removeCredential(_ id: UUID) {
        displayOrder = displayOrder.removingCredential(id)
    }

    func usagePreferences(for id: UUID) -> CredentialUsagePreferences {
        credentialUsagePreferences[id.uuidString] ?? .defaultValue
    }

    func storedUsagePreferences(for id: UUID) -> CredentialUsagePreferences? {
        credentialUsagePreferences[id.uuidString]
    }

    func setUsagePreferences(_ preferences: CredentialUsagePreferences, for id: UUID) {
        credentialUsagePreferences[id.uuidString] = preferences
        persistCredentialUsagePreferences()
    }

    func removeUsagePreferences(for id: UUID) {
        credentialUsagePreferences.removeValue(forKey: id.uuidString)
        persistCredentialUsagePreferences()
    }

    func migrateUsagePreferencesIfNeeded(
        for configuration: KeyConfiguration,
        metrics: [NormalizedUsageMetric],
        capabilities: [UsageMetricCapability]
    ) {
        let id = configuration.id
        guard storedUsagePreferences(for: id) == nil,
              !migratedUsagePreferenceIDs.contains(id.uuidString)
        else { return }

        var preferences = CredentialUsagePreferences.defaultValue
        preferences.menuBarMetricID = legacyMenuBarMetricID(
            for: displayDimension,
            metrics: metrics,
            capabilities: capabilities
        )
        preferences = MetricAlertRuleResolver.reconcile(
            existing: preferences,
            metrics: metrics,
            capabilities: capabilities,
            legacyThresholds: thresholds
        )
        setUsagePreferences(preferences, for: id)

        migratedUsagePreferenceIDs.insert(id.uuidString)
        persistMigratedUsagePreferenceIDs()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedRefreshMinutes = defaults.object(forKey: Keys.refreshMinutes) as? Int
        if let storedRefreshMinutes,
           Self.allowedRefreshMinutes.contains(storedRefreshMinutes) {
            refreshMinutes = storedRefreshMinutes
        } else {
            refreshMinutes = 5
        }

        let storedDimension = defaults.string(forKey: Keys.displayDimension)
            .flatMap(DisplayDimension.init(rawValue:))
        displayDimension = storedDimension ?? .fiveHour

        let storedMenuBarStyle = defaults.string(forKey: Keys.menuBarStyle)
            .flatMap(MenuBarStyle.init(rawValue:))
        menuBarStyle = storedMenuBarStyle ?? .aliasLogoProgress

        if defaults.object(forKey: Keys.notificationsEnabled) == nil {
            notificationsEnabled = true
        } else {
            notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        }

        let low = defaults.object(forKey: Keys.lowThreshold) as? Int
        let high = defaults.object(forKey: Keys.highThreshold) as? Int
        if let low, let high, AlertThresholds.isValid(low: low, high: high) {
            thresholds = AlertThresholds(low: low, high: high)
        } else {
            thresholds = AlertThresholds()
        }

        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

        updateChannel = defaults.string(forKey: Keys.updateChannel)
            .flatMap(UpdateChannel.init(rawValue:)) ?? .direct
        updateCDNBase = defaults.string(forKey: Keys.updateCDNBase) ?? Self.cdnBases[0]

        if let data = defaults.data(forKey: Self.displayOrderKey),
           let decoded = try? JSONDecoder().decode(CredentialDisplayOrder.self, from: data) {
            displayOrder = decoded
        } else {
            displayOrder = CredentialDisplayOrder()
        }

        if let data = defaults.data(forKey: Self.credentialUsagePreferencesKey),
           let decoded = try? JSONDecoder().decode(
               [String: CredentialUsagePreferences].self,
               from: data
           ) {
            credentialUsagePreferences = decoded
        } else {
            credentialUsagePreferences = [:]
        }

        let storedMigratedIDs = defaults.stringArray(forKey: Self.migratedUsagePreferenceIDsKey) ?? []
        migratedUsagePreferenceIDs = Set(storedMigratedIDs)
        syncUpdateMirrorBase()
    }
}

private extension AppSettings {
    enum Keys {
        static let refreshMinutes = "refreshMinutes"
        static let displayDimension = "displayDimension"
        static let menuBarStyle = "menuBarStyle"
        static let notificationsEnabled = "notificationsEnabled"
        static let lowThreshold = "notificationLowThreshold"
        static let highThreshold = "notificationHighThreshold"
        static let launchAtLogin = "launchAtLogin"
        static let updateChannel = "updateChannel"
        static let updateCDNBase = "updateCDNBase"
        static let selectedCredentialIDs = "selectedCredentialIDs"
        static let availableCredentialIDs = "availableCredentialIDs"
    }

    static let displayOrderKey = "displayOrder.v1"
    static let credentialUsagePreferencesKey = "credentialUsagePreferences.v1"
    static let migratedUsagePreferenceIDsKey = "credentialUsagePreferencesMigratedCredentialIDs.v1"

    func persistDisplayOrder() {
        if let data = try? JSONEncoder().encode(displayOrder) {
            defaults.set(data, forKey: Self.displayOrderKey)
        }
    }

    func persistCredentialUsagePreferences() {
        if let data = try? JSONEncoder().encode(credentialUsagePreferences) {
            defaults.set(data, forKey: Self.credentialUsagePreferencesKey)
        }
    }

    private func legacyMenuBarMetricID(
        for dimension: DisplayDimension,
        metrics: [NormalizedUsageMetric],
        capabilities: [UsageMetricCapability]
    ) -> String? {
        let acceptedIDs = Set(metrics.map(\.id) + capabilities.map(\.metricID))
        let primaryID = dimension == .fiveHour ? "fiveHour" : "weekly"
        if acceptedIDs.contains(primaryID) {
            return primaryID
        }

        let alternateID = dimension == .fiveHour ? "five-hour" : "weekly"
        return acceptedIDs.contains(alternateID) ? alternateID : nil
    }

    private func persistMigratedUsagePreferenceIDs() {
        defaults.set(Array(migratedUsagePreferenceIDs), forKey: Self.migratedUsagePreferenceIDsKey)
    }
}
