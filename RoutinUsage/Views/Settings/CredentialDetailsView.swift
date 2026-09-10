import SwiftUI

struct CredentialDetailsView: View {
    let state: KeyUsageState
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var copiedModelID: String?
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                summary
                if state.configuration.providerID == .routin ||
                   state.configuration.providerID == .volcengine ||
                   state.configuration.providerID == .commandCode {
                    planDetails
                } else if state.configuration.providerID == .glm || state.configuration.providerID == .deepseek {
                    modelDetails
                }
                metrics
                metadata
            }
            .padding(24)
            .frame(minWidth: 440, alignment: .leading)
        }
        .frame(minWidth: 480, minHeight: 420)
        .navigationTitle("凭证详情")
        .onDisappear {
            copyResetTask?.cancel()
        }
    }

    @ViewBuilder
    private var modelDetails: some View {
        if let snapshot = state.snapshot {
            detailSection("账户与模型", symbol: "person.crop.circle") {
                allowedModelsSection(snapshot.allowedModels)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: descriptor.iconName)
                .font(.title2)
                .foregroundStyle(ProviderTheme.accentColor(for: state.configuration.providerID))
                .frame(width: 36, height: 36)
                .background(
                    ProviderTheme.background(for: state.configuration.providerID),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(state.configuration.displayName)
                    .font(.title2.weight(.semibold))
                Text("\(descriptor.displayName) · \(planName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(
                state.configuration.isEnabled ? "已启用" : "已停用",
                systemImage: state.configuration.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(state.configuration.isEnabled ? .green : .secondary)

            Button {
                if let onClose {
                    onClose()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("关闭凭证详情")
            .accessibilityLabel("关闭凭证详情")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("状态")
                .font(.headline)
            detailRow(
                "最近更新",
                state.lastSuccessAt.map { UsageFormatter.fullDateTime($0) } ?? "尚未成功更新"
            )
            detailRow("当前状态", UsageFormatter.statusText(state: state))
            if let snapshot = state.snapshot {
                detailRow("套餐", snapshot.planName.isEmpty ? planName : snapshot.planName)
                detailRow("数据时间", UsageFormatter.fullDateTime(snapshot.fetchedAt))
            }
        }
        .padding(14)
        .liquidGlassControlSurface()
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("用量指标")
                .font(.headline)
            if let snapshot = state.snapshot, !snapshot.normalizedMetrics.isEmpty {
                if state.configuration.providerID == .commandCode {
                    CommandCodeUsageMetricsView(
                        metrics: snapshot.normalizedMetrics,
                        now: .now
                    )
                } else {
                    NormalizedUsageMetricGrid(
                        metrics: snapshot.normalizedMetrics,
                        columns: 2,
                        resetTimeStyle: .relativeDuration,
                        now: .now
                    )
                }
            } else {
                Text("暂无用量数据")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var planDetails: some View {
        if let snapshot = state.snapshot {
            VStack(alignment: .leading, spacing: 18) {
                detailSection("套餐状态", symbol: "checklist") {
                    HStack(alignment: .firstTextBaseline, spacing: 20) {
                        detailColumn("套餐", snapshot.planName.isEmpty ? planName : snapshot.planName)
                        detailColumn("类型", snapshot.kind == .periodic ? "周期订阅" : "Token 资源包")
                        detailColumn("状态", displayStatus(snapshot))
                    }
                }

                detailSection("订阅与周期", symbol: "calendar") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: 20) {
                            detailColumn(
                                "订阅开始",
                                snapshot.subscriptionStartAt.map { UsageFormatter.fullDateTime($0) } ?? "接口未返回"
                            )
                            detailColumn(
                                "订阅结束",
                                snapshot.subscriptionEndAt.map { UsageFormatter.fullDateTime($0) } ?? "接口未返回"
                            )
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 20) {
                            detailColumn(
                                "计费模式",
                                snapshot.billingMode ?? "接口未返回"
                            )
                        }

                        if snapshot.kind == .periodic, state.configuration.providerID == .routin {
                            HStack(alignment: .firstTextBaseline, spacing: 20) {
                                detailColumn(
                                    "5 小时结束",
                                    UsageFormatter.fullDateTime(snapshot.fiveHour?.windowEnd)
                                )
                                detailColumn(
                                    "周结束",
                                    UsageFormatter.fullDateTime(snapshot.weekly?.windowEnd)
                                )
                            }
                        }
                    }
                }

                detailSection("账户与模型", symbol: "person.crop.circle") {
                    VStack(alignment: .leading, spacing: 12) {
                        if state.configuration.providerID == .routin {
                            detailColumn(
                                "分组倍率",
                                snapshot.groupMultipliers.isEmpty
                                    ? "—"
                                    : UsageFormatter.groupMultiplierText(snapshot.groupMultipliers)
                            )
                        }
                        allowedModelsSection(snapshot.allowedModels)
                    }
                }
            }
        }
    }

    private func allowedModelsSection(_ models: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("允许模型")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !models.isEmpty {
                    Text("\(models.count) 个 · 点击复制")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if models.isEmpty {
                Text("接口未返回")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                ModelIDChipFlow(models: models, copiedModelID: copiedModelID, onCopied: copyModelID)
            }
        }
    }

    private func copyModelID(_ modelID: String) {
        copyResetTask?.cancel()
        copiedModelID = modelID
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_200))
            guard !Task.isCancelled else { return }
            copiedModelID = nil
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)

            content()
        }
        .padding(14)
        .liquidGlassControlSurface()
    }

    private func detailColumn(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subscriptionStatus(_ status: Int?) -> String {
        if state.error == nil, state.snapshot != nil {
            if state.isStale {
                return "已过期"
            }
            switch status {
            case 1, nil:
                return "正常"
            case let value?:
                return "状态 \(value)"
            }
        }
        return UsageFormatter.statusText(state: state)
    }

    private func displayStatus(_ snapshot: UsageSnapshot) -> String {
        if let statusText = snapshot.statusText, !statusText.isEmpty {
            return statusText
        }
        if state.configuration.providerID == .volcengine {
            return "接口未返回"
        }
        return subscriptionStatus(snapshot.status)
    }

    private var metadata: some View {
        let visible = state.configuration.metadata
            .filter { key, _ in
                !["accessKeyID", "secretAccessKey", "apiKey", "token", "password", "cookie"].contains(key)
            }
            .sorted { $0.key < $1.key }

        return Group {
            if !visible.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("配置")
                        .font(.headline)
                    ForEach(visible, id: \.key) { key, value in
                        if key == "websiteURL", let url = URL(string: value) {
                            detailLinkRow(metadataLabel(for: key), url)
                        } else {
                            detailRow(metadataLabel(for: key), metadataValue(for: key, value: value))
                        }
                    }
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }

    private func detailLinkRow(_ label: String, _ url: URL) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()

            Link(url.absoluteString, destination: url)
                .foregroundStyle(Color.accentColor)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .help("在浏览器中打开 \(url.absoluteString)")
                .accessibilityLabel("打开 \(metadataValue(for: "websiteURL", value: url.absoluteString))")
        }
        .font(.callout)
    }

    private func metadataLabel(for key: String) -> String {
        switch key {
        case "balanceWarningThreshold": "低额度预警值"
        case "baseURL": "接口地址"
        case "planType": "计划类型"
        case "region": "区域"
        case "userID": "用户 ID"
        case "usageKind": "用量类型"
        case "websiteURL": "官网地址"
        default: key
        }
    }

    private func metadataValue(for key: String, value: String) -> String {
        switch key {
        case "planType":
            return value == "coding" ? "Coding Plan" : "Agent Plan"
        case "usageKind":
            return value == "tokenPack" ? "Token 资源包" : value
        default:
            return value
        }
    }

    private var descriptor: ProviderDescriptor {
        ProviderRegistry.builtInDescriptors.first { $0.id == state.configuration.providerID }!
    }

    private var planName: String {
        if let planName = state.snapshot?.planName, !planName.isEmpty {
            return planName
        }
        if state.configuration.providerID == .volcengine {
            return state.configuration.metadata["planType"] == "coding" ? "Coding Plan" : "Agent Plan"
        }
        return state.configuration.credentialKind == .bearerAPIKey
            ? (state.configuration.providerID == .routin ? "Plan Key" : "Bearer Token")
            : "API Key"
    }
}
