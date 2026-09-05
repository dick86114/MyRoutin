import SwiftUI

struct MenuBarManagementView: View {
    @Bindable var environment: AppEnvironment
    let ordering: CredentialOrderingController
    @State private var draggedID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayOrder: CredentialDisplayOrder {
        environment.settings.displayOrder
    }

    private var enabledIDs: Set<UUID> {
        Set(environment.store.visibleKeyIDs)
    }

    private var visibility: CredentialDisplayVisibility {
        displayOrder.visible(enabledIDs: enabledIDs)
    }

    private var unifiedStates: [KeyUsageState] {
        visibility.popoverIDs.compactMap { environment.store.state(for: $0) }
    }

    private var menuBarStates: [KeyUsageState] {
        visibility.menuBarIDs.compactMap { environment.store.state(for: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(
                    title: "菜单栏管理",
                    subtitle: "最多显示 \(CredentialDisplayOrder.maximumMenuBarCount) 个菜单栏指标"
                )

                previews
                cardList
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var previews: some View {
        GeometryReader { geometry in
            if geometry.size.width < 820 {
                VStack(alignment: .leading, spacing: 18) {
                    menuBarPreview
                    popoverPreview
                }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    menuBarPreview
                    popoverPreview
                }
            }
        }
        .frame(height: 178)
    }

    private var menuBarPreview: some View {
        previewPanel(title: "菜单栏预览", count: menuBarStates.count) {
            HStack(spacing: 0) {
                if menuBarStates.isEmpty {
                    Text("尚未选择菜单栏指标")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(menuBarStates, id: \.configuration.id) { state in
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
        }
    }

    private var popoverPreview: some View {
        previewPanel(title: "弹窗预览", count: unifiedStates.count) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(unifiedStates.prefix(3), id: \.configuration.id) { state in
                    if let descriptor = descriptor(for: state) {
                        CredentialSummaryRow(
                            state: state,
                            descriptor: descriptor,
                            planType: planName(for: state.configuration)
                        )
                    }
                }
                if unifiedStates.count > 3 {
                    Text("还有 \(unifiedStates.count - 3) 个凭证")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func previewPanel<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
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

            content()
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassSurface(cornerRadius: 16)
    }

    private var cardList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("凭证顺序")
                    .font(.headline)
                Spacer()
                Text("\(unifiedStates.count) 个")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ReorderableCredentialCardList(
                ids: unifiedStates.map(\.configuration.id),
                draggedID: draggedID,
                itemHeight: 72,
                itemSpacing: 10,
                move: moveDisplay
            , card: { (state: UUID) in
                managementCard(state)
            }, externalDraggedID: $draggedID
        )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassSurface(cornerRadius: 16)
    }

    @ViewBuilder
    private func managementCard(_ id: UUID) -> some View {
        if let state = unifiedStates.first(where: { $0.configuration.id == id }) {
            managementCardContent(state)
        } else {
            Color.clear
        }
    }

    private func managementCardContent(_ state: KeyUsageState) -> some View {
        let id = state.configuration.id
        let isInMenuBar = displayOrder.menuBarCredentialIDs.contains(id)

        return HStack(spacing: 14) {
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            if let descriptor = descriptor(for: state) {
                MenuBarIndicatorPreview(
                    environment: environment,
                    state: state,
                    descriptor: descriptor
                )
                .frame(width: 42, height: 32)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(state.configuration.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    if isInMenuBar {
                        Text("菜单栏")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.14), in: Capsule())
                    }
                }

                Text("\(providerName(for: state)) · \(planName(for: state.configuration))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Button {
                setMenuBarMembership(isInMenuBar: !isInMenuBar, id: id)
            } label: {
                Image(systemName: isInMenuBar ? "minus.circle" : "plus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(!isInMenuBar && menuBarStates.count >= CredentialDisplayOrder.maximumMenuBarCount)
            .help(isInMenuBar ? "从菜单栏移除 \(state.configuration.displayName)" : "添加到菜单栏 \(state.configuration.displayName)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassControlSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(state.configuration.displayName)，\(providerName(for: state))，\(planName(for: state.configuration))，\(isInMenuBar ? "已加入菜单栏" : "未加入菜单栏")"
        )
        .accessibilityAction(named: isInMenuBar ? "从菜单栏移除" : "添加到菜单栏") {
            setMenuBarMembership(isInMenuBar: !isInMenuBar, id: id)
        }
        .accessibilityAction(named: "上移") {
            moveByOffset(id: id, offset: -1)
        }
        .accessibilityAction(named: "下移") {
            moveByOffset(id: id, offset: 1)
        }
    }

    private func moveDisplay(_ draggedID: UUID, before targetID: UUID) -> Bool {
        let updated = displayOrder.movingDisplay(id: draggedID, before: targetID)
        guard updated != displayOrder else { return false }

        var transaction = Transaction()
        transaction.animation = reduceMotion
            ? nil
            : .interactiveSpring(response: 0.28, dampingFraction: 0.82)
        withTransaction(transaction) {
            environment.settings.displayOrder = updated
        }
        return true
    }

    private func moveByOffset(id: UUID, offset: Int) {
        let ids = unifiedStates.map(\.configuration.id)
        guard let source = ids.firstIndex(of: id) else { return }
        let target = max(0, min(ids.count - 1, source + offset))
        guard target != source else { return }
        _ = moveDisplay(id, before: ids[target])
    }

    private func setMenuBarMembership(isInMenuBar: Bool, id: UUID) {
        var updated = displayOrder
        if isInMenuBar {
            let index = visibility.popoverIDs.firstIndex(of: id) ?? visibility.popoverIDs.count
            updated = updated.addingToMenuBar(id, toIndex: index)
        } else {
            updated = updated.removingFromMenuBar(id)
        }
        updated.menuBarCredentialIDs = updated.popoverCredentialIDs.filter {
            updated.menuBarCredentialIDs.contains($0)
        }

        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)) {
            environment.settings.displayOrder = updated
        }
    }

    private func descriptor(for state: KeyUsageState) -> ProviderDescriptor? {
        ProviderRegistry.builtInDescriptors.first { $0.id == state.configuration.providerID }
    }

    private func providerName(for state: KeyUsageState) -> String {
        descriptor(for: state)?.displayName ?? state.configuration.providerID.rawValue
    }

    private func planName(for configuration: KeyConfiguration) -> String {
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
}
