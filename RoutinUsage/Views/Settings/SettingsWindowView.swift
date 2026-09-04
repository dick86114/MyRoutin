import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case credentials
    case menuBar
    case popover
    case general
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .credentials: "凭证管理"
        case .menuBar: "菜单栏显示"
        case .popover: "弹窗显示"
        case .general: "通用"
        case .help: "帮助与更新"
        }
    }

    var symbol: String {
        switch self {
        case .credentials: "key.horizontal"
        case .menuBar: "menubar.rectangle"
        case .popover: "rectangle.bottomthird.inset.filled"
        case .general: "switch.2"
        case .help: "questionmark.circle"
        }
    }
}

struct SettingsWindowView: View {
    @Bindable var environment: AppEnvironment
    @State private var ordering: CredentialOrderingController
    @State private var selectedSection: SettingsSection = .credentials

    init(environment: AppEnvironment) {
        self.environment = environment
        _ordering = State(initialValue: CredentialOrderingController(
            settings: environment.settings,
            addCredential: { input in
                let previousIDs = Set(environment.store.orderedKeyIDs)
                let saveResult = try await environment.addValidatedCredential(input)
                let addedID = environment.store.orderedKeyIDs.first { !previousIDs.contains($0) }
                return CredentialAddOutcome(saveResult: saveResult, addedCredentialID: addedID)
            },
            setKeyEnabled: { try environment.setKeyEnabled($0, enabled: $1) },
            delete: { try environment.deleteKey($0) }
        ))
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("MyToken")
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .liquidGlassWindowBackground()
                .background(WindowFramePersistence())
                .background(SettingsWindowDockIconAnchor())
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, idealWidth: 880, minHeight: 560, idealHeight: 640)
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedSection {
        case .credentials:
            CredentialManagementView(environment: environment, ordering: ordering)
        case .menuBar:
            MenuBarOrderingView(environment: environment, ordering: ordering)
        case .popover:
            PopoverOrderingView(environment: environment, ordering: ordering)
        case .general:
            GeneralSettingsView(environment: environment)
        case .help:
            HelpUpdateView(environment: environment)
        }
    }
}
