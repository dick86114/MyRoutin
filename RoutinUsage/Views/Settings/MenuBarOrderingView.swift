import SwiftUI
import UniformTypeIdentifiers

struct MenuBarOrderingView: View {
    @Bindable var environment: AppEnvironment
    let ordering: CredentialOrderingController
    @State private var draggedID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibility: CredentialDisplayVisibility {
        environment.settings.displayOrder.visible(enabledIDs: enabledIDs)
    }

    private var enabledIDs: Set<UUID> {
        Set(environment.store.visibleKeyIDs)
    }

    private var selectedStates: [KeyUsageState] {
        visibility.menuBarIDs.compactMap { environment.store.state(for: $0) }
    }

    private var candidateStates: [KeyUsageState] {
        visibility.menuBarCandidateIDs.compactMap { environment.store.state(for: $0) }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsPageHeader(
                        title: "菜单栏显示",
                        subtitle: "最多显示 \(CredentialDisplayOrder.maximumMenuBarCount) 个指标"
                    )

                    menuBarSimulation

                    if geometry.size.width < 760 {
                        VStack(alignment: .leading, spacing: 18) {
                            selectionPanel
                            candidatePanel
                        }
                    } else {
                        HStack(alignment: .top, spacing: 20) {
                            selectionPanel
                            candidatePanel
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var menuBarSimulation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("模拟菜单栏")
                .font(.headline)

            HStack(spacing: 0) {
                if selectedStates.isEmpty {
                    Text("尚未选择菜单栏指标")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedStates, id: \.configuration.id) { state in
                        if let descriptor = descriptor(for: state) {
                            MenuBarIndicatorPreview(
                                environment: environment,
                                state: state,
                                descriptor: descriptor
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .liquidGlassControlSurface()
        }
    }

    private var selectionPanel: some View {
        orderingPanel(
            title: "展示区",
            count: selectedStates.count,
            emptyTitle: "尚未选择指标",
            emptyDescription: "从待选区拖入或点击添加"
        ) {
            ForEach(selectedStates, id: \.configuration.id) { state in
                selectedRow(state)
            }
        }
    }

    private var candidatePanel: some View {
        orderingPanel(
            title: "待选区",
            count: candidateStates.count,
            emptyTitle: "没有待选凭证",
            emptyDescription: "启用凭证后会出现在这里"
        ) {
            ForEach(candidateStates, id: \.configuration.id) { state in
                candidateRow(state)
            }
        }
    }

    private func orderingPanel<Rows: View>(
        title: String,
        count: Int,
        emptyTitle: String,
        emptyDescription: String,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(count) 个")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if count == 0 {
                ContentUnavailableView(emptyTitle, systemImage: "tray", description: Text(emptyDescription))
                    .frame(maxWidth: .infinity, minHeight: 148)
                    .liquidGlassControlSurface()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    rows()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .liquidGlassSurface(cornerRadius: 16)
    }

    private func selectedRow(_ state: KeyUsageState) -> some View {
        orderingRow(state, isInMenuBar: true)
            .onDrag {
                draggedID = state.configuration.id
                let provider = NSItemProvider(object: state.configuration.id.uuidString as NSString)
                provider.registerObject(state.configuration.id.uuidString as NSString, visibility: .all)
                return provider
            }
            .onDrop(
                of: [UTType.text],
                delegate: CredentialDropDelegate(
                    targetID: state.configuration.id,
                    draggedID: draggedID,
                    reduceMotion: reduceMotion,
                    canAccept: { draggedID in
                        selectedStates.contains { $0.configuration.id == draggedID }
                            || (candidateStates.contains { $0.configuration.id == draggedID }
                                && selectedStates.count < CredentialDisplayOrder.maximumMenuBarCount)
                    },
                    move: { dragged in move(dragged, before: state.configuration.id) },
                    finish: { draggedID = nil }
                )
            )
    }

    private func candidateRow(_ state: KeyUsageState) -> some View {
        orderingRow(state, isInMenuBar: false)
            .onDrag {
                draggedID = state.configuration.id
                let provider = NSItemProvider(object: state.configuration.id.uuidString as NSString)
                provider.registerObject(state.configuration.id.uuidString as NSString, visibility: .all)
                return provider
            }
            .onDrop(
                of: [UTType.text],
                delegate: CredentialDropDelegate(
                    targetID: state.configuration.id,
                    draggedID: draggedID,
                    reduceMotion: reduceMotion,
                    canAccept: { draggedID in
                        candidateStates.contains { $0.configuration.id == draggedID }
                    },
                    move: { dragged in move(dragged, before: state.configuration.id) },
                    finish: { draggedID = nil }
                )
            )
    }

    private func orderingRow(_ state: KeyUsageState, isInMenuBar: Bool) -> some View {
        HStack(spacing: 12) {
            if let descriptor = descriptor(for: state) {
                MenuBarIndicatorPreview(
                    environment: environment,
                    state: state,
                    descriptor: descriptor
                )
                .frame(width: 36, height: 28)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(state.configuration.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(providerName(for: state))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            rowActions(for: state, isInMenuBar: isInMenuBar)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassControlSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.configuration.displayName)，\(providerName(for: state))，\(isInMenuBar ? "展示区" : "待选区")")
    }

    private func rowActions(
        for state: KeyUsageState,
        isInMenuBar: Bool
    ) -> some View {
        let id = state.configuration.id

        return HStack(spacing: 6) {
            if isInMenuBar {
                Button {
                    ordering.removingFromMenuBar(id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("从菜单栏移除 \(state.configuration.displayName)")
            } else {
                Button {
                    addingToMenuBar(id)
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(selectedStates.count >= CredentialDisplayOrder.maximumMenuBarCount)
                .help("添加到菜单栏 \(state.configuration.displayName)")
            }
        }
        .accessibilityAction(named: isInMenuBar ? "从菜单栏移除" : "添加到菜单栏") {
            if isInMenuBar {
                ordering.removingFromMenuBar(id)
            } else if selectedStates.count < CredentialDisplayOrder.maximumMenuBarCount {
                addingToMenuBar(id)
            }
        }
    }

    private func move(_ dragged: UUID, before target: UUID) {
        if visibility.menuBarIDs.contains(dragged) {
            if visibility.menuBarIDs.contains(target) {
                let index = visibility.menuBarIDs.firstIndex(of: target) ?? 0
                ordering.moving(.menuBar, id: dragged, toIndex: index)
            }
        } else if visibility.menuBarIDs.contains(target) {
            let index = visibility.menuBarIDs.firstIndex(of: target) ?? 0
            ordering.addingToMenuBar(dragged, toIndex: index)
        } else if let candidateIndex = visibility.menuBarCandidateIDs.firstIndex(of: target) {
            let targetID = visibility.menuBarCandidateIDs[candidateIndex]
            let popoverIndex = visibility.popoverIDs.firstIndex(of: targetID) ?? 0
            ordering.moving(.popover, id: dragged, toIndex: popoverIndex)
        }
    }

    private func addingToMenuBar(_ id: UUID) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
            ordering.addingToMenuBar(id, toIndex: visibility.menuBarIDs.count)
        }
    }

    private func descriptor(for state: KeyUsageState) -> ProviderDescriptor? {
        ProviderRegistry.builtInDescriptors.first { $0.id == state.configuration.providerID }
    }

    private func providerName(for state: KeyUsageState) -> String {
        descriptor(for: state)?.displayName ?? state.configuration.providerID.rawValue
    }
}
