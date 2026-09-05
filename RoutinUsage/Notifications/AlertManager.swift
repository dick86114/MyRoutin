import Foundation
@preconcurrency import UserNotifications

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

enum AlertLevel: String, Codable, Equatable, Sendable {
    case low
    case high
}

struct UsageAlert: Equatable, Sendable {
    let keyID: UUID
    let keyName: String
    let dimension: UsageDimension
    let level: AlertLevel
    let percent: Double
    let windowEnd: Date?
    let balanceAmount: Decimal?
    let currencyCode: String?
    fileprivate let reservationID: UUID
    fileprivate let triggeredWindows: Set<AlertWindowKey>
    fileprivate let replacedReservationOwners: [AlertWindowKey: UUID]

    var notificationTitle: String {
        "Routin 用量预警"
    }

    func notificationBody(timeZone: TimeZone = .autoupdatingCurrent) -> String {
        if let balanceAmount {
            let amount = NSDecimalNumber(decimal: balanceAmount).stringValue
            let currency = currencyCode.map { " \($0)" } ?? ""
            return "\(keyName) · 余额低于预警值，当前 \(amount)\(currency)"
        }
        let base = "\(keyName) · \(dimension.notificationName)用量已达 \(formattedPercent)%"
        guard let windowEnd, dimension != .token else {
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

private extension UsageDimension {
    var notificationName: String {
        switch self {
        case .fiveHour:
            return "5 小时"
        case .weekly:
            return "周"
        case .token:
            return "Token "
        case .balance:
            return "余额"
        }
    }
}

struct AlertWindowKey: Codable, Hashable, Sendable {
    let keyID: UUID
    let dimension: UsageDimension
    let windowIdentifier: String
    let threshold: Int
}

private struct AlertPeriodicWindowWatermark: Codable, Hashable, Sendable {
    let keyID: UUID
    let dimension: UsageDimension
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
        thresholds: AlertThresholds
    ) -> [UsageAlert] {
        deliveryCoordinator.lock.lock()
        defer { deliveryCoordinator.lock.unlock() }

        let deliveredWindows = Self.loadTriggeredWindows(from: defaults)
        var triggeredWindows = deliveredWindows.union(deliveryCoordinator.reservationOwners.keys)
        var periodicWatermarks = Self.loadPeriodicWatermarks(from: defaults)
        var alerts: [UsageAlert] = []
        switch snapshot.kind {
        case .periodic:
            if let metric = snapshot.fiveHour, let windowEnd = metric.windowEnd {
                alerts += evaluate(
                    key: key,
                    metric: metric,
                    dimension: .fiveHour,
                    windowIdentifier: String(windowEnd.timeIntervalSince1970),
                    thresholds: thresholds,
                    clearsWhenBelowThreshold: false,
                    triggeredWindows: &triggeredWindows,
                    periodicWatermarks: &periodicWatermarks
                )
            }
            if let metric = snapshot.weekly, let windowEnd = metric.windowEnd {
                alerts += evaluate(
                    key: key,
                    metric: metric,
                    dimension: .weekly,
                    windowIdentifier: String(windowEnd.timeIntervalSince1970),
                    thresholds: thresholds,
                    clearsWhenBelowThreshold: false,
                    triggeredWindows: &triggeredWindows,
                    periodicWatermarks: &periodicWatermarks
                )
            }
        case .tokenPack:
            if let metric = snapshot.token {
                alerts += evaluate(
                    key: key,
                    metric: metric,
                    dimension: .token,
                    windowIdentifier: "token-pack",
                    thresholds: thresholds,
                    clearsWhenBelowThreshold: true,
                    triggeredWindows: &triggeredWindows,
                    periodicWatermarks: &periodicWatermarks
                )
            }
        }

        for metric in snapshot.metrics where metric.presentation == .progress {
            guard let limit = metric.limit, limit > 0 else { continue }
            let used: Decimal
            switch metric.semantic {
            case .usedQuota:
                guard let amount = metric.used else { continue }
                used = amount
            case .remainingQuota:
                guard let remaining = metric.remaining else { continue }
                used = limit - remaining
            case .balance, .status, .value:
                continue
            }
            let percent = NSDecimalNumber(decimal: used)
                .dividing(by: NSDecimalNumber(decimal: limit))
                .multiplying(by: 100)
                .doubleValue
            let dimension: UsageDimension
            if metric.id == "fiveHour" || metric.id == "five-hour" {
                dimension = .fiveHour
            } else if metric.id == "weekly" {
                dimension = .weekly
            } else {
                dimension = .token
            }
            let normalized = UsageMetric(
                used: used,
                limit: limit,
                remaining: metric.remaining ?? max(0, limit - used),
                percent: percent,
                unit: .token,
                windowEnd: metric.windowEnd
            )
            alerts += evaluate(
                key: key,
                metric: normalized,
                dimension: dimension,
                windowIdentifier: metric.windowEnd.map { String($0.timeIntervalSince1970) } ?? metric.id,
                thresholds: thresholds,
                clearsWhenBelowThreshold: metric.windowEnd == nil,
                triggeredWindows: &triggeredWindows,
                periodicWatermarks: &periodicWatermarks
            )
        }

        if let thresholdText = key.metadata["balanceWarningThreshold"],
           let threshold = Decimal(string: thresholdText),
           let balanceMetric = snapshot.metrics.first(where: { $0.semantic == .balance }),
           let balance = balanceMetric.value {
            alerts += evaluateBalance(
                key: key,
                balance: balance,
                threshold: threshold,
                currencyCode: balanceMetric.currencyCode,
                triggeredWindows: &triggeredWindows
            )
        }

        persistTriggeredWindows(deliveredWindows.intersection(triggeredWindows))
        persistPeriodicWatermarks(periodicWatermarks)
        return alerts
    }

    private func evaluateBalance(
        key: KeyConfiguration,
        balance: Decimal,
        threshold: Decimal,
        currencyCode: String?,
        triggeredWindows: inout Set<AlertWindowKey>
    ) -> [UsageAlert] {
        let windowKey = AlertWindowKey(
            keyID: key.id,
            dimension: .balance,
            windowIdentifier: currencyCode ?? "currency",
            threshold: 0
        )
        if balance > threshold {
            removeState(for: [windowKey], triggeredWindows: &triggeredWindows)
            return []
        }
        guard !triggeredWindows.contains(windowKey) else { return [] }
        let reservationID = UUID()
        triggeredWindows.insert(windowKey)
        deliveryCoordinator.reservationOwners[windowKey] = reservationID
        return [UsageAlert(
            keyID: key.id,
            keyName: key.displayName,
            dimension: .balance,
            level: .low,
            percent: 0,
            windowEnd: nil,
            balanceAmount: balance,
            currencyCode: currencyCode,
            reservationID: reservationID,
            triggeredWindows: [windowKey],
            replacedReservationOwners: [:]
        )]
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

    private func evaluate(
        key: KeyConfiguration,
        metric: UsageMetric,
        dimension: UsageDimension,
        windowIdentifier: String,
        thresholds: AlertThresholds,
        clearsWhenBelowThreshold: Bool,
        triggeredWindows: inout Set<AlertWindowKey>,
        periodicWatermarks: inout Set<AlertPeriodicWindowWatermark>
    ) -> [UsageAlert] {
        guard metric.percent.isSafeNotificationPercent else {
            return []
        }
        let levels: [(threshold: Int, level: AlertLevel)] = [
            (thresholds.low, .low),
            (thresholds.high, .high)
        ]

        guard prepareCurrentWindow(
            keyID: key.id,
            dimension: dimension,
            windowIdentifier: windowIdentifier,
            activeThresholds: Set(levels.map(\.threshold)),
            isPeriodic: !clearsWhenBelowThreshold,
            triggeredWindows: &triggeredWindows,
            periodicWatermarks: &periodicWatermarks
        ) else {
            return []
        }

        if clearsWhenBelowThreshold {
            for item in levels where metric.percent < Double(item.threshold) {
                let windowKey = AlertWindowKey(
                    keyID: key.id,
                    dimension: dimension,
                    windowIdentifier: windowIdentifier,
                    threshold: item.threshold
                )
                if
                    let reservationID = deliveryCoordinator.reservationOwners[windowKey],
                    deliveryCoordinator.inFlightReservations.contains(reservationID)
                {
                    deliveryCoordinator.pendingResetWindows[windowKey] = reservationID
                    continue
                }
                removeState(for: [windowKey], triggeredWindows: &triggeredWindows)
            }
        }

        let newlyReached = levels.filter { item in
            guard metric.percent >= Double(item.threshold) else {
                return false
            }
            let windowKey = AlertWindowKey(
                keyID: key.id,
                dimension: dimension,
                windowIdentifier: windowIdentifier,
                threshold: item.threshold
            )
            return !triggeredWindows.contains(windowKey)
        }

        guard let highest = newlyReached.last else {
            return []
        }

        let newlyTriggeredWindows = Set(newlyReached.map { item in
            AlertWindowKey(
                keyID: key.id,
                dimension: dimension,
                windowIdentifier: windowIdentifier,
                threshold: item.threshold
            )
        })
        let reservationID = UUID()
        triggeredWindows.formUnion(newlyTriggeredWindows)
        var reservedWindows = newlyTriggeredWindows
        var replacedReservationOwners: [AlertWindowKey: UUID] = [:]
        for item in levels where item.threshold < highest.threshold {
            let lowerWindowKey = AlertWindowKey(
                keyID: key.id,
                dimension: dimension,
                windowIdentifier: windowIdentifier,
                threshold: item.threshold
            )
            if
                !newlyTriggeredWindows.contains(lowerWindowKey),
                let previousOwner = deliveryCoordinator.reservationOwners[lowerWindowKey]
            {
                reservedWindows.insert(lowerWindowKey)
                replacedReservationOwners[lowerWindowKey] = previousOwner
            }
        }
        for windowKey in reservedWindows {
            deliveryCoordinator.reservationOwners[windowKey] = reservationID
            if replacedReservationOwners[windowKey] == nil {
                deliveryCoordinator.pendingResetWindows.removeValue(forKey: windowKey)
            }
        }

        return [UsageAlert(
            keyID: key.id,
            keyName: key.displayName,
            dimension: dimension,
            level: highest.level,
            percent: metric.percent,
            windowEnd: metric.windowEnd,
            balanceAmount: nil,
            currencyCode: nil,
            reservationID: reservationID,
            triggeredWindows: reservedWindows,
            replacedReservationOwners: replacedReservationOwners
        )]
    }

    private func prepareCurrentWindow(
        keyID: UUID,
        dimension: UsageDimension,
        windowIdentifier: String,
        activeThresholds: Set<Int>,
        isPeriodic: Bool,
        triggeredWindows: inout Set<AlertWindowKey>,
        periodicWatermarks: inout Set<AlertPeriodicWindowWatermark>
    ) -> Bool {
        let matchingKeys = triggeredWindows.filter {
            $0.keyID == keyID && $0.dimension == dimension
        }
        if isPeriodic, let currentWindow = Double(windowIdentifier) {
            let matchingWatermarks = periodicWatermarks.filter {
                $0.keyID == keyID && $0.dimension == dimension
            }
            let latestWindow = (
                matchingKeys.compactMap { Double($0.windowIdentifier) }
                    + matchingWatermarks.compactMap { Double($0.windowIdentifier) }
            ).max()
            if let latestWindow, currentWindow < latestWindow {
                return false
            }

            periodicWatermarks.subtract(matchingWatermarks)
            periodicWatermarks.insert(AlertPeriodicWindowWatermark(
                keyID: keyID,
                dimension: dimension,
                windowIdentifier: windowIdentifier
            ))
        }

        let obsoleteKeys = matchingKeys.filter {
            $0.windowIdentifier != windowIdentifier
                || !activeThresholds.contains($0.threshold)
        }
        removeState(for: obsoleteKeys, triggeredWindows: &triggeredWindows)
        return true
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
        thresholds: AlertThresholds = AlertThresholds(),
        notificationsEnabled: Bool,
        shouldDeliver: @escaping @Sendable () async -> Bool = { true }
    ) async throws -> [UsageAlert] {
        guard notificationsEnabled else {
            return []
        }

        let alerts = evaluator.evaluate(key: key, snapshot: snapshot, thresholds: thresholds)
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
