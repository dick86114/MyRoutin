import Observation
import SwiftUI

enum CredentialVisibility {
    static func canToggle(secret: String) -> Bool {
        !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func iconName(isVisible: Bool) -> String {
        isVisible ? "eye" : "eye.slash"
    }
}

struct ValidatedKeyInput: Equatable, Sendable {
    let name: String
    let secret: String
}

enum KeyEditorValidationError: LocalizedError, Equatable, Sendable {
    case emptyName
    case emptySecret
    case invalidSecretPrefix
    case unsafeName
    case secretTooShort
    case thresholdOutOfRange
    case invalidThresholdOrder

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "请输入 Key 名称"
        case .emptySecret:
            return "请输入 plan Key"
        case .invalidSecretPrefix:
            return "Key 必须以 plan- 开头"
        case .unsafeName:
            return "显示名称不能是 plan Key"
        case .secretTooShort:
            return "plan Key 内容至少需要 4 位"
        case .thresholdOutOfRange:
            return "阈值必须是 1 至 100 的整数"
        case .invalidThresholdOrder:
            return "低阈值必须小于高阈值"
        }
    }
}

enum KeyEditorValidation {
    static func validate(name: String, secret: String) throws -> ValidatedKeyInput {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw KeyEditorValidationError.emptyName
        }
        guard KeyCredentialPolicy.isSafeDisplayName(normalizedName) else {
            throw KeyEditorValidationError.unsafeName
        }
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KeyEditorValidationError.emptySecret
        }
        guard KeyCredentialPolicy.hasValidPrefix(secret) else {
            throw KeyEditorValidationError.invalidSecretPrefix
        }
        guard KeyCredentialPolicy.hasSufficientSecretPayload(secret) else {
            throw KeyEditorValidationError.secretTooShort
        }
        return ValidatedKeyInput(name: normalizedName, secret: secret)
    }

    static func validateThresholds(low: Int, high: Int) throws {
        guard (1...100).contains(low), (1...100).contains(high) else {
            throw KeyEditorValidationError.thresholdOutOfRange
        }
        guard low < high else {
            throw KeyEditorValidationError.invalidThresholdOrder
        }
    }
}

enum KeyEditorSaveResult: Equatable, Sendable {
    case saved
    case savedWithoutSubscription
}

@MainActor
@Observable
final class KeyEditorModel {
    var name: String
    var secret: String
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var saveResult: KeyEditorSaveResult?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var saveGeneration: UUID?

    init(name: String = "", secret: String = "") {
        self.name = name
        self.secret = secret
    }

    func startSaving(
        _ operation: @escaping @MainActor (String, String) async throws -> KeyEditorSaveResult
    ) {
        guard saveTask == nil else {
            return
        }
        let generation = UUID()
        saveGeneration = generation
        saveTask = Task { [weak self] in
            guard let self else {
                return
            }
            await save(operation)
            if saveGeneration == generation {
                saveTask = nil
                saveGeneration = nil
            }
        }
    }

    func cancelSaving() {
        saveTask?.cancel()
    }

    func save(
        _ operation: @escaping @MainActor (String, String) async throws -> KeyEditorSaveResult
    ) async {
        guard !isSaving else {
            return
        }

        let input: ValidatedKeyInput
        do {
            input = try KeyEditorValidation.validate(name: name, secret: secret)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isSaving = true
        errorMessage = nil
        saveResult = nil
        defer { isSaving = false }

        do {
            try Task.checkCancellation()
            let result = try await operation(input.name, input.secret)
            try Task.checkCancellation()
            saveResult = result
        } catch is CancellationError {
            return
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func clearSaveResult() {
        saveResult = nil
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? UsageStoreError else {
            return "保存失败，请稍后重试"
        }
        switch error {
        case .invalidName:
            return "请输入 Key 名称"
        case .invalidSecret:
            return "Key 必须以 plan- 开头"
        case .invalidURL:
            return "官网链接无效"
        case .invalidKey:
            return "Key 无效"
        case .network:
            return "网络连接失败，请检查网络后重试"
        case .invalidResponse:
            return "接口返回的数据无法识别，请稍后重试"
        case .server(statusCode: 401):
            return "Key 无效"
        case let .server(statusCode):
            return "服务暂时不可用（HTTP \(statusCode)）"
        case .persistence:
            return "保存失败，请稍后重试"
        case .cacheCleanupFailed:
            return "凭证已删除，但用量缓存未能清理"
        }
    }
}

@MainActor
struct KeyEditorView: View {
    private enum Field: Hashable {
        case name
        case secret
    }

    let title: String
    let save: @MainActor (String, String) async throws -> KeyEditorSaveResult
    let onSaved: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: KeyEditorModel
    @State private var isSecretVisible = false
    @FocusState private var focusedField: Field?

    init(
        title: String = "添加 Key",
        initialName: String = "",
        initialSecret: String = "",
        save: @escaping @MainActor (String, String) async throws -> KeyEditorSaveResult,
        onSaved: @escaping @MainActor () -> Void = {}
    ) {
        self.title = title
        self.save = save
        self.onSaved = onSaved
        _model = State(initialValue: KeyEditorModel(name: initialName, secret: initialSecret))
    }

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    model.cancelSaving()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭")
                .accessibilityLabel("关闭")
            }

            Form {
                TextField("名称", text: $model.name)
                    .focused($focusedField, equals: .name)
                    .accessibilityLabel("Key 名称")
                    .onSubmit { focusedField = .secret }

                HStack(spacing: 8) {
                    Group {
                        if isSecretVisible {
                            TextField("plan-…", text: $model.secret)
                        } else {
                            SecureField("plan-…", text: $model.secret)
                        }
                    }
                    .focused($focusedField, equals: .secret)
                    .accessibilityLabel("plan Key")
                    .textContentType(.password)
                    .onSubmit { submit() }

                    Button {
                        isSecretVisible.toggle()
                    } label: {
                        Image(systemName: CredentialVisibility.iconName(isVisible: isSecretVisible))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(CredentialVisibility.canToggle(secret: model.secret) ? .primary : .tertiary)
                    .disabled(!CredentialVisibility.canToggle(secret: model.secret))
                    .help(isSecretVisible ? "隐藏 plan Key" : "显示 plan Key")
                    .accessibilityLabel(isSecretVisible ? "隐藏 plan Key" : "显示 plan Key")
                }
            }
            .formStyle(.grouped)

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityLabel("保存失败，\(errorMessage)")
            }

            HStack {
                Button("取消") {
                    model.cancelSaving()
                    dismiss()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: submit) {
                    HStack(spacing: 7) {
                        if model.isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(model.isSaving ? "正在验证" : "保存")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .liquidGlassButton(prominent: true)
                .disabled(model.isSaving)
                .accessibilityLabel(model.isSaving ? "正在验证并保存 Key" : "验证并保存 Key")
            }
        }
        .padding(28)
        .frame(width: 440)
        .onAppear { focusedField = .name }
        .onDisappear { model.cancelSaving() }
        .onChange(of: model.secret) { _, secret in
            if !CredentialVisibility.canToggle(secret: secret) {
                isSecretVisible = false
            }
        }
        .onChange(of: model.saveResult) { _, result in
            guard result == .saved else {
                return
            }
            finish()
        }
        .alert(
            "当前没有可用订阅",
            isPresented: Binding(
                get: { model.saveResult == .savedWithoutSubscription },
                set: { isPresented in
                    if !isPresented {
                        model.clearSaveResult()
                    }
                }
            )
        ) {
            Button("完成") { finish() }
        } message: {
            Text("Key 已保存。检测到可用订阅后，应用会在后续刷新中自动显示用量。")
        }
    }

    private func submit() {
        model.startSaving(save)
    }

    private func finish() {
        onSaved()
        dismiss()
    }
}
