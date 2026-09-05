import Foundation
@preconcurrency import UserNotifications
import XCTest
@testable import RoutinUsage

final class AlertManagerTests: XCTestCase {
    @MainActor
    func test剩余百分比低于阈值才触发规则通知() throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let metric = NormalizedUsageMetric(
            id: "remaining",
            label: "剩余额度",
            used: 96,
            limit: 100,
            remaining: 4,
            unit: .token,
            windowEnd: Date(timeIntervalSince1970: 10_000),
            presentation: .progress,
            semantic: .remainingQuota
        )
        let snapshot = UsageSnapshot(
            planName: "套餐",
            kind: .periodic,
            fiveHour: nil,
            weekly: nil,
            token: nil,
            allowedModels: [],
            fetchedAt: .now,
            providerID: .glm,
            metrics: [metric]
        )

        let alerts = context.evaluator.evaluate(
            key: makeKey(),
            snapshot: snapshot,
            rules: [.remainingPercent(metricID: "remaining", isEnabled: true, low: 20, high: 5)]
        )

        XCTAssertEqual(alerts.map(\.level), [.high])
        XCTAssertTrue(alerts.allSatisfy { $0.metricID == "remaining" })
    }

    @MainActor
    func test规则关闭时不生成规则提醒() throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let snapshot = UsageSnapshot(
            planName: "套餐",
            kind: .periodic,
            fiveHour: nil,
            weekly: nil,
            token: nil,
            allowedModels: [],
            fetchedAt: .now,
            providerID: .glm,
            metrics: [NormalizedUsageMetric(
                id: "weekly",
                label: "周用量",
                used: 90,
                limit: 100,
                remaining: 10,
                unit: .token,
                presentation: .progress,
                semantic: .usedQuota
            )]
        )

        let alerts = context.evaluator.evaluate(
            key: makeKey(),
            snapshot: snapshot,
            rules: [.usedPercent(metricID: "weekly", isEnabled: false, low: 80, high: 95)]
        )

        XCTAssertEqual(alerts, [])
    }

    func test默认阈值为八十和九十五且只允许有效顺序与范围() {
        XCTAssertEqual(AlertThresholds().low, 80)
        XCTAssertEqual(AlertThresholds().high, 95)
        XCTAssertTrue(AlertThresholds.isValid(low: 1, high: 100))
        XCTAssertFalse(AlertThresholds.isValid(low: 0, high: 95))
        XCTAssertFalse(AlertThresholds.isValid(low: 80, high: 101))
        XCTAssertFalse(AlertThresholds.isValid(low: 80, high: 80))
        XCTAssertFalse(AlertThresholds.isValid(low: 95, high: 80))
    }

    func test五小时额度在低阈值以下不通知达到阈值后同窗口不重复() throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = makeKey()
        let windowEnd = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: periodicSnapshot(fiveHourPercent: 79, windowEnd: windowEnd),
                thresholds: .init(low: 80, high: 95)
            ),
            []
        )

        let alerts = context.evaluator.evaluate(
            key: key,
            snapshot: periodicSnapshot(fiveHourPercent: 80, windowEnd: windowEnd),
            thresholds: .init(low: 80, high: 95)
        )

        XCTAssertEqual(alerts.map(\.level), [.low])
        XCTAssertEqual(alerts.first?.keyName, "主账号")
        XCTAssertEqual(alerts.first?.metricID, "fiveHour")
        XCTAssertEqual(alerts.first?.percent, 80)
        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: periodicSnapshot(fiveHourPercent: 81, windowEnd: windowEnd),
                thresholds: .init(low: 80, high: 95)
            ),
            []
        )
    }

    func test一次跨越多个阈值只通知最高级且不会随后补发低级() {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = makeKey()
        let windowEnd = Date(timeIntervalSince1970: 10_000)

        _ = context.evaluator.evaluate(
            key: key,
            snapshot: periodicSnapshot(fiveHourPercent: 79, windowEnd: windowEnd),
            thresholds: .init(low: 80, high: 95)
        )
        let alerts = context.evaluator.evaluate(
            key: key,
            snapshot: periodicSnapshot(fiveHourPercent: 96, windowEnd: windowEnd),
            thresholds: .init(low: 80, high: 95)
        )

        XCTAssertEqual(alerts.map(\.level), [.high])
        XCTAssertEqual(alerts.first?.keyName, "主账号")
        XCTAssertEqual(alerts.first?.metricID, "fiveHour")
        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: periodicSnapshot(fiveHourPercent: 82, windowEnd: windowEnd),
                thresholds: .init(low: 80, high: 95)
            ),
            []
        )
    }

    func test周期额度分别评估五小时和周额度() {
        let context = makeContext()
        defer { context.cleanUp() }

        let alerts = context.evaluator.evaluate(
            key: makeKey(),
            snapshot: periodicSnapshot(
                fiveHourPercent: 80,
                fiveHourWindowEnd: Date(timeIntervalSince1970: 10_000),
                weeklyPercent: 96,
                weeklyWindowEnd: Date(timeIntervalSince1970: 20_000)
            ),
            thresholds: .init(low: 80, high: 95)
        )

        XCTAssertEqual(alerts.map(\.metricID), ["fiveHour", "weekly"])
        XCTAssertEqual(alerts.map(\.level), [.low, .high])
    }

    func test新周期窗口恢复通知资格且旧窗口记录跨评估器持久去重() {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = makeKey()

        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: periodicSnapshot(
                    fiveHourPercent: 80,
                    windowEnd: Date(timeIntervalSince1970: 10_000)
                ),
                thresholds: .init()
            ).map(\.level),
            [.low]
        )

        let reloadedEvaluator = AlertEvaluator(defaults: context.defaults)
        XCTAssertEqual(
            reloadedEvaluator.evaluate(
                key: key,
                snapshot: periodicSnapshot(
                    fiveHourPercent: 90,
                    windowEnd: Date(timeIntervalSince1970: 10_000)
                ),
                thresholds: .init()
            ),
            []
        )
        XCTAssertEqual(
            reloadedEvaluator.evaluate(
                key: key,
                snapshot: periodicSnapshot(
                    fiveHourPercent: 90,
                    windowEnd: Date(timeIntervalSince1970: 20_000)
                ),
                thresholds: .init()
            ).map(\.level),
            [.low]
        )
    }

    func test新周期低于阈值也会记录水位并阻止迟到旧窗口补发() throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = makeKey()
        let oldWindowEnd = Date(timeIntervalSince1970: 10_000)
        let newWindowEnd = Date(timeIntervalSince1970: 20_000)

        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: periodicSnapshot(
                    fiveHourPercent: 96,
                    windowEnd: oldWindowEnd
                ),
                thresholds: .init()
            ).map(\.level),
            [.high]
        )
        XCTAssertEqual(
            AlertEvaluator(
                defaults: try XCTUnwrap(UserDefaults(suiteName: context.suiteName))
            ).evaluate(
                key: key,
                snapshot: periodicSnapshot(
                    fiveHourPercent: 79,
                    windowEnd: newWindowEnd
                ),
                thresholds: .init()
            ),
            []
        )
        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: periodicSnapshot(
                    fiveHourPercent: 96,
                    windowEnd: oldWindowEnd
                ),
                thresholds: .init()
            ),
            []
        )
    }

    func test周期窗口和阈值变化后只保留当前去重记录() throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = makeKey()

        for windowIndex in 1...10 {
            let alerts = context.evaluator.evaluate(
                key: key,
                snapshot: periodicSnapshot(
                    fiveHourPercent: 96,
                    windowEnd: Date(timeIntervalSince1970: Double(windowIndex * 10_000))
                ),
                thresholds: .init()
            )
            XCTAssertEqual(
                alerts.map(\.level),
                [.high]
            )
            markDelivered(alerts, evaluator: context.evaluator)
        }

        var persistedKeys = try persistedWindowKeys(from: context.defaults)
        var currentKeys = persistedKeys.filter {
            $0.keyID == key.id && $0.metricID == "fiveHour"
        }
        XCTAssertEqual(currentKeys.count, 2)
        XCTAssertEqual(Set(currentKeys.map(\.windowIdentifier)), ["100000.0"])
        XCTAssertEqual(Set(currentKeys.map(\.threshold)), [80, 95])

        let changedThresholdAlerts = context.evaluator.evaluate(
            key: key,
            snapshot: periodicSnapshot(
                fiveHourPercent: 99,
                windowEnd: Date(timeIntervalSince1970: 100_000)
            ),
            thresholds: .init(low: 85, high: 98)
        )
        XCTAssertEqual(
            changedThresholdAlerts.map(\.level),
            [.high]
        )
        markDelivered(changedThresholdAlerts, evaluator: context.evaluator)

        persistedKeys = try persistedWindowKeys(from: context.defaults)
        currentKeys = persistedKeys.filter {
            $0.keyID == key.id && $0.metricID == "fiveHour"
        }
        XCTAssertEqual(currentKeys.count, 2)
        XCTAssertEqual(Set(currentKeys.map(\.windowIdentifier)), ["100000.0"])
        XCTAssertEqual(Set(currentKeys.map(\.threshold)), [85, 98])
    }

    func test跨评估器写入不同Key不会覆盖既有去重记录() throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let firstEvaluator = context.evaluator
        let secondDefaults = try XCTUnwrap(UserDefaults(suiteName: context.suiteName))
        let secondEvaluator = AlertEvaluator(defaults: secondDefaults)
        let firstKey = makeKey()
        let secondKey = makeKey()
        let snapshot = periodicSnapshot(
            fiveHourPercent: 80,
            windowEnd: Date(timeIntervalSince1970: 10_000)
        )

        let firstAlerts = firstEvaluator.evaluate(
            key: firstKey,
            snapshot: snapshot,
            thresholds: .init()
        )
        XCTAssertEqual(firstAlerts.map(\.level), [.low])
        markDelivered(firstAlerts, evaluator: firstEvaluator)
        let secondAlerts = secondEvaluator.evaluate(
            key: secondKey,
            snapshot: snapshot,
            thresholds: .init()
        )
        XCTAssertEqual(secondAlerts.map(\.level), [.low])
        markDelivered(secondAlerts, evaluator: secondEvaluator)

        let reloadedDefaults = try XCTUnwrap(UserDefaults(suiteName: context.suiteName))
        let reloadedEvaluator = AlertEvaluator(defaults: reloadedDefaults)
        XCTAssertEqual(
            reloadedEvaluator.evaluate(
                key: firstKey,
                snapshot: snapshot,
                thresholds: .init()
            ),
            []
        )
        XCTAssertEqual(
            reloadedEvaluator.evaluate(
                key: secondKey,
                snapshot: snapshot,
                thresholds: .init()
            ),
            []
        )
        XCTAssertEqual(try persistedWindowKeys(from: context.defaults).count, 2)
    }

    func test跨评估器评估同一窗口只产生一次通知() throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let firstEvaluator = context.evaluator
        let secondDefaults = try XCTUnwrap(UserDefaults(suiteName: context.suiteName))
        let secondEvaluator = AlertEvaluator(defaults: secondDefaults)
        let key = makeKey()
        let snapshot = tokenSnapshot(percent: 96)

        XCTAssertEqual(
            firstEvaluator.evaluate(
                key: key,
                snapshot: snapshot,
                thresholds: .init()
            ).map(\.level),
            [.high]
        )
        XCTAssertEqual(
            secondEvaluator.evaluate(
                key: key,
                snapshot: snapshot,
                thresholds: .init()
            ),
            []
        )
    }

    func test未完成投递在进程重启后恢复通知资格() {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = makeKey()
        let snapshot = tokenSnapshot(percent: 96)
        let firstProcess = AlertEvaluator(
            defaults: context.defaults,
            deliveryCoordinator: AlertDeliveryCoordinator()
        )

        XCTAssertEqual(
            firstProcess.evaluate(key: key, snapshot: snapshot, thresholds: .init()).map(\.level),
            [.high]
        )

        let restartedProcess = AlertEvaluator(
            defaults: context.defaults,
            deliveryCoordinator: AlertDeliveryCoordinator()
        )
        XCTAssertEqual(
            restartedProcess.evaluate(key: key, snapshot: snapshot, thresholds: .init()).map(\.level),
            [.high]
        )
    }

    func test成功投递后在进程重启仍保持去重() async throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = makeKey()
        let snapshot = tokenSnapshot(percent: 96)
        let firstProcess = AlertEvaluator(
            defaults: context.defaults,
            deliveryCoordinator: AlertDeliveryCoordinator()
        )
        let manager = AlertManager(
            evaluator: firstProcess,
            sender: NotificationSenderSpy(authorizationGranted: true)
        )

        _ = try await manager.evaluateAndNotify(
            key: key,
            snapshot: snapshot,
            notificationsEnabled: true
        )

        let restartedProcess = AlertEvaluator(
            defaults: context.defaults,
            deliveryCoordinator: AlertDeliveryCoordinator()
        )
        XCTAssertEqual(
            restartedProcess.evaluate(key: key, snapshot: snapshot, thresholds: .init()),
            []
        )
    }

    func test资源包只评估Token且回落到阈值以下后可再次通知() {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = makeKey()

        let initialAlerts = context.evaluator.evaluate(
            key: key,
            snapshot: tokenSnapshot(percent: 96),
            thresholds: .init()
        )
        XCTAssertEqual(initialAlerts.map(\.metricID), ["token"])
        XCTAssertEqual(initialAlerts.map(\.level), [.high])
        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: tokenSnapshot(percent: 94),
                thresholds: .init()
            ),
            []
        )
        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: tokenSnapshot(percent: 96),
                thresholds: .init()
            ).map(\.level),
            [.high]
        )
        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: tokenSnapshot(percent: 79),
                thresholds: .init()
            ),
            []
        )
        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: tokenSnapshot(percent: 81),
                thresholds: .init()
            ).map(\.level),
            [.low]
        )
    }

    func test关闭通知时不请求授权不发送且不消耗阈值资格() async throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let sender = NotificationSenderSpy(authorizationGranted: true)
        let manager = AlertManager(evaluator: context.evaluator, sender: sender)
        let key = makeKey()
        let snapshot = periodicSnapshot(
            fiveHourPercent: 96,
            windowEnd: Date(timeIntervalSince1970: 10_000)
        )

        let disabledAlerts = try await manager.evaluateAndNotify(
            key: key,
            snapshot: snapshot,
            thresholds: .init(),
            notificationsEnabled: false
        )

        XCTAssertEqual(disabledAlerts, [])
        let disabledSenderState = await sender.state
        XCTAssertEqual(disabledSenderState.authorizationRequestCount, 0)
        XCTAssertEqual(disabledSenderState.sentAlerts, [])

        let enabledAlerts = try await manager.evaluateAndNotify(
            key: key,
            snapshot: snapshot,
            thresholds: .init(),
            notificationsEnabled: true
        )
        XCTAssertEqual(enabledAlerts.map(\.level), [.high])
        let enabledSenderState = await sender.state
        XCTAssertEqual(enabledSenderState.authorizationRequestCount, 1)
        XCTAssertEqual(enabledSenderState.sentAlerts.map(\.level), [.high])
    }

    func test异常百分比不会请求授权发送通知或消耗提醒资格() async throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let sender = NotificationSenderSpy(authorizationResults: Array(repeating: true, count: 5))
        let manager = AlertManager(evaluator: context.evaluator, sender: sender)
        let key = makeKey()

        for percent in [
            Double.nan,
            Double.infinity,
            -Double.infinity,
            Double.greatestFiniteMagnitude,
            -1
        ] {
            let alerts = try await manager.evaluateAndNotify(
                key: key,
                snapshot: malformedTokenSnapshot(percent: percent),
                thresholds: .init(),
                notificationsEnabled: true
            )
            XCTAssertEqual(alerts, [], "异常百分比不应生成通知：\(percent)")
        }

        let senderState = await sender.state
        XCTAssertEqual(senderState.authorizationRequestCount, 0)
        XCTAssertEqual(senderState.sentAlerts, [])

        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: tokenSnapshot(percent: 80),
                thresholds: .init()
            ).map(\.level),
            [.low]
        )
    }

    func test授权未通过时不发送通知且下次授权后仍可提醒() async throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let sender = NotificationSenderSpy(authorizationResults: [false, true])
        let manager = AlertManager(evaluator: context.evaluator, sender: sender)
        let key = makeKey()
        let snapshot = tokenSnapshot(percent: 80)

        let alerts = try await manager.evaluateAndNotify(
            key: key,
            snapshot: snapshot,
            thresholds: .init(),
            notificationsEnabled: true
        )

        XCTAssertEqual(alerts.map(\.level), [.low])
        let senderState = await sender.state
        XCTAssertEqual(senderState.authorizationRequestCount, 1)
        XCTAssertEqual(senderState.sentAlerts, [])

        let retriedAlerts = try await manager.evaluateAndNotify(
            key: key,
            snapshot: snapshot,
            thresholds: .init(),
            notificationsEnabled: true
        )
        let retriedSenderState = await sender.state
        XCTAssertEqual(retriedAlerts.map(\.level), [.low])
        XCTAssertEqual(retriedSenderState.authorizationRequestCount, 2)
        XCTAssertEqual(retriedSenderState.sentAlerts.map(\.level), [.low])
    }

    func test发送失败后保留提醒资格供下次重试() async throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let sender = NotificationSenderSpy(
            authorizationResults: [true, true],
            sendFailureCount: 1
        )
        let manager = AlertManager(evaluator: context.evaluator, sender: sender)
        let key = makeKey()
        let snapshot = tokenSnapshot(percent: 96)

        do {
            _ = try await manager.evaluateAndNotify(
                key: key,
                snapshot: snapshot,
                thresholds: .init(),
                notificationsEnabled: true
            )
            XCTFail("首次发送应失败")
        } catch {
            XCTAssertEqual(error as? NotificationSenderSpyError, .发送失败)
        }

        let retriedAlerts = try await manager.evaluateAndNotify(
            key: key,
            snapshot: snapshot,
            thresholds: .init(),
            notificationsEnabled: true
        )
        let senderState = await sender.state
        XCTAssertEqual(retriedAlerts.map(\.level), [.high])
        XCTAssertEqual(senderState.authorizationRequestCount, 2)
        XCTAssertEqual(senderState.sentAlerts.map(\.level), [.high])
    }

    func test旧授权请求回滚不会删除较新成功通知的同一Token资格() async throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = makeKey()
        let delayedSender = ControlledAuthorizationSender()
        let delayedManager = AlertManager(evaluator: context.evaluator, sender: delayedSender)
        let highSnapshot = tokenSnapshot(percent: 96)
        let delayedTask = Task {
            try await delayedManager.evaluateAndNotify(
                key: key,
                snapshot: highSnapshot,
                thresholds: .init(),
                notificationsEnabled: true
            )
        }
        await delayedSender.waitUntilAuthorizationRequestCount(1)

        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: tokenSnapshot(percent: 94),
                thresholds: .init()
            ),
            []
        )
        let successfulSender = NotificationSenderSpy(authorizationGranted: true)
        let successfulManager = AlertManager(evaluator: context.evaluator, sender: successfulSender)
        let successfulAlerts = try await successfulManager.evaluateAndNotify(
            key: key,
            snapshot: highSnapshot,
            thresholds: .init(),
            notificationsEnabled: true
        )
        XCTAssertEqual(successfulAlerts.map(\.level), [.high])

        await delayedSender.resolveNextAuthorization(false)
        _ = try await delayedTask.value

        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: highSnapshot,
                thresholds: .init()
            ),
            []
        )
    }

    func test发送挂起期间Token回落再升高不会重复派发高阈值通知() async throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = makeKey()
        let highSnapshot = tokenSnapshot(percent: 96)
        let delayedSender = ControlledSendingSender()
        let delayedManager = AlertManager(evaluator: context.evaluator, sender: delayedSender)
        let delayedTask = Task {
            try await delayedManager.evaluateAndNotify(
                key: key,
                snapshot: highSnapshot,
                thresholds: .init(),
                notificationsEnabled: true
            )
        }
        await delayedSender.waitUntilSendCount(1)

        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: tokenSnapshot(percent: 94),
                thresholds: .init()
            ),
            []
        )
        let competingSender = NotificationSenderSpy(authorizationGranted: true)
        let competingManager = AlertManager(evaluator: context.evaluator, sender: competingSender)
        let competingAlerts = try await competingManager.evaluateAndNotify(
            key: key,
            snapshot: highSnapshot,
            thresholds: .init(),
            notificationsEnabled: true
        )
        XCTAssertEqual(competingAlerts, [])
        let competingState = await competingSender.state
        XCTAssertEqual(competingState.authorizationRequestCount, 0)
        XCTAssertEqual(competingState.sentAlerts, [])

        await delayedSender.resolveNextSend()
        _ = try await delayedTask.value
    }

    func test发送挂起期间Token回落会在发送完成后恢复高阈值资格() async throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = makeKey()
        let highSnapshot = tokenSnapshot(percent: 96)
        let delayedSender = ControlledSendingSender()
        let delayedManager = AlertManager(evaluator: context.evaluator, sender: delayedSender)
        let delayedTask = Task {
            try await delayedManager.evaluateAndNotify(
                key: key,
                snapshot: highSnapshot,
                thresholds: .init(),
                notificationsEnabled: true
            )
        }
        await delayedSender.waitUntilSendCount(1)

        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: tokenSnapshot(percent: 94),
                thresholds: .init()
            ),
            []
        )
        await delayedSender.resolveNextSend()
        _ = try await delayedTask.value

        let retrySender = NotificationSenderSpy(authorizationGranted: true)
        let retryManager = AlertManager(evaluator: context.evaluator, sender: retrySender)
        let retryAlerts = try await retryManager.evaluateAndNotify(
            key: key,
            snapshot: highSnapshot,
            thresholds: .init(),
            notificationsEnabled: true
        )
        XCTAssertEqual(retryAlerts.map(\.level), [.high])
        let retryState = await retrySender.state
        XCTAssertEqual(retryState.sentAlerts.map(\.level), [.high])
    }

    func test低阈值发送挂起后回落再由高阈值接管不会倒序补发低阈值() async throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = makeKey()
        let delayedSender = ControlledSendingSender()
        let delayedManager = AlertManager(evaluator: context.evaluator, sender: delayedSender)
        let lowSnapshot = tokenSnapshot(percent: 80)
        let delayedLowTask = Task {
            try await delayedManager.evaluateAndNotify(
                key: key,
                snapshot: lowSnapshot,
                thresholds: .init(),
                notificationsEnabled: true
            )
        }
        await delayedSender.waitUntilSendCount(1)

        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: tokenSnapshot(percent: 79),
                thresholds: .init()
            ),
            []
        )
        let highSender = NotificationSenderSpy(authorizationGranted: true)
        let highManager = AlertManager(evaluator: context.evaluator, sender: highSender)
        let highAlerts = try await highManager.evaluateAndNotify(
            key: key,
            snapshot: tokenSnapshot(percent: 96),
            thresholds: .init(),
            notificationsEnabled: true
        )
        XCTAssertEqual(highAlerts.map(\.level), [.high])
        let highState = await highSender.state
        XCTAssertEqual(highState.sentAlerts.map(\.level), [.high])

        await delayedSender.resolveNextSend()
        _ = try await delayedLowTask.value

        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: tokenSnapshot(percent: 96),
                thresholds: .init()
            ),
            []
        )
    }

    func test高阈值接管低阈值发送后失败不会解除低阈值保护() async throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = makeKey()
        let delayedSender = ControlledSendingSender()
        let delayedManager = AlertManager(evaluator: context.evaluator, sender: delayedSender)
        let lowSnapshot = tokenSnapshot(percent: 80)
        let delayedLowTask = Task {
            try await delayedManager.evaluateAndNotify(
                key: key,
                snapshot: lowSnapshot,
                thresholds: .init(),
                notificationsEnabled: true
            )
        }
        await delayedSender.waitUntilSendCount(1)

        let failingHighSender = NotificationSenderSpy(
            authorizationResults: [true],
            sendFailureCount: 1
        )
        let failingHighManager = AlertManager(
            evaluator: context.evaluator,
            sender: failingHighSender
        )
        do {
            _ = try await failingHighManager.evaluateAndNotify(
                key: key,
                snapshot: tokenSnapshot(percent: 95),
                thresholds: .init(),
                notificationsEnabled: true
            )
            XCTFail("高阈值发送应失败")
        } catch {
            XCTAssertEqual(error as? NotificationSenderSpyError, .发送失败)
        }

        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: lowSnapshot,
                thresholds: .init()
            ),
            []
        )

        await delayedSender.resolveNextSend()
        _ = try await delayedLowTask.value
    }

    func test被接管的低阈值与高阈值依次发送失败会恢复低阈值资格() async throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = makeKey()
        let lowSnapshot = tokenSnapshot(percent: 80)
        let highSnapshot = tokenSnapshot(percent: 95)
        let failingLowSender = ControlledFailingSendingSender()
        let lowManager = AlertManager(evaluator: context.evaluator, sender: failingLowSender)
        let lowTask = Task {
            try await lowManager.evaluateAndNotify(
                key: key,
                snapshot: lowSnapshot,
                thresholds: .init(),
                notificationsEnabled: true
            )
        }
        await failingLowSender.waitUntilSendCount(1)

        let failingHighSender = ControlledFailingSendingSender()
        let highManager = AlertManager(evaluator: context.evaluator, sender: failingHighSender)
        let highTask = Task {
            try await highManager.evaluateAndNotify(
                key: key,
                snapshot: highSnapshot,
                thresholds: .init(),
                notificationsEnabled: true
            )
        }
        await failingHighSender.waitUntilSendCount(1)

        await failingLowSender.failNextSend()
        do {
            _ = try await lowTask.value
            XCTFail("低阈值发送应失败")
        } catch {
            XCTAssertEqual(error as? NotificationSenderSpyError, .发送失败)
        }

        await failingHighSender.failNextSend()
        do {
            _ = try await highTask.value
            XCTFail("高阈值发送应失败")
        } catch {
            XCTAssertEqual(error as? NotificationSenderSpyError, .发送失败)
        }

        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: lowSnapshot,
                thresholds: .init()
            ).map(\.level),
            [.low]
        )
    }

    func test周期额度缺少窗口结束时间时不产生无法去重的通知() {
        let context = makeContext()
        defer { context.cleanUp() }
        let snapshot = UsageSnapshot(
            planName: "Pro",
            kind: .periodic,
            fiveHour: metric(percent: 96, windowEnd: nil),
            weekly: metric(percent: 96, windowEnd: nil),
            token: nil,
            allowedModels: [],
            fetchedAt: .now
        )

        XCTAssertEqual(
            context.evaluator.evaluate(
                key: makeKey(),
                snapshot: snapshot,
                thresholds: .init()
            ),
            []
        )
    }

    func test通知文案只含名称额度百分比与周期重置时间() throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let key = KeyConfiguration(
            id: UUID(),
            name: "主账号",
            keySuffix: "绝不能出现在通知里的Key尾号",
            sortOrder: 0
        )
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let periodicAlert = try XCTUnwrap(context.evaluator.evaluate(
            key: key,
            snapshot: periodicSnapshot(
                fiveHourPercent: 96,
                windowEnd: Date(timeIntervalSince1970: 50_400)
            ),
            thresholds: .init()
        ).first)

        XCTAssertEqual(periodicAlert.notificationTitle, "Routin 用量预警")
        XCTAssertEqual(
            periodicAlert.notificationBody(timeZone: timeZone),
            "主账号 · 5 小时用量已达 96%，窗口将在 14:00 重置"
        )
        XCTAssertFalse(periodicAlert.notificationBody(timeZone: timeZone).contains(key.keySuffix))

        let tokenAlert = try XCTUnwrap(context.evaluator.evaluate(
            key: key,
            snapshot: tokenSnapshot(percent: 80),
            thresholds: .init()
        ).first)
        XCTAssertEqual(tokenAlert.notificationBody(timeZone: timeZone), "主账号 · Token 用量已达 80%")
    }

    func test遗留Plan秘密名称不会进入通知文案() throws {
        let context = makeContext()
        defer { context.cleanUp() }
        let secret = "plan-sensitive-8F2A"
        let key = KeyConfiguration(
            id: UUID(),
            name: secret,
            keySuffix: "8F2A",
            sortOrder: 0
        )

        let alert = try XCTUnwrap(context.evaluator.evaluate(
            key: key,
            snapshot: tokenSnapshot(percent: 80),
            thresholds: .init()
        ).first)
        let body = alert.notificationBody()

        XCTAssertFalse(body.contains(secret))
        XCTAssertTrue(body.contains("未命名 Key"))
    }

    func test系统发送器安装并持有前台通知代理() async throws {
        let center = NotificationCenterSpy()
        weak var installedDelegate: AnyObject?

        do {
            let sender = UserNotificationSender(center: center)
            installedDelegate = center.delegate
            XCTAssertNotNil(installedDelegate)

            let context = makeContext()
            defer { context.cleanUp() }
            let alert = try XCTUnwrap(context.evaluator.evaluate(
                key: makeKey(),
                snapshot: tokenSnapshot(percent: 80),
                thresholds: .init()
            ).first)
            try await sender.send(alert)
            XCTAssertEqual(center.requests.count, 1)
            withExtendedLifetime(sender) {}
            XCTAssertNotNil(installedDelegate)
        }

        XCTAssertNil(installedDelegate)
    }

    func test系统授权撤回与恢复会在每次发送前重新查询() async throws {
        let center = NotificationCenterSpy(
            authorizationStatuses: [.denied, .authorized],
            authorizationRequestResult: false
        )
        let sender = AuthorizationCachingNotificationSender(
            sender: UserNotificationSender(center: center)
        )
        let context = makeContext()
        defer { context.cleanUp() }
        let manager = AlertManager(evaluator: context.evaluator, sender: sender)
        let key = makeKey()
        let snapshot = tokenSnapshot(percent: 80)

        _ = try await manager.evaluateAndNotify(
            key: key,
            snapshot: snapshot,
            notificationsEnabled: true
        )
        XCTAssertEqual(center.requests.count, 0)

        _ = try await manager.evaluateAndNotify(
            key: key,
            snapshot: snapshot,
            notificationsEnabled: true
        )

        XCTAssertEqual(center.settingsRequestCount, 2)
        XCTAssertEqual(center.authorizationRequestCount, 0)
        XCTAssertEqual(center.requests.count, 1)
    }

    func test系统授权未决定时才请求用户授权() async throws {
        let center = NotificationCenterSpy(
            authorizationStatuses: [.notDetermined],
            authorizationRequestResult: true
        )
        let sender = UserNotificationSender(center: center)

        let authorized = try await sender.requestAuthorization()

        XCTAssertTrue(authorized)
        XCTAssertEqual(center.settingsRequestCount, 1)
        XCTAssertEqual(center.authorizationRequestCount, 1)
    }

    func test前台通知展示策略包含横幅列表与声音() {
        XCTAssertEqual(
            ForegroundNotificationDelegate.presentationOptions,
            [.banner, .list, .sound]
        )
    }

    private func makeContext() -> AlertEvaluatorTestContext {
        let suiteName = "ai.routin.usage-monitor.alert-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AlertEvaluatorTestContext(
            suiteName: suiteName,
            defaults: defaults,
            evaluator: AlertEvaluator(defaults: defaults)
        )
    }

    private func makeKey() -> KeyConfiguration {
        KeyConfiguration(id: UUID(), name: "主账号", keySuffix: "abcd", sortOrder: 0)
    }

    private func periodicSnapshot(
        fiveHourPercent: Double,
        windowEnd: Date
    ) -> UsageSnapshot {
        periodicSnapshot(
            fiveHourPercent: fiveHourPercent,
            fiveHourWindowEnd: windowEnd,
            weeklyPercent: nil,
            weeklyWindowEnd: nil
        )
    }

    private func periodicSnapshot(
        fiveHourPercent: Double,
        fiveHourWindowEnd: Date,
        weeklyPercent: Double?,
        weeklyWindowEnd: Date?
    ) -> UsageSnapshot {
        UsageSnapshot(
            planName: "Pro",
            kind: .periodic,
            fiveHour: metric(percent: fiveHourPercent, windowEnd: fiveHourWindowEnd),
            weekly: weeklyPercent.map { metric(percent: $0, windowEnd: weeklyWindowEnd) },
            token: nil,
            allowedModels: [],
            fetchedAt: .now
        )
    }

    private func tokenSnapshot(percent: Double) -> UsageSnapshot {
        UsageSnapshot(
            planName: "资源包",
            kind: .tokenPack,
            fiveHour: nil,
            weekly: nil,
            token: metric(percent: percent, windowEnd: nil, unit: .token),
            allowedModels: [],
            fetchedAt: .now
        )
    }

    private func malformedTokenSnapshot(percent: Double) -> UsageSnapshot {
        UsageSnapshot(
            planName: "异常资源包",
            kind: .tokenPack,
            fiveHour: nil,
            weekly: nil,
            token: UsageMetric(
                used: 0,
                limit: 100,
                remaining: 100,
                percent: percent,
                unit: .token,
                windowEnd: nil
            ),
            allowedModels: [],
            fetchedAt: .now
        )
    }

    private func metric(
        percent: Double,
        windowEnd: Date?,
        unit: UsageUnit = .usd
    ) -> UsageMetric {
        UsageMetric(
            used: Decimal(percent),
            limit: 100,
            remaining: Decimal(100 - percent),
            percent: percent,
            unit: unit,
            windowEnd: windowEnd
        )
    }

    private func persistedWindowKeys(from defaults: UserDefaults) throws -> Set<AlertWindowKey> {
        let data = try XCTUnwrap(defaults.data(forKey: "usageAlertTriggeredWindows"))
        return try JSONDecoder().decode(Set<AlertWindowKey>.self, from: data)
    }

    private func markDelivered(_ alerts: [UsageAlert], evaluator: AlertEvaluator) {
        for alert in alerts {
            XCTAssertTrue(evaluator.beginDelivery(of: alert))
            evaluator.finishDelivery(of: alert)
        }
    }
}

extension AlertEvaluator {
    func evaluate(
        key: KeyConfiguration,
        snapshot: UsageSnapshot,
        thresholds: AlertThresholds
    ) -> [UsageAlert] {
        evaluate(
            key: key,
            snapshot: snapshot,
            rules: snapshot.normalizedMetrics.map { metric in
                .usedPercent(
                    metricID: metric.id,
                    isEnabled: true,
                    low: Decimal(thresholds.low),
                    high: Decimal(thresholds.high)
                )
            }
        )
    }
}

extension AlertManager {
    func evaluateAndNotify(
        key: KeyConfiguration,
        snapshot: UsageSnapshot,
        thresholds: AlertThresholds = .init(),
        notificationsEnabled: Bool,
        shouldDeliver: @escaping @Sendable () async -> Bool = { true }
    ) async throws -> [UsageAlert] {
        try await evaluateAndNotify(
            key: key,
            snapshot: snapshot,
            preferences: CredentialUsagePreferences(
                menuBarMetricID: nil,
                notificationsEnabled: true,
                alertRules: snapshot.normalizedMetrics.map { metric in
                    .usedPercent(
                        metricID: metric.id,
                        isEnabled: true,
                        low: Decimal(thresholds.low),
                        high: Decimal(thresholds.high)
                    )
                }
            ),
            applicationNotificationsEnabled: notificationsEnabled,
            shouldDeliver: shouldDeliver
        )
    }
}

private final class NotificationCenterSpy: UserNotificationCenterServing, @unchecked Sendable {
    weak var delegate: (any UNUserNotificationCenterDelegate)?
    private(set) var requests: [UNNotificationRequest] = []
    private(set) var settingsRequestCount = 0
    private(set) var authorizationRequestCount = 0
    private var authorizationStatuses: [UNAuthorizationStatus]
    private let authorizationRequestResult: Bool

    init(
        authorizationStatuses: [UNAuthorizationStatus] = [.authorized],
        authorizationRequestResult: Bool = true
    ) {
        self.authorizationStatuses = authorizationStatuses
        self.authorizationRequestResult = authorizationRequestResult
    }

    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        settingsRequestCount += 1
        return authorizationStatuses.removeFirst()
    }

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequestCount += 1
        return authorizationRequestResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
    }
}

private struct AlertEvaluatorTestContext {
    let suiteName: String
    let defaults: UserDefaults
    let evaluator: AlertEvaluator

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private actor NotificationSenderSpy: NotificationSending {
    private var authorizationResults: [Bool]
    private var sendFailureCount: Int
    private(set) var authorizationRequestCount = 0
    private(set) var sentAlerts: [UsageAlert] = []

    init(authorizationGranted: Bool) {
        authorizationResults = [authorizationGranted]
        sendFailureCount = 0
    }

    init(authorizationResults: [Bool], sendFailureCount: Int = 0) {
        self.authorizationResults = authorizationResults
        self.sendFailureCount = sendFailureCount
    }

    var state: (authorizationRequestCount: Int, sentAlerts: [UsageAlert]) {
        (authorizationRequestCount, sentAlerts)
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        return authorizationResults.removeFirst()
    }

    func send(_ alert: UsageAlert) async throws {
        if sendFailureCount > 0 {
            sendFailureCount -= 1
            throw NotificationSenderSpyError.发送失败
        }
        sentAlerts.append(alert)
    }
}

private enum NotificationSenderSpyError: Error, Equatable {
    case 发送失败
}

private actor ControlledAuthorizationSender: NotificationSending {
    private var authorizationRequestCount = 0
    private var authorizationContinuations: [CheckedContinuation<Bool, Never>] = []
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func waitUntilAuthorizationRequestCount(_ expectedCount: Int) async {
        guard authorizationRequestCount < expectedCount else {
            return
        }
        await withCheckedContinuation { continuation in
            requestWaiters.append((expectedCount, continuation))
        }
    }

    func resolveNextAuthorization(_ granted: Bool) {
        authorizationContinuations.removeFirst().resume(returning: granted)
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        let readyWaiters = requestWaiters.filter { authorizationRequestCount >= $0.count }
        requestWaiters.removeAll { authorizationRequestCount >= $0.count }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
        }
    }

    func send(_ alert: UsageAlert) async throws {}
}

private actor ControlledSendingSender: NotificationSending {
    private var sendCount = 0
    private var sendContinuations: [CheckedContinuation<Void, Never>] = []
    private var sendWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func waitUntilSendCount(_ expectedCount: Int) async {
        guard sendCount < expectedCount else {
            return
        }
        await withCheckedContinuation { continuation in
            sendWaiters.append((expectedCount, continuation))
        }
    }

    func resolveNextSend() {
        sendContinuations.removeFirst().resume()
    }

    func requestAuthorization() async throws -> Bool {
        true
    }

    func send(_ alert: UsageAlert) async throws {
        sendCount += 1
        let readyWaiters = sendWaiters.filter { sendCount >= $0.count }
        sendWaiters.removeAll { sendCount >= $0.count }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
        await withCheckedContinuation { continuation in
            sendContinuations.append(continuation)
        }
    }
}

private actor ControlledFailingSendingSender: NotificationSending {
    private var sendCount = 0
    private var sendContinuations: [CheckedContinuation<Void, Error>] = []
    private var sendWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func waitUntilSendCount(_ expectedCount: Int) async {
        guard sendCount < expectedCount else {
            return
        }
        await withCheckedContinuation { continuation in
            sendWaiters.append((expectedCount, continuation))
        }
    }

    func failNextSend() {
        sendContinuations.removeFirst().resume(throwing: NotificationSenderSpyError.发送失败)
    }

    func requestAuthorization() async throws -> Bool {
        true
    }

    func send(_ alert: UsageAlert) async throws {
        sendCount += 1
        let readyWaiters = sendWaiters.filter { sendCount >= $0.count }
        sendWaiters.removeAll { sendCount >= $0.count }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
        try await withCheckedThrowingContinuation { continuation in
            sendContinuations.append(continuation)
        }
    }
}
