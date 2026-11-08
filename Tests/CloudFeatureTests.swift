import XCTest
@testable import PortfolioCore

final class CloudFeatureTests: XCTestCase {
    private var decoder: JSONDecoder { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }
    func testMessagePaginationAndChartsDecode() throws {
        let raw = #"{"items":[{"id":"m","role":"assistant","content":"AI 生成","created_at":"2026-10-26T00:00:00Z"}],"next_cursor":"older"}"#
        let page = try decoder.decode(APIPage<APIMessage>.self, from: Data(raw.utf8))
        XCTAssertEqual(page.nextCursor, "older")
        let run = try decoder.decode(APIRun.self, from: Data(#"{"id":"r","status":"succeeded","answer":"done","error_code":null,"charts":[{"title":"历史","source":"sina","provider":"akshare:research","fetched_at":"2026-10-27T00:00:00Z","points":[{"date":"2026-10-23","close":"1.123456789012"}],"annotations":[{"index":0,"text":"观察"}]}]}"#.utf8))
        XCTAssertEqual(run.charts?.first?.points.first?.close, "1.123456789012")
        XCTAssertEqual(run.charts?.first?.source, "sina")
        let saved = try decoder.decode(APIMessage.self, from: Data(#"{"id":"m","role":"assistant","content":"报告","created_at":"2026-10-26T00:00:00Z","charts":[{"title":"净值","kind":"historical_nav","points":[{"date":"2026-10-23","close":"1.05"}],"annotations":[{"index":0,"text":"记录"}],"trendlines":[]}]}"#.utf8))
        XCTAssertEqual(saved.charts?.first?.kind, "historical_nav")
        XCTAssertEqual(saved.charts?.first?.annotations?.first?.text, "记录")
    }
    func testNavAndWatchlistDecode() throws {
        let raw = #"{"items":[{"instrument_id":"i","ticker":"000001","name":"基金","market":"CN","priority":2,"target_price":"1.2","note":"记录"}],"next_offset":null}"#
        let page = try decoder.decode(APIOffsetPage<APIWatchlistItem>.self, from: Data(raw.utf8))
        XCTAssertEqual(page.items.first?.id, "i")
        let nav = try decoder.decode(APICatalogItem.self, from: Data(#"{"id":"i","symbol":"000001","name":"基金","market":"CN","currency":"CNY","asset_class":"fund","quote_kind":"nav","can_add":true,"unavailable_reason":null,"quote_status":"nav","price":"1.05","as_of":"2026-10-26T00:00:00Z","nav_change_pct":"5","nav_previous_as_of":"2026-10-25T00:00:00Z"}"#.utf8))
        XCTAssertEqual(nav.navChangePct, "5")
        XCTAssertEqual(nav.quoteKind, "nav")
    }
    func testConsentRequiresCurrentProviderAndDisclosure() throws {
        let privacy = try decoder.decode(APIPrivacy.self, from: Data(#"{"ai_provider":"deepseek","disclosure_version":"2","consents":[{"purpose":"interactive_ai","granted":true,"provider":"deepseek","disclosure_version":"1"},{"purpose":"scheduled_ai","granted":true,"provider":"deepseek","disclosure_version":"2"}]}"#.utf8))
        XCTAssertFalse(privacy.granted("interactive_ai"))
        XCTAssertTrue(privacy.granted("scheduled_ai"))
    }
    func testQueryEscapesSearchAndOmitsEmptyCursor() {
        let path = apiPath("instruments", ["query": "A&B + 中", "cursor": nil])
        let components = URLComponents(string: "https://example.test/" + path)!
        XCTAssertEqual(components.queryItems?.count, 1)
        XCTAssertEqual(components.queryItems?.first?.value, "A&B + 中")
    }
    func testExportPreservesDecimalStringsAndFieldNames() throws {
        let raw = #"{"schema_version":1,"section":"positions","generated_at":"now","consistency":"per_page","items":[{"average_cost":"4.123456789012","quantity":"100.0000000001"}],"next_cursor":null}"#
        let page = try decoder.decode(APIExportPage.self, from: Data(raw.utf8))
        let encoded = try JSONEncoder().encode(page.items)
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String:String]])
        XCTAssertEqual(records[0]["average_cost"], "4.123456789012")
    }
    #if DEBUG
    func testLocalSimulatorImportHasExactLoopbackBoundary() throws {
        XCTAssertTrue(CloudSession.allowsOrigin(URL(string: "http://127.0.0.1:8000")!))
        for origin in ["http://127.0.0.1:9999", "http://127.0.0.1:8000/path", "http://localhost.evil:8000", "http://user:pass@localhost:8000", "http://localhost:8000?redirect=1"] {
            XCTAssertFalse(CloudSession.allowsOrigin(URL(string: origin)!))
        }
    }
    #endif
}
