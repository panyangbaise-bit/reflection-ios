import Foundation
import Observation

@MainActor @Observable final class AppStore {
    let cloud = CloudStore()
    private(set) var state: PortfolioState
    var error: String?
    var holdingSearchRequest: UUID?
    private(set) var loadFailed = false
    private let repository: LocalRepository
    let reports = SampleData.reports.sorted { $0.deliveredAt > $1.deliveredAt }
    var positions: [Position] { state.positions.filter { $0.quantity > 0 } }
    var total: Double { PortfolioMath.marketValue(positions) }
    var pnl: Double { PortfolioMath.unrealized(positions) }
    var overviewBlocks: [OverviewBlock] { cloud.enabled ? OverviewBlock.normalized(cloud.overviewOrder ?? state.overviewOrder) : state.overviewBlocks }
    var disciplineContent: String {
        cloud.enabled ? cloud.discipline : (state.tradingDiscipline ?? "")
    }
    var disciplineRules: [String] { TradingDisciplineRules.rules(disciplineContent) }
    var disciplineStorageLabel: String { cloud.enabled ? "云端 PostgreSQL" : "本地演示" }
    var disciplineStorageDetail: String {
        cloud.enabled
            ? "保存到你的云端账户；换设备登录后可继续使用。"
            : "当前未登录云端，规则只保存在本机演示数据中。"
    }
    func marketValue(of type: PositionType) -> Double {
        PortfolioMath.marketValue(positions.filter { $0.type == type })
    }

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        repository = LocalRepository(url: directory.appendingPathComponent("PortfolioAgent/portfolio-v1.json"))
        do {
            state = try repository.load() ?? SampleData.initialState
            state.migrateLegacyAgentConversation()
        } catch {
            state = PortfolioState(positions: [])
            loadFailed = true
            self.error = "无法读取本地数据，原文件已保留。请重新启动或检查存储：\(error.localizedDescription)"
        }
    }
    @discardableResult func update(_ mutation: (inout PortfolioState) throws -> Void) -> Bool {
        guard !loadFailed else { error = "本地数据未成功加载，为保护原文件暂不保存。"; return false }
        do {
            var next = state
            try mutation(&next)
            try repository.save(next)
            state = next
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func add(_ instrument: Instrument, account: String, quantity: Double, cost: Double, date: Date, positionType: PositionType = .core) -> Bool {
        update { try PortfolioMath.add(to: &$0, instrument: instrument, account: account, quantity: quantity, cost: cost, date: date, positionType: positionType) }
    }
    func trade(_ position: Position, buy: Bool, quantity: Double, price: Double, date: Date) -> Bool {
        update { try PortfolioMath.trade(in: &$0, positionID: position.id, buy: buy, quantity: quantity, price: price, date: date) }
    }
    func setPositionType(_ type: PositionType, for positionID: UUID) {
        update { state in
            guard let index = state.positions.firstIndex(where: { $0.id == positionID }) else { return }
            state.positions[index].positionType = type
        }
    }
    @discardableResult func setOverviewOrder(_ blocks: [OverviewBlock]) -> Bool {
        let order = OverviewBlock.normalized(blocks.map(\.rawValue)).map(\.rawValue)
        if cloud.enabled { Task { await cloud.saveOrder(order) }; return true }
        guard order != state.overviewOrder else { return true }
        return update { $0.overviewOrder = order }
    }
    @discardableResult func resetOverviewOrder() -> Bool {
        if cloud.enabled { Task { await cloud.saveOrder(OverviewBlock.defaultOrder.map(\.rawValue)) }; return true }
        guard state.overviewOrder != nil else { return true }
        return update { $0.overviewOrder = nil }
    }
    @discardableResult func saveDiscipline(_ text: String, expectedAt: String? = nil) async -> Bool {
        let content = TradingDisciplineRules.normalize(text)
        if cloud.enabled {
            return await cloud.saveDiscipline(content, expectedAt: expectedAt)
        }
        return update { state in
            state.tradingDiscipline = content.isEmpty ? nil : content
            state.disciplineUpdatedAt = content.isEmpty ? nil : Date()
        }
    }
    @discardableResult func ask(_ text: String, conversationID: UUID?) -> UUID? {
        let question = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !question.isEmpty else { return nil }
        let answer: String
        if question.contains("汇率") {
            let foreign = positions.filter { PortfolioMath.instrument($0.instrumentID)?.currency != "CNY" }
            let share = PortfolioMath.marketValue(foreign) / max(total, 1)
            answer = "当前示例报价下，外币资产占组合市值的 \(share.formatted(.percent.precision(.fractionLength(1))))。人民币计价的价值会同时受资产价格和汇率影响。这里使用固定示例汇率，不能代表实时外汇风险。"
        } else if question.contains("配置") || question.contains("集中") || question.contains("持仓") {
            let largest = positions.max { PortfolioMath.marketValue([$0]) < PortfolioMath.marketValue([$1]) }
            if let largest, let item = PortfolioMath.instrument(largest.instrumentID) {
                let share = PortfolioMath.marketValue([largest]) / max(total, 1)
                answer = "当前本地组合有 \(positions.count) 项持仓。按示例报价，\(item.name) 这一笔持仓占比最高，约 \(share.formatted(.percent.precision(.fractionLength(1))))。可以进一步比较不同市场、账户和资产类别的占比。以上是本地数据演示，不是实时分析。"
            } else { answer = "你还没有持仓。先添加一笔持仓，再查看组合配置。" }
        } else {
            answer = "当前本地组合共 \(positions.count) 项持仓，示例报价计算市值 ¥\(amount(total))。这个回答演示围绕组合继续对话的体验；真实行情、新闻检索和 AI 分析尚未接入。"
        }
        var conversations = state.agentConversations ?? []
        let id: UUID
        if let conversationID, let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            id = conversationID
            conversations[index].replies.append(Reply(question: question, answer: answer))
            conversations[index].updatedAt = Date()
        } else {
            var conversation = AgentConversation(title: String(question.prefix(28)))
            conversation.replies.append(Reply(question: question, answer: answer))
            id = conversation.id
            conversations.append(conversation)
        }
        return update({ $0.agentConversations = conversations; $0.activeAgentConversationID = id }) ? id : nil
    }
    func reply(_ question: String, report: Report) -> Bool {
        let question = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !question.isEmpty else { return false }
        let answer: String
        if question.contains("净值") || question.contains("日期") || question.contains("价格") { answer = report.evidence }
        else if question.contains("汇率") || question.contains("配置") { answer = "报告快照中，腾讯占 23%，Apple 占 27%，合计 50%。人民币口径的价值同时受价格和汇率影响；这是一份历史示例，不随你后续编辑持仓而变化。" }
        else { answer = "本报告的示例变化为 ¥\(amount(report.gain))。" + report.contributions.map { "\($0.name) \($0.amount >= 0 ? "+" : "")\(amount($0.amount))" }.joined(separator: "，") + "。收益贡献不代表涨跌原因。" }
        return update { try PortfolioMath.appendReply(to: &$0, reportID: report.id, question: question, answer: answer) }
    }
}

func amount(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }
func quantityText(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...6))) }
