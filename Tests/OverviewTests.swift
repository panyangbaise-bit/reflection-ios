import XCTest
@testable import PortfolioCore

final class OverviewTests: XCTestCase {
    func testLatestCardSelectsAcrossNewsAndReportsByAvailabilityTime() throws {
        let report: [String: Any] = ["id": "weekly", "title": "周总结", "summary": "复盘", "period": "2026-10-24", "kind": "weekly", "created_at": "2026-10-25T08:00:00Z"]
        func news(_ id: String, _ created: String, _ published: String) -> [String: Any] {
            ["id": id, "title": "新闻", "summary": "摘要", "source": "来源", "url": "https://example.com/\(id)", "published_at": published, "created_at": created, "usage_scope": "development"]
        }
        func decode(_ items: [[String: Any]]) throws -> APIHome {
            let body: [String: Any] = [
                "snapshot": ["complete": false, "as_of": "2026-10-25T08:00:00Z", "coverage": ["total": 1, "priced": 0], "priced_market_value_cny": "0", "positions": []],
                "entitlements": ["pro": true], "latest_content": report, "news": items
            ]
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(APIHome.self, from: JSONSerialization.data(withJSONObject: body))
        }
        let earlier = news("old", "2026-10-25T07:00:00Z", "2026-10-25T06:00:00Z")
        let arrivedLater = news("new", "2026-10-25T08:01:00.123456Z", "2026-10-24T20:00:00Z")
        XCTAssertEqual(OverviewNotice.cloud(try decode([earlier, arrivedLater]))?.id, "new")
        XCTAssertEqual(OverviewNotice.cloud(try decode([earlier]))?.id, "weekly")
        XCTAssertNil(try decode([]).snapshot.yesterdayPnlCny)
        XCTAssertNil(try decode([]).snapshot.cumulativePnlCny)
    }

    func testHistoryDoesNotInventMissingDatesOrTurnInvalidMarksIntoZero() {
        let points = OverviewPoint.from([
            APIAssetPoint(asOf: "2026-10-25T08:00:00Z", marketValueCny: "150.50"),
            APIAssetPoint(asOf: "2026-10-22T08:00:00Z", marketValueCny: "100"),
            APIAssetPoint(asOf: "invalid", marketValueCny: "999"),
            APIAssetPoint(asOf: "2026-10-23T08:00:00Z", marketValueCny: "NaN"),
            APIAssetPoint(asOf: "2026-10-24T08:00:00Z", marketValueCny: "-1")
        ])
        XCTAssertEqual(points.map(\.value), [100, 150.5])
        XCTAssertEqual(points.last!.date.timeIntervalSince(points.first!.date), 3 * 86400)
    }

    func testDemoNewsIsAlwaysTheLatestCard() {
        XCTAssertEqual(OverviewNotice.demo(reports: SampleData.reports)?.id, "demo-news")
    }

    func testOverviewOrderDefaultsToRulesThenReviewThenHoldings() {
        XCTAssertEqual(OverviewBlock.defaultOrder, [.discipline, .latest, .holdings])
        XCTAssertEqual(OverviewBlock.normalized(nil), [.discipline, .latest, .holdings])
        XCTAssertEqual(OverviewBlock.normalized([]), [.discipline, .latest, .holdings])
        XCTAssertEqual(OverviewBlock.normalized(["holdings", "discipline"]), [.holdings, .discipline, .latest])
        XCTAssertEqual(OverviewBlock.normalized(["latest", "latest", "unknown", "holdings"]), [.latest, .holdings, .discipline])
        XCTAssertEqual(PortfolioState(positions: []).overviewBlocks, [.discipline, .latest, .holdings])
    }

    func testDroppingABlockMovesItIntoTheTargetSlot() {
        let order: [OverviewBlock] = [.discipline, .latest, .holdings]
        XCTAssertEqual(OverviewBlock.moving(.discipline, onto: .holdings, in: order), [.latest, .holdings, .discipline])
        XCTAssertEqual(OverviewBlock.moving(.holdings, onto: .discipline, in: order), [.holdings, .discipline, .latest])
        XCTAssertEqual(OverviewBlock.moving(.latest, onto: .discipline, in: order), [.latest, .discipline, .holdings])
        XCTAssertEqual(OverviewBlock.moving(.latest, onto: .latest, in: order), order)
        XCTAssertEqual(OverviewBlock.moving(.discipline, onto: .latest, in: [.holdings]), [.holdings])
    }

    func testOverviewOrderAndRulesSurviveDiskRoundtrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalRepository(url: directory.appendingPathComponent("state.json"))
        var state = SampleData.initialState
        state.overviewOrder = ["holdings", "latest", "discipline"]
        state.tradingDiscipline = TradingDisciplineRules.normalize("  第一条规则  \n\n第二条规则\n")
        state.disciplineUpdatedAt = Date(timeIntervalSince1970: 1_900_000_000)
        try repository.save(state)
        let restored = try XCTUnwrap(repository.load())
        XCTAssertEqual(restored.overviewBlocks, [.holdings, .latest, .discipline])
        XCTAssertEqual(restored.tradingDiscipline, "第一条规则\n第二条规则")
        XCTAssertEqual(restored.disciplineUpdatedAt, state.disciplineUpdatedAt)
    }

    func testDisciplineNormalizesLinesAndCapsLength() {
        XCTAssertEqual(TradingDisciplineRules.rules(nil), [])
        XCTAssertEqual(TradingDisciplineRules.rules(" \n\t\n"), [])
        XCTAssertEqual(TradingDisciplineRules.rules("  A  \n\n B \n"), ["A", "B"])
        XCTAssertEqual(TradingDisciplineRules.normalize("A\r\n\r\nB"), "A\nB")
        let long = String(repeating: "规", count: TradingDisciplineRules.maxLength + 100)
        XCTAssertEqual(TradingDisciplineRules.normalize(long).count, TradingDisciplineRules.maxLength)
        XCTAssertEqual(TradingDisciplineRules.rules(SampleData.disciplineSample).count, 2)
    }

    func testPositionTypesDefaultToCoreAndPersistSatellite() throws {
        var state = PortfolioState(positions: [])
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        try PortfolioMath.add(to: &state, instrument: SampleData.instruments[0], account: "A", quantity: 10, cost: 4, date: now, positionType: .satellite, now: now)
        try PortfolioMath.add(to: &state, instrument: SampleData.instruments[1], account: "B", quantity: 10, cost: 1, date: now, now: now)
        XCTAssertEqual(state.positions[0].type, .satellite)
        XCTAssertEqual(state.positions[1].type, .core)
        let restored = try JSONDecoder().decode(PortfolioState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.positions[0].type, .satellite)
        XCTAssertEqual(restored.positions[1].type, .core)
        let sample = SampleData.initialState.positions
        XCTAssertEqual(sample.filter { $0.type == .core }.count, 3)
        XCTAssertEqual(sample.filter { $0.type == .satellite }.count, 2)
    }

    func testOlderLocalFilesWithoutNewOptionalFieldsStillLoad() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(SampleData.initialState)) as? [String: Any])
        json.removeValue(forKey: "tradingDiscipline")
        json.removeValue(forKey: "disciplineUpdatedAt")
        json.removeValue(forKey: "overviewOrder")
        if var positions = json["positions"] as? [[String: Any]] {
            for index in positions.indices { positions[index].removeValue(forKey: "positionType") }
            json["positions"] = positions
        }
        let restored = try JSONDecoder().decode(PortfolioState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.tradingDiscipline)
        XCTAssertNil(restored.disciplineUpdatedAt)
        XCTAssertEqual(restored.overviewBlocks, [.discipline, .latest, .holdings])
        XCTAssertTrue(restored.positions.allSatisfy { $0.type == .core })
    }
}
