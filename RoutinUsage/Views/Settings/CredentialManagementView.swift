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

extension KeyUsageState: Identifiable {
    var id: UUID { configuration.id }
}

struct CredentialManagementView: View {
    @Bindable var environment: AppEnvironment
    @State private var model: CredentialManagementModel
    @State private var editor: EditorPresentation?
    @State private var alertSettingsState: KeyUsageState?
    @State private var detailsState: KeyUsageState?

    init(environment: AppEnvironment, ordering: CredentialOrderingController) {
        self.environment = environment
        let model = CredentialManagementModel(environment: environment, ordering: ordering)
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(
                    title: "凭证管理",
                    subtitle: "\(model.storeCount) 个凭证",
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
        .sheet(item: $alertSettingsState) { state in
            CredentialAlertSettingsView(
                title: "\(state.configuration.displayName) 提醒设置",
                model: alertSettingsModel(for: state)
            )
        }
        .confirmationDialog(
            "确定删除这个凭证？",
            isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { model.deletePending() }
            Button("取消", role: .cancel) { model.pendingDeletion = nil }
        } message: {
            Text("将同时删除本地保存的密钥和用量缓存，此操作无法撤销。")
        }
        .alert(
            model.operationNotice?.title ?? "无法完成操作",
            isPresented: Binding(
                get: { model.operationNotice != nil },
                set: { if !$0 { model.clearOperationNotice() } }
            )
        ) {
            Button("好") { model.clearOperationNotice() }
        } message: {
            Text(model.operationNotice?.message ?? "发生未知错误")
        }
        .overlay {
            detailsOverlay
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
                Picker("状态", selection: $model.filter.status) {
                    ForEach(CredentialStatusFilter.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .accessibilityLabel("凭证状态筛选")

                TextField("搜索别名或供应商", text: $model.filter.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .accessibilityLabel("搜索别名或供应商")
            }

            ProviderFilterChips(
                providers: model.usedProviderDescriptors,
                selectedProviderID: model.filter.provider,
                select: { model.filter.provider = $0 }
            )
        }
    }

    @ViewBuilder
    private var providerGroups: some View {
        if groups.isEmpty {
            ContentUnavailableView(
                model.hasCredentials ? "没有匹配的凭证" : "尚未添加凭证",
                systemImage: model.hasCredentials ? "line.3.horizontal.decrease.circle" : "key.slash",
                description: Text(
                    model.hasCredentials
                        ? "添加供应商凭证后即可管理用量展示"
                        : "调整状态、供应商或搜索条件后再试"
                )
            )
            .frame(maxWidth: .infinity, minHeight: 260)
            .accessibilityLabel(model.hasCredentials ? "没有匹配的凭证" : "尚未添加凭证")
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
                get: { !model.collapsedProviderIDs.contains(group.provider.id) },
                set: { isExpanded in
                    if isExpanded {
                        model.collapsedProviderIDs.remove(group.provider.id)
                    } else {
                        model.collapsedProviderIDs.insert(group.provider.id)
                    }
                }
            )
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 330), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(group.states, id: \.configuration.id) { state in
                    credentialCard(state, provider: group.provider)
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

    private func credentialCard(
        _ state: KeyUsageState,
        provider: ProviderDescriptor
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            rowActions(state)
                .frame(height: 24)

            UsageRowView(
                state: state,
                detectionState: .idle,
                detectionRecord: nil,
                isAnotherDetectionActive: false,
                requestDetection: {},
                actions: nil
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(model.accessibilitySummary(
                state,
                providerName: provider.displayName,
                planType: model.planTitle(for: state.configuration)
            ))
        }
    }

    @ViewBuilder
    private var detailsOverlay: some View {
        if let state = detailsState {
            ZStack {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeDetails()
                    }

                CredentialDetailsView(state: state, onClose: closeDetails)
                    .frame(width: 560)
                    .frame(minHeight: 420, maxHeight: 660)
                    .liquidGlassSurface(cornerRadius: 18)
                    .padding(36)
                    .contentShape(Rectangle())
                    .onTapGesture {}
            }
        }
    }

    private func closeDetails() {
        detailsState = nil
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
                set: { model.setEnabled(state.configuration.id, enabled: $0) }
            )) {
                Text(state.configuration.isEnabled ? "启用" : "已停用")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .tint(state.configuration.isEnabled ? .green : .secondary)
            .frame(width: 62)
            .help(state.configuration.isEnabled ? "停用 \(state.configuration.displayName)" : "启用 \(state.configuration.displayName)")
            .accessibilityLabel(state.configuration.isEnabled ? "停用 \(state.configuration.displayName)" : "启用 \(state.configuration.displayName)")

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button {
                    editor = .edit(state.configuration)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("编辑 \(state.configuration.displayName)")
                .accessibilityLabel("编辑 \(state.configuration.displayName)")

                Button {
                    alertSettingsState = state
                } label: {
                    Image(systemName: alertIcon(for: state))
                }
                .buttonStyle(.borderless)
                .help("设置 \(state.configuration.displayName) 的用量提醒")
                .accessibilityLabel("提醒设置")

                Button(role: .destructive) {
                    model.pendingDeletion = state.configuration
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除 \(state.configuration.displayName)")
                .accessibilityLabel("删除 \(state.configuration.displayName)")

                Button {
                    detailsState = state
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
                .help("查看 \(state.configuration.displayName) 的更多信息")
                .accessibilityLabel("更多信息")
            }
        }
    }

    private var groups: [(provider: ProviderDescriptor, states: [KeyUsageState])] {
        model.groups
    }

    @ViewBuilder
    private func credentialEditor(_ presentation: EditorPresentation) -> some View {
        switch presentation {
        case .add:
            CredentialEditorView(save: model.addValidatedCredential)
        case let .edit(configuration):
            CredentialEditorView(
                title: "编辑凭证",
                initialProviderID: configuration.providerID,
                initialName: configuration.displayName,
                initialSecret: environment.readKey(id: configuration.id) ?? "",
                initialMetadata: configuration.metadata
            ) { input in
                try await model.updateValidatedCredential(id: configuration.id, input: input)
            }
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

private extension CredentialManagementView {
    func alertSettingsModel(for state: KeyUsageState) -> CredentialAlertSettingsModel {
        CredentialAlertSettingsModel(
            credentialID: state.configuration.id,
            preferences: environment.settings.usagePreferences(for: state.configuration.id),
            metrics: state.snapshot?.normalizedMetrics ?? [],
            capabilities: environment.providerRegistry?.metricCapabilities(for: state.configuration) ?? []
        ) { preferences in
            environment.settings.setUsagePreferences(preferences, for: state.configuration.id)
        }
    }

    func alertIcon(for state: KeyUsageState) -> String {
        environment.settings.usagePreferences(for: state.configuration.id).notificationsEnabled
            ? "bell.badge"
            : "bell.slash"
    }
}
