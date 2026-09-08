import SwiftUI

struct HelpUpdateView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(
                    title: "帮助与更新",
                    subtitle: "版本维护和问题反馈"
                )

                currentVersionSection
                updateChannelSection
                updateStatusSection
                feedbackSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var currentVersionSection: some View {
        settingSection {
            LabeledContent("当前版本") {
                Text(RoutinUsageApp.currentVersion)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("当前版本 \(RoutinUsageApp.currentVersion)")
        }
    }

    private var updateChannelSection: some View {
        @Bindable var settings = environment.settings
        return settingSection {
            Picker("更新通道", selection: $settings.updateChannel) {
                Text("GitHub 直连").tag(UpdateChannel.direct)
                Text("CDN 加速").tag(UpdateChannel.cdn)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("更新通道")

            if environment.settings.updateChannel == .cdn {
                Picker("CDN 源", selection: $settings.updateCDNBase) {
                    ForEach(AppSettings.cdnBases, id: \.self) { base in
                        Text(base.replacingOccurrences(of: "https://", with: "")).tag(base)
                    }
                }
                .accessibilityLabel("CDN 加速源")

                Text("大陆网络建议选择 CDN 加速；若某镜像不可用可切换其他源。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var updateStatusSection: some View {
        settingSection {
            switch environment.updateStatus {
            case .idle:
                HStack(spacing: 12) {
                    Button("检查更新") {
                        Task { await environment.checkForUpdates() }
                    }
                    .liquidGlassButton()
                    .accessibilityLabel("检查更新")

                    Spacer(minLength: 0)
                }
            case .checking:
                HStack {
                    Text("正在检查更新")
                    Spacer(minLength: 8)
                    ProgressView()
                        .controlSize(.small)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在检查更新")
            case let .available(update):
                availableUpdate(update)
            case let .downloading(progress):
                downloadingUpdate(progress)
            case let .completed(version):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("更新完成，当前版本 \(version)")
                }
                .accessibilityElement(children: .combine)
            case let .failed(message):
                VStack(alignment: .leading, spacing: 12) {
                    Text(message)
                        .foregroundStyle(.red)

                    Button("重试") {
                        Task { await environment.checkForUpdates() }
                    }
                    .liquidGlassButton()
                }
            }
        }
    }

    private func availableUpdate(_ update: AppUpdate) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("发现新版本 \(update.version)")
                .font(.headline)

            UpdateNotesView(notes: update.notes)

            HStack(spacing: 12) {
                Button("安装更新") {
                    Task { await environment.installAvailableUpdate() }
                }
                .liquidGlassButton(prominent: true)
                .accessibilityLabel("安装更新")

                Link("查看发布说明", destination: update.releaseURL)
                    .font(.callout)
                    .accessibilityLabel("查看发布说明")

                Spacer(minLength: 0)
            }
        }
    }

    private func downloadingUpdate(_ progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("正在下载更新")
                Spacer(minLength: 8)

                if let progress {
                    Text("\(Int(progress * 100))%")
                        .monospacedDigit()
                }
            }

            if let progress {
                ProgressView(value: progress, total: 1)
            } else {
                ProgressView()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            progress.map { "正在下载更新，已完成 \(Int($0 * 100))%" } ?? "正在下载更新"
        )
    }

    private var feedbackSection: some View {
        settingSection {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("遇到问题？")
                        .font(.headline)

                    Text("发送问题描述和本地诊断日志")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Button("提交问题") {
                    Task { await environment.openIssueReport() }
                }
                .liquidGlassButton()
                .accessibilityLabel("提交问题")
            }
        }
    }

    private func settingSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .liquidGlassSurface(cornerRadius: 16)
    }
}
