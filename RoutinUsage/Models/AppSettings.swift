import Foundation
import Observation

@Observable
final class AppSettings {
    static let allowedRefreshMinutes = [1, 5, 15, 30]

    @ObservationIgnored private let defaults: UserDefaults

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

        if let data = defaults.data(forKey: Self.displayOrderKey),
           let decoded = try? JSONDecoder().decode(CredentialDisplayOrder.self, from: data) {
            displayOrder = decoded
        } else {
            displayOrder = CredentialDisplayOrder()
        }
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
        static let selectedCredentialIDs = "selectedCredentialIDs"
        static let availableCredentialIDs = "availableCredentialIDs"
    }

    static let displayOrderKey = "displayOrder.v1"

    func persistDisplayOrder() {
        if let data = try? JSONEncoder().encode(displayOrder) {
            defaults.set(data, forKey: Self.displayOrderKey)
        }
    }
}
