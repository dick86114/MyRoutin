import AppKit
import SwiftUI

@MainActor
struct UsagePopoverView: View {
    typealias InstallAvailableUpdate = @MainActor () async -> Void
    typealias StartCodexGroupDetection = @MainActor (UUID) async -> Void

    @Bindable var store: UsageStore
    @Bindable var settings: AppSettings
    @Bindable var codexGroupDetection: CodexGroupDetectionService
    let updateStatus: AppUpdateStatus
    let installAvailableUpdate: InstallAvailableUpdate
    let startCodexGroupDetection: StartCodexGroupDetection
    let openSettings: @MainActor () -> Void

    @Environment(\.openWindow) private var openWindow
    @State private var pendingDetectionKeyID: UUID?
    @State private var providerFilter: ProviderID?
    @State private var selectedUpdate: AppUpdate?
    @State private var isUpdateIndicatorVisible = true
    @State private var showRefreshSuccess = false
    @State private var isVersionLinkHovered = false
    @State private var isUpdateBadgeHovered = false
    @State private var scrollMetrics = PopoverScrollMetrics(contentHeight: 0, contentOffset: 0)

    init(
        store: UsageStore,
        settings: AppSettings,
        codexGroupDetection: CodexGroupDetectionService,
        updateStatus: AppUpdateStatus = .idle,
        installAvailableUpdate: @escaping InstallAvailableUpdate = {},
        startCodexGroupDetection: @escaping StartCodexGroupDetection = { _ in },
        openSettings: @escaping @MainActor () -> Void = {}
    ) {
        self.store = store
        self.settings = settings
        self.codexGroupDetection = codexGroupDetection
        self.updateStatus = updateStatus
        self.installAvailableUpdate = installAvailableUpdate
        self.startCodexGroupDetection = startCodexGroupDetection
        self.openSettings = openSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    usageListHeader

                    usageList
                        .padding(.vertical, 4)
                        .padding(.bottom, 8)

                    footerStatuses
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: PopoverScrollMetricsKey.self,
                            value: PopoverScrollMetrics(
                                contentHeight: geometry.size.height,
                                contentOffset: -geometry.frame(in: .named("popoverScroll")).minY
                            )
                        )
                    }
                )
            }
            .coordinateSpace(name: "popoverScroll")
            .overlay(alignment: .trailing) {
                GeometryReader { geometry in
                    ThinVerticalScrollIndicator(
                        metrics: scrollMetrics,
                        viewportHeight: geometry.size.height
                    )
                }
                .frame(width: 4)
                .padding(.trailing, 1)
            }
            .onPreferenceChange(PopoverScrollMetricsKey.self) { scrollMetrics = $0 }

            Divider()

            bottomBar
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(width: 440)
        // 窗口偶尔高于内容时固定顶部对齐，避免内容悬浮居中。
        .frame(maxHeight: maxPopoverHeight, alignment: .top)
        .liquidGlassWindowBackground()
        .overlay {
            updateReleaseOverlay
        }
        .confirmationDialog(
            "获取 Codex 当前分组？",
            isPresented: Binding(
                get: { pendingDetectionKeyID != nil },
                set: { if !$0 { pendingDetectionKeyID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("继续") {
                guard let keyID = pendingDetectionKeyID else { return }
                pendingDetectionKeyID = nil
                Task {
                    await startCodexGroupDetection(keyID)
                    if codexGroupDetection.state(for: keyID) == .needsLogin {
                        openWindow(id: "routin-check-in")
                    }
                }
            }
            Button("取消", role: .cancel) { pendingDetectionKeyID = nil }
        } message: {
            Text("将发送一次真实 Codex 请求并产生极少量额度消耗。")
        }
    }
}

private extension UsagePopoverView {
    var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Link(destination: RoutinUsageApp.releasesURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .imageScale(.small)
                        Text("v\(RoutinUsageApp.currentVersion)")
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background {
                        Capsule()
                            .fill(Color.primary.opacity(isVersionLinkHovered ? 0.12 : 0.055))
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(isVersionLinkHovered ? 0.24 : 0.12))
                    }
                }
                .buttonStyle(.plain)
                .onHover { isVersionLinkHovered = $0 }
                .animation(.easeInOut(duration: 0.15), value: isVersionLinkHovered)
                .foregroundStyle(.secondary)
                .help("打开 Releases 页面")
                .accessibilityLabel("当前版本 v\(RoutinUsageApp.currentVersion)，打开 Releases 页面")

                if case let .available(update) = updateStatus {
                    Button {
                        selectedUpdate = update
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                            .frame(width: 22, height: 22)
                            .background {
                                Circle()
                                    .fill(Color.green.opacity(0.10))
                            }
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.green.opacity(0.55), lineWidth: 1)
                            }
                            .opacity(isUpdateIndicatorVisible ? 1 : 0.28)
                            .scaleEffect(isUpdateBadgeHovered ? 1.08 : isUpdateIndicatorVisible ? 1 : 0.94)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                                    isUpdateIndicatorVisible = false
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .onHover { isUpdateBadgeHovered = $0 }
                    .help("查看 v\(update.version) 更新详情")
                    .accessibilityLabel("发现新版本 v\(update.version)，查看更新详情")
                }
            }
            .overlay(alignment: .leading) {
                EmptyView()
            }

            Spacer()

            GlassIconButton(
                action: { openSettings() },
                help: "设置"
            ) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
            }
            .keyboardShortcut(",")
            .accessibilityLabel("打开设置")
        }
        .overlay(alignment: .center) {
            Link(destination: RoutinUsageApp.websiteURL) {
                Image(nsImage: NSImage(named: "PopoverColorBrandLogo") ?? NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(4)
                    .frame(width: 32, height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.black.opacity(0.72))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.52),
                                        .white.opacity(0.14),
                                        .white.opacity(0.38)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .white.opacity(0.16), radius: 5, x: 0, y: 0)
                    .shadow(color: .white.opacity(0.07), radius: 12, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.26), radius: 2.5, y: 1.5)
            }
            .buttonStyle(.plain)
            .help("打开 MyToken 官网")
            .accessibilityLabel("打开 MyToken 官网")
        }
    }

    @ViewBuilder
    var usageList: some View {
        if store.visibleKeyIDs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "key.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(store.orderedKeyIDs.isEmpty ? "尚未配置 Key" : "没有启用的 Key")
                    .font(.headline)
                Text(store.orderedKeyIDs.isEmpty ? "请在设置中添加一个 plan Key" : "请在设置中启用至少一个 Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("空配置，尚未配置 Key")
        } else {
            VStack(spacing: 8) {
                ForEach(filteredPopoverKeyIDs, id: \.self) { id in
                    if let state = store.state(for: id) {
                        UsageRowView(
                            state: state,
                            detectionState: codexGroupDetection.state(for: id),
                            detectionRecord: codexGroupDetection.record(for: id),
                            isAnotherDetectionActive: codexGroupDetection.activeKeyID != nil
                                && codexGroupDetection.activeKeyID != id,
                            requestDetection: { pendingDetectionKeyID = id },
                            actions: nil
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    var popoverKeyIDs: [UUID] {
        let enabledIDs = Set(store.visibleKeyIDs)
        let visibility = settings.displayOrder.visible(enabledIDs: enabledIDs)
        return visibility.popoverIDs
    }

    var maxPopoverHeight: CGFloat {
        let visibleFrame = NSScreen.main?.visibleFrame
        let visibleHeight = visibleFrame?.height ?? 800
        return visibleHeight * 0.9
    }

    var usageListHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("账户用量")
                    .font(.title3.weight(.semibold))
                Text("\(filteredPopoverKeyIDs.count) 个 Key")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            WrappingFilterChips {
                filterChip(title: "全部", isSelected: providerFilter == nil) {
                    providerFilter = nil
                }

                ForEach(visibleProviderIDs, id: \.self) { providerID in
                    filterChip(
                        title: providerName(providerID),
                        isSelected: providerFilter == providerID
                    ) {
                        providerFilter = providerFilter == providerID ? nil : providerID
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("账户用量，共 \(filteredPopoverKeyIDs.count) 个 Key")
    }

    @ViewBuilder
    var updateReleaseOverlay: some View {
        if let selectedUpdate {
            ZStack {
                Color.black.opacity(0.34)
                    .ignoresSafeArea()

                UpdateReleaseDetailView(
                    update: selectedUpdate,
                    onCancel: { self.selectedUpdate = nil },
                    onConfirm: {
                        self.selectedUpdate = nil
                        Task { await installAvailableUpdate() }
                    }
                )
                .padding(.horizontal, 22)
            }
            .transition(.opacity)
        }
    }

    var filteredPopoverKeyIDs: [UUID] {
        guard let providerFilter else { return popoverKeyIDs }
        return popoverKeyIDs.filter {
            store.state(for: $0)?.configuration.providerID == providerFilter
        }
    }

    var visibleProviderIDs: [ProviderID] {
        let visibleIDs = Set(popoverKeyIDs.compactMap {
            store.state(for: $0)?.configuration.providerID
        })
        return ProviderID.allCases.filter { visibleIDs.contains($0) }
    }

    func providerName(_ providerID: ProviderID) -> String {
        ProviderRegistry.builtInDescriptors.first(where: { $0.id == providerID })?.displayName
            ?? providerID.rawValue
    }

    func filterChip(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        ProviderFilterChip(title: title, isSelected: isSelected, action: action)
    }
}

private struct ProviderFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(isHovered ? 0.10 : 0.05))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.58) : Color.primary.opacity(isHovered ? 0.24 : 0.12),
                            lineWidth: 1
                        )
                }
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(title)供应商筛选")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

}

private extension UsagePopoverView {
    @ViewBuilder
    var footerStatuses: some View {
        VStack(alignment: .leading, spacing: 9) {
            if case let .downloading(progress) = updateStatus {
                updateProgressView(progress)
            }

            if case let .completed(version) = updateStatus {
                Label("更新完成，当前版本 \(version)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityElement(children: .combine)
            }

            codexGroupDetectionStatus
        }
    }

    var bottomBar: some View {
        HStack(spacing: 10) {
            GlassIconButton(
                action: { Task { await store.refreshAll() } },
                help: "刷新全部 Key"
            ) {
                Group {
                    if store.isRefreshing {
                        TimelineView(.animation) { timeline in
                            let angle = timeline.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: 1) * 360
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .rotationEffect(.degrees(angle))
                        }
                    } else if showRefreshSuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .transition(.opacity)
                    }
                }
                .font(.system(size: 13, weight: .medium))
            }
            .disabled(store.isRefreshing || store.visibleKeyIDs.isEmpty)
            .accessibilityLabel(store.isRefreshing ? "正在刷新全部 Key" : "刷新全部 Key")
            .onChange(of: store.isRefreshing) { _, isRefreshing in
                if !isRefreshing {
                    withAnimation(.spring(duration: 0.3)) {
                        showRefreshSuccess = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeOut(duration: 0.35)) {
                            showRefreshSuccess = false
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: store.isRefreshing ? "arrow.triangle.2.circlepath" : "clock")
                    .accessibilityHidden(true)
                Text(refreshDescription)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(refreshAccessibilityLabel)

            Spacer(minLength: 4)

            GlassIconButton(
                action: { NSApplication.shared.terminate(nil) },
                help: "退出 MyToken"
            ) {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .medium))
            }
            .keyboardShortcut("q")
            .accessibilityLabel("退出 MyToken")
        }
    }

    @ViewBuilder
    var codexGroupDetectionStatus: some View {
        let activeStates = store.visibleKeyIDs.compactMap { keyID -> (KeyUsageState, CodexGroupDetectionState)? in
            guard let keyState = store.state(for: keyID) else {
                return nil
            }
            let detectionState = codexGroupDetection.state(for: keyID)
            guard detectionState != .idle else {
                return nil
            }
            return (keyState, detectionState)
        }

        if let (keyState, detectionState) = activeStates.first(where: { $0.1.isBusy || $0.1 == .needsLogin })
            ?? activeStates.first {
            HStack(alignment: .top, spacing: 6) {
                codexGroupDetectionStatusIcon(for: detectionState)
                Text("Codex 分组：\(keyState.configuration.displayName)，\(codexGroupDetectionText(for: keyState, state: detectionState))")
                    .lineLimit(2)
                Spacer(minLength: 4)
            }
            .font(.caption)
            .foregroundStyle(codexGroupDetectionColor(for: detectionState))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Codex 分组检测：\(keyState.configuration.displayName)，\(codexGroupDetectionText(for: keyState, state: detectionState))")
        }
    }

    @ViewBuilder
    func codexGroupDetectionStatusIcon(for state: CodexGroupDetectionState) -> some View {
        if state.isBusy {
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
        } else {
            Image(systemName: codexGroupDetectionSymbol(for: state))
                .accessibilityHidden(true)
        }
    }

    func codexGroupDetectionText(
        for keyState: KeyUsageState,
        state: CodexGroupDetectionState
    ) -> String {
        if state == .succeeded,
           let groupName = codexGroupDetection.record(for: keyState.configuration.id)?.groupName {
            return "已获取当前分组：\(groupName)"
        }
        return state.statusText
    }

    func codexGroupDetectionSymbol(for state: CodexGroupDetectionState) -> String {
        if state.isBusy {
            return "arrow.triangle.2.circlepath"
        }
        if state == .succeeded {
            return "checkmark.circle.fill"
        }
        if state == .needsLogin {
            return "person.crop.circle.badge.exclamationmark"
        }
        return state.isFailure ? "exclamationmark.triangle.fill" : "info.circle"
    }

    func codexGroupDetectionColor(for state: CodexGroupDetectionState) -> Color {
        if state == .succeeded {
            return .green
        }
        return state.isFailure ? .orange : .secondary
    }

    @ViewBuilder
    func updateProgressView(_ progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle")
                    .accessibilityHidden(true)
                Text("正在下载更新")
                Spacer(minLength: 4)
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
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            progress.map { "正在下载更新，已完成 \(Int($0 * 100))%" } ?? "正在下载更新"
        )
    }

    var latestRefreshDate: Date? {
        store.states.values.compactMap(\.lastSuccessAt).max()
    }

    var refreshDescription: String {
        if store.isRefreshing {
            return "正在刷新"
        }
        guard let latestRefreshDate else {
            return "尚未刷新"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "最后刷新 \(formatter.string(from: latestRefreshDate))"
    }

    var refreshAccessibilityLabel: String {
        if store.isRefreshing {
            return "正在刷新用量"
        }
        guard latestRefreshDate != nil else {
            return "尚未刷新用量"
        }
        return refreshDescription
    }
}

extension AppUpdate: Identifiable {
    var id: String { version }
}

private struct PopoverScrollMetrics: Equatable {
    var contentHeight: CGFloat = 0
    var contentOffset: CGFloat = 0
}

private struct PopoverScrollMetricsKey: PreferenceKey {
    static var defaultValue = PopoverScrollMetrics()

    static func reduce(value: inout PopoverScrollMetrics, nextValue: () -> PopoverScrollMetrics) {
        value = nextValue()
    }
}

private struct ThinVerticalScrollIndicator: View {
    let metrics: PopoverScrollMetrics
    let viewportHeight: CGFloat

    var body: some View {
        let visibleHeight = min(max(viewportHeight, 1), max(metrics.contentHeight, 1))
        let scrollRange = max(metrics.contentHeight - visibleHeight, 0)
        let thumbHeight = max(32, visibleHeight * visibleHeight / max(metrics.contentHeight, 1))
        let travelRange = max(visibleHeight - thumbHeight, 0)
        let thumbOffset = scrollRange > 0
            ? min(max(metrics.contentOffset / scrollRange, 0), 1) * travelRange
            : 0

        Capsule()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 3, height: visibleHeight)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.primary.opacity(0.36))
                    .frame(height: thumbHeight)
                    .offset(y: thumbOffset)
            }
            .clipShape(Capsule())
            .opacity(scrollRange > 0 ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: metrics)
            .accessibilityHidden(true)
    }
}

private struct WrappingFilterChips: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 320
        let rows = calculateRows(subviews: subviews, maxWidth: maxWidth)
        var height: CGFloat = 0

        for row in rows {
            height += row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += spacing
        }

        return CGSize(width: maxWidth, height: max(height - spacing, 0))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = calculateRows(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            let rowWidth = row.reduce(0) { partial, view in
                partial + view.sizeThatFits(.unspecified).width
            } + CGFloat(max(row.count - 1, 0)) * spacing
            var x = bounds.maxX - rowWidth

            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(
                    at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2),
                    anchor: .topLeading,
                    proposal: .unspecified
                )
                x += size.width + spacing
            }

            y += rowHeight + spacing
        }
    }

    private func calculateRows(
        subviews: Subviews,
        maxWidth: CGFloat
    ) -> [[Subviews.Element]] {
        var rows: [[Subviews.Element]] = [[]]
        var x: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(view)
            x += size.width + spacing
        }

        return rows.filter { !$0.isEmpty }
    }
}

private struct UpdateReleaseDetailView: View {
    let update: AppUpdate
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("发现新版本")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("v\(update.version)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                Link(destination: update.releaseURL) {
                    Text("发布页")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.14))
                        }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text("发布时间")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                Text(publishedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("更新日志")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                ScrollView(.vertical, showsIndicators: false) {
                    UpdateNotesView(notes: update.notes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 210)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10))
                }
            }

            HStack(spacing: 8) {
                Button {
                    onCancel()
                } label: {
                    Text("取消")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12))
                }

                Button {
                    onConfirm()
                } label: {
                    Text("确定")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.52))
                }
            }
            .font(.callout.weight(.medium))
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16))
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private var publishedText: String {
        guard let publishedAt = update.publishedAt else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: publishedAt)
    }
}

/// 弹窗内统一的玻璃图标按钮：整个 30×30 边框区域都是点击热区，
/// 悬停时底色和描边加深，按下时再加深，给出明确的可点击反馈。
private struct GlassIconButton<Label: View>: View {
    var action: () -> Void
    var help: String
    @ViewBuilder var label: () -> Label

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button {
            action()
        } label: {
            label()
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isPressed ? 0.12 : isHovered ? 0.14 : 0.07))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isHovered ? 0.26 : 0.12))
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .help(help)
    }
}
