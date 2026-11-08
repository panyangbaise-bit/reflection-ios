import Foundation
import XCTest
@testable import PortfolioCore

final class PortfolioCoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)
    private func empty() -> PortfolioState { PortfolioState(positions: []) }

    func testOldStateMigratesAgentHistoryWithoutLosingReplies() throws {
        var state = empty()
        state.replies["ask"] = [Reply(question: "旧问答", answer: "旧回答")]
        try PortfolioMath.appendReply(to: &state, reportID: "daily", question: "日报追问", answer: "回答")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json.removeValue(forKey: "agentConversations")
        json.removeValue(forKey: "activeAgentConversationID")
        var restored = try JSONDecoder().decode(PortfolioState.self, from: JSONSerialization.data(withJSONObject: json))
        restored.migrateLegacyAgentConversation()
        XCTAssertEqual(restored.agentConversations?.first?.replies.first?.answer, "旧回答")
        XCTAssertEqual(restored.replies["daily"]?.count, 1)
        let id = restored.activeAgentConversationID
        restored.migrateLegacyAgentConversation()
        XCTAssertEqual(restored.agentConversations?.count, 1)
        XCTAssertEqual(restored.activeAgentConversationID, id)
    }

    func testSeparateAgentConversationsSurvivePersistence() throws {
        var state = empty()
        let first = AgentConversation(title: "配置", replies: [Reply(question: "问题一", answer: "回答一")])
        let second = AgentConversation(title: "汇率", replies: [Reply(question: "问题二", answer: "回答二")])
        state.agentConversations = [first, second]
        state.activeAgentConversationID = second.id
        let restored = try JSONDecoder().decode(PortfolioState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.agentConversations?.count, 2)
        XCTAssertEqual(restored.activeAgentConversationID, second.id)
        XCTAssertEqual(restored.agentConversations?.first?.replies.first?.question, "问题一")
    }

    func testInitialSnapshotIsNotATodaysBuy() throws {
        var state = empty()
        let date = now.addingTimeInterval(-86_400)
        try PortfolioMath.add(to: &state, instrument: SampleData.instruments[0], account: "  支付宝  ", quantity: 100, cost: 4, date: date, now: now)
        XCTAssertEqual(state.ledger.first?.action, "初始持仓")
        XCTAssertEqual(state.ledger.first?.date, date)
        XCTAssertEqual(state.positions.first?.account, "支付宝")
        XCTAssertEqual(state.positions.first?.quantity, 100)
    }
    func testQuoteRequiredAndUnknownInstrumentRejected() {
        var state = empty()
        let unavailable = Instrument(id: "unknown", name: "未覆盖", category: "基金", currency: "CNY", quote: 0, cnyRate: 1, quoteDate: "", quoteKind: "净值", available: false)
        XCTAssertThrowsError(try PortfolioMath.add(to: &state, instrument: unavailable, account: "账户", quantity: 1, cost: 1, date: now, now: now))
        XCTAssertTrue(state.positions.isEmpty)
    }
    func testInvalidNumbersAndFutureDateLeaveLedgerUnchanged() {
        for number in [Double.nan, .infinity, -1, 0] {
            var state = empty()
            XCTAssertThrowsError(try PortfolioMath.add(to: &state, instrument: SampleData.instruments[0], account: "账户", quantity: number, cost: 4, date: now, now: now))
            XCTAssertTrue(state.ledger.isEmpty)
        }
        var state = empty()
        XCTAssertThrowsError(try PortfolioMath.add(to: &state, instrument: SampleData.instruments[0], account: "账户", quantity: 1, cost: 4, date: now.addingTimeInterval(1), now: now))
    }
    func testDuplicatePositionBlockedButDifferentAccountsAllowed() throws {
        var state = empty()
        let instrument = SampleData.instruments[0]
        try PortfolioMath.add(to: &state, instrument: instrument, account: "A", quantity: 100, cost: 4, date: now, now: now)
        XCTAssertThrowsError(try PortfolioMath.add(to: &state, instrument: instrument, account: "A", quantity: 100, cost: 4, date: now, now: now))
        try PortfolioMath.add(to: &state, instrument: instrument, account: "B", quantity: 100, cost: 4, date: now, now: now)
        XCTAssertEqual(state.positions.count, 2)
    }
    func testWeightedCostPartialSaleAndOversell() throws {
        var state = empty()
        try PortfolioMath.add(to: &state, instrument: SampleData.instruments[0], account: "A", quantity: 100, cost: 4, date: now, now: now)
        let id = state.positions[0].id
        try PortfolioMath.trade(in: &state, positionID: id, buy: true, quantity: 100, price: 6, date: now, now: now)
        XCTAssertEqual(state.positions[0].quantity, 200)
        XCTAssertEqual(state.positions[0].unitCost, 5)
        try PortfolioMath.trade(in: &state, positionID: id, buy: false, quantity: 50, price: 7, date: now, now: now)
        XCTAssertEqual(state.positions[0].quantity, 150)
        XCTAssertEqual(state.positions[0].unitCost, 5)
        XCTAssertThrowsError(try PortfolioMath.trade(in: &state, positionID: id, buy: false, quantity: 151, price: 7, date: now, now: now))
        XCTAssertEqual(state.positions[0].quantity, 150)
        XCTAssertEqual(state.ledger.count, 3)
    }
    func testBackdatedTradeRejectedInsteadOfWrongCostReplay() throws {
        var state = empty()
        try PortfolioMath.add(to: &state, instrument: SampleData.instruments[0], account: "A", quantity: 100, cost: 4, date: now, now: now)
        XCTAssertThrowsError(try PortfolioMath.trade(in: &state, positionID: state.positions[0].id, buy: true, quantity: 1, price: 3, date: now.addingTimeInterval(-1), now: now))
        XCTAssertEqual(state.ledger.count, 1)
    }
    func testRepliesAreUnrestrictedAndPersistent() throws {
        var state = empty()
        for index in 0..<8 { try PortfolioMath.appendReply(to: &state, reportID: "daily", question: "问题\(index)", answer: "成功回答") }
        let restored = try JSONDecoder().decode(PortfolioState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.replies["daily"]?.count, 8)
        XCTAssertNil(restored.replies["weekly"])
    }
    func testEmptyInputOrEmptyAnswerIsIgnored() throws {
        var state = empty()
        try PortfolioMath.appendReply(to: &state, reportID: "daily", question: "  ", answer: "回答")
        try PortfolioMath.appendReply(to: &state, reportID: "daily", question: "问题", answer: "")
        XCTAssertNil(state.replies["daily"])
    }
    func testDiskRoundtripAndCorruptDataNeverSilentlyReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalRepository(url: directory.appendingPathComponent("state.json"))
        XCTAssertNil(try repository.load())
        var state = SampleData.initialState
        state.preferences.hideAmounts = true
        state.reviewedReportIDs.insert("daily")
        try repository.save(state)
        let restored = try XCTUnwrap(repository.load())
        XCTAssertEqual(restored.positions.map(\.id), state.positions.map(\.id))
        XCTAssertTrue(restored.preferences.hideAmounts)
        XCTAssertTrue(restored.reviewedReportIDs.contains("daily"))
        let corrupt = Data("broken JSON".utf8)
        try corrupt.write(to: repository.url)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.url), corrupt)
    }
}
