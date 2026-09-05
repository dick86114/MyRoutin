import Foundation
@preconcurrency import UserNotifications

enum AlertLevel: String, Codable, Equatable, Sendable {
    case low
    case high
}

struct UsageAlert: Equatable, Sendable {
    let keyID: UUID
    let keyName: String
    let providerName: String
    let metricID: String
    let metricLabel: String
    let valueSource: MetricAlertValueSource
    let currentValue: Decimal?
    let level: AlertLevel
    let percent: Double
    let windowEnd: Date?
    let balanceAmount: Decimal?
    let currencyCode: String?
    fileprivate let reservationID: UUID
    fileprivate let triggeredWindows: Set<AlertWindowKey>
    fileprivate let replacedReservationOwners: [AlertWindowKey: UUID]

    init(
        keyID: UUID,
        keyName: String,
        providerName: String,
        metricID: String,
        metricLabel: String,
        valueSource: MetricAlertValueSource,
        currentValue: Decimal?,
        level: AlertLevel,
        percent: Double,
        windowEnd: Date?,
        balanceAmount: Decimal?,
        currencyCode: String?,
        reservationID: UUID,
        triggeredWindows: Set<AlertWindowKey>,
        replacedReservationOwners: [AlertWindowKey: UUID]
    ) {
        self.keyID = keyID
        self.keyName = keyName
        self.providerName = providerName
        self.metricID = metricID
        self.metricLabel = metricLabel
        self.valueSource = valueSource
        self.currentValue = currentValue
        self.level = level
        self.percent = percent
        self.windowEnd = windowEnd
        self.balanceAmount = balanceAmount
        self.currencyCode = currencyCode
        self.reservationID = reservationID
        self.triggeredWindows = triggeredWindows
        self.replacedReservationOwners = replacedReservationOwners
    }

    var notificationTitle: String {
        "Routin 用量预警"
    }

    func notificationBody(timeZone: TimeZone = .autoupdatingCurrent) -> String {
        if let balanceAmount {
            let amount = NSDecimalNumber(decimal: balanceAmount).stringValue
            let currency = currencyCode.map { " \($0)" } ?? ""
            return "\(keyName) · 余额低于预警值，当前 \(amount)\(currency)"
        }
        let action: String
        switch valueSource {
        case .usedPercent:
            action = "用量已达"
        case .remainingPercent:
            action = "剩余低于"
        case .absoluteValue, .healthState:
            action = "状态异常"
        }
        let label: String
        switch metricLabel {
        case "周": label = "周用量"
        case "Token": label = "Token "
        default: label = metricLabel
        }
        let base = "\(keyName) · \(label)\(action) \(formattedPercent)%"
        guard let windowEnd, valueSource == .usedPercent || valueSource == .remainingPercent else {
            return base
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return "\(base)，窗口将在 \(formatter.string(from: windowEnd)) 重置"
    }

    private var formattedPercent: String {
        guard percent.isSafeNotificationPercent else {
            return "—"
        }
        let rounded = percent.rounded()
        if abs(percent - rounded) < 0.000_001 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), percent)
    }
}

struct AlertWindowKey: Codable, Hashable, Sendable {
    let keyID: UUID
    let metricID: String
    let ruleID: String
    let windowIdentifier: String
    let threshold: Int

    init(
        keyID: UUID,
        metricID: String,
        ruleID: String,
        windowIdentifier: String,
        threshold: Int
    ) {
        self.keyID = keyID
        self.metricID = metricID
        self.ruleID = ruleID
        self.windowIdentifier = windowIdentifier
        self.threshold = threshold
    }
}

private struct AlertPeriodicWindowWatermark: Codable, Hashable, Sendable {
    let keyID: UUID
    let metricID: String
    let ruleID: String
    let windowIdentifier: String
}

final class AlertDeliveryCoordinator: @unchecked Sendable {
    static let processShared = AlertDeliveryCoordinator()

    let lock = NSLock()
    var reservationOwners: [AlertWindowKey: UUID] = [:]
    var inFlightReservations: Set<UUID> = []
    var pendingResetWindows: [AlertWindowKey: UUID] = [:]
    var failedSupersededReservations: Set<UUID> = []
}

final class AlertEvaluator: @unchecked Sendable {
    private static let persistedKey = "usageAlertTriggeredWindows"
    private static let periodicWatermarksKey = "usageAlertLatestPeriodicWindows"
    private let defaults: UserDefaults
    private let deliveryCoordinator: AlertDeliveryCoordinator

    init(
        defaults: UserDefaults = .standard,
        deliveryCoordinator: AlertDeliveryCoordinator = .processShared
    ) {
        self.defaults = defaults
        self.deliveryCoordinator = deliveryCoordinator
    }

    func evaluate(
        key: KeyConfiguration,
        snapshot: UsageSnapshot,
        rules: [MetricAlertRule]
    ) -> [UsageAlert] {
        deliveryCoordinator.lock.lock()
        defer { deliveryCoordinator.lock.unlock() }

        let deliveredWindows = Self.loadTriggeredWindows(from: defaults)
        var triggeredWindows = deliveredWindows.union(deliveryCoordinator.reservationOwners.keys)
        var alerts: [UsageAlert] = []
        let metricsByID = Dictionary(uniqueKeysWithValues: snapshot.normalizedMetrics.map { ($0.id, $0) })
        var periodicWatermarks = Self.loadPeriodicWatermarks(from: defaults)

        for rule in rules where rule.isEnabled {
            guard let metric = metricsByID[rule.metricID] else { continue }
            let matchedThresholds: [MetricAlertThreshold]
            let percent: Double
            let windowIdentifier = metric.windowEnd.map { String($0.timeIntervalSince1970) } ?? metric.id
            let numericWindow = Double(windowIdentifier)

            switch rule.valueSource {
            case .usedPercent:
                guard let used = metric.used, let limit = metric.limit, limit > 0 else { continue }
                percent = Self.percent(used: used, limit: limit)
                matchedThresholds = rule.thresholds.filter { threshold in
                    guard let value = threshold.value else { return false }
                    return percent >= NSDecimalNumber(decimal: value).doubleValue
                }
            case .remainingPercent:
                guard let remaining = metric.remaining, let limit = metric.limit, limit > 0 else { continue }
                percent = Self.percent(used: remaining, limit: limit)
                matchedThresholds = rule.thresholds.filter { threshold in
                    guard let value = threshold.value else { return false }
                    return percent <= NSDecimalNumber(decimal: value).doubleValue
                }
            case .absoluteValue:
                guard
                    let value = metric.value,
                    rule.currencyCode == metric.currencyCode,
                    let threshold = rule.thresholds.first?.value
                else { continue }
                percent = 0
                matchedThresholds = value <= threshold ? rule.thresholds : []
            case .healthState:
                percent = 0
                matchedThresholds = [.warning, .critical, .unavailable].contains(metric.healthState)
                    ? [MetricAlertThreshold(level: .high, value: nil)]
                    : []
            }

            let ruleWindowKeys = triggeredWindows.filter { $0.keyID == key.id && $0.ruleID == rule.id }
            let obsoleteWindowKeys = ruleWindowKeys.filter { $0.windowIdentifier != windowIdentifier }
            removeState(for: obsoleteWindowKeys, triggeredWindows: &triggeredWindows)
            let matchingWatermarks = periodicWatermarks.filter {
                $0.keyID == key.id && $0.metricID == rule.metricID && $0.ruleID == rule.id
            }
            if let numericWindow {
                let historicWindows = (
                    ruleWindowKeys.compactMap { Double($0.windowIdentifier) }
                        + matchingWatermarks.compactMap { Double($0.windowIdentifier) }
                ).max()
                guard historicWindows == nil || numericWindow >= historicWindows! else {
                    continue
                }
                periodicWatermarks.subtract(matchingWatermarks)
                periodicWatermarks.insert(AlertPeriodicWindowWatermark(
                    keyID: key.id,
                    metricID: rule.metricID,
                    ruleID: rule.id,
                    windowIdentifier: windowIdentifier
                ))
            }

            guard !matchedThresholds.isEmpty else {
                let isWindowlessPercent = metric.windowEnd == nil
                    && (rule.valueSource == .usedPercent || rule.valueSource == .remainingPercent)
                if !isWindowlessPercent {
                    removeState(for: ruleWindowKeys, triggeredWindows: &triggeredWindows)
                } else {
                    for windowKey in ruleWindowKeys where Double(windowKey.threshold) > percent {
                        if
                            let reservationID = deliveryCoordinator.reservationOwners[windowKey],
                            deliveryCoordinator.inFlightReservations.contains(reservationID)
                        {
                            deliveryCoordinator.pendingResetWindows[windowKey] = reservationID
                        } else {
                            removeState(for: [windowKey], triggeredWindows: &triggeredWindows)
                        }
                    }
                }
                continue
            }
            if metric.windowEnd == nil
                && (rule.valueSource == .usedPercent || rule.valueSource == .remainingPercent) {
                for windowKey in ruleWindowKeys where Double(windowKey.threshold) > percent {
                    if
                        let reservationID = deliveryCoordinator.reservationOwners[windowKey],
                        deliveryCoordinator.inFlightReservations.contains(reservationID)
                    {
                        deliveryCoordinator.pendingResetWindows[windowKey] = reservationID
                    } else {
                        removeState(for: [windowKey], triggeredWindows: &triggeredWindows)
                    }
                }
            }

            guard
                metric.windowEnd != nil
                    || snapshot.kind == .tokenPack
                    || (rule.valueSource != .usedPercent && rule.valueSource != .remainingPercent)
            else {
                continue
            }

            let newlyReached = matchedThresholds.filter { threshold in
                let windowKey = AlertWindowKey(
                    keyID: key.id,
                    metricID: rule.metricID,
                    ruleID: rule.id,
                    windowIdentifier: windowIdentifier,
                    threshold: NSDecimalNumber(decimal: threshold.value ?? 0).intValue
                )
                return !triggeredWindows.contains(windowKey)
            }
            guard let highestThreshold = newlyReached.last else {
                continue
            }

            let reservationID = UUID()
            var reservedWindows = Set<AlertWindowKey>()
            var replacedReservationOwners: [AlertWindowKey: UUID] = [:]

            for threshold in newlyReached {
                let windowKey = AlertWindowKey(
                    keyID: key.id,
                    metricID: rule.metricID,
                    ruleID: rule.id,
                    windowIdentifier: windowIdentifier,
                    threshold: NSDecimalNumber(decimal: threshold.value ?? 0).intValue
                )
                if !triggeredWindows.contains(windowKey) {
                    triggeredWindows.insert(windowKey)
                } else if let previousOwner = deliveryCoordinator.reservationOwners[windowKey],
                          previousOwner != reservationID {
                    replacedReservationOwners[windowKey] = previousOwner
                }
                reservedWindows.insert(windowKey)
                deliveryCoordinator.reservationOwners[windowKey] = reservationID
                if replacedReservationOwners[windowKey] == nil {
                    deliveryCoordinator.pendingResetWindows.removeValue(forKey: windowKey)
                }
            }

            for previousKey in ruleWindowKeys
            where previousKey.windowIdentifier == windowIdentifier && !reservedWindows.contains(previousKey) {
                if let previousOwner = deliveryCoordinator.reservationOwners[previousKey] {
                    reservedWindows.insert(previousKey)
                    replacedReservationOwners[previousKey] = previousOwner
                    deliveryCoordinator.reservationOwners[previousKey] = reservationID
                }
            }
            let obsoleteThresholdKeys = ruleWindowKeys.filter {
                $0.windowIdentifier == windowIdentifier && !reservedWindows.contains($0)
            }
            removeState(for: obsoleteThresholdKeys, triggeredWindows: &triggeredWindows)

            alerts.append(UsageAlert(
                keyID: key.id,
                keyName: key.displayName,
                providerName: Self.providerName(for: key.providerID),
                metricID: metric.id,
                metricLabel: metric.label,
                valueSource: rule.valueSource,
                currentValue: rule.valueSource == .absoluteValue ? metric.value : nil,
                level: highestThreshold.level,
                percent: percent,
                windowEnd: metric.windowEnd,
                balanceAmount: rule.valueSource == .absoluteValue ? metric.value : nil,
                currencyCode: metric.currencyCode,
                reservationID: reservationID,
                triggeredWindows: reservedWindows,
                replacedReservationOwners: replacedReservationOwners
            ))
        }

        persistTriggeredWindows(deliveredWindows.intersection(triggeredWindows))
        persistPeriodicWatermarks(periodicWatermarks)
        return alerts
    }

    private static func percent(used: Decimal, limit: Decimal) -> Double {
        NSDecimalNumber(decimal: used)
            .dividing(by: NSDecimalNumber(decimal: limit))
            .multiplying(by: 100)
            .doubleValue
    }

    private static func providerName(for id: ProviderID) -> String {
        ProviderRegistry.builtInDescriptors.first { $0.id == id }?.displayName ?? id.rawValue
    }


    func restoreEligibility(for alerts: ArraySlice<UsageAlert>) {
        deliveryCoordinator.lock.lock()
        defer { deliveryCoordinator.lock.unlock() }

        let deliveredWindows = Self.loadTriggeredWindows(from: defaults)
        var triggeredWindows = deliveredWindows.union(deliveryCoordinator.reservationOwners.keys)
        for alert in alerts {
            deliveryCoordinator.inFlightReservations.remove(alert.reservationID)
            let wasSuperseded = alert.triggeredWindows.contains { windowKey in
                guard let owner = deliveryCoordinator.reservationOwners[windowKey] else {
                    return false
                }
                return owner != alert.reservationID
            }
            if wasSuperseded {
                deliveryCoordinator.failedSupersededReservations.insert(alert.reservationID)
            }
            for windowKey in alert.triggeredWindows
                where deliveryCoordinator.reservationOwners[windowKey] == alert.reservationID {
                guard let previousOwner = alert.replacedReservationOwners[windowKey] else {
                    triggeredWindows.remove(windowKey)
                    deliveryCoordinator.reservationOwners.removeValue(forKey: windowKey)
                    deliveryCoordinator.pendingResetWindows.removeValue(forKey: windowKey)
                    continue
                }

                if deliveryCoordinator.failedSupersededReservations.contains(previousOwner) {
                    triggeredWindows.remove(windowKey)
                    deliveryCoordinator.reservationOwners.removeValue(forKey: windowKey)
                    deliveryCoordinator.pendingResetWindows.removeValue(forKey: windowKey)
                    continue
                }

                let pendingResetOwner = deliveryCoordinator.pendingResetWindows[windowKey]
                if
                    pendingResetOwner != nil,
                    !deliveryCoordinator.inFlightReservations.contains(previousOwner)
                {
                    triggeredWindows.remove(windowKey)
                    deliveryCoordinator.reservationOwners.removeValue(forKey: windowKey)
                    deliveryCoordinator.pendingResetWindows.removeValue(forKey: windowKey)
                    continue
                }

                deliveryCoordinator.reservationOwners[windowKey] = previousOwner
                if pendingResetOwner == alert.reservationID {
                    deliveryCoordinator.pendingResetWindows[windowKey] = previousOwner
                }
            }
            deliveryCoordinator.failedSupersededReservations.subtract(
                alert.replacedReservationOwners.values
            )
        }
        persistTriggeredWindows(deliveredWindows.intersection(triggeredWindows))
    }

    func restoreEligibility(for alerts: [UsageAlert]) {
        restoreEligibility(for: alerts[...])
    }

    func beginDelivery(of alert: UsageAlert) -> Bool {
        deliveryCoordinator.lock.lock()
        defer { deliveryCoordinator.lock.unlock() }

        let triggeredWindows = Self.loadTriggeredWindows(from: defaults)
            .union(deliveryCoordinator.reservationOwners.keys)
        let isCurrent = alert.triggeredWindows.allSatisfy { windowKey in
            triggeredWindows.contains(windowKey)
                && deliveryCoordinator.reservationOwners[windowKey] == alert.reservationID
        }
        guard isCurrent else {
            return false
        }

        deliveryCoordinator.inFlightReservations.insert(alert.reservationID)
        return true
    }

    func finishDelivery(of alert: UsageAlert) {
        deliveryCoordinator.lock.lock()
        defer { deliveryCoordinator.lock.unlock() }

        var triggeredWindows = Self.loadTriggeredWindows(from: defaults)
        deliveryCoordinator.inFlightReservations.remove(alert.reservationID)
        for windowKey in alert.triggeredWindows
            where deliveryCoordinator.reservationOwners[windowKey] == alert.reservationID {
            if deliveryCoordinator.pendingResetWindows[windowKey] == alert.reservationID {
                triggeredWindows.remove(windowKey)
            } else {
                triggeredWindows.insert(windowKey)
            }
            deliveryCoordinator.pendingResetWindows.removeValue(forKey: windowKey)
            deliveryCoordinator.reservationOwners.removeValue(forKey: windowKey)
        }
        deliveryCoordinator.failedSupersededReservations.subtract(
            alert.replacedReservationOwners.values
        )
        persistTriggeredWindows(triggeredWindows)
    }

    func clearState(for keyID: UUID) {
        deliveryCoordinator.lock.lock()
        defer { deliveryCoordinator.lock.unlock() }

        var triggeredWindows = Self.loadTriggeredWindows(from: defaults)
        let removedWindows = Set(triggeredWindows.filter { $0.keyID == keyID }).union(
            deliveryCoordinator.reservationOwners.keys.filter { $0.keyID == keyID }
        )
        triggeredWindows.subtract(removedWindows)

        var periodicWatermarks = Self.loadPeriodicWatermarks(from: defaults)
        periodicWatermarks = periodicWatermarks.filter { $0.keyID != keyID }

        let removedReservations = Set(removedWindows.compactMap {
            deliveryCoordinator.reservationOwners.removeValue(forKey: $0)
        })
        for window in removedWindows {
            deliveryCoordinator.pendingResetWindows.removeValue(forKey: window)
        }
        let remainingReservations = Set(deliveryCoordinator.reservationOwners.values)
        for reservationID in removedReservations where !remainingReservations.contains(reservationID) {
            deliveryCoordinator.inFlightReservations.remove(reservationID)
            deliveryCoordinator.failedSupersededReservations.remove(reservationID)
        }

        persistTriggeredWindows(triggeredWindows)
        persistPeriodicWatermarks(periodicWatermarks)
    }

    private func removeState(
        for windowKeys: some Sequence<AlertWindowKey>,
        triggeredWindows: inout Set<AlertWindowKey>
    ) {
        var affectedReservations: Set<UUID> = []
        for windowKey in windowKeys {
            triggeredWindows.remove(windowKey)
            deliveryCoordinator.pendingResetWindows.removeValue(forKey: windowKey)
            if let reservationID = deliveryCoordinator.reservationOwners.removeValue(forKey: windowKey) {
                affectedReservations.insert(reservationID)
            }
        }
        let remainingReservations = Set(deliveryCoordinator.reservationOwners.values)
        for reservationID in affectedReservations where !remainingReservations.contains(reservationID) {
            deliveryCoordinator.inFlightReservations.remove(reservationID)
        }
    }

    private func persistTriggeredWindows(_ triggeredWindows: Set<AlertWindowKey>) {
        guard let data = try? JSONEncoder().encode(triggeredWindows) else {
            return
        }
        defaults.set(data, forKey: Self.persistedKey)
    }

    private func persistPeriodicWatermarks(
        _ periodicWatermarks: Set<AlertPeriodicWindowWatermark>
    ) {
        guard let data = try? JSONEncoder().encode(periodicWatermarks) else {
            return
        }
        defaults.set(data, forKey: Self.periodicWatermarksKey)
    }

    private static func loadTriggeredWindows(from defaults: UserDefaults) -> Set<AlertWindowKey> {
        guard
            let data = defaults.data(forKey: persistedKey),
            let values = try? JSONDecoder().decode(Set<AlertWindowKey>.self, from: data)
        else {
            return []
        }
        return values
    }

    private static func loadPeriodicWatermarks(
        from defaults: UserDefaults
    ) -> Set<AlertPeriodicWindowWatermark> {
        guard
            let data = defaults.data(forKey: periodicWatermarksKey),
            let values = try? JSONDecoder().decode(
                Set<AlertPeriodicWindowWatermark>.self,
                from: data
            )
        else {
            return []
        }
        return values
    }
}

private extension Double {
    var isSafeNotificationPercent: Bool {
        isFinite && self >= 0 && rounded() < Double(Int.max)
    }
}

protocol NotificationSending: Sendable {
    func requestAuthorization() async throws -> Bool
    func send(_ alert: UsageAlert) async throws
}

struct AlertManager: Sendable {
    private let evaluator: AlertEvaluator
    private let sender: any NotificationSending

    init(evaluator: AlertEvaluator = AlertEvaluator(), sender: any NotificationSending) {
        self.evaluator = evaluator
        self.sender = sender
    }

    func evaluateAndNotify(
        key: KeyConfiguration,
        snapshot: UsageSnapshot,
        preferences: CredentialUsagePreferences,
        applicationNotificationsEnabled: Bool,
        shouldDeliver: @escaping @Sendable () async -> Bool = { true }
    ) async throws -> [UsageAlert] {
        guard applicationNotificationsEnabled, preferences.notificationsEnabled else {
            return []
        }

        let alerts = evaluator.evaluate(key: key, snapshot: snapshot, rules: preferences.alertRules)
        return try await deliver(
            alerts,
            shouldDeliver: shouldDeliver
        )
    }

    private func deliver(
        _ alerts: [UsageAlert],
        shouldDeliver: @escaping @Sendable () async -> Bool
    ) async throws -> [UsageAlert] {
        guard !alerts.isEmpty else {
            return []
        }
        guard !Task.isCancelled, await shouldDeliver() else {
            evaluator.restoreEligibility(for: alerts)
            return alerts
        }
        let authorized: Bool
        do {
            authorized = try await sender.requestAuthorization()
        } catch {
            evaluator.restoreEligibility(for: alerts)
            throw error
        }
        guard authorized else {
            evaluator.restoreEligibility(for: alerts)
            return alerts
        }
        for (index, alert) in alerts.enumerated() {
            guard !Task.isCancelled, await shouldDeliver() else {
                evaluator.restoreEligibility(for: alerts[index...])
                return alerts
            }
            guard evaluator.beginDelivery(of: alert) else {
                evaluator.restoreEligibility(for: [alert])
                continue
            }
            do {
                try await sender.send(alert)
                evaluator.finishDelivery(of: alert)
            } catch {
                evaluator.restoreEligibility(for: alerts[index...])
                throw error
            }
        }
        return alerts
    }
}

protocol UserNotificationCenterServing: AnyObject {
    var delegate: (any UNUserNotificationCenterDelegate)? { get set }
    func currentAuthorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
}

extension UNUserNotificationCenter: UserNotificationCenterServing {
    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }
}

final class ForegroundNotificationDelegate:
    NSObject,
    UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    static let presentationOptions: UNNotificationPresentationOptions = [
        .banner,
        .list,
        .sound
    ]

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.presentationOptions
    }
}

final class UserNotificationSender: NotificationSending, @unchecked Sendable {
    private let center: any UserNotificationCenterServing
    private let timeZone: TimeZone
    private let foregroundDelegate: ForegroundNotificationDelegate

    init(
        center: any UserNotificationCenterServing = UNUserNotificationCenter.current(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        self.center = center
        self.timeZone = timeZone
        let foregroundDelegate = ForegroundNotificationDelegate()
        self.foregroundDelegate = foregroundDelegate
        center.delegate = foregroundDelegate
    }

    func requestAuthorization() async throws -> Bool {
        switch await center.currentAuthorizationStatus() {
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound])
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func send(_ alert: UsageAlert) async throws {
        let content = UNMutableNotificationContent()
        content.title = alert.notificationTitle
        content.body = alert.notificationBody(timeZone: timeZone)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }
}
