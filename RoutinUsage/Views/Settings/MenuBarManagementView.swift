import AppKit
import SwiftUI

private struct SystemPopoverArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX - 2, y: rect.minY + 2),
            control: CGPoint(x: rect.midX * 0.62, y: rect.maxY * 0.28)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + 2, y: rect.minY + 2),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX * 1.38, y: rect.maxY * 0.28)
        )
        path.closeSubpath()
        return path
    }
}

struct MenuBarManagementView: View {
    @Bindable var environment: AppEnvironment
    let ordering: CredentialOrderingController
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

                workspace
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var workspace: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                previewColumn
                    .frame(width: 440)

                cardList
                    .frame(minWidth: 360, maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 16) {
                previewColumn
                cardList
            }
        }
    }

    private var previewColumn: some View {
        preview
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var preview: some View {
        previewPanel(title: "预览", count: unifiedStates.count) {
            VStack(alignment: .trailing, spacing: 8) {
                systemMenuBarStrip(highlightIndicator: true)

                popoverContent
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            }
        }
    }

    private func systemMenuBarStrip(highlightIndicator: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "apple.logo")
                .font(.caption.weight(.semibold))
            Text("Finder")
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text("文件")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 12)

            menuBarIndicators
                .padding(.horizontal, highlightIndicator ? 6 : 0)
                .padding(.vertical, highlightIndicator ? 3 : 0)
                .background(
                    highlightIndicator ? Color.accentColor.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .overlay(alignment: .bottom) {
                    if highlightIndicator {
                        SystemPopoverArrow()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .frame(width: 24, height: 11)
                            .overlay {
                                SystemPopoverArrow()
                                    .stroke(.primary.opacity(0.12), lineWidth: 0.5)
                            }
                            .offset(y: 15)
                            .zIndex(2)
                    }
                }

            Image(systemName: "wifi")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("10:09")
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.primary.opacity(0.09), lineWidth: 0.5)
        }
    }

    private var menuBarIndicators: some View {
        HStack(spacing: 0) {
            if menuBarStates.isEmpty {
                Text("未显示指标")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                ForEach(menuBarStates, id: \.configuration.id) { state in
                    if let descriptor = descriptor(for: state) {
                        MenuBarIndicatorPreview(
                            state: state,
                            descriptor: descriptor,
                            metric: menuBarMetric(for: state)
                        )
                        .equatable()
                    }
                }
            }
        }
    }

    private var popoverContent: some View {
        VStack(spacing: 10) {
            ZStack {
                HStack {
                    Text("v1.0.0")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.primary.opacity(0.06), in: Capsule())

                    Spacer()

                    Image(systemName: "arrow.clockwise")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                }

                Image(nsImage: NSImage(named: "PopoverColorBrandLogo") ?? NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Text("账户用量")
                    .font(.headline)
                Spacer()
                Text("\(unifiedStates.count) 个凭证")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)

            if unifiedStates.isEmpty {
                Text("尚无可展示凭证")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            } else {
                VStack(spacing: 8) {
                    ForEach(unifiedStates, id: \.configuration.id) { state in
                        previewCredentialRow(state)
                    }
                }
                .padding(.horizontal, 10)
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text("最后刷新 刚刚")
                Spacer()
                Image(systemName: "gearshape")
                Image(systemName: "power")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previewCredentialRow(_ state: KeyUsageState) -> some View {
        HStack(spacing: 6) {
            Text(state.configuration.displayName)
            Text(providerName(for: state))
            Text("·")
                .foregroundStyle(.secondary)
            Text(planName(for: state.configuration))
            Spacer(minLength: 0)
        }
        .font(.callout.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            ProviderTheme.background(for: state.configuration.providerID),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    ProviderTheme.borderColor(for: state.configuration.providerID),
                    lineWidth: 0.8
                )
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
                itemHeight: 72,
                itemSpacing: 10,
                move: moveDisplay,
                card: { (state: UUID) in
                    managementCard(state)
                }
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
                    state: state,
                    descriptor: descriptor,
                    metric: menuBarMetric(for: state)
                )
                .equatable()
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

            metricMenu(for: state)

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

    private func moveDisplay(_ draggedID: UUID, to targetIndex: Int) -> Bool {
        let updated = displayOrder.movingDisplay(id: draggedID, toIndex: targetIndex)
        guard updated != displayOrder else { return false }

        var transaction = Transaction()
        transaction.animation = nil
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
        _ = moveDisplay(id, to: target)
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

    private func menuBarMetric(for state: KeyUsageState) -> NormalizedUsageMetric? {
        menuBarResolution(for: state).metric
    }

    private func menuBarResolution(for state: KeyUsageState) -> MenuBarMetricResolution {
        let id = state.configuration.id
        let preferences = environment.settings.usagePreferences(for: id)
        let capabilities = environment.providerRegistry?.metricCapabilities(for: state.configuration) ?? []
        return MenuBarMetricResolver.resolve(
            selectedMetricID: preferences.menuBarMetricID,
            metrics: state.snapshot?.normalizedMetrics ?? [],
            capabilities: capabilities
        )
    }

    private func metricMenu(for state: KeyUsageState) -> some View {
        let resolution = menuBarResolution(for: state)

        return Menu {
            Button("自动") {
                setMenuBarMetric(nil, for: state.configuration.id)
            }

            ForEach(metricOptions(for: state)) { option in
                Button(option.label) {
                    setMenuBarMetric(option.metricID, for: state.configuration.id)
                }
            }
        } label: {
            Label(selectedMetricTitle(for: state, resolution: resolution), systemImage: "gauge.with.dots.needle.33percent")
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("设置 \(state.configuration.displayName) 的菜单栏指标")
    }

    private func metricOptions(for state: KeyUsageState) -> [UsageMetricCapability] {
        MenuBarMetricResolver.options(
            metrics: state.snapshot?.normalizedMetrics ?? [],
            capabilities: environment.providerRegistry?.metricCapabilities(for: state.configuration) ?? []
        )
    }

    private func selectedMetricTitle(
        for state: KeyUsageState,
        resolution: MenuBarMetricResolution
    ) -> String {
        if resolution.isFallback {
            return "自动（原指标当前不可用）"
        }
        guard let selectedMetricID = resolution.selectedMetricID else {
            return "自动"
        }
        let metricTitle = state.snapshot?.normalizedMetrics.first { $0.id == selectedMetricID }?.label
        let capabilityTitle = environment.providerRegistry?
            .metricCapabilities(for: state.configuration)
            .first { $0.metricID == selectedMetricID }?
            .label
        return metricTitle ?? capabilityTitle ?? selectedMetricID
    }

    private func setMenuBarMetric(_ metricID: String?, for id: UUID) {
        var preferences = environment.settings.usagePreferences(for: id)
        preferences.menuBarMetricID = metricID
        environment.settings.setUsagePreferences(preferences, for: id)
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
