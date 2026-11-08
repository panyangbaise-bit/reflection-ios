import XCTest
@testable import PortfolioCore

private final class MemoryVault: SessionVault, @unchecked Sendable {
    private let lock = NSLock()
    private var value: CloudSession?
    func save(_ session: CloudSession) throws { lock.lock(); defer { lock.unlock() }; value = session }
    func load() throws -> CloudSession? { lock.lock(); defer { lock.unlock() }; return value }
    func clear() throws { lock.lock(); defer { lock.unlock() }; value = nil }
}
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class MobileAPITests: XCTestCase {
    func testOnlyCancellationIsSuppressed() {
        XCTAssertTrue(isRequestCancellation(CancellationError()))
        XCTAssertTrue(isRequestCancellation(URLError(.cancelled)))
        XCTAssertTrue(isRequestCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        XCTAssertFalse(isRequestCancellation(URLError(.timedOut)))
        XCTAssertFalse(isRequestCancellation(APIError(status: 401, code: "unauthorized", message: "请登录")))
    }
    func testPasswordLoginPersistsVerifiedSession() async throws {
        let vault = MemoryVault()
        StubProtocol.handler = { request in
            XCTAssertTrue(request.url!.path.hasSuffix("auth/password/login"))
            return (200, #"{"data":{"access_token":"password-access","refresh_token":"password-refresh"}}"#)
        }
        try await client(vault: vault).passwordLogin(body: ["phone":"13800138000", "password":"password123", "agreements_accepted":true])
        XCTAssertEqual(try vault.load()?.tokens.accessToken, "password-access")
    }
    func testRejectedLoginNeverOverwritesExistingSession() async throws {
        let vault = MemoryVault(); let api = client(vault: vault)
        try await api.persistSession()
        StubProtocol.handler = { _ in (400, #"{"error":{"code":"invalid_credentials","message":"手机号或密码错误"}}"#) }
        do { try await api.passwordLogin(body: ["phone":"13800138000", "password":"wrong-password", "agreements_accepted":true]); XCTFail() }
        catch { XCTAssertEqual((error as? APIError)?.code, "invalid_credentials") }
        XCTAssertEqual(try vault.load()?.tokens.accessToken, "old-access")
    }
    #if DEBUG
    func testBetaSessionImportNeverSendsCredentialsToAnotherOrigin() throws {
        let tokens = APITokens(accessToken: String(repeating: "a", count: 32), refreshToken: String(repeating: "b", count: 48))
        for origin in ["https://other.example.com", "https://api.example.com/extra", "https://api.example.com?redirect=1", "http://api.example.com", "https://user:pass@api.example.com", "https://api.example.com:8443"] {
            let data = try JSONEncoder().encode(CloudSession(origin: URL(string: origin)!, tokens: tokens))
            XCTAssertThrowsError(try CloudSession.betaImport(data))
        }
        let data = try JSONEncoder().encode(CloudSession(origin: APIOrigin.defaultURL, tokens: tokens))
        XCTAssertEqual(try CloudSession.betaImport(data).tokens, tokens)
    }
    func testConfiguredOriginHasSafePlaceholderDefault() {
        XCTAssertEqual(APIOrigin.placeholder, "https://api.example.com")
        XCTAssertEqual(APIOrigin.defaultURL.absoluteString, "https://api.example.com")
        XCTAssertTrue(CloudSession.allowsOrigin(APIOrigin.defaultURL))
        XCTAssertFalse(CloudSession.allowsOrigin(URL(string: "https://api.example.com.evil.com")!))
    }
    #endif
    private func client(vault: MemoryVault = MemoryVault()) -> MobileAPI {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        return MobileAPI(origin: URL(string: "https://api.example.com")!, tokens: APITokens(accessToken: "old-access", refreshToken: "old-refresh"), vault: vault, session: URLSession(configuration: config))
    }
    func testDecimalAndEndpointValidation() throws {
        XCTAssertEqual(try wireDecimal(" 123456789.1234567890 "), "123456789.1234567890")
        XCTAssertEqual(try wireDecimal("0", allowZero: true), "0")
        for bad in ["0", "-1", "1e3", "1,000", "2abc", "NaN", "1.2.3", "1000000000001"] { XCTAssertThrowsError(try wireDecimal(bad)) }
        for bad in ["http://example.com", "https://user:pass@example.com", "https://example.com/anything", "https://example.com?token=secret"] { XCTAssertThrowsError(try MobileAPI.validateOrigin(bad, allowLocal: true)) }
        XCTAssertThrowsError(try MobileAPI.validateOrigin("http://127.0.0.1:8000"))
        XCTAssertThrowsError(try MobileAPI.validateOrigin("http://127.0.0.1:9000", allowLocal: true))
        XCTAssertThrowsError(try MobileAPI.validateOrigin("http://localhost:9000", allowLocal: true))
        XCTAssertEqual(try MobileAPI.validateOrigin("http://127.0.0.1:8000", allowLocal: true).port, 8000)
        XCTAssertEqual(try MobileAPI.validateOrigin("https://api.example.com").absoluteString, "https://api.example.com")
        XCTAssertEqual(cloudAmount(nil), "—")
    }
    func testConcurrentUnauthorizedRequestsRefreshOnlyOnce() async throws {
        let lock = NSLock()
        var refreshCount = 0
        StubProtocol.handler = { request in
            if request.url!.path.hasSuffix("auth/refresh") {
                lock.lock(); refreshCount += 1; lock.unlock()
                return (200, #"{"data":{"access_token":"next-access","refresh_token":"next-refresh"}}"#)
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access" { return (401, #"{"error":{"code":"unauthorized","message":"expired"}}"#) }
            return (200, #"{"data":{"id":"u","app_account_token":"u","store_environment":"Sandbox"}}"#)
        }
        let vault = MemoryVault(); let api = client(vault: vault)
        async let a: APIMe = api.request("me")
        async let b: APIMe = api.request("me")
        let results = try await (a, b)
        XCTAssertEqual(results.0.id, "u"); XCTAssertEqual(results.1.id, "u")
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(try vault.load()?.tokens.refreshToken, "next-refresh")
    }
    func testWriteRetriesAfterAuthUseSameIdempotencyKey() async throws {
        var keys: [String?] = []
        StubProtocol.handler = { request in
            if request.url!.path.hasSuffix("auth/refresh") { return (200, #"{"data":{"access_token":"next-access","refresh_token":"next-refresh"}}"#) }
            keys.append(request.value(forHTTPHeaderField: "Idempotency-Key"))
            if keys.count == 1 { return (401, #"{"error":{"code":"unauthorized"}}"#) }
            return (201, #"{"data":{}}"#)
        }
        let _: APIAck = try await client().request("opening-positions", method: "POST", body: ["quantity":"0.1234567890"], key: "one-intent")
        XCTAssertEqual(keys, ["one-intent", "one-intent"])
    }
    func testTransportFailureDoesNotBlindlyRepeatMutation() async throws {
        var calls = 0
        StubProtocol.handler = { _ in calls += 1; throw URLError(.timedOut) }
        do { let _: APIAck = try await client().request("accounts", method: "POST", body: ["name":"account"], key: "one-intent"); XCTFail() }
        catch { XCTAssertEqual(calls, 1) }
    }
    func testFailedRefreshClearsCredentialsAndNeverReplaysOldToken() async throws {
        let vault = MemoryVault(); let api = client(vault: vault)
        try await api.persistSession()
        var refreshes = 0
        StubProtocol.handler = { request in
            if request.url!.path.hasSuffix("auth/refresh") { refreshes += 1; throw URLError(.timedOut) }
            return (401, #"{"error":{"code":"unauthorized"}}"#)
        }
        for _ in 0..<2 {
            do { let _: APIMe = try await api.request("me"); XCTFail() } catch {}
        }
        XCTAssertEqual(refreshes, 1); XCTAssertNil(try vault.load())
    }
    func testMissingValuationIsNotDecodedAsZero() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = #"{"complete":false,"as_of":"2026-10-24","coverage":{"total":1,"priced":0},"market_value_cny":null,"priced_market_value_cny":"0","unrealized_pnl_cny":null,"positions":[]}"#
        let snapshot = try decoder.decode(APISnapshot.self, from: Data(raw.utf8))
        XCTAssertNil(snapshot.marketValueCny); XCTAssertFalse(snapshot.complete)
    }
}

final class MobileAPIIntegrationTests: XCTestCase {
    private struct LiveSession {
        let origin: URL
        let tokens: APITokens
    }

    private func liveSession() throws -> LiveSession? {
        guard let path = ProcessInfo.processInfo.environment["PA_IOS_TEST_SESSION"] else { return nil }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
        let originString = json["origin"] as? String ?? APIOrigin.configured
        let nested = json["tokens"] as? [String: Any]
        let access = nested?["accessToken"] as? String ?? json["access_token"] as? String
        let refresh = nested?["refreshToken"] as? String ?? json["refresh_token"] as? String
        guard let access, let refresh, access.count >= 20, refresh.count >= 20 else {
            throw APIError(status: 0, code: "invalid_test_session", message: "测试会话文件缺少 access/refresh token。")
        }
        return LiveSession(
            origin: try MobileAPI.validateOrigin(originString, allowLocal: true),
            tokens: APITokens(accessToken: access, refreshToken: refresh)
        )
    }

    func testLiveCatalogSearch() async throws {
        guard let session = try liveSession() else {
            throw XCTSkip("Set PA_IOS_TEST_SESSION to a Sandbox session issued by the test server.")
        }
        let api = MobileAPI(origin: session.origin, tokens: session.tokens, vault: MemoryVault())
        let me: APIMe = try await api.request("me")
        XCTAssertEqual(me.storeEnvironment, "Sandbox")
        for query in ["600519", "700", "159998"] {
            let page: APIPage<APICatalogItem> = try await api.request("instruments?query=" + query + "&limit=5")
            let item = try XCTUnwrap(page.items.first { $0.canAdd }, "no addable result for \(query)")
            XCTAssertFalse(item.symbol.isEmpty)
            print("live catalog \(query) -> \(item.symbol) \(item.name) quote=\(item.quoteStatus ?? "nil")")
        }
    }

    func testLiveDisciplineRoundtrip() async throws {
        guard let session = try liveSession() else {
            throw XCTSkip("Set PA_IOS_TEST_SESSION to a Sandbox session issued by the test server.")
        }
        let api = MobileAPI(origin: session.origin, tokens: session.tokens, vault: MemoryVault())
        let original: APIDiscipline = try await api.request("me/discipline")
        let content = "核心仓分批建仓\n卫星仓先定退出条件"
        let saved: APIDisciplineSaved = try await api.request(
            "me/discipline", method: "PUT", body: ["content": content]
        )
        XCTAssertTrue(saved.saved)
        XCTAssertNotNil(saved.updatedAt)
        let loaded: APIDiscipline = try await api.request("me/discipline")
        XCTAssertEqual(loaded.content, content)
        XCTAssertEqual(loaded.updatedAt, saved.updatedAt)
        let _: APIDisciplineSaved = try await api.request(
            "me/discipline", method: "PUT", body: ["content": original.content]
        )
    }

    func testLiveBackendLedgerRoundtrip() async throws {
        guard let session = try liveSession() else {
            throw XCTSkip("Set PA_IOS_TEST_SESSION to a Sandbox session issued by the test server.")
        }
        let api = MobileAPI(origin: session.origin, tokens: session.tokens, vault: MemoryVault())
        let me: APIMe = try await api.request("me")
        XCTAssertEqual(me.storeEnvironment, "Sandbox")
        let account: APIAccount = try await api.request("accounts", method: "POST", body: ["name":"iOS integration " + UUID().uuidString], key: UUID().uuidString)
        let catalog: APIPage<APICatalogItem> = try await api.request("instruments?query=510300&limit=5")
        let item = try XCTUnwrap(catalog.items.first { $0.symbol == "510300" && $0.canAdd })
        let instant = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-2))
        let opening: [String: Any] = ["account_id":account.id,"instrument_id":item.id,"quantity":"100.1234567890","price":"4.10","occurred_at":instant]
        let key = UUID().uuidString
        let _: APIAck = try await api.request("opening-positions", method: "POST", body: opening, key: key)
        let _: APIAck = try await api.request("opening-positions", method: "POST", body: opening, key: key)
        let snapshot: APISnapshot = try await api.request("portfolio/snapshot")
        let positions = snapshot.positions.filter { $0.accountId == account.id }
        XCTAssertEqual(positions.count, 1)
        let position = try XCTUnwrap(positions.first)
        XCTAssertEqual(Decimal(string: position.quantity), Decimal(string: "100.1234567890"))
        let trade: [String: Any] = ["position_id":position.id,"kind":"sell","expected_version":position.version,"quantity":"0.1234567890","price":"4.20","fee":"0.01","occurred_at":ISO8601DateFormatter().string(from: Date())]
        let _: APIAck = try await api.request("ledger-events", method: "POST", body: trade, key: UUID().uuidString)
        let next: APIHome = try await api.request("home")
        XCTAssertEqual(Decimal(string: next.snapshot.positions.first { $0.id == position.id }!.quantity), 100)
        do {
            let _: APIAck = try await api.request("ledger-events", method: "POST", body: trade, key: UUID().uuidString)
            XCTFail("Old position version must be rejected")
        } catch let error as APIError { XCTAssertEqual(error.code, "version_conflict") }
    }
}
