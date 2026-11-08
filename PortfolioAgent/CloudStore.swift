import Foundation
import Observation
import Security
import UIKit

struct KeychainVault: SessionVault {
    private let service = "com.portfolioagent.ios.cloud-session"
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "current"] }
    func save(_ session: CloudSession) throws {
        let data = try JSONEncoder().encode(session)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            // 解锁一次后即可读写：设备锁屏时后台刷新也能恢复会话（不迁移到其他设备）。
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw keychainError(status) }
        } else if result != errSecSuccess {
            throw keychainError(result)
        }
    }
    func load() throws -> CloudSession? {
        var item = query
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        var status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecInteractionNotAllowed {
            // 设备刚启动尚未解锁时的瞬时失败：短重试一次。
            usleep(250_000)
            status = SecItemCopyMatching(item as CFDictionary, &result)
        }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw keychainError(status) }
        return try JSONDecoder().decode(CloudSession.self, from: data)
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
    }
    private func keychainError(_ status: OSStatus) -> APIError {
        if status == errSecInteractionNotAllowed {
            return APIError(status: 0, code: "keychain_locked", message: "设备尚未解锁，暂时无法读取登录状态，请解锁后重试。")
        }
        if status == errSecMissingEntitlement {
            return APIError(status: 0, code: "keychain_entitlement", message: "当前构建缺少钥匙串权限，请使用 Xcode 正常签名的构建（不要关闭代码签名）。")
        }
        return APIError(status: 0, code: "keychain", message: "无法访问安全存储（\(status)），请重试或重新打开 App。")
    }
}

@MainActor @Observable final class CloudStore {
    private var deletionReceipt: DeletionReceiptVault.Receipt?
    private(set) var enabled = false
    private(set) var busy = false
    private(set) var requiresSignIn = false
    private(set) var home: APIHome?
    private(set) var accounts: [APIAccount] = []
    private(set) var catalog: [APICatalogItem] = []
    private(set) var reports: [APIReport] = []
    private(set) var user: APIMe?
    private(set) var origin = ""
    private(set) var overviewOrder: [String]?
    private(set) var layoutVersion = 0
    private(set) var discipline = ""
    private(set) var disciplineUpdatedAt: String?
    var error: String?
    private(set) var reportsCursor: String?
    private(set) var catalogCursor: String?
    private var catalogQuery = ""
    private var api: MobileAPI?
    private let vault = KeychainVault()
    private var restored = false
    private(set) var restorationFinished = false
    var canEnterHome: Bool { restorationFinished && enabled && !requiresSignIn && user?.passwordSetupRequired != true }
    private var generation = UUID()
    private let cloudOnly: Bool
    init() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--beta-cloud-only") {
            UserDefaults.standard.set(true, forKey: "betaCloudOnly")
        }
        cloudOnly = UserDefaults.standard.bool(forKey: "betaCloudOnly")
        #else
        cloudOnly = false
        #endif
        enabled = cloudOnly; requiresSignIn = cloudOnly
    }
    var positions: [APIPosition] { (home?.snapshot.positions ?? []).filter { (Decimal(string: $0.quantity) ?? 0) > 0 } }
    static var allowLocal: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
    func restore() async {
        guard !restored else { return }; restored = true
        defer { restorationFinished = true }
        do {
            #if DEBUG && targetEnvironment(simulator)
            if cloudOnly {
                let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let file = directory.appendingPathComponent("beta-session.json")
                if FileManager.default.fileExists(atPath: file.path) {
                    defer { try? FileManager.default.removeItem(at: file) }
                    try vault.save(CloudSession.betaImport(Data(contentsOf: file)))
                }
            }
            #endif
            if let session = try vault.load() {
                let origin = try MobileAPI.validateOrigin(session.origin.absoluteString, allowLocal: Self.allowLocal)
                guard CloudSession.allowsOrigin(origin) else {
                    try? vault.clear()
                    throw APIError(status: 0, code: "wrong_origin", message: "登录会话的服务地址与当前 API 配置不一致，请重新登录。")
                }
                self.api = MobileAPI(origin: origin, tokens: session.tokens, vault: vault)
                self.origin = origin.absoluteString; enabled = true; requiresSignIn = false
                await refresh()
            }
        } catch { if !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
    @discardableResult func perform(_ work: () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        do { try await work(); error = nil; return true }
        catch {
            guard !isRequestCancellation(error), !Task.isCancelled else { return false }
            if (error as? APIError)?.status == 401 || (error as? URLError)?.code == .userAuthenticationRequired {
                requiresSignIn = true; home = nil; accounts = []; reports = []; catalog = []; user = nil
                discipline = ""; disciplineUpdatedAt = nil; overviewOrder = nil; layoutVersion = 0
            }
            self.error = error.localizedDescription; return false
        }
    }
    func signIn(origin: String, phone: String, password: String, agreementsAccepted: Bool) async {
        await perform {
            try AppAgreements.requireAcceptance(agreementsAccepted)
            let url = try connectionOrigin(origin)
            let client = MobileAPI(origin: url, vault: vault)
            try await client.passwordLogin(body: ["phone": phone, "password": password, "agreements_accepted": true])
            AppAgreements.record()
            try await activate(client, url: url)
        }
    }
    func refreshIdentity() async throws {
        try await load()
    }
    #if DEBUG
    func connectDevelopment(origin: String, access: String, refresh: String, agreementsAccepted: Bool) async {
        guard !busy else { return }
        do { try AppAgreements.requireAcceptance(agreementsAccepted) }
        catch { self.error = error.localizedDescription; return }
        await perform {
            let url = try connectionOrigin(origin)
            guard access.count >= 20, refresh.count >= 20 else { throw URLError(.userAuthenticationRequired) }
            let client = MobileAPI(origin: url, tokens: APITokens(accessToken: access, refreshToken: refresh), vault: vault)
            let _: APIMe = try await client.request("me")
            try await client.persistSession()
            AppAgreements.record()
            try await activate(client, url: url)
        }
    }
    #endif
    private func connectionOrigin(_ value: String) throws -> URL {
        let url = try MobileAPI.validateOrigin(value, allowLocal: Self.allowLocal)
        if cloudOnly && !CloudSession.allowsOrigin(url) {
            throw APIError(status: 0, code: "wrong_environment", message: "模拟器仅连接配置的 API 地址或本机开发服务器。")
        }
        return url
    }
    private func activate(_ client: MobileAPI, url: URL) async throws {
        generation = UUID(); home = nil; accounts = []; reports = []; catalog = []; user = nil
        discipline = ""; disciplineUpdatedAt = nil; overviewOrder = nil; layoutVersion = 0
        api = client; origin = url.absoluteString; enabled = true; requiresSignIn = false
        try await load()
    }
    private func load() async throws {
        guard let api else { return }
        let id = generation
        let me: APIMe = try await api.request("me")
        if cloudOnly && me.storeEnvironment != "Sandbox" {
            throw APIError(status: 0, code: "wrong_environment", message: "测试会话必须属于 Sandbox 环境。")
        }
        guard id == generation else { return }
        self.user = me
        guard me.passwordSetupRequired != true else { home = nil; accounts = []; reports = []; return }
        let home: APIHome = try await api.request("home")
        let accounts: [APIAccount] = try await api.request("accounts")
        let feed: APIPage<APIReport> = try await api.request("feed?limit=100")
        var nextDiscipline = discipline
        var nextDisciplineAt = disciplineUpdatedAt
        do {
            let discipline: APIDiscipline = try await api.request("me/discipline")
            nextDiscipline = discipline.content
            nextDisciplineAt = discipline.updatedAt
        } catch let error as APIError where error.status == 401 {
            throw error
        } catch let error as APIError where error.status == 404 {
            // Older test deployments may not expose the discipline endpoint yet.
            nextDiscipline = ""
            nextDisciplineAt = nil
        } catch {
            // A transient discipline failure must not hide the rest of the home screen.
        }
        guard id == generation else { return }
        self.user = me; self.home = home; self.accounts = accounts; self.reports = feed.items; self.reportsCursor = feed.nextCursor
        self.discipline = nextDiscipline; self.disciplineUpdatedAt = nextDisciplineAt
        let preferences: APIPreferences = try await api.request("me/preferences")
        guard id == generation else { return }
        overviewOrder = preferences.overviewOrder; layoutVersion = preferences.layoutVersion ?? 0
    }
    func refresh() async { await perform { try await load() } }
    func search(_ query: String) async {
        guard let api else { return }
        let id = generation
        do {
            var components = URLComponents(); components.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "limit", value: "100")]
            let page: APIPage<APICatalogItem> = try await api.request("instruments?" + (components.percentEncodedQuery ?? ""))
            guard id == generation, !Task.isCancelled else { return }
            catalog = page.items; catalogCursor = page.nextCursor; catalogQuery = query
        } catch { if !Task.isCancelled && !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
    func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: [String: Any]? = nil, key: String? = nil) async throws -> T {
        guard let api, !requiresSignIn else { throw URLError(.userAuthenticationRequired) }
        let id = generation
        do {
            let value: T = try await api.request(path, method: method, body: body, key: key)
            guard generation == id else { throw CancellationError() }
            return value
        } catch {
            if generation == id, (error as? APIError)?.status == 401 {
                requiresSignIn = true; home = nil; accounts = []; reports = []; catalog = []; user = nil
                discipline = ""; disciplineUpdatedAt = nil; overviewOrder = nil; layoutVersion = 0
            }
            throw error
        }
    }
    func moreReports() async {
        guard let cursor = reportsCursor else { return }
        await perform {
            let page: APIPage<APIReport> = try await request(apiPath("feed", ["cursor": cursor, "limit": "30"]))
            let ids = Set(reports.map(\.id))
            reports += page.items.filter { !ids.contains($0.id) }; reportsCursor = page.nextCursor
        }
    }
    func moreCatalog() async {
        guard let cursor = catalogCursor else { return }
        let query = catalogQuery
        await perform {
            let page: APIPage<APICatalogItem> = try await request(apiPath("instruments", ["cursor": cursor, "query": query, "limit": "100"]))
            guard query == catalogQuery else { return }
            let ids = Set(catalog.map(\.id))
            catalog += page.items.filter { !ids.contains($0.id) }; catalogCursor = page.nextCursor
        }
    }
    func deleteAccount() async throws -> APIDeletion {
        let response: APIDeletion = try await request("me/deletion-requests", method: "POST", body: ["confirmation": "DELETE"])
        deletionReceipt = .init(origin: URL(string: origin)!, receipt: response.receipt)
        do { try DeletionReceiptVault.save(deletionReceipt!) }
        catch { self.error = "删除请求已受理，但进度回执未能保存到设备；请在离开此页前查看处理结果。" }
        // The server has already revoked the session. Local storage failure must
        // never leave the deleted account visible or turn acceptance into a retry.
        do { try await api?.clearLocalSession() }
        catch { self.error = "删除请求已受理，登录已失效；本机安全存储清理失败，请解锁设备后退出登录重试。" }
        generation = UUID(); enabled = true; requiresSignIn = true
        home = nil; accounts = []; reports = []; catalog = []; user = nil; discipline = ""; disciplineUpdatedAt = nil; overviewOrder = nil; layoutVersion = 0
        return response
    }
    func deletionStatus(_ receipt: String) async throws -> APIDeletionStatus {
        guard let saved = try deletionReceipt ?? DeletionReceiptVault.load(), saved.receipt == receipt else { throw URLError(.userAuthenticationRequired) }
        let origin = try MobileAPI.validateOrigin(saved.origin.absoluteString, allowLocal: Self.allowLocal)
        return try await MobileAPI(origin: origin, vault: vault).deletionStatus(receipt: receipt)
    }
    func createAccount(_ name: String, key: String) async -> Bool {
        await perform {
            guard let api else { throw URLError(.userAuthenticationRequired) }
            let _: APIAck = try await api.request("accounts", method: "POST", body: ["name": name], key: key)
            accounts = try await api.request("accounts")
        }
    }
    func opening(item: APICatalogItem, quantity: String, price: String, date: Date, key: String, positionType: String = "core") async -> Bool {
        await perform {
            guard let api else { throw URLError(.userAuthenticationRequired) }
            var body: [String: Any] = ["instrument_id": item.id, "position_type": positionType,
                "quantity": try wireDecimal(quantity), "occurred_at": ISO8601DateFormatter().string(from: date)]
            if !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["price"] = try wireDecimal(price) }
            let _: APIAck = try await api.request("opening-positions", method: "POST", body: body, key: key)
            // A successful write remains successful even if the subsequent refresh fails.
            do { try await load() } catch { home = nil }
        }
    }
    func trade(position: APIPosition, buy: Bool, quantity: String, price: String, fee: String, date: Date, key: String) async -> Bool {
        await perform {
            guard let api else { throw URLError(.userAuthenticationRequired) }
            let body: [String: Any] = ["position_id": position.id, "kind": buy ? "buy" : "sell",
                "expected_version": position.version, "quantity": try wireDecimal(quantity), "price": try wireDecimal(price),
                "fee": try wireDecimal(fee, allowZero: true), "occurred_at": ISO8601DateFormatter().string(from: date)]
            let _: APIAck = try await api.request("ledger-events", method: "POST", body: body, key: key)
            do { try await load() } catch { home = nil }
        }
    }
    func saveDiscipline(_ content: String, expectedAt: String?) async -> Bool {
        await perform {
            guard let api else { throw URLError(.userAuthenticationRequired) }
            let response: APIDisciplineSaved = try await api.request(
                "me/discipline", method: "PUT", body: ["content": content, "expected_updated_at": expectedAt.map { $0 as Any } ?? NSNull()]
            )
            discipline = content
            disciplineUpdatedAt = response.updatedAt
        }
    }
    func initializeLayout(_ local: [String]?) async {
        guard overviewOrder == nil, !requiresSignIn, home != nil else { return }
        await saveOrder(OverviewBlock.normalized(local).map(\.rawValue))
    }
    func saveOrder(_ order: [String]) async {
        await perform {
            let result: APILayout = try await request("me/layout", method: "PUT", body: ["overview_order": order, "expected_version": layoutVersion])
            overviewOrder = result.overviewOrder; layoutVersion = result.layoutVersion
        }
    }
    func classify(_ position: APIPosition, type: String) async {
        await perform {
            let _: APIAck = try await request("positions/\(position.id)/classification", method: "PATCH", body: ["position_type": type, "expected_version": position.version])
            try await load()
        }
    }
    func logout() async {
        await perform {
            guard let api else { return }
            try await api.logout()
            generation = UUID(); self.api = nil; enabled = cloudOnly
            home = nil; accounts = []; catalog = []; reports = []; user = nil; origin = ""; requiresSignIn = cloudOnly
            discipline = ""; disciplineUpdatedAt = nil; overviewOrder = nil; layoutVersion = 0
        }
    }
}

struct DeletionReceiptVault {
    struct Receipt: Codable { let origin: URL; let receipt: String }
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.portfolioagent.ios.deletion", kSecAttrAccount as String: "receipt"] }
    static func save(_ value: Receipt) throws {
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw URLError(.cannotWriteToFile) }
        } else if status != errSecSuccess { throw URLError(.cannotWriteToFile) }
    }
    static func load() throws -> Receipt? {
        var item = query; item[kSecReturnData as String] = true; item[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw URLError(.cannotOpenFile) }
        return try JSONDecoder().decode(Receipt.self, from: data)
    }
}


extension CloudStore: CloudChatClient {
    func chatRequest<T: Decodable & Sendable>(_ path: String, method: String, body: [String: Any]?, key: String?) async throws -> T {
        try await request(path, method: method, body: body, key: key)
    }
}

extension CloudStore: InstrumentSearching {
    func searchInstruments(_ query: String) async throws -> [APICatalogItem] {
        let page: APIPage<APICatalogItem> = try await request(apiPath("instruments", ["query": query, "limit": "30"]))
        return page.items
    }
}
