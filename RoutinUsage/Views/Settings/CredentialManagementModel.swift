import Foundation
import Observation

struct CredentialOperationNotice: Equatable, Sendable {
    let title: String
    let message: String
}

@MainActor
@Observable
final class CredentialManagementModel {
    private let store: UsageStore
    private let settings: AppSettings
    @ObservationIgnored private let ordering: CredentialOrderingController
    @ObservationIgnored private let updateCredential: @MainActor (
        UUID,
        ValidatedCredentialInput
    ) async throws -> KeyEditorSaveResult

    var filter = CredentialFilter()
    var collapsedProviderIDs: Set<ProviderID> = []
    var pendingDeletion: KeyConfiguration?
    private(set) var operationNotice: CredentialOperationNotice?

    init(
        store: UsageStore,
        settings: AppSettings,
        ordering: CredentialOrderingController,
        updateCredential: @escaping @MainActor (
            UUID,
            ValidatedCredentialInput
        ) async throws -> KeyEditorSaveResult
    ) {
        self.store = store
        self.settings = settings
        self.ordering = ordering
        self.updateCredential = updateCredential
    }

    convenience init(
        environment: AppEnvironment,
        ordering: CredentialOrderingController
    ) {
        self.init(
            store: environment.store,
            settings: environment.settings,
            ordering: ordering,
            updateCredential: { id, input in
                try await environment.updateValidatedCredential(id: id, input: input)
            }
        )
    }

    var hasCredentials: Bool {
        !store.orderedKeyIDs.isEmpty
    }

    var storeCount: Int {
        store.orderedKeyIDs.count
    }

    var allStates: [KeyUsageState] {
        let statesByID = store.states
        var seenIDs = Set<UUID>()
        let orderedIDs = settings.displayOrder.popoverCredentialIDs
            + store.orderedKeyIDs.filter {
                !settings.displayOrder.popoverCredentialIDs.contains($0)
            }

        return orderedIDs.compactMap { id in
            guard let state = statesByID[id], seenIDs.insert(id).inserted else {
                return nil
            }
            return state
        }
    }

    var visibleStates: [KeyUsageState] {
        allStates.filter { state in
            matchesStatus(state)
                && matchesProvider(state)
                && matchesSearch(state)
        }
    }

    var groups: [(provider: ProviderDescriptor, states: [KeyUsageState])] {
        ProviderID.allCases.compactMap { providerID in
            let states = visibleStates.filter { $0.configuration.providerID == providerID }
            guard let descriptor = ProviderRegistry.builtInDescriptors.first(where: {
                $0.id == providerID
            }), !states.isEmpty else {
                return nil
            }
            return (descriptor, states)
        }
    }

    var usedProviderDescriptors: [ProviderDescriptor] {
        let usedIDs = Set(allStates.map(\.configuration.providerID))
        return ProviderID.allCases.compactMap { providerID in
            guard usedIDs.contains(providerID) else {
                return nil
            }
            return ProviderRegistry.builtInDescriptors.first { $0.id == providerID }
        }
    }

    private func providerDescriptor(for state: KeyUsageState) -> ProviderDescriptor? {
        ProviderRegistry.builtInDescriptors.first {
            $0.id == state.configuration.providerID
        }
    }

    func addValidatedCredential(
        _ input: ValidatedCredentialInput
    ) async throws -> KeyEditorSaveResult {
        try await ordering.addValidatedCredential(input)
    }

    func updateValidatedCredential(
        id: UUID,
        input: ValidatedCredentialInput
    ) async throws -> KeyEditorSaveResult {
        try await updateCredential(id, input)
    }

    func setEnabled(_ id: UUID, enabled: Bool) {
        do {
            try ordering.setEnabled(id, enabled: enabled)
        } catch {
            operationNotice = CredentialOperationNotice(
                title: "无法完成操作",
                message: "无法更新凭证状态，请稍后重试"
            )
        }
    }

    func deletePending() {
        guard let configuration = pendingDeletion else {
            return
        }
        pendingDeletion = nil
        do {
            if try ordering.delete(configuration.id) == .cacheCleanupFailed {
                operationNotice = CredentialOperationNotice(
                    title: "缓存清理失败",
                    message: "凭证已删除，但用量缓存未能清理。"
                )
            }
        } catch {
            operationNotice = CredentialOperationNotice(
                title: "无法完成操作",
                message: "无法删除凭证，请稍后重试"
            )
        }
    }

    func clearOperationNotice() {
        operationNotice = nil
    }

    func accessibilitySummary(
        _ state: KeyUsageState,
        providerName: String,
        planType: String
    ) -> String {
        let status = state.configuration.isEnabled ? "已启用" : "已停用"
        return [
            state.configuration.displayName,
            providerName,
            planType,
            status
        ].joined(separator: "，")
    }

    func planTitle(for configuration: KeyConfiguration) -> String {
        if configuration.providerID == .volcengine {
            return configuration.metadata["planType"] == "coding" ? "Coding Plan" : "Agent Plan"
        }
        switch configuration.credentialKind {
        case .bearerAPIKey:
            return configuration.providerID == .routin ? "Plan Key" : "Bearer Token"
        case .apiKey:
            return "API Key"
        case .accessKeyPair:
            return "Access Key Pair"
        }
    }

    private func matchesStatus(_ state: KeyUsageState) -> Bool {
        switch filter.status {
        case .all:
            true
        case .enabled:
            state.configuration.isEnabled
        case .disabled:
            !state.configuration.isEnabled
        }
    }

    private func matchesProvider(_ state: KeyUsageState) -> Bool {
        filter.provider == nil || filter.provider == state.configuration.providerID
    }

    private func matchesSearch(_ state: KeyUsageState) -> Bool {
        let query = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return true
        }
        let providerName = providerDescriptor(for: state)?.displayName
            ?? state.configuration.providerID.rawValue
        return state.configuration.displayName.localizedCaseInsensitiveContains(query)
            || providerName.localizedCaseInsensitiveContains(query)
    }
}
