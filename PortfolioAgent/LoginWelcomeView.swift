import SwiftUI

struct LoginWelcomeView: View {
    @Environment(AppStore.self) private var store
    @State private var showingPassword = false
    private var cloud: CloudStore { store.cloud }
    private var origin: String {
        cloud.origin.isEmpty ? APIOrigin.configured : cloud.origin
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 36)
                    ZStack {
                        Circle().fill(Color.blue.opacity(0.12)).frame(width: 250, height: 250)
                        RoundedRectangle(cornerRadius: 34).fill(.white).frame(width: 130, height: 130)
                            .rotationEffect(.degrees(-7))
                        BrandMark(style: .whiteboard).frame(width: 92, height: 92)
                        Image(systemName: "chart.xyaxis.line").font(.system(size: 32, weight: .medium))
                            .foregroundStyle(.cyan).offset(x: -124, y: -105).rotationEffect(.degrees(-12))
                        Image(systemName: "doc.text").font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Color.blue).offset(x: 120, y: 84).rotationEffect(.degrees(12))
                    }.frame(maxWidth: .infinity).frame(height: 280).accessibilityHidden(true)
                    Text("复盘了").font(Palette.wordmark(42)).foregroundStyle(.primary)
                    Text("每天，把持仓读清楚。")
                        .font(.title3).foregroundStyle(.secondary).padding(.top, 16)
                    Spacer(minLength: 60)
                    VStack(spacing: 12) {
                        Button { showingPassword = true } label: {
                            HStack(spacing: 10) {
                                if cloud.busy { ProgressView().tint(Color(uiColor: .systemBackground)) }
                                Text("使用手机号和密码")
                            }
                            .font(.headline).foregroundStyle(Color(uiColor: .systemBackground))
                            .frame(maxWidth: .infinity).frame(minHeight: 58)
                            .background(Color.primary, in: Capsule())
                        }
                        .disabled(cloud.busy)
                        .accessibilityIdentifier("welcomePasswordLogin")
                        Text("登录后可在多台设备同步持仓、交易与复盘。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(.bottom, 24)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 30)
            }.background(Color(uiColor: .systemBackground).ignoresSafeArea())
        }
        .sheet(isPresented: $showingPassword) { PasswordLoginSheet(origin: origin) }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// 手机号与密码登录。
struct PasswordLoginSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let origin: String
    @State private var phone = ""
    @State private var password = ""
    @State private var accepted = true
    @FocusState private var phoneFocused: Bool
    private var cloud: CloudStore { store.cloud }
    private var valid: Bool {
        phone.range(of: #"^1[3-9][0-9]{9}$"#, options: .regularExpression) != nil
            && (10...128).contains(password.count)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("使用手机号和密码").font(.title2.bold())
                    Text("使用注册时设置的密码登录。忘记密码将无法登录，请妥善保管。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Text("+86")
                        TextField("手机号", text: $phone)
                            .keyboardType(.phonePad).textContentType(.telephoneNumber)
                            .focused($phoneFocused)
                            .accessibilityIdentifier("passwordLoginPhone")
                    }.padding(18).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16))
                    SecureField("登录密码", text: $password).textContentType(.password)
                        .padding(18).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("passwordLoginPassword")
                    Button { phoneFocused = false; Task { await submit() } } label: {
                        HStack {
                            if cloud.busy { ProgressView().tint(.white) }
                            Text(cloud.busy ? "正在登录…" : "登录")
                        }.font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(.white).background(Color.blue, in: Capsule())
                    }
                    .disabled(cloud.busy || !accepted || !valid)
                    .accessibilityIdentifier("passwordLoginSubmit")
                    LoginConsentView(accepted: $accepted)
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onChange(of: cloud.user?.id) { _, id in
            if id != nil { dismiss() }
        }
    }
    private func submit() async {
        await cloud.signIn(origin: origin, phone: phone, password: password, agreementsAccepted: accepted)
        if cloud.user != nil { dismiss() }
    }
}

struct LoginConsentView: View {
    @Binding var accepted: Bool
    @State private var reading: AppLegalDocument?
    var body: some View {
        HStack(spacing: 3) {
            Button { accepted.toggle() } label: {
                Image(systemName: accepted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).frame(width: 40, height: 44)
            }.buttonStyle(.plain).foregroundStyle(accepted ? Color.blue : Color.secondary)
                .accessibilityLabel("同意用户协议和隐私政策")
                .accessibilityValue(accepted ? "已勾选" : "未勾选")
                .accessibilityIdentifier("agreementCheckbox")
            Text("已阅读并同意[用户协议](reflection://terms)与[隐私政策](reflection://privacy)")
                .font(.footnote).foregroundStyle(.secondary).tint(.blue)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.openURL, OpenURLAction { url in
                    switch url.absoluteString {
                    case "reflection://terms": reading = .terms
                    case "reflection://privacy": reading = .privacy
                    default: return .discarded
                    }
                    return .handled
                })
        }
        .sheet(item: $reading) { document in
            NavigationStack {
                LegalDocumentView(document: document)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { reading = nil } } }
            }
        }
    }
}

struct PasswordSetupView: View {
    @Environment(AppStore.self) private var store
    @State private var password = ""
    @State private var confirmation = ""
    private var valid: Bool { (10...128).contains(password.count) && password == confirmation }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "lock.shield").font(.system(size: 44)).foregroundStyle(.blue).padding(.top, 36)
            Text("设置登录密码").font(.largeTitle.bold())
            Text("设置密码后，下次可直接使用手机号和密码登录。")
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(spacing: 14) {
                SecureField("密码（10–128 位）", text: $password).textContentType(.newPassword)
                    .padding(18).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("setupPassword")
                SecureField("再次输入密码", text: $confirmation).textContentType(.newPassword)
                    .padding(18).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("confirmPassword")
            }
            Spacer()
            Button {
                Task { await store.cloud.perform {
                    let _: APIAck = try await store.cloud.request("me/password/setup", method: "POST", body: ["password": password])
                    try await store.cloud.refreshIdentity()
                } }
            } label: {
                HStack { if store.cloud.busy { ProgressView().tint(.white) }; Text("完成并进入") }
                    .font(.headline).frame(maxWidth: .infinity).frame(height: 56)
                    .foregroundStyle(.white).background(Color.blue.opacity(valid ? 1 : 0.4), in: Capsule())
            }.disabled(!valid || store.cloud.busy).accessibilityIdentifier("completeRegistration")
            Button("退出当前账户") { Task { await store.cloud.logout() } }
                .frame(maxWidth: .infinity, minHeight: 44).disabled(store.cloud.busy)
        }.padding(28).background(Color(uiColor: .systemBackground))
    }
}
