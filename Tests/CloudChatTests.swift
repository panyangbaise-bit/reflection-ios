import XCTest
@testable import PortfolioCore

@MainActor private final class ChatFixture: CloudChatClient {
    var requiresSignIn = false
    var requests: [(String, String?, [String: Any]?)] = []
    var failSend = false
    func chatRequest<T: Decodable>(_ path: String, method: String, body: [String: Any]?, key: String?) async throws -> T {
        requests.append((path, key, body))
        let json: String
        if path == "conversations" && method == "POST" { json = #"{"id":"c","title":"Question","report_id":null}"# }
        else if method == "POST" {
            if failSend { throw URLError(.timedOut) }
            json = #"{"run_id":"r","conversation_id":"c","status":"queued","remaining_free":2}"#
        }
        else if path.hasPrefix("runs/") { json = #"{"id":"r","status":"succeeded","answer":"AI 生成","charts":[]}"# }
        else if path.hasSuffix("active-run") { json = #"{"run_id":"r","status":"succeeded"}"# }
        else { json = #"{"items":[{"id":"m","role":"assistant","content":"AI 生成","created_at":"now"}],"next_cursor":null}"# }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }
}

@MainActor final class CloudChatTests: XCTestCase {
    func testAmbiguousSendKeepsIntentAndKey() async {
        let fixture = ChatFixture(); fixture.failSend = true
        let model = CloudChatModel()
        let failed = await model.send("原问题", fixture)
        XCTAssertFalse(failed); XCTAssertEqual(model.pendingText, "原问题")
        fixture.failSend = false
        let sent = await model.send("编辑后的不同问题", fixture)
        XCTAssertTrue(sent); XCTAssertNil(model.pendingText)
        let writes = fixture.requests.filter { $0.0.hasSuffix("/messages") }
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0].1, writes[1].1)
        XCTAssertEqual(writes[1].2?["content"] as? String, "原问题")
        XCTAssertEqual(fixture.requests.filter { $0.0 == "conversations" }.count, 1)
    }
    func testReportUsesReportRouteAndLoadsFinalMessage() async {
        let fixture = ChatFixture()
        let model = CloudChatModel(reportId: "report")
        let sent = await model.send("解释报告", fixture)
        XCTAssertTrue(sent)
        XCTAssertEqual(fixture.requests.first?.0, "reports/report/questions")
        await model.poll(fixture)
        XCTAssertNil(model.runId)
        XCTAssertEqual(model.messages.last?.content, "AI 生成")
    }
    func testCannotChangeConversationWithAmbiguousIntent() async {
        let fixture = ChatFixture(); fixture.failSend = true
        let model = CloudChatModel()
        _ = await model.send("尚未确认的发送", fixture)
        await model.select("different", fixture)
        XCTAssertEqual(model.conversationId, "c")
        XCTAssertNotNil(model.error)
    }
    func testEmptyInputNeverCreatesConversation() async {
        let fixture = ChatFixture()
        let sent = await CloudChatModel().send("   ", fixture)
        XCTAssertFalse(sent); XCTAssertTrue(fixture.requests.isEmpty)
    }
}
