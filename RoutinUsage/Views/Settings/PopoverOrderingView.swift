import SwiftUI
import UniformTypeIdentifiers

struct PopoverOrderingView: View {
    @Bindable var environment: AppEnvironment
    let ordering: CredentialOrderingController
    @State private var draggedID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visiblePopoverIDs: [UUID] {
        environment.settings.displayOrder.visible(enabledIDs: enabledIDs).popoverIDs
    }

    private var visibleStates: [KeyUsageState] {
        visiblePopoverIDs.compactMap { environment.store.state(for: $0) }
    }

    private var enabledIDs: Set<UUID> {
        Set(environment.store.visibleKeyIDs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(
                    title: "弹窗显示",
                    subtitle: "已启用凭证的弹窗顺序"
                )

                simulatedPopover

                Text("实时同步到菜单栏弹窗")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var simulatedPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            if visibleStates.isEmpty {
                ContentUnavailableView(
                    "没有可显示凭证",
                    systemImage: "rectangle.bottomthird.inset.filled",
                    description: Text("启用凭证后会按此顺序显示")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ForEach(visibleStates, id: \.configuration.id) { state in
                    popoverRow(state)
                }
            }
        }
        .frame(width: 440, alignment: .leading)
        .padding(16)
        .liquidGlassSurface(cornerRadius: 18)
    }

    private func popoverRow(_ state: KeyUsageState) -> some View {
        HStack(spacing: 12) {
            if let descriptor = descriptor(for: state) {
                CredentialSummaryRow(
                    state: state,
                    descriptor: descriptor,
                    planType: planName(for: state.configuration),
                    leading: AnyView(providerIcon(descriptor)),
                    trailing: AnyView(
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                    )
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlassSurface(cornerRadius: 12)
        .contentShape(Rectangle())
        .onDrag {
            draggedID = state.configuration.id
            let provider = NSItemProvider(object: state.configuration.id.uuidString as NSString)
            provider.registerObject(state.configuration.id.uuidString as NSString, visibility: .all)
            return provider
        }
        .onDrop(
            of: [UTType.credentialID],
                delegate: CredentialDropDelegate(
                    targetID: state.configuration.id,
                    draggedID: draggedID,
                    reduceMotion: reduceMotion,
                    canAccept: { draggedID in
                    visiblePopoverIDs.contains(draggedID)
                },
                move: { dragged in
                    let targetIndex = visiblePopoverIDs.firstIndex(of: state.configuration.id) ?? 0
                    ordering.moving(.popover, id: dragged, toIndex: targetIndex)
                },
                finish: { draggedID = nil }
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(state.configuration.displayName)，供应商 \(providerName(for: state))，套餐 \(planName(for: state.configuration))"
        )
    }

    private func providerIcon(_ descriptor: ProviderDescriptor) -> some View {
        Image(systemName: descriptor.iconName)
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
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
