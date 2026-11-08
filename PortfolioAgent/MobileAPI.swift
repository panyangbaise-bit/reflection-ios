import Foundation

struct APITokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
}
/// API origin resolved from the `API_ORIGIN` build setting (surfaced through the
/// `APIOrigin` Info.plist key). The checked-in placeholder is not a real server.
enum APIOrigin {
    static let placeholder = "https://api.example.com"
    static var configured: String {
        let value = (Bundle.main.object(forInfoDictionaryKey: "APIOrigin") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty, !value.contains("$(") else { return placeholder }
        return value
    }
    static var defaultURL: URL { URL(string: configured) ?? URL(string: placeholder)! }
    static func matches(_ url: URL) -> Bool {
        guard let expected = URLComponents(string: configured),
              let actual = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return actual.scheme?.lowercased() == expected.scheme?.lowercased()
            && actual.host?.lowercased() == expected.host?.lowercased()
            && normalizedPort(actual) == normalizedPort(expected)
            && (actual.path.isEmpty || actual.path == "/")
            && (expected.path.isEmpty || expected.path == "/")
            && actual.user == nil && actual.password == nil && actual.query == nil && actual.fragment == nil
    }
    /// Debug-only loopback development server. Release builds always return false.
    static func isLocalDevelopment(_ url: URL) -> Bool {
        #if DEBUG
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme == "http"
            && ["localhost", "127.0.0.1", "::1"].contains(components.host ?? "")
            && components.port == 8000
            && (components.path.isEmpty || components.path == "/")
            && components.user == nil && components.password == nil && components.query == nil && components.fragment == nil
        #else
        return false
        #endif
    }
    private static func normalizedPort(_ components: URLComponents) -> Int? {
        if let port = components.port { return port }
        switch components.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}

struct CloudSession: Codable, Sendable {
    let origin: URL
    let tokens: APITokens
    static func allowsOrigin(_ url: URL) -> Bool {
        APIOrigin.matches(url) || APIOrigin.isLocalDevelopment(url)
    }
    #if DEBUG
    static func betaImport(_ data: Data) throws -> Self {
        let session = try JSONDecoder().decode(Self.self, from: data)
        guard allowsOrigin(session.origin),
              session.tokens.accessToken.count >= 20, session.tokens.refreshToken.count >= 20 else {
            throw APIError(status: 0, code: "invalid_beta_session", message: "测试会话必须由配置的 API 地址或本机开发服务器签发。")
        }
        return session
    }
    #endif
}
protocol SessionVault: Sendable {
    func save(_ session: CloudSession) throws
    func load() throws -> CloudSession?
    func clear() throws
}
struct APIError: Error, LocalizedError {
    let status: Int
    let code: String
    let message: String
    var errorDescription: String? { message }
}
struct APIEnvelope<T: Decodable>: Decodable { let data: T }
extension APIEnvelope: Sendable where T: Sendable {}
struct APIProblem: Decodable {
    struct Detail: Decodable { let code: String; let message: String? }
    let error: Detail
}
struct APIPage<T: Decodable>: Decodable { let items: [T]; let nextCursor: String? }
extension APIPage: Sendable where T: Sendable {}
struct APIMe: Decodable { let id: String; let appAccountToken: String; let storeEnvironment: String; var phoneMasked: String? = nil; var hasPassword: Bool? = nil; var passwordSetupRequired: Bool? = nil }

func isRequestCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let ns = error as NSError
    return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
}

struct APIAccount: Decodable, Identifiable { let id: String; let name: String }
struct APICatalogItem: Decodable, Identifiable {
    let id: String; let symbol: String; let name: String; let market: String; let currency: String
    let assetClass: String; let quoteKind: String; let canAdd: Bool; let unavailableReason: String?
    let quoteStatus: String?; let price: String?; let asOf: String?
    var navChange: String? = nil; var navChangePct: String? = nil; var navPreviousAsOf: String? = nil
    var searchDetail: String {
        let venue = ["CN": "A股", "HK": "港股", "US": "美股"][market] ?? market
        let category: String
        switch assetClass {
        case "etf": category = market == "CN" ? "场内 ETF" : "\(venue) ETF"
        case "listed_fund": category = "场内基金"
        case "fund": category = market == "CN" ? "场外基金" : "基金"
        default: category = venue
        }
        return "\(category) · \(currency)"
    }
}
struct APIPosition: Decodable, Identifiable {
    let id: String; let accountId: String; let instrumentId: String
    let name: String; let symbol: String; let currency: String
    let quantity: String; let averageCost: String?; let price: String?
    let marketValueCny: String?; let unrealizedPnl: String?; let quoteStatus: String
    let version: Int; let lastOccurredAt: String
    var market: String? = nil; var assetClass: String? = nil
    var positionType: String? = nil
    var quoteKind: String? = nil; var navChange: String? = nil; var navChangePct: String? = nil
    var asOf: String? = nil
    var navPreviousAsOf: String? = nil; var openingCostSource: String? = nil; var openingQuoteAsOf: String? = nil
    var quoteStatusLabel: String {
        switch quoteStatus {
        case "current": return "实时行情"
        case "close_mark": return "收盘价"
        case "nav": return "基金净值"
        case "delayed": return "延迟行情"
        case "stale": return "行情已过期"
        case "missing": return "无行情"
        case "not_needed": return "已清仓"
        case "fx_missing": return "缺汇率"
        case "display_rights_unconfirmed": return "展示权未确认"
        case "instrument_disabled": return "标的下架"
        case "provider_mismatch": return "数据源不匹配"
        default: return quoteStatus
        }
    }
}
struct APISnapshot: Decodable {
    struct Coverage: Decodable { let total: Int; let priced: Int }
    struct Analysis: Decodable { let charts: [APIChart]? }
    let complete: Bool; let asOf: String; let coverage: Coverage
    let marketValueCny: String?; let pricedMarketValueCny: String; let unrealizedPnlCny: String?
    let yesterdayPnlCny: String?; let cumulativePnlCny: String?
    let positions: [APIPosition]
    var analysis: Analysis? = nil
}
struct APIReport: Decodable, Identifiable {
    let id: String; let title: String; let summary: String; let period: String; let kind: String
    let analysisKind: String?; let aiProvider: String?
    let createdAt: String?
}
// Legacy server field kept only so older deployments continue to decode. Not used by the UI.
struct APIEntitlements: Decodable { let pro: Bool }
struct APINews: Decodable, Identifiable {
    let id: String; let title: String; let summary: String; let source: String; let url: String
    let publishedAt: String; let usageScope: String
    let createdAt: String?
}
struct APIAssetPoint: Decodable { let asOf: String; let marketValueCny: String }
struct APIHome: Decodable { let snapshot: APISnapshot; let latestContent: APIReport?; let entitlements: APIEntitlements; let news: [APINews]?; let assetHistory: [APIAssetPoint]? }
struct APIDiscipline: Decodable { let content: String; let updatedAt: String? }
struct APIDisciplineSaved: Decodable { let saved: Bool; let updatedAt: String? }
struct APIAck: Decodable {} // Ignore additive server fields, never trust client-computed balances.

/// Preserve decimal strings on the wire; reject locale ambiguity rather than round via Double.
func wireDecimal(_ value: String, allowZero: Bool = false) throws -> String {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
          let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
          decimal <= Decimal(string: "1000000000000")!, allowZero ? decimal >= 0 : decimal > 0 else {
        throw APIError(status: 0, code: "invalid_decimal", message: "请输入有效的十进制数字，使用小数点且不要包含千位分隔符。")
    }
    return value
}
func cloudAmount(_ value: String?) -> String {
    guard let value, let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return "—" }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.string(from: decimal as NSDecimalNumber) ?? "—"
}

final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

actor MobileAPI {
    let origin: URL
    private let session: URLSession
    private let vault: any SessionVault
    private var tokens: APITokens?
    private var refreshTask: Task<APITokens, Error>?
    private var epoch = 0
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; return decoder
    }()

    static func validateOrigin(_ value: String, allowLocal: Bool = false) throws -> URL {
        guard let url = URL(string: value), let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw APIError(status: 0, code: "invalid_origin", message: "服务地址必须是 HTTPS 域名，不包含路径或账户信息。")
        }
        let local = ["localhost", "127.0.0.1", "::1"].contains(host) && components.port == 8000
        guard components.scheme == "https" || (allowLocal && components.scheme == "http" && local) else {
            throw APIError(status: 0, code: "invalid_origin", message: "服务地址必须是 HTTPS 域名，不包含路径或账户信息。开发版只允许本机 8000 端口使用 HTTP。")
        }
        return url
    }
    init(origin: URL, tokens: APITokens? = nil, vault: any SessionVault, session: URLSession? = nil) {
        self.origin = origin; self.tokens = tokens; self.vault = vault
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 35
        config.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    private func send<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                                    token: String? = nil, key: String? = nil) async throws -> T {
        guard let url = URL(string: "/api/mobile/v1/" + path, relativeTo: origin)?.absoluteURL else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let key { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            let problem = try? Self.decoder.decode(APIProblem.self, from: data)
            throw APIError(status: response.statusCode, code: problem?.error.code ?? "http_error",
                           message: problem?.error.message ?? "请求未完成，请检查输入或稍后重试。")
        }
        return try Self.decoder.decode(APIEnvelope<T>.self, from: data).data
    }
    func passwordLogin(body: [String: Any]) async throws {
        let next: APITokens = try await send("auth/password/login", method: "POST", body: body)
        try vault.save(CloudSession(origin: origin, tokens: next)); tokens = next
    }
    func persistSession() throws {
        guard let tokens else { throw URLError(.userAuthenticationRequired) }
        try vault.save(CloudSession(origin: origin, tokens: tokens))
    }
    func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: [String: Any]? = nil, key: String? = nil) async throws -> T {
        guard let token = tokens?.accessToken else { throw URLError(.userAuthenticationRequired) }
        let requestEpoch = epoch
        do { return try await send(path, method: method, body: body, token: token, key: key) }
        catch let error as APIError where error.status == 401 {
            try await refresh(rejectedToken: token)
            guard requestEpoch == epoch, let next = tokens?.accessToken else { throw CancellationError() }
            return try await send(path, method: method, body: body, token: next, key: key)
        }
    }
    private func refresh(rejectedToken: String) async throws {
        guard let current = tokens else { throw URLError(.userAuthenticationRequired) }
        if current.accessToken != rejectedToken { return }
        let requestEpoch = epoch
        let task: Task<APITokens, Error>
        if let running = refreshTask { task = running }
        else {
            task = Task { try await self.send("auth/refresh", method: "POST", body: ["refresh_token": current.refreshToken]) }
            refreshTask = task
        }
        do {
            let next = try await task.value
            guard epoch == requestEpoch else { throw CancellationError() }
            if tokens?.accessToken == rejectedToken {
                try vault.save(CloudSession(origin: origin, tokens: next))
                tokens = next
            }
            refreshTask = nil
        } catch {
            refreshTask = nil
            // A failed/ambiguous refresh must not replay the old token; the server rotates it once.
            if epoch == requestEpoch { tokens = nil; try? vault.clear() }
            throw APIError(status: 401, code: "reauthentication_required", message: "登录状态需要更新，请重新登录。")
        }
    }
    func logout() async throws {
        // Server revocation must succeed before the UI claims a complete sign out.
        let _: APIAck = try await request("auth/logout", method: "POST")
        epoch += 1; refreshTask?.cancel(); refreshTask = nil; tokens = nil
        try vault.clear()
    }
}

struct APIConversation: Decodable, Identifiable { let id: String; let title: String; let reportId: String? }
struct APIMessage: Decodable, Identifiable { let id: String; let role: String; let content: String; let createdAt: String; var charts: [APIChart]? = nil }
struct APIQueuedRun: Decodable { let runId: String; let conversationId: String; let status: String; let remainingFree: Int? }
struct APIActiveRun: Decodable { let runId: String?; let status: String? }
struct APIRun: Decodable { let id: String; let status: String; let answer: String?; let errorCode: String?; let charts: [APIChart]? }
struct APIChart: Decodable {
    struct Point: Decodable { let date: String; let close: String; var open: String? = nil; var high: String? = nil; var low: String? = nil }
    struct Annotation: Decodable { let index: Int; let text: String }
    struct Trendline: Decodable { let startIndex: Int; let endIndex: Int; let text: String }
    let title: String?; let ticker: String?; let market: String?; let points: [Point]; let annotations: [Annotation]?
    let trendlines: [Trendline]?
    var kind: String? = nil
    var source: String? = nil; var provider: String? = nil; var fetchedAt: String? = nil; var adjust: String? = nil
}
struct APIWatchlistItem: Decodable, Identifiable {
    let instrumentId: String; let ticker: String; let market: String; let name: String
    let priority: Int; let targetPrice: String?; let note: String
    var id: String { instrumentId }
}
struct APIOffsetPage<T: Decodable>: Decodable { let items: [T]; let nextOffset: Int? }
extension APIOffsetPage: Sendable where T: Sendable {}
struct APIReportDetail: Decodable {
    let id: String; let title: String; let summary: String; let period: String; let kind: String
    let snapshot: APISnapshot; let remainingFree: Int; let read: Bool; let analysisKind: String?
}
struct APILedgerEvent: Decodable, Identifiable {
    let id: String; let positionId: String; let kind: String; let quantity: String; let price: String
    let fee: String; let occurredAt: String
    var kindLabel: String { ["opening_snapshot": "初始持仓快照", "buy": "买入", "sell": "卖出"][kind] ?? kind }
}
struct APIPrivacy: Decodable {
    struct Consent: Decodable { let purpose: String; let granted: Bool; let provider: String; let disclosureVersion: String }
    let aiProvider: String?; let disclosureVersion: String; let consents: [Consent]; let traceCaptureContent: Bool?
    func granted(_ purpose: String) -> Bool { consents.contains { $0.purpose == purpose && $0.granted && $0.provider == aiProvider && $0.disclosureVersion == disclosureVersion } }
}
struct APIPreferences: Codable {
    var dailyReport: Bool; var weeklyReport: Bool; var reportPush: Bool; var newsPush: Bool; var timezone: String
    var overviewOrder: [String]? = nil; var layoutVersion: Int? = nil
}
// `subscriptionNotice` is a legacy server field; it is decoded but never displayed.
struct APIDeletion: Decodable { let status: String; let receipt: String; let subscriptionNotice: String }
struct APIDeletionStatus: Decodable { let status: String; let completedAt: String? }

func apiPath(_ path: String, _ query: [String: String?]) -> String {
    var components = URLComponents()
    components.queryItems = query.sorted { $0.key < $1.key }.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
    return path + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
}

extension MobileAPI {
    func clearLocalSession() throws {
        epoch += 1; refreshTask?.cancel(); refreshTask = nil; tokens = nil
        try vault.clear()
    }
    func deletionStatus(receipt: String) async throws -> APIDeletionStatus {
        try await send("auth/deletion-status", method: "POST", body: ["refresh_token": receipt])
    }
}

struct APILayout: Decodable { let overviewOrder: [String]; let layoutVersion: Int }

indirect enum APIJSON: Codable {
    case object([String: APIJSON]), array([APIJSON]), string(String), number(Decimal), bool(Bool), null
    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let b = try? box.decode(Bool.self) { self = .bool(b) }
        else if let s = try? box.decode(String.self) { self = .string(s) }
        else if let d = try? box.decode(Decimal.self) { self = .number(d) }
        else if let a = try? box.decode([APIJSON].self) { self = .array(a) }
        else { self = .object(try box.decode([String: APIJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .object(let v): try box.encode(v)
        case .array(let v): try box.encode(v)
        case .string(let v): try box.encode(v)
        case .number(let v): try box.encode(v)
        case .bool(let v): try box.encode(v)
        case .null: try box.encodeNil()
        }
    }
}
struct APIExportPage: Codable {
    let schemaVersion: Int; let section: String; let generatedAt: String; let consistency: String
    let items: [APIJSON]; let nextCursor: String?
}
