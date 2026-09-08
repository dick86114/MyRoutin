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

/// Builds the transfer package handed to the transfer server for AEAD sealing.
///
/// Secrets leave the app exactly once: the builder reads each credential's
/// stored secret through a caller-provided reader (the app's credential secret
/// store, i.e. the `CredentialStoring` path that backs `UsageStore`), maps it
/// to the typed `EncryptedSecretEntry` fields required by transfer schema v1,
/// and the whole package JSON is then sealed by `TransferSession.sealMessage`.
/// The envelope-level `nonce`/`ciphertext`/`tag`/`ephemeralPublicKey` fields
/// stay at their inert placeholder values: confidentiality is provided by the
/// outer session AEAD, and the Android importer validates those fields
/// lexically only (see shared/transfer-schema/wire-contract.md).
enum TransferPackageBuilder {
    // Mirrors the allowlist enforced by TransferCredential decoding; keep in
    // sync with the transfer schema v1 metadata contract.
    private static let metadataAllowlist: Set<String> = [
        "baseURL", "userID", "region", "planType", "usageKind", "websiteURL"
    ]

    /// Unpadded URL-safe Base64 (RFC 4648 §5): the lexical contract shared by
    /// transfer-schema-v1.json `base64url` and the Android secret-entry decoder.
    static func base64URLEncode(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func makePackage(
        credentials: [KeyConfiguration],
        secretReader: (UUID) -> String? = { _ in nil },
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
        let secretEntries = secretEntries(for: credentials, secretReader: secretReader)
        let envelope = try EncryptedSecretEnvelope(
            algorithm: "AES-256-GCM",
            keyAgreement: "X25519-HKDF-SHA256",
            nonce: EncryptedSecretEnvelope.empty.nonce,
            ciphertext: EncryptedSecretEnvelope.empty.ciphertext,
            tag: EncryptedSecretEnvelope.empty.tag,
            ephemeralPublicKey: EncryptedSecretEnvelope.empty.ephemeralPublicKey,
            associatedData: nil,
            entries: secretEntries
        )
        return TransferPackageV1(
            credentials: transferCredentials,
            preferences: TransferPreferences(),
            secretEnvelope: envelope,
            exportedAt: exportedAt
        )
    }

    /// Builds one typed secret entry per credential whose secret is readable.
    /// Field mapping follows the credential kind: `bearerAPIKey` → `bearerToken`,
    /// `apiKey` → `apiKey`, `accessKeyPair` → `accessKeyID` + `secretAccessKey`
    /// (the access key ID lives in metadata; only the secret access key is a
    /// stored secret). Credentials with a missing/unreadable secret are omitted,
    /// so Android reports them as "skipped without secret" instead of failing.
    static func secretEntries(
        for credentials: [KeyConfiguration],
        secretReader: (UUID) -> String?
    ) -> [EncryptedSecretEntry] {
        credentials.compactMap { configuration in
            let secret = secretReader(configuration.id).flatMap { $0.isEmpty ? nil : $0 }
            switch configuration.credentialKind {
            case .bearerAPIKey:
                guard let secret else { return nil }
                return try? EncryptedSecretEntry(
                    credentialId: configuration.id,
                    bearerToken: base64URLEncode(secret)
                )
            case .apiKey:
                guard let secret else { return nil }
                return try? EncryptedSecretEntry(
                    credentialId: configuration.id,
                    apiKey: base64URLEncode(secret)
                )
            case .accessKeyPair:
                guard let secret,
                      let accessKeyID = configuration.metadata["accessKeyID"],
                      !accessKeyID.isEmpty else { return nil }
                return try? EncryptedSecretEntry(
                    credentialId: configuration.id,
                    accessKeyID: base64URLEncode(accessKeyID),
                    secretAccessKey: base64URLEncode(secret)
                )
            }
        }
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

    /// Number of credentials whose secret can actually be exported right now.
    /// Shown on the summary so the user knows how many sensitive items will
    /// travel; credentials without a readable secret are reported separately.
    var exportableSecretCount: Int {
        TransferPackageBuilder.secretEntries(
            for: currentConfigurations,
            secretReader: { [store] keyID in store.secretForExport(for: keyID) }
        ).count
    }

    /// Summary line describing what will travel. The "encrypted" claim is now
    /// backed by real secret export: every listed key travels only inside the
    /// session-sealed package (previously the envelope was always empty).
    var migrationSummaryText: String {
        let total = currentConfigurations.count
        let exportable = exportableSecretCount
        if exportable == total {
            return "将迁移以下配置（\(total) 项密钥将以密文传输）"
        }
        if exportable == 0 {
            return "将迁移以下配置（未读取到任何密钥，这些配置将无法完成迁移）"
        }
        return "将迁移以下配置（\(exportable) 项密钥以密文传输，\(total - exportable) 个凭据缺少密钥将被跳过）"
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
        try TransferPackageBuilder.makePackage(
            credentials: currentConfigurations,
            secretReader: { [store] keyID in store.secretForExport(for: keyID) }
        )
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
                    payload = nil
                    expiresAt = nil
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
        VStack(alignment: .leading, spacing: 0) {
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

            if model.hasCredentials {
                if let payload = model.payload, let encoded = try? payload.encodedString() {
                    qrSection(payload: encoded)
                }

                statusSection
                    .padding(.top, 12)

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        model.cancelTapped()
                        onClose()
                    } label: {
                        Text("取消迁移")
                    }
                    .accessibilityLabel("取消迁移")
                }
                .padding(.top, 16)
            }
        }
        .padding(24)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .task { await model.start() }
        .onDisappear {
            Task { await model.stop() }
        }
    }

    private var credentialSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.migrationSummaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            providerChips
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var providerChips: some View {
        let summaries = model.providerSummaries
        if summaries.count <= 3 {
            HStack(spacing: 6) {
                ForEach(model.providerSummaries) { summary in
                    providerChip(summary)
                }
            }
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(summaries) { providerChip($0) }
            }
        }
    }

    private func providerChip(_ summary: TransferProviderSummary) -> some View {
        HStack(spacing: 4) {
            Text(summary.providerName)
                .lineLimit(1)
            Text("×\(summary.credentialCount)")
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }

    private func qrSection(payload: String) -> some View {
        VStack(spacing: 10) {
            TransferQRCodeImageView(string: payload)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = model.remainingSeconds(now: context.date)
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(countdownText(seconds))
                        .font(.caption.monospacedDigit().weight(.medium))
                }
                .foregroundStyle(seconds < 60 ? Color.orange : Color.secondary)
                .accessibilityLabel("剩余有效时间 \(countdownText(seconds))")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var statusSection: some View {
        let (title, symbol) = statusDescription
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(statusColor)
                .font(.callout)
            Text(title)
                .font(.callout.weight(.medium))
                .accessibilityLabel("连接状态：\(title)")
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .idle, .preparing, .waiting:
            .secondary
        case .connected, .sending:
            .blue
        case .sent:
            .green
        case .cancelled, .expired, .failed:
            .red
        }
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
