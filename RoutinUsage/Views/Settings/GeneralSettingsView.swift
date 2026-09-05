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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(
                    title: "通用",
                    subtitle: "刷新、启动与提醒"
                )

                refreshSection
                launchSection
                notificationSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var refreshSection: some View {
        settingSection {
            HStack(alignment: .center, spacing: 16) {
                settingLabel(
                    title: "刷新间隔",
                    message: "只刷新已启用的凭证，每个凭证的用量保持独立。"
                )

                Spacer(minLength: 16)

                Picker("刷新间隔", selection: $settings.refreshMinutes) {
                    ForEach(AppSettings.allowedRefreshMinutes, id: \.self) { minutes in
                        Text("每 \(minutes) 分钟")
                            .tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 150)
                .accessibilityLabel("自动刷新间隔")
            }
        }
    }

    private var launchSection: some View {
        settingSection {
            HStack {
                settingLabel(title: "登录时启动", message: "开机后自动启动 MyToken")

                Spacer(minLength: 16)

                Toggle("登录时启动", isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("登录时启动")
            }
        }
    }

    private var notificationSection: some View {
        settingSection {
            HStack {
                settingLabel(
                    title: "启用通知",
                    message: "额度接近限制或订阅即将到期时提醒"
                )

                Spacer(minLength: 16)

                Toggle("启用通知", isOn: $settings.notificationsEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("启用通知")
            }
        }
    }

    private func settingLabel(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
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
