import Foundation

struct Instrument: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let currency: String
    let quote: Double
    let cnyRate: Double
    let quoteDate: String
    let quoteKind: String
    let available: Bool
}

enum PositionType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case core, satellite
    var id: String { rawValue }
    var title: String {
        switch self {
        case .core: "核心仓"
        case .satellite: "卫星仓"
        }
    }
    var guideline: String {
        switch self {
        case .core: "长期持有，重逻辑与配置比例"
        case .satellite: "主题与波段，先定退出条件"
        }
    }
}

struct Position: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    let instrumentID: String
    var account: String
    var quantity: Double
    var unitCost: Double
    var recordedAt: Date
    // Optional keeps local v1 files without a type readable; unclassified positions are core.
    var positionType: PositionType?
    var type: PositionType { positionType ?? .core }
}

struct LedgerEntry: Codable, Identifiable {
    var id = UUID()
    let positionID: UUID
    let name: String
    let action: String
    let quantity: Double
    let price: Double
    let date: Date
    let recordedAt: Date
}

struct Reply: Codable, Identifiable {
    var id = UUID()
    let question: String
    let answer: String
}

struct AgentConversation: Codable, Identifiable {
    var id = UUID()
    var title: String
    var updatedAt = Date()
    var replies: [Reply] = []
}

struct Report: Identifiable, Hashable {
    enum Kind: String, CaseIterable { case daily = "收盘总结", weekly = "每周复盘" }
    let id: String
    let kind: Kind
    let date: String
    let deliveredAt: Date
    let title: String
    let summary: String
    let gain: Double
    let startValue: Double
    let contributions: [Contribution]
    let evidence: String
    struct Contribution: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let amount: Double
    }
}

struct Preferences: Codable {
    var hideAmounts = false
    var redIsGain = false
    var dailyReminder = true
    var weeklyReminder = true
    var reminderHour = 8
    var reminderMinute = 0
}

struct PortfolioState: Codable {
    var schemaVersion = 1
    var positions: [Position]
    var ledger: [LedgerEntry] = []
    var replies: [String: [Reply]] = [:]
    var reviewedReportIDs: Set<String> = []
    var preferences = Preferences()
    // Optional fields keep the original v1 local files readable.
    var agentConversations: [AgentConversation]?
    var activeAgentConversationID: UUID?
    var tradingDiscipline: String?
    var disciplineUpdatedAt: Date?
    var overviewOrder: [String]?
    var overviewBlocks: [OverviewBlock] { OverviewBlock.normalized(overviewOrder) }

    mutating func migrateLegacyAgentConversation() {
        guard agentConversations == nil, let legacy = replies["ask"], !legacy.isEmpty else { return }
        let conversation = AgentConversation(title: String(legacy[0].question.prefix(28)), replies: legacy)
        agentConversations = [conversation]
        activeAgentConversationID = conversation.id
    }
}

enum LedgerError: LocalizedError {
    case invalidAmount, unavailableQuote, duplicatePosition, missingAccount, excessiveSale, invalidDate, unsupportedVersion
    var errorDescription: String? {
        switch self {
        case .invalidAmount: "数量、成本和成交价格须为有效正数。"
        case .unavailableQuote: "该标的没有可用报价，暂不能新增持仓。"
        case .duplicatePosition: "此账户已持有该标的，请到持仓详情记录买卖。"
        case .missingAccount: "请填写持有账户。"
        case .excessiveSale: "卖出数量不能超过当前持仓。"
        case .invalidDate: "日期不能晚于今天，也不能早于该持仓的最近一笔记录。"
        case .unsupportedVersion: "本地数据版本不受支持，未修改原文件。"
        }
    }
}

// Local MVP only. This catalog is explicitly marked as sample data in every quote UI.
// A production instrument directory must be supplied and validated by the backend.
enum SampleData {
    static let date = ISO8601DateFormatter().date(from: "2026-10-21T08:05:00Z")!
    static let instruments: [Instrument] = [
        .init(id: "510300", name: "沪深300 ETF", category: "A 股", currency: "CNY", quote: 4.2, cnyRate: 1, quoteDate: "10月21日 15:00", quoteKind: "收盘价", available: true),
        .init(id: "005827", name: "易方达蓝筹精选", category: "场外基金", currency: "CNY", quote: 1.5, cnyRate: 1, quoteDate: "10月20日", quoteKind: "官方净值", available: true),
        .init(id: "00700", name: "腾讯控股", category: "港股", currency: "HKD", quote: 400, cnyRate: 0.92, quoteDate: "10月21日 16:00", quoteKind: "收盘价", available: true),
        .init(id: "AAPL", name: "Apple", category: "美股", currency: "USD", quote: 200, cnyRate: 7.2, quoteDate: "10月20日 美东", quoteKind: "收盘价", available: true),
        .init(id: "518880", name: "黄金 ETF", category: "黄金", currency: "CNY", quote: 8, cnyRate: 1, quoteDate: "10月21日 15:00", quoteKind: "收盘价", available: true),
        .init(id: "510500", name: "中证500 ETF", category: "A 股", currency: "CNY", quote: 6.25, cnyRate: 1, quoteDate: "10月21日 15:00", quoteKind: "收盘价", available: true)
    ]
    static var initialState: PortfolioState {
        let quantities: [Double] = [10000, 20000, 100, 30, 1000]
        let costs: [Double] = [4, 1.42, 370, 193.3333333333, 7.48]
        let accounts = ["证券账户", "支付宝", "港股账户", "美股账户", "证券账户"]
        let types: [PositionType] = [.core, .core, .satellite, .core, .satellite]
        var state = PortfolioState(positions: instruments.prefix(5).enumerated().map { i, item in
            Position(instrumentID: item.id, account: accounts[i], quantity: quantities[i], unitCost: costs[i], recordedAt: date, positionType: types[i])
        })
        state.tradingDiscipline = disciplineSample
        state.disciplineUpdatedAt = date
        return state
    }
    static let disciplineSample = """
    核心仓的建仓必须分批、且首笔不超计划仓位的 1/3。
    “长逻辑不破不卖”与“跌破硬线就砍”不能同时成立。若要设硬止损，就应归类为卫星仓并给相应小权重。
    """
    static let reports: [Report] = [
        Report(id: "daily-2026-10-21", kind: .daily, date: "10月21日", deliveredAt: date, title: "收盘之后，\n看清今天的变化。", summary: "A 股与美股对本轮估值变化贡献为正。基金采用最新公布净值。", gain: 620, startValue: 159380,
               contributions: [.init(name: "沪深300 ETF", amount: 260), .init(name: "场外基金", amount: 160), .init(name: "腾讯控股", amount: -120), .init(name: "Apple", amount: 240), .init(name: "黄金 ETF", amount: 80)],
               evidence: "A 股、港股为 10月21日收盘价；美股为 10月20日美东收盘价；场外基金为 10月20日官方净值。汇率为示例固定值。各市场结算时点不同，本轮估值变化不等于同一交易日收益。"),
        Report(id: "weekly-2026-10-18", kind: .weekly, date: "10月12日—18日", deliveredAt: ISO8601DateFormatter().date(from: "2026-10-19T00:00:00Z")!, title: "收益有起伏，\n配置更值得看。", summary: "本周收益主要来自 A 股与基金。港美股合计占比达到 50%。", gain: 1760, startValue: 158240,
               contributions: [.init(name: "沪深300 ETF", amount: 1200), .init(name: "场外基金", amount: 640), .init(name: "腾讯控股", amount: -320), .init(name: "Apple", amount: 160), .init(name: "黄金 ETF", amount: 80)],
               evidence: "本周报告截点为 10月18日，使用此前可用的收盘价和官方净值；示例期间无资金进出。报告保留生成时的快照，后续持仓修改不会重写历史报告。")
    ]
}

enum PortfolioMath {
    static func instrument(_ id: String) -> Instrument? { SampleData.instruments.first { $0.id == id } }
    static func marketValue(_ positions: [Position]) -> Double {
        positions.reduce(0) { total, p in total + p.quantity * (instrument(p.instrumentID)?.quote ?? 0) * (instrument(p.instrumentID)?.cnyRate ?? 0) }
    }
    static func unrealized(_ positions: [Position]) -> Double {
        positions.reduce(0) { total, p in
            guard let i = instrument(p.instrumentID) else { return total }
            return total + p.quantity * (i.quote - p.unitCost) * i.cnyRate
        }
    }
    static func positive(_ value: Double) -> Bool { value.isFinite && value > 0 && value <= 1e12 }
    static func add(to state: inout PortfolioState, instrument: Instrument, account: String, quantity: Double, cost: Double, date: Date, positionType: PositionType = .core, now: Date = Date()) throws {
        guard instrument.available, positive(instrument.quote), positive(instrument.cnyRate), SampleData.instruments.contains(instrument) else { throw LedgerError.unavailableQuote }
        guard positive(quantity), positive(cost), (quantity * cost).isFinite else { throw LedgerError.invalidAmount }
        let account = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, account.count <= 50 else { throw LedgerError.missingAccount }
        guard date <= now else { throw LedgerError.invalidDate }
        guard !state.positions.contains(where: { $0.instrumentID == instrument.id && $0.account == account && $0.quantity > 0 }) else { throw LedgerError.duplicatePosition }
        let position = Position(instrumentID: instrument.id, account: account, quantity: quantity, unitCost: cost, recordedAt: date, positionType: positionType)
        state.positions.append(position)
        state.ledger.insert(LedgerEntry(positionID: position.id, name: instrument.name, action: "初始持仓", quantity: quantity, price: cost, date: date, recordedAt: now), at: 0)
    }
    static func trade(in state: inout PortfolioState, positionID: UUID, buy: Bool, quantity: Double, price: Double, date: Date, now: Date = Date()) throws {
        guard positive(quantity), positive(price), let index = state.positions.firstIndex(where: { $0.id == positionID }) else { throw LedgerError.invalidAmount }
        let p = state.positions[index]
        let lastDate = state.ledger.filter { $0.positionID == positionID }.map(\.date).max() ?? p.recordedAt
        guard date <= now, date >= lastDate else { throw LedgerError.invalidDate }
        guard buy || quantity <= p.quantity else { throw LedgerError.excessiveSale }
        if buy {
            let newQuantity = p.quantity + quantity
            guard positive(newQuantity) else { throw LedgerError.invalidAmount }
            state.positions[index].unitCost = (p.quantity * p.unitCost + quantity * price) / newQuantity
            state.positions[index].quantity = newQuantity
        } else { state.positions[index].quantity = max(0, p.quantity - quantity) }
        state.ledger.insert(LedgerEntry(positionID: positionID, name: instrument(p.instrumentID)?.name ?? p.instrumentID, action: buy ? "买入" : "卖出", quantity: quantity, price: price, date: date, recordedAt: now), at: 0)
    }
    static func appendReply(to state: inout PortfolioState, reportID: String, question: String, answer: String) throws {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !answer.isEmpty else { return }
        state.replies[reportID, default: []].append(Reply(question: question, answer: answer))
    }
}

struct LocalRepository {
    let url: URL
    func load() throws -> PortfolioState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let state = try JSONDecoder().decode(PortfolioState.self, from: Data(contentsOf: url))
        guard state.schemaVersion == 1 else { throw LedgerError.unsupportedVersion }
        return state
    }
    func save(_ state: PortfolioState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}
