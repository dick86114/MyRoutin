import SwiftUI

struct HelpUpdateView: View {
    @Bindable var environment: AppEnvironment
    @State private var showingReleaseHistory = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(
                    title: "帮助与更新",
                    subtitle: "版本维护和问题反馈"
                )

                currentVersionSection
                updateSection
                feedbackSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await environment.loadReleaseHistoryIfNeeded()
        }
        .sheet(isPresented: $showingReleaseHistory) {
            ReleaseHistorySheet(state: environment.releaseHistoryState) {
                await environment.loadReleaseHistoryIfNeeded(force: true)
            }
        }
    }

    private var currentVersionSection: some View {
        settingSection {
            HStack(spacing: 12) {
                Text("当前版本")

                Text(RoutinUsageApp.currentVersion)
                    .monospacedDigit()

                Spacer(minLength: 12)

                Link(destination: currentReleaseURL) {
                    Label("GitHub", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("在 GitHub 查看当前版本")
            }

            Divider()

            Text("当前版本更新日志")
                .font(.headline)

            currentReleaseNotes

            HStack {
                Button("查看历史版本") {
                    showingReleaseHistory = true
                }
                .liquidGlassButton()
                .accessibilityLabel("查看历史版本更新日志")

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var currentReleaseNotes: some View {
        switch environment.releaseHistoryState {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在加载更新日志")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .foregroundStyle(.red)

                Button("重试") {
                    Task { await environment.loadReleaseHistoryIfNeeded(force: true) }
                }
                .liquidGlassButton()
            }
        case let .loaded(releases):
            if let current = releases.first(where: { $0.version == RoutinUsageApp.currentVersion }) {
                UpdateNotesView(notes: current.notes)
            } else {
                Text("此版本未提供更新日志")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var currentReleaseURL: URL {
        guard case let .loaded(releases) = environment.releaseHistoryState,
              let current = releases.first(where: { $0.version == RoutinUsageApp.currentVersion }) else {
            return RoutinUsageApp.releasesURL
        }
        return current.releaseURL
    }

    private var updateSection: some View {
        @Bindable var settings = environment.settings
        return settingSection {
            Text("应用更新")
                .font(.headline)

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

            Divider()

            updateStatusContent
        }
    }

    @ViewBuilder
    private var updateStatusContent: some View {
        switch environment.updateStatus {
        case .idle:
            HStack(spacing: 12) {
                Button("检测更新") {
                    Task { await environment.checkForUpdates() }
                }
                .liquidGlassButton()
                .accessibilityLabel("检测更新")

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

private struct ReleaseHistorySheet: View {
    @Environment(\.dismiss) private var dismiss

    let state: AppReleaseHistoryState
    let onRetry: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("历史版本更新日志")
                    .font(.title2.weight(.semibold))

                Spacer(minLength: 16)

                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在加载更新日志")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .foregroundStyle(.red)

                Button("重试") {
                    Task { await onRetry() }
                }
                .liquidGlassButton()
            }
            .padding(24)
        case let .loaded(releases):
            if releases.isEmpty {
                Text("暂无历史版本更新日志")
                    .foregroundStyle(.secondary)
                    .padding(24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(releases.enumerated()), id: \.element.id) { index, release in
                            releaseRow(release)

                            if index < releases.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    private func releaseRow(_ release: AppReleaseHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("v\(release.version)")
                    .font(.headline)

                Spacer(minLength: 12)

                if let publishedAt = release.publishedAt {
                    Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            UpdateNotesView(notes: release.notes)

            Link("在 GitHub 查看", destination: release.releaseURL)
                .font(.caption)
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .contain)
    }
}
