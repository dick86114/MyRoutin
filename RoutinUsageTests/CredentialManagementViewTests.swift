import XCTest
@testable import RoutinUsage

@MainActor
final class CredentialManagementViewTests: XCTestCase {
    func test凭证卡片提供独立提醒设置入口() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "CredentialManagementView.swift"
        ])

        XCTAssertTrue(source.contains("bell.badge"))
        XCTAssertTrue(source.contains("提醒设置"))
        XCTAssertTrue(source.contains("CredentialAlertSettingsView"))
        XCTAssertTrue(source.contains("CredentialAlertSettingsPresentation"))
        XCTAssertTrue(source.contains(".sheet(item: $alertSettingsPresentation)"))
        XCTAssertTrue(source.contains("model: presentation.model"))
    }

    func test过滤状态供应商和搜索组合只保留匹配凭证() throws {
        let context = CredentialManagementTestContext()
        defer { context.cleanUp() }
        let enabled = try context.addCredential(name: "主账号", providerID: .routin)
        let disabled = try context.addCredential(name: "备用账号", providerID: .routin)
        let otherProvider = try context.addCredential(name: "主账号", providerID: .deepseek)
        _ = try context.repository.setEnabled(id: disabled.id, enabled: false)
        context.store.reloadConfigurations()
        let model = context.makeModel()

        model.filter = CredentialFilter(
            status: .disabled,
            provider: .routin,
            searchText: " 备用 "
        )

        XCTAssertEqual(model.visibleStates.map(\.configuration.id), [disabled.id])
        XCTAssertEqual(model.groups.count, 1)
        XCTAssertEqual(model.groups.first?.provider.id, .routin)
        XCTAssertFalse(model.visibleStates.contains { $0.configuration.id == enabled.id })
        XCTAssertFalse(model.visibleStates.contains { $0.configuration.id == otherProvider.id })
    }

    func test搜索归一化空白并匹配别名或供应商() throws {
        let context = CredentialManagementTestContext()
        defer { context.cleanUp() }
        let alias = try context.addCredential(name: "Work Account", providerID: .glm)
        let provider = try context.addCredential(name: "个人凭证", providerID: .deepseek)
        _ = try context.addCredential(name: "其他凭证", providerID: .newAPI)
        let model = context.makeModel()

        model.filter.searchText = "  work  "
        XCTAssertEqual(model.visibleStates.map(\.configuration.id), [alias.id])

        model.filter.searchText = " deepSEEK "
        XCTAssertEqual(model.visibleStates.map(\.configuration.id), [provider.id])
    }

    func test添加凭证默认追加弹窗顺序并进入菜单栏() async throws {
        let context = CredentialManagementTestContext()
        defer { context.cleanUp() }
        let model = context.makeModel()
        let input = ValidatedCredentialInput(
            providerID: .deepseek,
            credentialKind: .apiKey,
            name: "新凭证",
            secret: "deepseek-secret",
            metadata: [:]
        )

        let result = try await model.addValidatedCredential(input)

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(
            context.settings.displayOrder.menuBarCredentialIDs,
            context.settings.displayOrder.popoverCredentialIDs
        )
        XCTAssertEqual(context.settings.displayOrder.popoverCredentialIDs.count, 1)
        XCTAssertEqual(context.store.orderedKeyIDs, context.settings.displayOrder.popoverCredentialIDs)
    }

    func test菜单栏满额后添加凭证只追加弹窗顺序() async throws {
        let context = CredentialManagementTestContext()
        defer { context.cleanUp() }
        for index in 0..<CredentialDisplayOrder.maximumMenuBarCount {
            let configuration = try context.addCredential(name: "已满 \(index)", providerID: .routin)
            context.settings.displayOrder = context.settings.displayOrder.addingToMenuBar(
                configuration.id,
                toIndex: index
            )
        }
        let model = context.makeModel()
        let input = ValidatedCredentialInput(
            providerID: .deepseek,
            credentialKind: .apiKey,
            name: "菜单栏外凭证",
            secret: "deepseek-secret",
            metadata: [:]
        )

        _ = try await model.addValidatedCredential(input)

        XCTAssertEqual(
            context.settings.displayOrder.menuBarCredentialIDs.count,
            CredentialDisplayOrder.maximumMenuBarCount
        )
        XCTAssertEqual(
            context.settings.displayOrder.popoverCredentialIDs.count,
            CredentialDisplayOrder.maximumMenuBarCount + 1
        )
        XCTAssertFalse(
            context.settings.displayOrder.menuBarCredentialIDs.contains(
                context.settings.displayOrder.popoverCredentialIDs.last!
            )
        )
    }

    func test启停凭证保留两个独立顺序数组() throws {
        let context = CredentialManagementTestContext()
        defer { context.cleanUp() }
        let first = try context.addCredential(name: "主账号", providerID: .routin)
        let second = try context.addCredential(name: "备用账号", providerID: .deepseek)
        context.settings.displayOrder.menuBarCredentialIDs = [first.id]
        context.settings.displayOrder.popoverCredentialIDs = [first.id, second.id]
        let model = context.makeModel()

        model.setEnabled(first.id, enabled: false)

        XCTAssertEqual(
            context.repository.list().first { $0.id == first.id }?.isEnabled,
            false
        )
        XCTAssertEqual(context.settings.displayOrder.menuBarCredentialIDs, [first.id])
        XCTAssertEqual(context.settings.displayOrder.popoverCredentialIDs, [first.id, second.id])
        XCTAssertEqual(model.allStates.map(\.configuration.id), [first.id, second.id])
        model.filter.status = .enabled
        XCTAssertEqual(model.visibleStates.map(\.configuration.id), [second.id])
    }

    func test删除成功清理凭证顺序和提示状态() throws {
        let context = CredentialManagementTestContext()
        defer { context.cleanUp() }
        let key = try context.addCredential(name: "待删除", providerID: .routin)
        context.settings.displayOrder.menuBarCredentialIDs = [key.id]
        context.settings.displayOrder.popoverCredentialIDs = [key.id]
        context.settings.setUsagePreferences(
            CredentialUsagePreferences(
                menuBarMetricID: "weekly",
                notificationsEnabled: true,
                alertRules: []
            ),
            for: key.id
        )
        let model = context.makeModel()
        model.pendingDeletion = key

        model.deletePending()

        XCTAssertNil(context.store.state(for: key.id))
        XCTAssertEqual(context.store.orderedKeyIDs, [])
        XCTAssertEqual(context.settings.displayOrder.menuBarCredentialIDs, [])
        XCTAssertEqual(context.settings.displayOrder.popoverCredentialIDs, [])
        XCTAssertNil(context.settings.storedUsagePreferences(for: key.id))
        XCTAssertNil(model.operationNotice)
    }

    func test删除缓存失败仍移除凭证并产生专门提示() throws {
        let context = CredentialManagementTestContext(cache: DeleteFailingUsageCache())
        defer { context.cleanUp() }
        let key = try context.addCredential(name: "缓存失败", providerID: .routin)
        context.settings.displayOrder.menuBarCredentialIDs = [key.id]
        context.settings.displayOrder.popoverCredentialIDs = [key.id]
        context.settings.setUsagePreferences(
            CredentialUsagePreferences(
                menuBarMetricID: "balance",
                notificationsEnabled: false,
                alertRules: []
            ),
            for: key.id
        )
        let model = context.makeModel()
        model.pendingDeletion = key

        model.deletePending()

        XCTAssertNil(context.store.state(for: key.id))
        XCTAssertEqual(context.store.orderedKeyIDs, [])
        XCTAssertEqual(context.settings.displayOrder.menuBarCredentialIDs, [])
        XCTAssertEqual(context.settings.displayOrder.popoverCredentialIDs, [])
        XCTAssertNil(context.settings.storedUsagePreferences(for: key.id))
        XCTAssertEqual(
            model.operationNotice,
            CredentialOperationNotice(
                title: "缓存清理失败",
                message: "凭证已删除，但用量缓存未能清理。"
            )
        )
    }

    func test编辑凭证调用更新合同() async throws {
        let context = CredentialManagementTestContext()
        defer { context.cleanUp() }
        let key = try context.addCredential(name: "旧名称", providerID: .deepseek)
        var updatedIDs: [UUID] = []
        var updatedInputs: [ValidatedCredentialInput] = []
        let model = context.makeModel(
            updateCredential: { id, input in
                updatedIDs.append(id)
                updatedInputs.append(input)
                return .saved
            }
        )
        let input = ValidatedCredentialInput(
            providerID: .deepseek,
            credentialKind: .apiKey,
            name: "新名称",
            secret: "deepseek-new-secret",
            metadata: [:]
        )

        let result = try await model.updateValidatedCredential(id: key.id, input: input)

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(updatedIDs, [key.id])
        XCTAssertEqual(updatedInputs, [input])
    }

    func test行级摘要完整朗读别名供应商套餐和状态() throws {
        let context = CredentialManagementTestContext()
        defer { context.cleanUp() }
        let key = try context.addCredential(name: "工作账号", providerID: .routin)
        _ = try context.repository.setEnabled(id: key.id, enabled: false)
        context.store.reloadConfigurations()
        let model = context.makeModel()
        let state = try XCTUnwrap(context.store.state(for: key.id))

        XCTAssertEqual(
            model.accessibilitySummary(
                state,
                providerName: "Routin",
                planType: "Plan Key"
            ),
            "工作账号，Routin，Plan Key，已停用"
        )
    }

    func test凭证管理页包含分组筛选搜索和危险删除确认() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "CredentialManagementView.swift"
        ])
        let modelSource = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "CredentialManagementModel.swift"
        ])

        XCTAssertTrue(source.contains("struct CredentialFilter"))
        XCTAssertTrue(modelSource.contains("ProviderID.allCases"))
        XCTAssertTrue(source.contains("searchText"))
        XCTAssertTrue(source.contains("confirmationDialog"))
        XCTAssertTrue(source.contains("将同时删除本地保存的密钥和用量缓存"))
        XCTAssertTrue(source.contains("UsageRowView("))
        XCTAssertTrue(source.contains("LazyVGrid"))
        XCTAssertTrue(source.contains("detailsState"))
        XCTAssertTrue(source.contains("ellipsis.circle"))
    }

    func test页面视觉与可访问性约束作为补充() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "CredentialManagementView.swift"
        ])
        let rowSource = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "Components", "CredentialSummaryRow.swift"
        ])
        let chipsSource = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "Components", "ProviderFilterChips.swift"
        ])
        let usageRowSource = try TestSourceReader.read([
            "RoutinUsage", "Views", "UsageRowView.swift"
        ])

        XCTAssertTrue(source.contains("TextField(\"搜索别名或供应商\""))
        XCTAssertTrue(source.contains("搜索别名或供应商"))
        XCTAssertTrue(source.contains("LazyVGrid"))
        XCTAssertTrue(source.contains("CredentialDetailsView"))
        XCTAssertTrue(source.contains("detailsOverlay"))
        XCTAssertTrue(source.contains("onTapGesture {"))
        XCTAssertTrue(source.contains("closeDetails()"))
        XCTAssertTrue(source.contains("CredentialDetailsView(state: state, onClose: closeDetails)"))
        XCTAssertTrue(source.contains(".frame(width: 640)"))
        XCTAssertTrue(source.contains(".frame(minHeight: 500, maxHeight: 720)"))
        XCTAssertTrue(source.contains("accessibilitySummary("))
        XCTAssertTrue(usageRowSource.contains(".saturation(state.configuration.isEnabled ? 1 : 0)"))
        XCTAssertTrue(rowSource.contains("credentialContent"))
        XCTAssertFalse(rowSource.contains(".opacity(state.configuration.isEnabled ? 1 : 0.58)\n        }\n    }"))
        XCTAssertTrue(chipsSource.contains("ScrollView(.horizontal"))
        XCTAssertTrue(chipsSource.contains("accessibilityAddTraits(isSelected ? [.isSelected] : [])"))
    }
}

@MainActor
private struct CredentialManagementTestContext {
    let suiteName: String
    let defaults: UserDefaults
    let keychain: LocalKeyStore
    let repository: KeyRepository
    let store: UsageStore
    let settings: AppSettings
    let cache: InMemoryUsageCache

    init(cache: (any UsageCaching)? = nil) {
        suiteName = "credential-management-view.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        defaults.removePersistentDomain(forName: suiteName)
        self.defaults = defaults
        keychain = LocalKeyStore(defaults: defaults)
        repository = KeyRepository(defaults: defaults, localStore: keychain)
        let inMemoryCache = InMemoryUsageCache()
        self.cache = inMemoryCache
        settings = AppSettings(defaults: defaults)
        store = UsageStore(
            keyRepository: repository,
            localStore: keychain,
            apiClient: ScriptedUsageFetcher(responses: [:]),
            cache: cache ?? inMemoryCache,
            alertEvaluator: AlertEvaluator(defaults: defaults),
            notificationSender: NotificationSenderFake(),
            defaults: defaults
        )
    }

    func addCredential(name: String, providerID: ProviderID) throws -> KeyConfiguration {
        let secret = providerID == .routin
            ? "plan-\(UUID().uuidString)"
            : "secret-\(UUID().uuidString)"
        let configuration = try repository.add(
            name: name,
            secret: secret,
            providerID: providerID,
            credentialKind: providerID == .routin ? .bearerAPIKey : .apiKey,
            metadata: [:]
        )
        settings.appendCredential(configuration.id)
        store.reloadConfigurations()
        return configuration
    }

    func makeModel(
        updateCredential: @escaping @MainActor (
            UUID,
            ValidatedCredentialInput
        ) async throws -> KeyEditorSaveResult = { _, _ in .saved }
    ) -> CredentialManagementModel {
        let settings = settings
        let store = store
        let repository = repository
        let ordering = CredentialOrderingController(
            settings: settings,
            addCredential: { input in
                let configuration = try repository.add(
                    name: input.name,
                    secret: input.secret,
                    providerID: input.providerID,
                    credentialKind: input.credentialKind,
                    metadata: input.metadata
                )
                store.reloadConfigurations()
                return CredentialAddOutcome(
                    saveResult: .saved,
                    addedCredentialID: configuration.id
                )
            },
            setKeyEnabled: { try store.setKeyEnabled($0, enabled: $1) },
            delete: { try store.deleteKey($0) }
        )
        return CredentialManagementModel(
            store: store,
            settings: settings,
            ordering: ordering,
            updateCredential: updateCredential
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
