import SwiftUI

struct CredentialFilter: Equatable {
    var status: CredentialStatusFilter = .all
    var provider: ProviderID?
    var searchText = ""
}

enum CredentialStatusFilter: String, CaseIterable, Identifiable {
    case all, enabled, disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .enabled: "启用"
        case .disabled: "停用"
        }
    }
}

struct CredentialManagementView: View {
    @Bindable var environment: AppEnvironment
    let ordering: CredentialOrderingController
    @State private var filter = CredentialFilter()
    @State private var collapsedProviderIDs: Set<ProviderID> = []
    @State private var editor: EditorPresentation?
    @State private var pendingDeletion: KeyConfiguration?
    @State private var operationError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(
                    title: "凭证管理",
                    subtitle: "\(environment.store.orderedKeyIDs.count) 个凭证",
                    trailing: AnyView(addButton)
                )
                filterBar
                providerGroups
            }
            .padding(24)
        }
        .sheet(item: $editor) { presentation in
            credentialEditor(presentation)
        }
        .confirmationDialog(
            "确定删除这个凭证？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { deletePending() }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("将同时删除本地保存的密钥和用量缓存，此操作无法撤销。")
        }
        .alert(
            "无法完成操作",
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button("好") { operationError = nil }
        } message: {
            Text(operationError ?? "发生未知错误")
        }
    }

    private var addButton: some View {
        Button {
            editor = .add
        } label: {
            Label("添加凭证", systemImage: "plus")
        }
        .liquidGlassButton(prominent: true)
        .accessibilityLabel("添加凭证")
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("状态", selection: $filter.status) {
                    ForEach(CredentialStatusFilter.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .accessibilityLabel("凭证状态筛选")

                TextField("搜索别名", text: $filter.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .accessibilityLabel("搜索凭证别名")
            }

            ProviderFilterChips(
                providers: usedProviderDescriptors,
                selectedProviderID: filter.provider,
                select: { filter.provider = $0 }
            )
        }
    }

    @ViewBuilder
    private var providerGroups: some View {
        if groups.isEmpty {
            ContentUnavailableView(
                environment.store.orderedKeyIDs.isEmpty ? "尚未添加凭证" : "没有匹配的凭证",
                systemImage: environment.store.orderedKeyIDs.isEmpty ? "key.slash" : "line.3.horizontal.decrease.circle",
                description: Text(
                    environment.store.orderedKeyIDs.isEmpty
                        ? "添加供应商凭证后即可管理用量展示"
                        : "调整状态、供应商或搜索条件后再试"
                )
            )
            .frame(maxWidth: .infinity, minHeight: 260)
            .accessibilityLabel(environment.store.orderedKeyIDs.isEmpty ? "尚未添加凭证" : "没有匹配的凭证")
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups, id: \.provider.id) { group in
                    providerGroup(group)
                }
            }
        }
    }

    private func providerGroup(
        _ group: (provider: ProviderDescriptor, states: [KeyUsageState])
    ) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { !collapsedProviderIDs.contains(group.provider.id) },
                set: { isExpanded in
                    if isExpanded {
                        collapsedProviderIDs.remove(group.provider.id)
                    } else {
                        collapsedProviderIDs.insert(group.provider.id)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.states, id: \.configuration.id) { state in
                    credentialRow(state, provider: group.provider)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: group.provider.iconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(group.provider.displayName)
                    .font(.headline)
                Text("\(group.states.count)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .disclosureGroupStyle(.automatic)
    }

    private func credentialRow(
        _ state: KeyUsageState,
        provider: ProviderDescriptor
    ) -> some View {
        CredentialSummaryRow(
            state: state,
            descriptor: provider,
            planType: planTitle(for: state.configuration),
            leading: AnyView(providerIcon(provider)),
            trailing: AnyView(rowActions(state))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlassSurface(cornerRadius: 8)
        .accessibilityElement(children: .contain)
    }

    private func providerIcon(_ provider: ProviderDescriptor) -> some View {
        Image(systemName: provider.iconName)
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
    }

    private func rowActions(_ state: KeyUsageState) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { state.configuration.isEnabled },
                set: { setEnabled(state, enabled: $0) }
            )) {
                Text(state.configuration.isEnabled ? "启用" : "已停用")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .tint(state.configuration.isEnabled ? .green : .secondary)
            .frame(width: 62)
            .help(state.configuration.isEnabled ? "停用 \(state.configuration.displayName)" : "启用 \(state.configuration.displayName)")
            .accessibilityLabel(state.configuration.isEnabled ? "停用 \(state.configuration.displayName)" : "启用 \(state.configuration.displayName)")

            Button {
                editor = .edit(state.configuration)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("编辑 \(state.configuration.displayName)")
            .accessibilityLabel("编辑 \(state.configuration.displayName)")

            Button(role: .destructive) {
                pendingDeletion = state.configuration
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除 \(state.configuration.displayName)")
            .accessibilityLabel("删除 \(state.configuration.displayName)")
        }
    }

    private var usedProviderDescriptors: [ProviderDescriptor] {
        ProviderID.allCases.compactMap { providerID in
            let hasCredential = allStates.contains {
                $0.configuration.providerID == providerID
            }
            guard hasCredential else { return nil }
            return ProviderRegistry.builtInDescriptors.first { $0.id == providerID }
        }
    }

    private var allStates: [KeyUsageState] {
        let statesByID = environment.store.states
        var seenIDs = Set<UUID>()
        let orderedIDs = environment.settings.displayOrder.popoverCredentialIDs
            + environment.store.orderedKeyIDs.filter {
                !environment.settings.displayOrder.popoverCredentialIDs.contains($0)
            }

        return orderedIDs.compactMap { id in
            guard let state = statesByID[id], seenIDs.insert(id).inserted else {
                return nil
            }
            return state
        }
    }

    private var visibleStates: [KeyUsageState] {
        allStates.filter { state in
            let matchesStatus: Bool
            switch filter.status {
            case .all:
                matchesStatus = true
            case .enabled:
                matchesStatus = state.configuration.isEnabled
            case .disabled:
                matchesStatus = !state.configuration.isEnabled
            }

            guard matchesStatus,
                  filter.provider == nil || filter.provider == state.configuration.providerID,
                  matchesSearch(state)
            else { return false }
            return true
        }
    }

    private var groups: [(provider: ProviderDescriptor, states: [KeyUsageState])] {
        ProviderID.allCases.compactMap { providerID in
            let states = visibleStates.filter { $0.configuration.providerID == providerID }
            guard let descriptor = ProviderRegistry.builtInDescriptors.first(where: { $0.id == providerID }),
                  !states.isEmpty
            else { return nil }
            return (descriptor, states)
        }
    }

    private func matchesSearch(_ state: KeyUsageState) -> Bool {
        let query = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let providerName = ProviderRegistry.builtInDescriptors
            .first { $0.id == state.configuration.providerID }?
            .displayName ?? state.configuration.providerID.rawValue
        return state.configuration.displayName.localizedCaseInsensitiveContains(query)
            || providerName.localizedCaseInsensitiveContains(query)
    }

    @ViewBuilder
    private func credentialEditor(_ presentation: EditorPresentation) -> some View {
        switch presentation {
        case .add:
            CredentialEditorView(save: ordering.addValidatedCredential)
        case let .edit(configuration):
            CredentialEditorView(
                title: "编辑凭证",
                initialProviderID: configuration.providerID,
                initialName: configuration.displayName,
                initialSecret: environment.readKey(id: configuration.id) ?? "",
                initialMetadata: configuration.metadata
            ) { input in
                try await environment.updateValidatedCredential(id: configuration.id, input: input)
            }
        }
    }

    private func setEnabled(_ state: KeyUsageState, enabled: Bool) {
        do {
            try ordering.setEnabled(state.configuration.id, enabled: enabled)
        } catch {
            operationError = "无法更新凭证状态，请稍后重试"
        }
    }

    private func deletePending() {
        guard let configuration = pendingDeletion else { return }
        pendingDeletion = nil
        do {
            try ordering.delete(configuration.id)
        } catch {
            operationError = "无法删除凭证，请稍后重试"
        }
    }

    private func planTitle(for configuration: KeyConfiguration) -> String {
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

    private enum EditorPresentation: Identifiable {
        case add
        case edit(KeyConfiguration)

        var id: String {
            switch self {
            case .add:
                "add"
            case let .edit(configuration):
                configuration.id.uuidString
            }
        }
    }
}
