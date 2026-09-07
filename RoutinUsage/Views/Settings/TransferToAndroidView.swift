import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// One provider's credential count shown on the migration page. Only names
/// and counts are displayed; no credential material.
struct TransferProviderSummary: Equatable, Identifiable {
    var id: String { providerName }
    let providerName: String
    let credentialCount: Int
}

/// Builds the metadata-only transfer package that is handed to the transfer
/// server for AEAD sealing. Secrets never enter the package here; the
/// per-credential secret envelope is populated by the secure export data
/// layer in a later task.
enum TransferPackageBuilder {
    // Mirrors the allowlist enforced by TransferCredential decoding; keep in
    // sync with the transfer schema v1 metadata contract.
    private static let metadataAllowlist: Set<String> = [
        "baseURL", "userID", "region", "planType", "usageKind", "websiteURL"
    ]

    static func makePackage(
        credentials: [KeyConfiguration],
        exportedAt: Date = Date()
    ) throws -> TransferPackageV1 {
        let transferCredentials = credentials.enumerated().map { index, configuration in
            TransferCredential(
                credentialId: configuration.id,
                providerId: configuration.providerID.rawValue,
                credentialKind: configuration.credentialKind.rawValue,
                name: configuration.displayName,
                isEnabled: configuration.isEnabled,
                sortOrder: index,
                metadata: configuration.metadata.filter { metadataAllowlist.contains($0.key) }
            )
        }
        return TransferPackageV1(
            credentials: transferCredentials,
            preferences: TransferPreferences(),
            secretEnvelope: .empty,
            exportedAt: exportedAt
        )
    }
}

@MainActor
@Observable
final class TransferToAndroidModel {
    enum Phase: Equatable {
        case idle
        case preparing
        case waiting
        case connected
        case sending
        case sent
        case cancelled
        case expired
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var payload: TransferQRCodePayload?
    private(set) var expiresAt: Date?

    @ObservationIgnored private let store: UsageStore
    @ObservationIgnored private var server: TransferServer?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?

    init(store: UsageStore) {
        self.store = store
    }

    var providerSummaries: [TransferProviderSummary] {
        let counts = Dictionary(grouping: currentConfigurations, by: \.providerID)
        return ProviderID.allCases.compactMap { providerID in
            guard let configurations = counts[providerID], !configurations.isEmpty else {
                return nil
            }
            return TransferProviderSummary(
                providerName: ProviderRegistry.builtInDescriptors.first { $0.id == providerID }?.displayName
                    ?? providerID.rawValue,
                credentialCount: configurations.count
            )
        }
    }

    var hasCredentials: Bool {
        !currentConfigurations.isEmpty
    }

    func remainingSeconds(now: Date = Date()) -> Int {
        remainingSeconds(now: now, expiresAt: expiresAt)
    }

    func remainingSeconds(now: Date, expiresAt: Date?) -> Int {
        guard let expiresAt else { return 0 }
        return max(0, Int(expiresAt.timeIntervalSince(now).rounded(.up)))
    }

    func start() async {
        guard server == nil, monitorTask == nil else { return }
        phase = .preparing
        let server = TransferServer()
        self.server = server
        do {
            let payload = try await server.start()
            self.payload = payload
            expiresAt = payload.expiresAt
            phase = .waiting
        } catch {
            self.server = nil
            phase = .failed(failureMessage(for: error))
            return
        }
        monitorTask = Task { [weak self] in
            await self?.monitor()
        }
    }

    /// Stops the LAN service and destroys the session. Idempotent; called on
    /// page close and when the user cancels.
    func stop() async {
        monitorTask?.cancel()
        monitorTask = nil
        let server = self.server
        self.server = nil
        if let server {
            await server.stop()
        }
        switch phase {
        case .idle, .preparing, .waiting, .connected, .sending:
            phase = .cancelled
        default:
            break
        }
    }

    func cancelTapped() {
        Task { await stop() }
    }

    func makeTransferPackage() throws -> TransferPackageV1 {
        try TransferPackageBuilder.makePackage(credentials: currentConfigurations)
    }

    private var currentConfigurations: [KeyConfiguration] {
        store.orderedKeyIDs.compactMap { store.state(for: $0)?.configuration }
    }

    private func monitor() async {
        while !Task.isCancelled {
            guard let server else { return }
            let state = await server.session.state
            switch state {
            case .connected:
                phase = .connected
                let hasSessionKey = await server.session.hasSessionKey
                guard hasSessionKey else { break }
                phase = .sending
                do {
                    let package = try makeTransferPackage()
                    try await server.send(package: package)
                    phase = .sent
                } catch {
                    phase = .failed(failureMessage(for: error))
                    await stop()
                }
                return
            case .expired:
                phase = .expired
                await stop()
                return
            case .cancelled:
                if phase != .sent { phase = .cancelled }
                return
            case .completed:
                return
            default:
                break
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private func failureMessage(for error: Error) -> String {
        switch error {
        case TransferServerError.sessionExpired:
            return "迁移二维码已过期，请重新发起迁移。"
        case TransferSessionError.expired:
            return "迁移二维码已过期，请重新发起迁移。"
        case is CancellationError:
            return "迁移已取消。"
        default:
            return "迁移未完成，请重试。"
        }
    }
}

struct TransferToAndroidView: View {
    @State private var model: TransferToAndroidModel
    var onClose: () -> Void

    init(environment: AppEnvironment, onClose: @escaping () -> Void) {
        _model = State(initialValue: TransferToAndroidModel(store: environment.store))
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("迁移到 Android")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("关闭迁移页面")
                .accessibilityLabel("关闭迁移页面")
            }

            if model.hasCredentials {
                credentialSummary
            } else {
                ContentUnavailableView(
                    "没有可迁移的凭证",
                    systemImage: "key.slash",
                    description: Text("请先添加供应商凭证")
                )
                .frame(minHeight: 180)
            }

            if let payload = model.payload, let encoded = try? payload.encodedString() {
                TransferQRCodeImageView(string: encoded)
                    .frame(maxWidth: .infinity)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("剩余有效时间 \(countdownText(model.remainingSeconds(now: context.date)))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            statusSection

            Spacer()

            Button(role: .destructive) {
                model.cancelTapped()
                onClose()
            } label: {
                Text("取消迁移")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("取消迁移")
        }
        .padding(28)
        .frame(width: 460, height: 640)
        .task { await model.start() }
        .onDisappear {
            Task { await model.stop() }
        }
    }

    private var credentialSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("将迁移以下配置（密钥仅在密文内传输）")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(model.providerSummaries) { summary in
                    Text("\(summary.providerName) ×\(summary.credentialCount)")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: Capsule())
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        let (title, symbol) = statusDescription
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(title)
                .accessibilityLabel("连接状态：\(title)")
        }
        .font(.callout)
    }

    private var statusDescription: (String, String) {
        switch model.phase {
        case .idle, .preparing:
            ("正在准备迁移服务…", "hourglass")
        case .waiting:
            ("等待 Android 扫码连接", "qrcode")
        case .connected:
            ("Android 已连接，正在校验会话", "link")
        case .sending:
            ("正在加密并发送配置", "lock.shield")
        case .sent:
            ("配置已加密发送，可在 Android 上完成导入", "checkmark.seal")
        case .cancelled:
            ("迁移已取消", "xmark.circle")
        case .expired:
            ("二维码已过期，请重新发起迁移", "clock.badge.exclamationmark")
        case let .failed(message):
            (message, "exclamationmark.triangle")
        }
    }

    private func countdownText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct TransferQRCodeImageView: View {
    let string: String

    var body: some View {
        if let image = Self.qrImage(for: string) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .accessibilityLabel("迁移二维码")
        } else {
            ContentUnavailableView("无法生成二维码", systemImage: "qrcode")
                .frame(height: 220)
        }
    }

    static func qrImage(for string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: scaled.extent.width, height: scaled.extent.height)
        )
    }
}
