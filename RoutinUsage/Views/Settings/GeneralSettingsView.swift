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

                Section("显示") {
                    Picker("用量维度", selection: $settings.displayDimension) {
                        ForEach(DisplayDimension.allCases, id: \.self) { dimension in
                            Text(dimension.title)
                                .tag(dimension)
                        }
                    }
                    .accessibilityLabel("用量显示维度")
                }

                Section("通知") {
                    Toggle("启用通知", isOn: $settings.notificationsEnabled)
                        .accessibilityLabel("启用通知")

                    Stepper(value: lowThresholdBinding, in: 1...(settings.thresholds.high - 1)) {
                        Text("低阈值 \(environment.settings.thresholds.low)%")
                    }
                    .accessibilityLabel("低用量提醒阈值")

                    Stepper(value: highThresholdBinding, in: (settings.thresholds.low + 1)...100) {
                        Text("高阈值 \(environment.settings.thresholds.high)%")
                    }
                    .accessibilityLabel("高用量提醒阈值")
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

    private var lowThresholdBinding: Binding<Int> {
        Binding(
            get: { settings.thresholds.low },
            set: { low in
                settings.thresholds = AlertThresholds(
                    low: low,
                    high: settings.thresholds.high
                )
            }
        )
    }

    private var highThresholdBinding: Binding<Int> {
        Binding(
            get: { settings.thresholds.high },
            set: { high in
                settings.thresholds = AlertThresholds(
                    low: settings.thresholds.low,
                    high: high
                )
            }
        )
    }
}

extension DisplayDimension {
    var title: String {
        switch self {
        case .fiveHour: "5 小时"
        case .weekly: "周"
        }
    }
}
