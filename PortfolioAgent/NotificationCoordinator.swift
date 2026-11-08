import SwiftUI
import UIKit
import UserNotifications
import Observation

@MainActor @Observable final class NotificationCoordinator {
    static let shared = NotificationCoordinator()
    var showOnboarding = false
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var busy = false
    private(set) var error: String?
    private var token: String?
    private var registeredIdentity: String?
    private weak var cloud: CloudStore?
    private let decisionKey = "reviewNotifications.onboardingHandled.v1"
    var allowed: Bool { authorization == .authorized || authorization == .provisional || authorization == .ephemeral }
    var statusLabel: String { allowed ? "已允许" : authorization == .denied ? "未允许" : "尚未开启" }

    func prepare(cloud: CloudStore) async {
        self.cloud = cloud
        guard cloud.canEnterHome else { showOnboarding = false; registeredIdentity = nil; return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
        if authorization == .notDetermined && !UserDefaults.standard.bool(forKey: decisionKey) {
            showOnboarding = true
        }
        if allowed { UIApplication.shared.registerForRemoteNotifications(); await syncDevice() }
    }

    func requestPermission(cloud: CloudStore) async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        self.cloud = cloud
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            authorization = (await UNUserNotificationCenter.current().notificationSettings()).authorizationStatus
            if granted {
                // Save the user's report preference, independently of APNs token delivery.
                let _: APIPreferences = try await cloud.request("me/preferences", method: "PATCH", body: ["report_push": true])
                UIApplication.shared.registerForRemoteNotifications()
                await syncDevice()
            }
            UserDefaults.standard.set(true, forKey: decisionKey)
            showOnboarding = false
        } catch { self.error = "暂未完成通知设置，请重试。你也可以稍后在设置中开启。" }
    }

    func skip() {
        UserDefaults.standard.set(true, forKey: decisionKey)
        showOnboarding = false
    }

    func receivedToken(_ data: Data) async {
        token = data.map { String(format: "%02x", $0) }.joined()
        await syncDevice()
    }

    private func syncDevice() async {
        guard let cloud, cloud.canEnterHome, allowed, let token, let userID = cloud.user?.id else { return }
        let identity = cloud.origin + ":" + userID + ":" + token
        guard identity != registeredIdentity else { return }
        let defaults = UserDefaults.standard
        let deviceID = defaults.string(forKey: "reviewNotifications.deviceID") ?? UUID().uuidString
        defaults.set(deviceID, forKey: "reviewNotifications.deviceID")
        let environment = Bundle.main.object(forInfoDictionaryKey: "APNSEnvironment") as? String ?? "production"
        do {
            let _: DeviceRegistration = try await cloud.request("me/devices/\(deviceID)", method: "PUT",
                body: ["token": token, "environment": environment == "development" ? "sandbox" : "production"])
            registeredIdentity = identity
        } catch { registeredIdentity = nil } // Retry on next token callback / foreground.
    }
    private struct DeviceRegistration: Decodable { let registered: Bool }
}

final class NotificationAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await NotificationCoordinator.shared.receivedToken(deviceToken) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Permission remains valid; registration is retried when the app returns to foreground.
    }
}

struct NotificationOnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var notifications = NotificationCoordinator.shared
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bell.badge.fill").font(.system(size: 72)).foregroundStyle(Palette.chalkBlue)
                .padding(36).background(Color.blue.opacity(0.08), in: Circle()).accessibilityHidden(true)
            Text("复盘就绪，及时知道").font(.title.bold())
            Text("允许通知，在日报和周报生成后收到提醒。\n你可以随时在设置中更改。")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            Spacer()
            if let error = notifications.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            Button { Task { await notifications.requestPermission(cloud: store.cloud) } } label: {
                HStack { if notifications.busy { ProgressView().tint(.white) }; Text("开启通知") }
                    .font(.headline).frame(maxWidth: .infinity).frame(height: 56)
                    .foregroundStyle(.white).background(Color.blue, in: Capsule())
            }.disabled(notifications.busy).accessibilityIdentifier("enableReviewNotifications")
            Button("暂不") { notifications.skip() }.frame(minHeight: 44).disabled(notifications.busy)
                .accessibilityIdentifier("skipReviewNotifications")
        }.padding(30).background(Color(uiColor: .systemBackground)).interactiveDismissDisabled()
    }
}
