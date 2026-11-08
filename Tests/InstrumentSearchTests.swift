import XCTest
@testable import PortfolioCore

@MainActor final class InstrumentSearchTests: XCTestCase {
    final class Client: InstrumentSearching {
        var pending: [String: CheckedContinuation<[APICatalogItem], Error>] = [:]
        func searchInstruments(_ query: String) async throws -> [APICatalogItem] {
            try await withCheckedThrowingContinuation { pending[query] = $0 }
        }
        func finish(_ query: String, name: String) {
            pending.removeValue(forKey: query)?.resume(returning: [APICatalogItem(id: name, symbol: name, name: name, market: "US", currency: "USD", assetClass: "stock", quoteKind: "delayed", canAdd: true, unavailableReason: nil, quoteStatus: nil, price: nil, asOf: nil)])
        }
    }
    func testLateResponseCannotReplaceNewSearch() async {
        let client = Client(), model = InstrumentSearch()
        let first = Task { await model.search("DU", using: client, debounce: .zero) }
        while client.pending["DU"] == nil { await Task.yield() }
        let second = Task { await model.search("DUOL", using: client, debounce: .zero) }
        while client.pending["DUOL"] == nil { await Task.yield() }
        client.finish("DUOL", name: "DUOL"); await second.value
        client.finish("DU", name: "OLD"); await first.value
        XCTAssertEqual(model.items.map(\.symbol), ["DUOL"])
        XCTAssertFalse(model.loading)
    }
    func testClearingSearchDiscardsPendingResults() async {
        let client = Client(), model = InstrumentSearch()
        let work = Task { await model.search("DUOL", using: client, debounce: .zero) }
        while client.pending["DUOL"] == nil { await Task.yield() }
        await model.search("  ", using: client, debounce: .zero)
        client.finish("DUOL", name: "DUOL"); await work.value
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.loading)
        XCTAssertNil(model.error)
    }
    func testURLSessionCancellationDoesNotBecomeSearchError() async {
        let client = Client(), model = InstrumentSearch()
        let work = Task { await model.search("DUOL", using: client, debounce: .zero) }
        while client.pending["DUOL"] == nil { await Task.yield() }
        client.pending.removeValue(forKey: "DUOL")?.resume(throwing: URLError(.cancelled))
        await work.value
        XCTAssertNil(model.error)
        XCTAssertFalse(model.loading)
        XCTAssertTrue(model.items.isEmpty)
    }
    func testFailureClearsResultsAndSurfacesError() async {
        let client = Client(), model = InstrumentSearch()
        let work = Task { await model.search("  DUOL  ", using: client, debounce: .zero) }
        while client.pending["DUOL"] == nil { await Task.yield() }
        client.pending.removeValue(forKey: "DUOL")?.resume(throwing: URLError(.notConnectedToInternet))
        await work.value
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.loading)
    }
}

final class AssetCompositionTests: XCTestCase {
    func testAggregationIgnoresInvalidAndZeroValues() {
        let slices = AssetComposition.grouped([("A 股", 20), ("A 股", 30), ("美股", 50), ("空", 0), ("坏数据", .nan)])
        XCTAssertEqual(slices.count, 2)
        XCTAssertEqual(slices.reduce(0) { $0 + $1.value }, 100)
        XCTAssertEqual(slices.first { $0.title == "A 股" }?.value, 50)
    }
    func testCloudCompositionUsesAssetClassAndSuppressesIncompleteValuation() throws {
        let json = """
        [{"id":"p1","account_id":"a1","instrument_id":"i1","name":"ETF","symbol":"510300","market":"CN","asset_class":"etf","currency":"CNY","quantity":"1","market_value_cny":"100","quote_status":"current","version":1,"last_occurred_at":"2026-10-29"}]
        """
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let positions = try decoder.decode([APIPosition].self, from: Data(json.utf8))
        XCTAssertEqual(AssetComposition.cloud(positions, complete: true), [AssetSlice(title: "ETF", value: 100)])
        XCTAssertTrue(AssetComposition.cloud(positions, complete: false).isEmpty)
    }
    func testCloudCompositionSkipsNavHoldingsWithoutBlankingChart() throws {
        // NAV holdings have no live market value and must not blank the whole pie.
        let json = """
        [{"id":"p1","account_id":"a1","instrument_id":"i1","name":"ETF","symbol":"510300","market":"CN","asset_class":"etf","currency":"CNY","quantity":"1","market_value_cny":"100","quote_status":"close_mark","version":1,"last_occurred_at":"2026-10-29"},
         {"id":"p2","account_id":"a1","instrument_id":"i2","name":"货币基金","symbol":"000198","market":"CN","asset_class":"fund","currency":"CNY","quantity":"10000","quote_status":"nav","version":1,"last_occurred_at":"2026-10-29"}]
        """
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let positions = try decoder.decode([APIPosition].self, from: Data(json.utf8))
        XCTAssertEqual(AssetComposition.cloud(positions, complete: true), [AssetSlice(title: "ETF", value: 100)])
    }
}
