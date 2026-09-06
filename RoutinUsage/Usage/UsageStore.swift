import CryptoKit
import Foundation
import Observation

enum UsageDisplayError: Equatable, Sendable {
    case noSubscription
    case invalidKey
    case network
    case invalidResponse
    case server(statusCode: Int)
}

enum UsageStoreError: Error, Equatable, Sendable {
    case invalidName
    case invalidSecret
    case invalidURL
    case invalidKey
    case network
    case invalidResponse
    case server(statusCode: Int)
    case persistence
    case cacheCleanupFailed
}

extension UsageStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "请输入凭证名称"
        case .invalidSecret:
            return "凭证内容无效"
        case .invalidURL:
            return "官网链接无效"
        case .invalidKey:
            return "凭证无效"
        case .network:
            return "网络连接失败，请检查网络后重试"
        case .invalidResponse:
            return "供应商返回的数据无法识别"
        case .server(let statusCode):
            return "服务暂时不可用（HTTP \(statusCode)）"
        case .persistence:
            return "保存失败，请稍后重试"
        case .cacheCleanupFailed:
            return "凭证已删除，但用量缓存未能清理"
        }
    }
}

struct KeyUsageState: Equatable, Sendable {
    var configuration: KeyConfiguration
    var snapshot: UsageSnapshot?
    var lastSuccessAt: Date?
    var isRefreshing: Bool
    var isStale: Bool
    var error: UsageDisplayError?
}

@MainActor
@Observable
final class UsageStore {
    private(set) var states: [UUID: KeyUsageState] = [:]
    private(set) var orderedKeyIDs: [UUID] = []
    private(set) var isRefreshing = false

    var visibleKeyIDs: [UUID] {
        orderedKeyIDs.filter { states[$0]?.configuration.isEnabled == true }
    }

    @ObservationIgnored private let keyRepository: KeyRepository
    @ObservationIgnored private let localStore: any SecureCredentialStoring
    @ObservationIgnored private let apiClient: any UsageFetching
    @ObservationIgnored private let providerRegistry: ProviderRegistry?
    @ObservationIgnored private let cache: any UsageCaching
    @ObservationIgnored private let alertEvaluator: AlertEvaluator
    @ObservationIgnored private let notificationSender: any NotificationSending
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var refreshMinutes: Int
    @ObservationIgnored private var notificationsEnabled: Bool
    @ObservationIgnored private let usagePreferencesProvider: @MainActor @Sendable (UUID) -> CredentialUsagePreferences
    @ObservationIgnored private let setUsagePreferencesHandler: @MainActor @Sendable (CredentialUsagePreferences, UUID) -> Void
    @ObservationIgnored private let metricCapabilitiesProvider: @MainActor @Sendable (KeyConfiguration) -> [UsageMetricCapability]
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var refreshingKeyIDs: Set<UUID> = []
    @ObservationIgnored private var refreshGenerationByKeyID: [UUID: UUID] = [:]
    @ObservationIgnored private var invalidKeyFingerprintsByKeyID: [UUID: CredentialFingerprint] = [:]

    init(
        keyRepository: KeyRepository,
        localStore: any SecureCredentialStoring,
        apiClient: any UsageFetching,
        cache: any UsageCaching,
        alertEvaluator: AlertEvaluator,
        notificationSender: any NotificationSending,
        defaults: UserDefaults = .standard,
        refreshMinutes: Int = 5,
        notificationsEnabled: Bool = true,
        usagePreferencesProvider: @escaping @MainActor @Sendable (UUID) -> CredentialUsagePreferences = { _ in .defaultValue },
        setUsagePreferencesHandler: @escaping @MainActor @Sendable (CredentialUsagePreferences, UUID) -> Void = { _, _ in },
        metricCapabilitiesProvider: @escaping @MainActor @Sendable (KeyConfiguration) -> [UsageMetricCapability] = { _ in [] },
        providerRegistry: ProviderRegistry? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.keyRepository = keyRepository
        self.localStore = localStore
        self.apiClient = apiClient
        self.providerRegistry = providerRegistry
        self.cache = cache
        self.alertEvaluator = alertEvaluator
        self.notificationSender = notificationSender
        self.defaults = defaults
        self.refreshMinutes = refreshMinutes
        self.notificationsEnabled = notificationsEnabled
        self.usagePreferencesProvider = usagePreferencesProvider
        self.setUsagePreferencesHandler = setUsagePreferencesHandler
        self.metricCapabilitiesProvider = metricCapabilitiesProvider
        self.now = now

        restoreState()
    }

    func state(for keyID: UUID) -> KeyUsageState? {
        states[keyID]
    }

    func refreshAll() async {
        synchronizeConfigurations()
        let requests: [RefreshRequest] = visibleKeyIDs.compactMap { keyID -> RefreshRequest? in
            guard !shouldSkipBatchRefresh(for: keyID) else {
                return nil
            }
            return prepareRefreshRequest(for: keyID)
        }
        await perform(requests)
    }

    func refresh(keyID: UUID) async {
        synchronizeConfigurations()
        guard let request = prepareRefreshRequest(for: keyID) else {
            return
        }
        await perform([request])
    }

    func updateSettings(
        refreshMinutes: Int,
        notificationsEnabled: Bool
    ) {
        self.refreshMinutes = refreshMinutes
        self.notificationsEnabled = notificationsEnabled
        let currentTime = now()
        for keyID in states.keys {
            guard var state = states[keyID] else {
                continue
            }
            state.isStale = state.snapshot != nil && state.lastSuccessAt.map {
                UsageFreshness.isStale(
                    lastSuccess: $0,
                    now: currentTime,
                    refreshMinutes: refreshMinutes
                )
            } == true
            states[keyID] = state
        }
    }

    func reloadConfigurations() {
        synchronizeConfigurations()
    }

    func applyValidatedSnapshot(
        _ snapshot: UsageSnapshot?,
        for keyID: UUID,
        validatedAt: Date
    ) async {
        synchronizeConfigurations()
        guard var state = states[keyID] else {
            return
        }
        refreshGenerationByKeyID[keyID] = UUID()
        invalidKeyFingerprintsByKeyID.removeValue(forKey: keyID)
        state.snapshot = snapshot
        state.lastSuccessAt = snapshot?.fetchedAt ?? validatedAt
        state.isRefreshing = refreshingKeyIDs.contains(keyID)
        state.isStale = false
        state.error = snapshot == nil ? .noSubscription : nil
        states[keyID] = state

        if let snapshot {
            try? cache.save(snapshot, for: keyID)
            var preferences = usagePreferencesProvider(keyID)
            preferences = MetricAlertRuleResolver.reconcile(
                existing: preferences,
                metrics: snapshot.normalizedMetrics,
                capabilities: metricCapabilitiesProvider(state.configuration),
                legacyThresholds: .init()
            )
            setUsagePreferencesHandler(preferences, keyID)
            scheduleNotification(NotificationWork(
                keyID: keyID,
                refreshGeneration: refreshGenerationByKeyID[keyID]!,
                configuration: state.configuration,
                snapshot: snapshot,
                usagePreferences: preferences
            ))
        } else {
            try? cache.delete(for: keyID)
        }
    }

    func setKeyEnabled(_ id: UUID, enabled: Bool) throws {
        do {
            _ = try keyRepository.setEnabled(id: id, enabled: enabled)
        } catch {
            throw Self.storeError(from: error)
        }
        synchronizeConfigurations()
    }

    func addValidatedKey(name: String, secret: String) async throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw UsageStoreError.invalidName
        }
        guard KeyCredentialPolicy.isSafeDisplayName(normalizedName) else {
            throw UsageStoreError.invalidName
        }
        guard
            KeyCredentialPolicy.hasValidPrefix(secret),
            KeyCredentialPolicy.hasSufficientSecretPayload(secret)
        else {
            throw UsageStoreError.invalidSecret
        }

        let validationTime = now()
        let result: UsageSnapshot?
        do {
            result = try await apiClient.fetchUsage(apiKey: secret, now: validationTime)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw Self.storeError(from: error)
        }

        let configuration: KeyConfiguration
        do {
            configuration = try keyRepository.add(name: normalizedName, secret: secret)
        } catch {
            throw Self.storeError(from: error)
        }

        orderedKeyIDs.append(configuration.id)
        states[configuration.id] = KeyUsageState(
            configuration: configuration,
            snapshot: result,
            lastSuccessAt: result?.fetchedAt ?? validationTime,
            isRefreshing: false,
            isStale: false,
            error: result == nil ? .noSubscription : nil
        )
        if let result {
            try? cache.save(result, for: configuration.id)
            let refreshGeneration = UUID()
            refreshGenerationByKeyID[configuration.id] = refreshGeneration
            var preferences = usagePreferencesProvider(configuration.id)
            preferences = MetricAlertRuleResolver.reconcile(
                existing: preferences,
                metrics: result.normalizedMetrics,
                capabilities: metricCapabilitiesProvider(configuration),
                legacyThresholds: .init()
            )
            setUsagePreferencesHandler(preferences, configuration.id)
            scheduleNotification(NotificationWork(
                keyID: configuration.id,
                refreshGeneration: refreshGeneration,
                configuration: configuration,
                snapshot: result,
                usagePreferences: preferences
            ))
        } else {
            try? cache.delete(for: configuration.id)
        }
    }

    func deleteKey(_ id: UUID) throws {
        do {
            try keyRepository.delete(id: id)
        } catch {
            throw Self.storeError(from: error)
        }

        var cacheDeletionFailed = false
        do {
            try cache.delete(for: id)
        } catch {
            cacheDeletionFailed = true
        }
        alertEvaluator.clearState(for: id)
        refreshingKeyIDs.remove(id)
        refreshGenerationByKeyID.removeValue(forKey: id)
        invalidKeyFingerprintsByKeyID.removeValue(forKey: id)
        states.removeValue(forKey: id)
        orderedKeyIDs.removeAll { $0 == id }
        isRefreshing = !refreshingKeyIDs.isEmpty
        if cacheDeletionFailed {
            throw UsageStoreError.cacheCleanupFailed
        }
    }

    private func restoreState() {
        let currentTime = now()
        let configurations = keyRepository.list()
        orderedKeyIDs = configurations.map(\.id)
        states = Dictionary(uniqueKeysWithValues: configurations.map { configuration in
            let cached = try? cache.load(for: configuration.id)
            return (
                configuration.id,
                KeyUsageState(
                    configuration: configuration,
                    snapshot: cached,
                    lastSuccessAt: cached?.fetchedAt,
                    isRefreshing: false,
                    isStale: cached.map {
                        UsageFreshness.isStale(
                            lastSuccess: $0.fetchedAt,
                            now: currentTime,
                            refreshMinutes: refreshMinutes
                        )
                    } ?? false,
                    error: nil
                )
            )
        })
    }

    private func synchronizeConfigurations() {
        let configurations = keyRepository.list()
        let validIDs = Set(configurations.map(\.id))
        states = states.filter { validIDs.contains($0.key) }
        refreshGenerationByKeyID = refreshGenerationByKeyID.filter { validIDs.contains($0.key) }
        invalidKeyFingerprintsByKeyID = invalidKeyFingerprintsByKeyID.filter { validIDs.contains($0.key) }
        orderedKeyIDs = configurations.map(\.id)

        for configuration in configurations {
            if var state = states[configuration.id] {
                state.configuration = configuration
                states[configuration.id] = state
            } else {
                let cached = try? cache.load(for: configuration.id)
                states[configuration.id] = KeyUsageState(
                    configuration: configuration,
                    snapshot: cached,
                    lastSuccessAt: cached?.fetchedAt,
                    isRefreshing: false,
                    isStale: cached.map {
                        UsageFreshness.isStale(
                            lastSuccess: $0.fetchedAt,
                            now: now(),
                            refreshMinutes: refreshMinutes
                        )
                    } ?? false,
                    error: nil
                )
            }
        }
    }

    private func prepareRefreshRequest(for keyID: UUID) -> RefreshRequest? {
        guard
            !refreshingKeyIDs.contains(keyID),
            var state = states[keyID],
            state.configuration.isEnabled
        else {
            return nil
        }

        let secret: String
        do {
            guard let storedSecret = try localStore.read(for: keyID) else {
                applyFailure(.invalidKey, to: keyID)
                return nil
            }
            secret = storedSecret
        } catch {
            applyFailure(.invalidResponse, to: keyID)
            return nil
        }

        refreshingKeyIDs.insert(keyID)
        let refreshGeneration = UUID()
        refreshGenerationByKeyID[keyID] = refreshGeneration
        state.isRefreshing = true
        states[keyID] = state
        isRefreshing = true
        return RefreshRequest(
            keyID: keyID,
            secret: secret,
            configuration: state.configuration,
            credentialFingerprint: CredentialFingerprint(secret: secret),
            refreshGeneration: refreshGeneration,
            requestedAt: now()
        )
    }

    private func perform(_ requests: [RefreshRequest]) async {
        guard !requests.isEmpty else {
            isRefreshing = !refreshingKeyIDs.isEmpty
            return
        }

        let apiClient = apiClient
        let providerRegistry = providerRegistry
        var notificationWorks: [NotificationWork] = []
        await withTaskGroup(of: RefreshOutcome.self) { group in
            for request in requests {
                group.addTask {
                    do {
                        let snapshot: UsageSnapshot?
                        if let provider = providerRegistry?.provider(for: request.configuration.providerID) {
                            let credential = ProviderCredential(
                                credentialID: request.configuration.id,
                                providerID: request.configuration.providerID,
                                kind: request.configuration.credentialKind,
                                secret: request.secret,
                                metadata: request.configuration.metadata
                            )
                            snapshot = try await provider.fetchUsage(credential, now: request.requestedAt)
                        } else {
                            snapshot = try await apiClient.fetchUsage(
                                apiKey: request.secret,
                                now: request.requestedAt
                            )
                        }
                        try Task.checkCancellation()
                        return RefreshOutcome(
                            keyID: request.keyID,
                            credentialFingerprint: request.credentialFingerprint,
                            refreshGeneration: request.refreshGeneration,
                            requestedAt: request.requestedAt,
                            result: .success(snapshot)
                        )
                    } catch is CancellationError {
                        return RefreshOutcome(
                            keyID: request.keyID,
                            credentialFingerprint: request.credentialFingerprint,
                            refreshGeneration: request.refreshGeneration,
                            requestedAt: request.requestedAt,
                            result: .cancelled
                        )
                    } catch let error as UsageAPIError {
                        return RefreshOutcome(
                            keyID: request.keyID,
                            credentialFingerprint: request.credentialFingerprint,
                            refreshGeneration: request.refreshGeneration,
                            requestedAt: request.requestedAt,
                            result: Task.isCancelled ? .cancelled : .failure(error)
                        )
                    } catch let error as UsageProviderError {
                        return RefreshOutcome(
                            keyID: request.keyID,
                            credentialFingerprint: request.credentialFingerprint,
                            refreshGeneration: request.refreshGeneration,
                            requestedAt: request.requestedAt,
                            result: Task.isCancelled ? .cancelled : .failure(Self.apiError(from: error))
                        )
                    } catch {
                        return RefreshOutcome(
                            keyID: request.keyID,
                            credentialFingerprint: request.credentialFingerprint,
                            refreshGeneration: request.refreshGeneration,
                            requestedAt: request.requestedAt,
                            result: Task.isCancelled ? .cancelled : .failure(.invalidResponse)
                        )
                    }
                }
            }

            for await outcome in group {
                if let notificationWork = merge(outcome) {
                    notificationWorks.append(notificationWork)
                }
            }
        }

        guard !Task.isCancelled else {
            return
        }
        for work in notificationWorks where isNotificationWorkCurrent(work) {
            scheduleNotification(work)
        }
    }

    private func isNotificationWorkCurrent(_ work: NotificationWork) -> Bool {
        refreshGenerationByKeyID[work.keyID] == work.refreshGeneration
            && states[work.keyID] != nil
    }

    private func shouldDeliverNotification(_ work: NotificationWork) -> Bool {
        notificationsEnabled && isNotificationWorkCurrent(work)
    }

    private func merge(_ outcome: RefreshOutcome) -> NotificationWork? {
        defer {
            refreshingKeyIDs.remove(outcome.keyID)
            if var state = states[outcome.keyID] {
                state.isRefreshing = false
                states[outcome.keyID] = state
            }
            isRefreshing = !refreshingKeyIDs.isEmpty
        }

        if Task.isCancelled || outcome.result.isCancelled {
            return nil
        }
        guard var state = states[outcome.keyID] else {
            return nil
        }
        guard
            refreshGenerationByKeyID[outcome.keyID] == outcome.refreshGeneration,
            let currentFingerprint = credentialFingerprint(for: outcome.keyID),
            currentFingerprint == outcome.credentialFingerprint
        else {
            return nil
        }
        switch outcome.result {
        case let .success(snapshot):
            invalidKeyFingerprintsByKeyID.removeValue(forKey: outcome.keyID)
            state.snapshot = snapshot
            state.lastSuccessAt = snapshot?.fetchedAt ?? outcome.requestedAt
            state.isStale = false
            state.error = snapshot == nil ? .noSubscription : nil
            states[outcome.keyID] = state
            if let snapshot {
                try? cache.save(snapshot, for: outcome.keyID)
                var preferences = usagePreferencesProvider(outcome.keyID)
                preferences = MetricAlertRuleResolver.reconcile(
                    existing: preferences,
                    metrics: snapshot.normalizedMetrics,
                    capabilities: metricCapabilitiesProvider(state.configuration),
                    legacyThresholds: .init()
                )
                setUsagePreferencesHandler(preferences, outcome.keyID)
                return NotificationWork(
                    keyID: outcome.keyID,
                    refreshGeneration: outcome.refreshGeneration,
                    configuration: state.configuration,
                    snapshot: snapshot,
                    usagePreferences: preferences
                )
            } else {
                try? cache.delete(for: outcome.keyID)
            }
        case let .failure(error):
            let displayError = Self.displayError(from: error)
            if displayError == .invalidKey {
                invalidKeyFingerprintsByKeyID[outcome.keyID] = outcome.credentialFingerprint
            }
            applyFailure(displayError, to: outcome.keyID)
        case .cancelled:
            break
        }
        return nil
    }

    private func applyFailure(_ error: UsageDisplayError, to keyID: UUID) {
        guard var state = states[keyID] else {
            return
        }
        state.error = error
        state.isStale = state.snapshot != nil && state.lastSuccessAt.map {
            UsageFreshness.isStale(
                lastSuccess: $0,
                now: now(),
                refreshMinutes: refreshMinutes
            )
        } == true
        states[keyID] = state
    }

    private func shouldSkipBatchRefresh(for keyID: UUID) -> Bool {
        guard states[keyID]?.error == .invalidKey else {
            return false
        }

        guard let failedFingerprint = invalidKeyFingerprintsByKeyID[keyID] else {
            // 没有可读取的密钥时也跳过批量刷新；密钥恢复后会再次尝试。
            return credentialFingerprint(for: keyID) == nil
        }
        return credentialFingerprint(for: keyID) == failedFingerprint
    }

    private func credentialFingerprint(for keyID: UUID) -> CredentialFingerprint? {
        do {
            guard let secret = try localStore.read(for: keyID) else {
                return nil
            }
            return CredentialFingerprint(secret: secret)
        } catch {
            return nil
        }
    }

    private func scheduleNotification(_ work: NotificationWork) {
        let manager = AlertManager(evaluator: alertEvaluator, sender: notificationSender)
        let notificationsEnabled = notificationsEnabled
        Task { [weak self] in
            guard let self, self.isNotificationWorkCurrent(work) else {
                return
            }
            _ = try? await manager.evaluateAndNotify(
                key: work.configuration,
                snapshot: work.snapshot,
                preferences: work.usagePreferences,
                applicationNotificationsEnabled: notificationsEnabled,
                shouldDeliver: { [weak self] in
                    guard let self else {
                        return false
                    }
                    return await self.shouldDeliverNotification(work)
                }
            )
        }
    }

    private static func displayError(from error: UsageAPIError) -> UsageDisplayError {
        switch error {
        case .invalidKey:
            return .invalidKey
        case .transport:
            return .network
        case .invalidResponse:
            return .invalidResponse
        case .server(statusCode: 401):
            return .invalidKey
        case let .server(statusCode):
            return .server(statusCode: statusCode)
        }
    }

    nonisolated private static func apiError(from error: UsageProviderError) -> UsageAPIError {
        switch error {
        case .invalidCredential, .unauthorized:
            return .invalidKey
        case .rateLimited:
            return .server(statusCode: 429)
        case .transport, .timeout:
            return .transport
        case .invalidResponse:
            return .invalidResponse
        case .providerUnavailable:
            return .server(statusCode: 503)
        case .providerMessage:
            return .invalidResponse
        }
    }

    private static func storeError(from error: Error) -> UsageStoreError {
        switch error {
        case KeyRepositoryError.invalidName:
            return .invalidName
        case KeyRepositoryError.invalidSecret:
            return .invalidSecret
        case let apiError as UsageAPIError:
            switch apiError {
            case .invalidKey:
                return .invalidKey
            case .transport:
                return .network
            case .invalidResponse:
                return .invalidResponse
            case .server(statusCode: 401):
                return .invalidKey
            case let .server(statusCode):
                return .server(statusCode: statusCode)
            }
        default:
            return .persistence
        }
    }
}

private struct RefreshRequest: Sendable {
    let keyID: UUID
    let secret: String
    let configuration: KeyConfiguration
    let credentialFingerprint: CredentialFingerprint
    let refreshGeneration: UUID
    let requestedAt: Date
}

private struct RefreshOutcome: Sendable {
    let keyID: UUID
    let credentialFingerprint: CredentialFingerprint
    let refreshGeneration: UUID
    let requestedAt: Date
    let result: RefreshResult
}

private enum RefreshResult: Sendable {
    case success(UsageSnapshot?)
    case failure(UsageAPIError)
    case cancelled

    var isCancelled: Bool {
        if case .cancelled = self {
            return true
        }
        return false
    }
}

private struct NotificationWork: Sendable {
    let keyID: UUID
    let refreshGeneration: UUID
    let configuration: KeyConfiguration
    let snapshot: UsageSnapshot
    let usagePreferences: CredentialUsagePreferences
}

private struct CredentialFingerprint: Equatable, Sendable {
    let bytes: [UInt8]

    init(secret: String) {
        bytes = Array(SHA256.hash(data: Data(secret.utf8)))
    }
}
