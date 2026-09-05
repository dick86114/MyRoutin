import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var environment: AppEnvironment
    @Bindable var settings: AppSettings
    @State private var operationError: String?

    init(environment: AppEnvironment) {
        self.environment = environment
        self.settings = environment.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsPageHeader(
                title: "通用",
                subtitle: "刷新、启动与提醒"
            )

            Form {
                Section("刷新") {
                    Picker("刷新间隔", selection: $settings.refreshMinutes) {
                        ForEach(AppSettings.allowedRefreshMinutes, id: \.self) { minutes in
                            Text("每 \(minutes) 分钟")
                                .tag(minutes)
                        }
                    }
                    .accessibilityLabel("自动刷新间隔")

                    Text("只刷新已启用的凭证，每个凭证的用量保持独立。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("启动") {
                    Toggle("登录时启动", isOn: launchAtLoginBinding)
                        .accessibilityLabel("登录时启动")
                }

                Section("通知") {
                    Toggle("启用通知", isOn: $settings.notificationsEnabled)
                        .accessibilityLabel("启用通知")
                }
            }
            .formStyle(.grouped)
        }
        .alert(
            "无法完成操作",
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button("好") { operationError = nil }
        } message: {
            Text(operationError ?? "发生未知错误")
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { environment.settings.launchAtLogin },
            set: { enabled in
                do {
                    try LoginItemSettingSynchronizer.setEnabled(
                        enabled,
                        settings: environment.settings,
                        manager: environment.loginItemManager
                    )
                } catch {
                    operationError = "无法更新登录启动设置：\(error.localizedDescription)"
                }
            }
    )
    }

}
