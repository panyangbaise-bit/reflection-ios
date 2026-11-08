import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmingLogout = false
    private var cloud: CloudStore { store.cloud }
    private var signedIn: Bool { cloud.enabled && !cloud.requiresSignIn }
    var body: some View {
        List {
            Section("账户") {
                NavigationLink { AccountSettingsView() } label: {
                    SettingsLabel("账号管理", icon: "person")
                }
                NavigationLink { DataSettingsView() } label: {
                    SettingsLabel("数据管理", icon: "externaldrive")
                }
            }
            Section("应用") {
                NavigationLink { DisplaySettingsView() } label: {
                    SettingsLabel("显示设置", icon: "circle.lefthalf.filled")
                }
                if signedIn {
                    NavigationLink(value: Route.notifications) { SettingsLabel("通知权限与提醒", icon: "bell.badge") }
                    NavigationLink { CloudPreferencesView() } label: {
                        SettingsLabel("报告偏好", icon: "bell")
                    }
                    NavigationLink { CloudPrivacyView() } label: {
                        SettingsLabel("AI 授权与隐私", icon: "checkmark.shield")
                    }
                } else if !cloud.enabled {
                    NavigationLink(value: Route.notifications) {
                        SettingsLabel("复盘提醒", icon: "bell")
                    }
                }
            }
            Section("关于") {
                NavigationLink { AppAboutView() } label: {
                    HStack {
                        SettingsLabel("关于复盘了", icon: "info.circle")
                        Spacer()
                        Text(appVersion).foregroundStyle(.secondary)
                    }
                }
                NavigationLink { ServiceAgreementsView() } label: {
                    SettingsLabel("服务协议", icon: "doc.text")
                }
            }
            if signedIn {
                Section {
                    Button { confirmingLogout = true } label: {
                        SettingsLabel("退出登录", icon: "rectangle.portrait.and.arrow.right")
                    }.disabled(cloud.busy)
                }
            }
            Section {} footer: {
                Text(cloud.enabled ? "复盘了 · 让每次投资都有迹可循" : "本地演示 · 数据仅保存在此设备")
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
        }
        .modifier(SettingsListStyle(title: "设置"))
        .confirmationDialog("退出登录？", isPresented: $confirmingLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await cloud.logout() } }
        } message: { Text("云端数据会保留，可随时重新登录。") }
    }
}

private struct AccountSettingsView: View {
    @Environment(AppStore.self) private var store
    private var cloud: CloudStore { store.cloud }
    private var signedIn: Bool { cloud.enabled && !cloud.requiresSignIn }
    var body: some View {
        List {
            Section("账户") {
                NavigationLink(value: Route.connection) {
                    HStack {
                        SettingsLabel(signedIn ? "登录管理" : "登录复盘了", icon: "person.crop.circle")
                        Spacer()
                        Text(signedIn ? "已登录" : "未登录").foregroundStyle(.secondary)
                    }
                }
                if signedIn, let phone = cloud.user?.phoneMasked {
                    LabeledContent("手机号", value: "+86 " + phone)
                }
            }
            if signedIn {
                Section {
                    NavigationLink { CloudDeletionView() } label: {
                        Text("注销账号").foregroundStyle(.red)
                    }
                } footer: { Text("注销前可在数据管理中导出数据。") }
            }
        }.modifier(SettingsListStyle(title: "账号管理"))
    }
}

private struct DataSettingsView: View {
    @Environment(AppStore.self) private var store
    private var cloud: CloudStore { store.cloud }
    private var signedIn: Bool { cloud.enabled && !cloud.requiresSignIn }
    var body: some View {
        List {
            if cloud.requiresSignIn {
                Section { NavigationLink("登录后管理数据", value: Route.connection) }
            } else {
                Section {
                    if signedIn {
                        NavigationLink { CloudLedgerView() } label: { SettingsLabel("交易记录", icon: "clock.arrow.circlepath") }
                        NavigationLink { CloudWatchlistView() } label: { SettingsLabel("监察表", icon: "eye") }
                    } else {
                        NavigationLink(value: Route.history) { SettingsLabel("手动记录历史", icon: "clock.arrow.circlepath") }
                    }
                }
                if signedIn {
                    Section {
                        NavigationLink { CloudExportView() } label: { SettingsLabel("导出我的数据", icon: "square.and.arrow.up") }
                    }
                }
            }
        }.modifier(SettingsListStyle(title: "数据管理"))
    }
}

private struct DisplaySettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @Environment(AppStore.self) private var store
    var body: some View {
        List {
            Section {
                Picker("外观", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                Toggle("红涨绿跌", isOn: Binding(get: { store.state.preferences.redIsGain }, set: { value in
                    store.update { $0.preferences.redIsGain = value }
                }))
                LabeledContent("展示币种", value: "人民币 CNY")
            } footer: { Text("关闭红涨绿跌后，将使用绿涨红跌。资产总值统一折算为人民币。") }
        }.modifier(SettingsListStyle(title: "显示设置"))
    }
}

private struct ServiceAgreementsView: View {
    var body: some View {
        List {
            Section {
                ForEach(AppLegalDocument.allCases) { document in
                    NavigationLink { LegalDocumentView(document: document) } label: { Text(document.title) }
                }
            }
        }.modifier(SettingsListStyle(title: "服务协议"))
    }
}

private struct SettingsListStyle: ViewModifier {
    let title: String
    func body(content: Content) -> some View {
        content.listStyle(.insetGrouped)
            .listSectionSpacing(24)
            .environment(\.defaultMinListRowHeight, 54)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).tint(Palette.chalkBlue)
    }
}

struct SettingsLabel: View {
    let title: String
    let icon: String
    init(_ title: String, icon: String) { self.title = title; self.icon = icon }
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 20, weight: .regular))
                .frame(width: 26).accessibilityHidden(true)
            Text(title)
        }.foregroundStyle(.primary).padding(.vertical, 4)
    }
}

private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
struct AppAboutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    BrandMark(style: .whiteboard).frame(width: 64, height: 64)
                    Text("复盘了").font(Palette.wordmark(28))
                    Text("每天，把持仓读清楚。").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24)
                LabeledContent("版本", value: appVersion)
            }
            Section("当前版本") {
                Text("当前为测试版。系统推送尚未开放；AI 回答可能存在错误，请结合数据来源核对。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.listStyle(.insetGrouped).navigationTitle("关于复盘了")
            .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
    }
}
struct NotificationPreferencesView: View {
    @Environment(AppStore.self) private var store
    @State private var notifications = NotificationCoordinator.shared
    @State private var reportPush = false
    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: store.state.preferences.reminderHour, minute: store.state.preferences.reminderMinute)) ?? Date()
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            store.update { $0.preferences.reminderHour = c.hour ?? 8; $0.preferences.reminderMinute = c.minute ?? 0 }
        })
    }
    var body: some View {
        Form {
            Section("系统通知") {
                LabeledContent("通知权限", value: notifications.statusLabel)
                if notifications.authorization == .notDetermined {
                    Button("开启通知") { Task {
                        await notifications.requestPermission(cloud: store.cloud)
                        await loadPushPreference()
                    } }.disabled(notifications.busy)
                } else {
                    Button("前往系统通知设置") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Toggle("复盘推送", isOn: Binding(get: { reportPush }, set: { value in
                    Task { await store.cloud.perform {
                        let prefs: APIPreferences = try await store.cloud.request("me/preferences", method: "PATCH", body: ["report_push": value])
                        reportPush = prefs.reportPush
                    } }
                })).disabled(!notifications.allowed || store.cloud.busy)
            }
            Section {
                Toggle("每日收盘总结", isOn: Binding(get: { store.state.preferences.dailyReminder }, set: { value in store.update { $0.preferences.dailyReminder = value } }))
                DatePicker("提醒时间", selection: time, displayedComponents: .hourAndMinute)
                Toggle("每周复盘", isOn: Binding(get: { store.state.preferences.weeklyReminder }, set: { value in store.update { $0.preferences.weeklyReminder = value } }))
            } header: { Text("复盘提醒") } footer: { Text("北京时间。通知权限可在系统设置中随时更改；不开启通知也可在复盘页查看报告。") }
            Section("通知预览") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("复盘了").foregroundStyle(.secondary); Spacer(); Text(String(format: "%02d:%02d", store.state.preferences.reminderHour, store.state.preferences.reminderMinute)).foregroundStyle(.secondary) }
                    Text("你的收盘总结已就绪").font(.headline)
                    Text("查看最新一轮持仓变化。").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }
        }.navigationTitle("复盘提醒").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).tint(Palette.chalkBlue)
            .task { await notifications.prepare(cloud: store.cloud); await loadPushPreference() }
    }
    private func loadPushPreference() async {
        if let prefs: APIPreferences = try? await store.cloud.request("me/preferences") { reportPush = prefs.reportPush }
    }
}
