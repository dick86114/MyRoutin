import Foundation
import XCTest
@testable import RoutinUsage

@MainActor
final class UsageStoreTests: XCTestCase {
    func test首次加载恢复缓存并按最后成功时间判断过期() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let key = try context.addKey(name: "主账号", secret: "plan-cache-0001")
        let cached = makeSnapshot(planName: "缓存版", fetchedAt: context.now.addingTimeInterval(-600))
        try context.cache.save(cached, for: key.id)

        let store = context.makeStore(refreshMinutes: 5)

        XCTAssertEqual(store.state(for: key.id)?.snapshot, cached)
        XCTAssertEqual(store.state(for: key.id)?.lastSuccessAt, cached.fetchedAt)
        XCTAssertTrue(store.state(for: key.id)?.isStale == true)
    }

    func test刷新设置变化不会把新鲜缓存的网络错误误标为过期() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let key = try context.addKey(name: "主账号", secret: "plan-settings-fresh-0001")
        let cached = makeSnapshot(planName: "缓存版", fetchedAt: context.now.addingTimeInterval(-30))
        try context.cache.save(cached, for: key.id)
        let store = context.makeStore(fetcher: ScriptedUsageFetcher(responses: [
            "plan-settings-fresh-0001": .failure(.transport)
        ]))

        await store.refresh(keyID: key.id)
        XCTAssertEqual(store.state(for: key.id)?.error, .network)
        XCTAssertFalse(store.state(for: key.id)?.isStale == true)

        store.updateSettings(
            refreshMinutes: 1,
            notificationsEnabled: true
        )

        XCTAssertFalse(store.state(for: key.id)?.isStale == true)
    }

    func test刷新全部时单个Key失败不阻塞其他Key() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let success = try context.addKey(name: "成功", secret: "plan-success-0001")
        let failure = try context.addKey(name: "失败", secret: "plan-failure-0002")
        let fresh = makeSnapshot(planName: "Pro", fetchedAt: context.now)
        let fetcher = ScriptedUsageFetcher(responses: [
            "plan-success-0001": .success(fresh),
            "plan-failure-0002": .failure(.transport)
        ])
        let store = context.makeStore(fetcher: fetcher)

        await store.refreshAll()

        XCTAssertEqual(store.state(for: success.id)?.snapshot?.planName, "Pro")
        XCTAssertEqual(store.state(for: failure.id)?.error, .network)
        XCTAssertFalse(store.isRefreshing)
    }

    func test首个Key失效后批量刷新跳过该Key但继续刷新其他Key() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let invalidKey = try context.addKey(name: "失效", secret: "plan-invalid-first-0001")
        let activeKey = try context.addKey(name: "正常", secret: "plan-active-second-0002")
        let fresh = makeSnapshot(planName: "Pro", fetchedAt: context.now)
        let fetcher = ScriptedUsageFetcher(responses: [
            "plan-invalid-first-0001": .failure(.invalidKey),
            "plan-active-second-0002": .success(fresh)
        ])
        let store = context.makeStore(fetcher: fetcher)

        await store.refreshAll()
        await store.refreshAll()

        let invalidRequestCount = await fetcher.requestCount(for: "plan-invalid-first-0001")
        let activeRequestCount = await fetcher.requestCount(for: "plan-active-second-0002")
        XCTAssertEqual(store.state(for: invalidKey.id)?.error, .invalidKey)
        XCTAssertEqual(store.state(for: activeKey.id)?.snapshot, fresh)
        XCTAssertEqual(invalidRequestCount, 1)
        XCTAssertEqual(activeRequestCount, 2)
    }

    func test禁用Key不显示不刷新() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let disabledKey = try context.addKey(name: "禁用", secret: "plan-disabled-0001")
        let enabledKey = try context.addKey(name: "启用", secret: "plan-enabled-0002")
        let fetcher = ScriptedUsageFetcher(responses: [
            "plan-disabled-0001": .success(makeSnapshot(planName: "禁用数据", fetchedAt: context.now)),
            "plan-enabled-0002": .success(makeSnapshot(planName: "启用数据", fetchedAt: context.now))
        ])
        let store = context.makeStore(fetcher: fetcher)

        try store.setKeyEnabled(disabledKey.id, enabled: false)
        await store.refreshAll()

        let disabledRequestCount = await fetcher.requestCount(for: "plan-disabled-0001")
        let enabledRequestCount = await fetcher.requestCount(for: "plan-enabled-0002")
        XCTAssertEqual(store.visibleKeyIDs, [enabledKey.id])
        XCTAssertEqual(disabledRequestCount, 0)
        XCTAssertEqual(enabledRequestCount, 1)
    }

    func test成功刷新覆盖缓存并只对成功快照发送通知() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let key = try context.addKey(name: "主账号", secret: "plan-success-0001")
        let failedKey = try context.addKey(name: "失败账号", secret: "plan-failure-0002")
        let emptyKey = try context.addKey(name: "空账号", secret: "plan-empty-0003")
        let cached = makeSnapshot(planName: "旧缓存", fetchedAt: context.now.addingTimeInterval(-600))
        let failedCache = makeSnapshot(
            planName: "失败缓存",
            percent: 96,
            fetchedAt: context.now.addingTimeInterval(-600)
        )
        let fresh = makeSnapshot(planName: "Pro", percent: 96, fetchedAt: context.now)
        try context.cache.save(cached, for: key.id)
        try context.cache.save(failedCache, for: failedKey.id)
        let fetcher = ScriptedUsageFetcher(responses: [
            "plan-success-0001": .success(fresh),
            "plan-failure-0002": .failure(.transport),
            "plan-empty-0003": .success(nil)
        ])
        let store = context.makeStore(
            fetcher: fetcher,
            notificationsEnabled: true
        )

        await store.refreshAll()

        XCTAssertEqual(try context.cache.load(for: key.id), fresh)
        XCTAssertEqual(store.state(for: key.id)?.snapshot, fresh)
        XCTAssertEqual(store.state(for: key.id)?.lastSuccessAt, context.now)
        XCTAssertFalse(store.state(for: key.id)?.isStale == true)
        let didSendAlert = await waitUntilAsync {
            await context.sender.sentAlerts().count == 1
        }
        XCTAssertTrue(didSendAlert)
        let alerts = await context.sender.sentAlerts()
        XCTAssertEqual(alerts.map(\.keyID), [key.id])
        XCTAssertEqual(store.state(for: failedKey.id)?.snapshot, failedCache)
        XCTAssertEqual(store.state(for: emptyKey.id)?.error, .noSubscription)
    }

    func test失败刷新保留仍新鲜的缓存但不标记为过期() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let key = try context.addKey(name: "主账号", secret: "plan-offline-0001")
        let cached = makeSnapshot(planName: "缓存版", fetchedAt: context.now.addingTimeInterval(-30))
        try context.cache.save(cached, for: key.id)
        let fetcher = ScriptedUsageFetcher(responses: ["plan-offline-0001": .failure(.transport)])
        let store = context.makeStore(fetcher: fetcher)

        await store.refresh(keyID: key.id)

        XCTAssertEqual(store.state(for: key.id)?.snapshot, cached)
        XCTAssertEqual(try context.cache.load(for: key.id), cached)
        XCTAssertEqual(store.state(for: key.id)?.error, .network)
        XCTAssertFalse(store.state(for: key.id)?.isStale == true)
    }

    func test失败刷新保留过期缓存并标记为过期() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let key = try context.addKey(name: "主账号", secret: "plan-offline-stale-0001")
        let cached = makeSnapshot(planName: "缓存版", fetchedAt: context.now.addingTimeInterval(-600))
        try context.cache.save(cached, for: key.id)
        let fetcher = ScriptedUsageFetcher(responses: [
            "plan-offline-stale-0001": .failure(.transport)
        ])
        let store = context.makeStore(fetcher: fetcher)

        await store.refresh(keyID: key.id)

        XCTAssertEqual(store.state(for: key.id)?.snapshot, cached)
        XCTAssertEqual(store.state(for: key.id)?.error, .network)
        XCTAssertTrue(store.state(for: key.id)?.isStale == true)
    }

    func test空响应显示无可用订阅() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let key = try context.addKey(name: "主账号", secret: "plan-empty-0001")
        let fetcher = ScriptedUsageFetcher(responses: ["plan-empty-0001": .success(nil)])
        let store = context.makeStore(fetcher: fetcher)

        await store.refresh(keyID: key.id)

        XCTAssertNil(store.state(for: key.id)?.snapshot)
        XCTAssertEqual(store.state(for: key.id)?.error, .noSubscription)
        XCTAssertEqual(store.state(for: key.id)?.lastSuccessAt, context.now)
        XCTAssertFalse(store.state(for: key.id)?.isStale == true)
    }

    func test未授权响应显示Key无效且不泄露密钥() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let secret = "plan-sensitive-value"
        let key = try context.addKey(name: "主账号", secret: secret)
        let fetcher = ScriptedUsageFetcher(responses: [secret: .failure(.server(statusCode: 401))])
        let store = context.makeStore(fetcher: fetcher)

        await store.refresh(keyID: key.id)

        XCTAssertEqual(store.state(for: key.id)?.error, .invalidKey)
        XCTAssertFalse(String(describing: store.state(for: key.id)).contains(secret))
    }

    func test重复刷新同一Key只创建一个请求() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let secret = "plan-controlled-0001"
        let key = try context.addKey(name: "主账号", secret: secret)
        let fetcher = ScriptedUsageFetcher(responses: [secret: .suspended])
        let store = context.makeStore(fetcher: fetcher)

        let first = Task { await store.refresh(keyID: key.id) }
        await fetcher.waitUntilRequested(secret)
        await store.refresh(keyID: key.id)

        let requestCount = await fetcher.requestCount(for: secret)
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(store.state(for: key.id)?.isRefreshing == true)
        await fetcher.resume(secret, with: .success(makeSnapshot(planName: "Pro", fetchedAt: context.now)))
        await first.value
        XCTAssertFalse(store.state(for: key.id)?.isRefreshing == true)
    }

    func test取消刷新只清理刷新标记并保留缓存状态() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let secret = "plan-cancelled-0001"
        let key = try context.addKey(name: "主账号", secret: secret)
        let cached = makeSnapshot(planName: "缓存版", fetchedAt: context.now.addingTimeInterval(-60))
        try context.cache.save(cached, for: key.id)
        let fetcher = CancellationAwareUsageFetcher()
        let store = context.makeStore(fetcher: fetcher)

        let refresh = Task { await store.refresh(keyID: key.id) }
        await fetcher.waitUntilRequested(secret)
        refresh.cancel()
        await refresh.value

        XCTAssertEqual(store.state(for: key.id)?.snapshot, cached)
        XCTAssertNil(store.state(for: key.id)?.error)
        XCTAssertFalse(store.state(for: key.id)?.isRefreshing == true)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(try context.cache.load(for: key.id), cached)
    }

    func test已有网络错误时取消下一次刷新会完整保留旧状态() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let secret = "plan-cancelled-preserves-error-0001"
        let key = try context.addKey(name: "主账号", secret: secret)
        let cached = makeSnapshot(planName: "缓存版", fetchedAt: context.now.addingTimeInterval(-60))
        try context.cache.save(cached, for: key.id)
        let fetcher = CancellationAwareUsageFetcher(initialFailureCount: 1)
        let store = context.makeStore(fetcher: fetcher)

        await store.refresh(keyID: key.id)
        XCTAssertEqual(store.state(for: key.id)?.error, .network)

        let refresh = Task { await store.refresh(keyID: key.id) }
        await fetcher.waitUntilRequested(secret, count: 2)
        refresh.cancel()
        await refresh.value

        XCTAssertEqual(store.state(for: key.id)?.snapshot, cached)
        XCTAssertEqual(store.state(for: key.id)?.lastSuccessAt, cached.fetchedAt)
        XCTAssertEqual(store.state(for: key.id)?.error, .network)
        XCTAssertFalse(store.state(for: key.id)?.isStale == true)
        XCTAssertFalse(store.state(for: key.id)?.isRefreshing == true)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(try context.cache.load(for: key.id), cached)
    }

    func test取消后Fetcher忽略取消并返回成功时不合并结果() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let secret = "plan-cancelled-success-0001"
        let key = try context.addKey(name: "主账号", secret: secret)
        let cached = makeSnapshot(planName: "缓存版", fetchedAt: context.now.addingTimeInterval(-60))
        let unexpected = makeSnapshot(planName: "不应合并", fetchedAt: context.now)
        try context.cache.save(cached, for: key.id)
        let fetcher = ScriptedUsageFetcher(responses: [secret: .suspended])
        let store = context.makeStore(fetcher: fetcher)

        let refresh = Task { await store.refresh(keyID: key.id) }
        await fetcher.waitUntilRequested(secret)
        refresh.cancel()
        await fetcher.resume(secret, with: .success(unexpected))
        await refresh.value

        XCTAssertEqual(store.state(for: key.id)?.snapshot, cached)
        XCTAssertNil(store.state(for: key.id)?.error)
        XCTAssertFalse(store.state(for: key.id)?.isRefreshing == true)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(try context.cache.load(for: key.id), cached)
    }

    func test取消后Fetcher忽略取消并返回业务错误时不合并结果() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let secret = "plan-cancelled-failure-0001"
        let key = try context.addKey(name: "主账号", secret: secret)
        let cached = makeSnapshot(planName: "缓存版", fetchedAt: context.now.addingTimeInterval(-60))
        try context.cache.save(cached, for: key.id)
        let fetcher = ScriptedUsageFetcher(responses: [secret: .suspended])
        let store = context.makeStore(fetcher: fetcher)

        let refresh = Task { await store.refresh(keyID: key.id) }
        await fetcher.waitUntilRequested(secret)
        refresh.cancel()
        await fetcher.resume(secret, with: .failure(.transport))
        await refresh.value

        XCTAssertEqual(store.state(for: key.id)?.snapshot, cached)
        XCTAssertNil(store.state(for: key.id)?.error)
        XCTAssertFalse(store.state(for: key.id)?.isRefreshing == true)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(try context.cache.load(for: key.id), cached)
    }

    func test通知发送挂起时其他Key仍及时发布刷新结果() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let blockedSecret = "plan-notification-blocked-0001"
        let otherSecret = "plan-notification-other-0002"
        let blockedKey = try context.addKey(name: "通知挂起", secret: blockedSecret)
        let otherKey = try context.addKey(name: "正常账号", secret: otherSecret)
        let blockedSnapshot = makeSnapshot(planName: "高用量", percent: 96, fetchedAt: context.now)
        let otherSnapshot = makeSnapshot(planName: "普通用量", fetchedAt: context.now)
        let fetcher = ScriptedUsageFetcher(responses: [
            blockedSecret: .success(blockedSnapshot),
            otherSecret: .suspended
        ])
        let sender = BlockingNotificationSender(blockedKeyID: blockedKey.id)
        let store = context.makeStore(
            fetcher: fetcher,
            notificationSender: sender,
            notificationsEnabled: true
        )

        let refresh = Task { await store.refreshAll() }
        await fetcher.waitUntilRequested(otherSecret)
        let releaseOtherRequest = Task { @MainActor in
            while true {
                let notificationStarted = await sender.isSending(keyID: blockedKey.id)
                let blockedResultPublished = store.state(for: blockedKey.id)?.snapshot == blockedSnapshot
                    && store.state(for: blockedKey.id)?.isRefreshing == false
                if notificationStarted || blockedResultPublished {
                    await fetcher.resume(otherSecret, with: .success(otherSnapshot))
                    return
                }
                await Task.yield()
            }
        }
        await sender.waitUntilSending(keyID: blockedKey.id)
        await releaseOtherRequest.value

        let didPublishOtherKey = await waitUntil {
            store.state(for: otherKey.id)?.snapshot == otherSnapshot
        }
        XCTAssertTrue(didPublishOtherKey)
        XCTAssertFalse(store.state(for: otherKey.id)?.isRefreshing == true)
        XCTAssertFalse(store.isRefreshing)

        await sender.resume(keyID: blockedKey.id)
        await refresh.value
    }

    func test刷新成功时生成默认规则并按规则发送通知() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let key = try context.addKey(name: "主账号", secret: "plan-rules-0001")
        let snapshot = makeSnapshot(planName: "高用量", percent: 96, fetchedAt: context.now)
        let fetcher = ScriptedUsageFetcher(responses: [
            "plan-rules-0001": .success(snapshot)
        ])
        let storedPreferences = UsagePreferenceStore()
        let store = context.makeStore(
            fetcher: fetcher,
            notificationsEnabled: true,
            usagePreferences: { _ in .defaultValue },
            setUsagePreferences: { preferences, keyID in
                storedPreferences.preferences[keyID] = preferences
            },
            metricCapabilities: { _ in [] }
        )

        await store.refreshAll()

        _ = await waitUntilAsync {
            await !(context.sender.sentAlerts().isEmpty)
        }
        let alerts = await context.sender.sentAlerts()
        XCTAssertEqual(alerts.first?.metricID, "token")
        XCTAssertEqual(alerts.first?.level, .high)
        let preferences = try XCTUnwrap(storedPreferences.preferences[key.id])
        XCTAssertTrue(preferences.notificationsEnabled)
        XCTAssertTrue(preferences.alertRules.contains { $0.metricID == "token" })
    }

    func test刷新全部提交状态后不等待通知授权完成() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let secret = "plan-refresh-notification-0001"
        let key = try context.addKey(name: "主账号", secret: secret)
        let snapshot = makeSnapshot(planName: "高用量", percent: 96, fetchedAt: context.now)
        let sender = BlockingAuthorizationNotificationSender()
        let store = context.makeStore(
            fetcher: ScriptedUsageFetcher(responses: [secret: .success(snapshot)]),
            notificationSender: sender,
            notificationsEnabled: true
        )
        var didReturn = false

        let refresh = Task { @MainActor in
            await store.refreshAll()
            didReturn = true
        }
        await sender.waitUntilAuthorizationRequested()

        let returnedBeforeAuthorization = await waitUntil { didReturn }
        XCTAssertTrue(returnedBeforeAuthorization)
        XCTAssertEqual(store.state(for: key.id)?.snapshot, snapshot)
        XCTAssertFalse(store.isRefreshing)

        await sender.resolveAuthorization(true)
        await refresh.value
    }

    func test新增Key落库发布后不等待通知授权完成() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let secret = "plan-add-notification-0001"
        let snapshot = makeSnapshot(planName: "高用量", percent: 96, fetchedAt: context.now)
        let sender = BlockingAuthorizationNotificationSender()
        let store = context.makeStore(
            fetcher: ScriptedUsageFetcher(responses: [secret: .success(snapshot)]),
            notificationSender: sender,
            notificationsEnabled: true
        )
        var result: Result<Void, Error>?

        let addition = Task { @MainActor in
            do {
                try await store.addValidatedKey(name: "新账号", secret: secret)
                result = .success(())
            } catch {
                result = .failure(error)
            }
        }
        await sender.waitUntilAuthorizationRequested()

        let returnedBeforeAuthorization = await waitUntil { result != nil }
        XCTAssertTrue(returnedBeforeAuthorization)
        let saved = try XCTUnwrap(context.repository.list().first)
        XCTAssertEqual(store.state(for: saved.id)?.snapshot, snapshot)
        XCTAssertEqual(try context.cache.load(for: saved.id), snapshot)

        await sender.resolveAuthorization(true)
        await addition.value
        _ = try result?.get()
    }

    func test旧代际通知授权完成时不会发送已过时高用量提醒() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let secret = "plan-generation-notification-0001"
        let key = try context.addKey(name: "主账号", secret: secret)
        let highSnapshot = makeSnapshot(planName: "高用量", percent: 96, fetchedAt: context.now)
        let lowSnapshot = makeSnapshot(planName: "低用量", percent: 20, fetchedAt: context.now)
        let fetcher = ScriptedUsageFetcher(responses: [secret: .success(highSnapshot)])
        let sender = BlockingAuthorizationNotificationSender()
        let store = context.makeStore(
            fetcher: fetcher,
            notificationSender: sender,
            notificationsEnabled: true
        )

        await store.refresh(keyID: key.id)
        await sender.waitUntilAuthorizationRequested()
        await fetcher.setResponse(.success(lowSnapshot), for: secret)
        await store.refresh(keyID: key.id)
        await sender.resolveAuthorization(true)
        for _ in 0..<100 {
            await Task.yield()
        }

        let sentAlerts = await sender.sentAlerts()
        XCTAssertEqual(sentAlerts, [])
        XCTAssertEqual(store.state(for: key.id)?.snapshot, lowSnapshot)
        XCTAssertEqual(
            context.evaluator.evaluate(
                key: key,
                snapshot: highSnapshot,
                thresholds: .init()
            ).map(\.level),
            [.high]
        )
    }

    func test等待其他网络结果期间删除Key会丢弃其延迟通知() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let deletedSecret = "plan-notification-deleted-0001"
        let pendingSecret = "plan-notification-pending-0002"
        let deletedKey = try context.addKey(name: "即将删除", secret: deletedSecret)
        _ = try context.addKey(name: "等待账号", secret: pendingSecret)
        let highUsage = makeSnapshot(planName: "高用量", percent: 96, fetchedAt: context.now)
        let ordinaryUsage = makeSnapshot(planName: "普通用量", fetchedAt: context.now)
        let fetcher = ScriptedUsageFetcher(responses: [
            deletedSecret: .success(highUsage),
            pendingSecret: .suspended
        ])
        let store = context.makeStore(fetcher: fetcher, notificationsEnabled: true)

        let refresh = Task { await store.refreshAll() }
        await fetcher.waitUntilRequested(pendingSecret)
        let didPublishDeletedKey = await waitUntil {
            store.state(for: deletedKey.id)?.snapshot == highUsage
                && store.state(for: deletedKey.id)?.isRefreshing == false
        }
        XCTAssertTrue(didPublishDeletedKey)
        try store.deleteKey(deletedKey.id)
        await fetcher.resume(pendingSecret, with: .success(ordinaryUsage))
        await refresh.value

        let alerts = await context.sender.sentAlerts()
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertEqual(
            context.evaluator.evaluate(
                key: deletedKey,
                snapshot: highUsage,
                thresholds: .init()
            ).map(\.level),
            [.high]
        )
    }

    func test删除Key同步清除配置密钥缓存和通知状态() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let secret = "plan-delete-0001"
        let key = try context.addKey(name: "待删除", secret: secret)
        let snapshot = makeSnapshot(planName: "Pro", percent: 96, fetchedAt: context.now)
        try context.cache.save(snapshot, for: key.id)
        let fetcher = ScriptedUsageFetcher(responses: [secret: .success(snapshot)])
        let store = context.makeStore(fetcher: fetcher, notificationsEnabled: true)
        await store.refresh(keyID: key.id)
        let didSendAlert = await waitUntilAsync {
            await context.sender.sentAlerts().count == 1
        }
        XCTAssertTrue(didSendAlert)
        XCTAssertTrue(context.evaluator.evaluate(
            key: key,
            snapshot: snapshot,
            rules: context.evaluationRules
        ).isEmpty)

        try store.deleteKey(key.id)

        XCTAssertTrue(context.repository.list().isEmpty)
        XCTAssertNil(try context.keychain.read(for: key.id))
        XCTAssertNil(try context.cache.load(for: key.id))
        XCTAssertNil(store.state(for: key.id))
        XCTAssertEqual(
            context.evaluator.evaluate(key: key, snapshot: snapshot, rules: context.evaluationRules).map(\.level),
            [.high]
        )
    }

    func test缓存清理失败时仍收敛已删除Key的内存和通知状态() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let secret = "plan-delete-failure-0001"
        let key = try context.addKey(name: "待删除", secret: secret)
        let snapshot = makeSnapshot(planName: "Pro", percent: 96, fetchedAt: context.now)
        let failingCache = DeleteFailingUsageCache(snapshots: [key.id: snapshot])
        let fetcher = ScriptedUsageFetcher(responses: [secret: .success(snapshot)])
        let store = context.makeStore(
            fetcher: fetcher,
            cache: failingCache,
            notificationsEnabled: true
        )
        await store.refresh(keyID: key.id)

        XCTAssertThrowsError(try store.deleteKey(key.id)) { error in
            XCTAssertEqual(error as? UsageStoreError, .cacheCleanupFailed)
        }

        XCTAssertTrue(context.repository.list().isEmpty)
        XCTAssertNil(try context.keychain.read(for: key.id))
        XCTAssertNil(store.state(for: key.id))
        XCTAssertEqual(
            context.evaluator.evaluate(key: key, snapshot: snapshot, thresholds: .init()).map(\.level),
            [.high]
        )
    }

    func test仓储更新配置后刷新会发布最新元数据() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let key = try context.addKey(name: "旧名称", secret: "plan-old-0001")
        let snapshot = makeSnapshot(planName: "Pro", fetchedAt: context.now)
        let fetcher = ScriptedUsageFetcher(responses: ["plan-new-9999": .success(snapshot)])
        let store = context.makeStore(fetcher: fetcher)
        let updated = try context.repository.update(
            id: key.id,
            name: "新名称",
            secret: "plan-new-9999"
        )

        await store.refresh(keyID: key.id)

        XCTAssertEqual(store.state(for: key.id)?.configuration, updated)
    }

    func test密钥更新发生在刷新挂起期间时丢弃旧密钥结果() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let oldSecret = "plan-old-credential-0001"
        let newSecret = "plan-new-credential-9999"
        let key = try context.addKey(name: "旧名称", secret: oldSecret)
        let staleSnapshot = makeSnapshot(planName: "旧密钥结果", percent: 96, fetchedAt: context.now)
        let freshSnapshot = makeSnapshot(planName: "新密钥结果", fetchedAt: context.now)
        let fetcher = ScriptedUsageFetcher(responses: [
            oldSecret: .suspended,
            newSecret: .success(freshSnapshot)
        ])
        let store = context.makeStore(fetcher: fetcher, notificationsEnabled: true)

        let oldRefresh = Task { await store.refresh(keyID: key.id) }
        await fetcher.waitUntilRequested(oldSecret)
        let updated = try context.repository.update(
            id: key.id,
            name: "新名称",
            secret: newSecret
        )
        await store.refresh(keyID: key.id)
        await fetcher.resume(oldSecret, with: .success(staleSnapshot))
        await oldRefresh.value

        XCTAssertEqual(store.state(for: key.id)?.configuration, updated)
        XCTAssertNil(store.state(for: key.id)?.snapshot)
        XCTAssertNil(try context.cache.load(for: key.id))
        let alerts = await context.sender.sentAlerts()
        XCTAssertTrue(alerts.isEmpty)

        await store.refresh(keyID: key.id)
        XCTAssertEqual(store.state(for: key.id)?.snapshot, freshSnapshot)
    }

    func test新增Key验证失败时不会保存配置或密钥() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let secret = "plan-rejected-0001"
        let fetcher = ScriptedUsageFetcher(responses: [secret: .failure(.invalidKey)])
        let store = context.makeStore(fetcher: fetcher)

        await XCTAssert抛出Store错误(.invalidKey) {
            try await store.addValidatedKey(name: "新账号", secret: secret)
        }

        XCTAssertTrue(context.repository.list().isEmpty)
        let requestCount = await fetcher.requestCount(for: secret)
        XCTAssertEqual(requestCount, 1)
        XCTAssertFalse(context.keychain.contains(secret: secret))
    }

    func test取消新增Key验证时保留CancellationError且不保存() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let secret = "plan-validation-cancelled-0001"
        let fetcher = CancellationAwareUsageFetcher()
        let store = context.makeStore(fetcher: fetcher)

        let validation = Task {
            try await store.addValidatedKey(name: "新账号", secret: secret)
        }
        await fetcher.waitUntilRequested(secret)
        validation.cancel()

        do {
            try await validation.value
            XCTFail("预期抛出 CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(context.repository.list().isEmpty)
        XCTAssertFalse(context.keychain.contains(secret: secret))
    }

    func test新增Key验证成功后才保存并发布状态() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let secret = "plan-new-0001"
        let snapshot = makeSnapshot(planName: "Pro", fetchedAt: context.now)
        let fetcher = ScriptedUsageFetcher(responses: [secret: .success(snapshot)])
        let store = context.makeStore(fetcher: fetcher)

        try await store.addValidatedKey(name: " 新账号 ", secret: secret)

        let saved = try XCTUnwrap(context.repository.list().first)
        XCTAssertEqual(saved.name, "新账号")
        XCTAssertEqual(store.state(for: saved.id)?.snapshot, snapshot)
        XCTAssertEqual(try context.cache.load(for: saved.id), snapshot)
        let requestCount = await fetcher.requestCount(for: secret)
        XCTAssertEqual(requestCount, 1)
    }
}

private extension UsageStoreTests {
    func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }

    func waitUntilAsync(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        return await condition()
    }

    func makeContext() throws -> UsageStoreTestContext {
        let suiteName = "ai.routin.usage-monitor.store-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let keychain = StoreKeychainFake()
        return UsageStoreTestContext(
            suiteName: suiteName,
            defaults: defaults,
            keychain: keychain,
            repository: KeyRepository(defaults: defaults, localStore: keychain),
            cache: InMemoryUsageCache(),
            evaluator: AlertEvaluator(defaults: defaults),
            sender: NotificationSenderFake(),
            now: Date(timeIntervalSince1970: 10_000)
        )
    }

    func makeSnapshot(
        planName: String,
        percent: Double = 25,
        fetchedAt: Date
    ) -> UsageSnapshot {
        UsageSnapshot(
            planName: planName,
            kind: .tokenPack,
            fiveHour: nil,
            weekly: nil,
            token: UsageMetric(
                used: Decimal(percent),
                limit: 100,
                remaining: Decimal(100 - percent),
                percent: percent,
                unit: .token,
                windowEnd: nil
            ),
            allowedModels: ["gpt-5"],
            fetchedAt: fetchedAt
        )
    }
}

private struct UsageStoreTestContext {
    let suiteName: String
    let defaults: UserDefaults
    let keychain: StoreKeychainFake
    let repository: KeyRepository
    let cache: InMemoryUsageCache
    let evaluator: AlertEvaluator
    let sender: NotificationSenderFake
    let now: Date
    let evaluationRules = [
        MetricAlertRule.usedPercent(
            metricID: "token",
            isEnabled: true,
            low: 80,
            high: 95
        )
    ]

    func addKey(name: String, secret: String) throws -> KeyConfiguration {
        try repository.add(name: name, secret: secret)
    }

    @MainActor
    func makeStore(
        fetcher: any UsageFetching = ScriptedUsageFetcher(responses: [:]),
        cache customCache: (any UsageCaching)? = nil,
        notificationSender: (any NotificationSending)? = nil,
        refreshMinutes: Int = 5,
        notificationsEnabled: Bool = false,
        usagePreferences: @escaping @MainActor @Sendable (UUID) -> CredentialUsagePreferences = { _ in .defaultValue },
        setUsagePreferences: @escaping @MainActor @Sendable (CredentialUsagePreferences, UUID) -> Void = { _, _ in },
        metricCapabilities: @escaping @MainActor @Sendable (KeyConfiguration) -> [UsageMetricCapability] = { _ in [] }
    ) -> UsageStore {
        let currentTime = now
        return UsageStore(
            keyRepository: repository,
            localStore: keychain,
            apiClient: fetcher,
            cache: customCache ?? cache,
            alertEvaluator: evaluator,
            notificationSender: notificationSender ?? sender,
            defaults: defaults,
            refreshMinutes: refreshMinutes,
            notificationsEnabled: notificationsEnabled,
            usagePreferencesProvider: usagePreferences,
            setUsagePreferencesHandler: setUsagePreferences,
            metricCapabilitiesProvider: metricCapabilities,
            now: { currentTime }
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

final class UsagePreferenceStore {
    var preferences: [UUID: CredentialUsagePreferences] = [:]
}

private final class StoreKeychainFake: LocalKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [UUID: String] = [:]

    func save(_ secret: String, for id: UUID) throws {
        lock.withLock { secrets[id] = secret }
    }

    func read(for id: UUID) throws -> String? {
        lock.withLock { secrets[id] }
    }

    func delete(for id: UUID) throws {
        _ = lock.withLock { secrets.removeValue(forKey: id) }
    }

    func contains(secret: String) -> Bool {
        lock.withLock { secrets.values.contains(secret) }
    }
}

@MainActor
private func XCTAssert抛出Store错误(
    _ expected: UsageStoreError,
    operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("预期抛出 UsageStore 错误", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? UsageStoreError, expected, file: file, line: line)
    }
}
