import SwiftUI
import Charts
import Observation

struct CloudChatView: View {
    @Environment(AppStore.self) private var store
    @State private var model: CloudChatModel
    @State private var text = ""
    @State private var showHistory = false
    init(reportId: String? = nil) { _model = State(initialValue: CloudChatModel(reportId: reportId)) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if model.reportId == nil {
                    HStack(spacing: 9) {
                        Text("Ask").font(Palette.mono(18))
                        AgentMark(color: .primary).frame(width: 34)
                    }
                } else {
                    Text("报告追问").font(Palette.mono(18))
                }
                Spacer()
                if model.reportId == nil {
                    Button("历史") { showHistory = true; Task { await model.history(store.cloud) } }.disabled(model.busy || model.pendingText != nil)
                    Button("新对话") { text = ""; Task { await model.select(nil, store.cloud) } }.disabled(model.busy || model.pendingText != nil)
                }
            }.padding()
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if model.messagesCursor != nil { Button("加载更早消息") { Task { await model.older(store.cloud) } }.disabled(model.busy) }
                        if model.messages.isEmpty {
                            PageTitle(title: "一起看清你的投资组合")
                            Note(text: model.reportId == nil ? "Ask Ai 需要登录云端账户并授权交互 AI。可以先阅读历史对话。" : "依据这份报告生成时的事实提问。")
                            if model.reportId == nil {
                                Button("检查组合集中度") { text = "请检查当前组合的集中度，并说明数据缺失情况。" }.buttonStyle(SquareButton())
                                Button("查看近期交易") { text = "请回顾近期交易记录，区分初始快照与买卖。" }.buttonStyle(SquareButton())
                            }
                            NavigationLink("查看 AI 授权") { CloudPrivacyView() }
                        }
                        ForEach(model.messages) { message in
                            VStack(alignment: .leading, spacing: 8) {
                                Note(text: message.role == "user" ? "你" : "复盘了 · AI 生成")
                                Text(.init(message.content)).textSelection(.enabled).font(.system(size: 16)).lineSpacing(6)
                                ForEach(Array((message.charts ?? []).enumerated()), id: \.offset) { _, chart in CloudPriceChart(chart: chart) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(message.role == "user" ? Color.gray.opacity(0.12) : Color(uiColor: .systemBackground))
                                .overlay(Rectangle().stroke(Palette.line))
                        }
                        if !model.messages.contains(where: { !($0.charts ?? []).isEmpty }) {
                            ForEach(Array(model.charts.enumerated()), id: \.offset) { _, chart in CloudPriceChart(chart: chart) }
                        }
                        if model.runId != nil { HStack { ProgressView(); Text(model.runStatus == "queued" ? "问题已提交，等待回答…" : "正在分析…") } }
                        if let error = model.error { Note(text: error).foregroundStyle(Palette.red) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(20)
                }.onChange(of: model.messages.last?.id) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            Divider()
            HStack(alignment: .bottom) {
                TextField("输入问题", text: $text, axis: .vertical).lineLimit(1...5).padding(12).overlay(Rectangle().stroke(Palette.line))
                    .disabled(model.pendingText != nil)
                Button(model.pendingText == nil ? "发送" : "重试发送") { Task { if await model.send(text, store.cloud) { text = "" } } }
                    .buttonStyle(SquareButton(primary: true)).frame(width: 88).disabled(model.busy || model.runId != nil || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.pendingText == nil))
            }.padding()
        }.background(Color(uiColor: .systemBackground))
            .task { await model.history(store.cloud) }
            .onChange(of: store.cloud.user?.id) { _, _ in model = CloudChatModel(reportId: model.reportId); text = "" }
            .task(id: model.runId) { await model.poll(store.cloud) }
            .sheet(isPresented: $showHistory) {
                NavigationStack {
                    List {
                        ForEach(model.conversations.filter { $0.reportId == nil }) { conversation in
                            Button(conversation.title) { showHistory = false; Task { await model.select(conversation.id, store.cloud) } }
                        }
                        if model.conversationCursor != nil { Button("加载更多会话") { Task { await model.history(store.cloud, more: true) } } }
                    }.navigationTitle("历史会话").toolbar { Button("完成") { showHistory = false } }
                }
            }
    }
}

struct CloudPriceChart: View {
    let chart: APIChart
    private var yDomain: ClosedRange<Double> {
        let values = chart.points.flatMap { point in [point.low, point.high, point.close] }
            .compactMap { $0.flatMap(Double.init) }.filter { $0.isFinite && $0 > 0 }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let padding = max((high - low) * 0.12, high * 0.01)
        return max(0, low - padding)...(high + padding)
    }
    var body: some View {
        Panel {
            Text(chart.title ?? "历史日线").font(.headline)
            Chart {
                ForEach(Array(chart.points.enumerated()), id: \.offset) { index, point in
                    if let close = Double(point.close), let open = point.open.flatMap(Double.init),
                       let high = point.high.flatMap(Double.init), let low = point.low.flatMap(Double.init) {
                        let color: Color = close >= open ? .red : .green
                        RuleMark(x: .value("交易日", index), yStart: .value("最低", low), yEnd: .value("最高", high))
                            .foregroundStyle(color)
                        BarMark(x: .value("交易日", index), yStart: .value("开盘", open), yEnd: .value("收盘", close), width: .fixed(5))
                            .foregroundStyle(color).accessibilityLabel(point.date).accessibilityValue("开盘 \(point.open ?? "")，收盘 \(point.close)")
                    } else if let close = Double(point.close) {
                        LineMark(x: .value("交易日", index), y: .value("收盘价", close), series: .value("序列", "close")).foregroundStyle(Palette.blue)
                            .accessibilityLabel(point.date).accessibilityValue(point.close)
                    }
                }
                ForEach(Array((chart.trendlines ?? []).enumerated()), id: \.offset) { number, line in
                    ForEach([line.startIndex, line.endIndex], id: \.self) { index in
                        if chart.points.indices.contains(index), let close = Double(chart.points[index].close) {
                            LineMark(x: .value("交易日", index), y: .value("收盘价", close), series: .value("序列", "trend-\(number)"))
                                .foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .accessibilityLabel(line.text)
                        }
                    }
                }
                ForEach(Array((chart.annotations ?? []).enumerated()), id: \.offset) { _, annotation in
                    if chart.points.indices.contains(annotation.index), let close = Double(chart.points[annotation.index].close) {
                        PointMark(x: .value("交易日", annotation.index), y: .value("数值", close))
                            .foregroundStyle(Palette.blue)
                            .annotation(position: .top) { Text(annotation.text).font(.caption2).lineLimit(2) }
                    }
                }
            }.chartYScale(domain: yDomain).frame(height: 180).chartXAxis(.hidden)
            Note(text: "\(chart.ticker ?? "") · \(chart.points.first?.date ?? "") — \(chart.points.last?.date ?? "") · \(chart.kind == "historical_nav" ? "历史单位净值" : "历史收盘价")")
            if let provider = chart.provider {
                let name = provider == "local-fixture" ? "本机合成" : (provider.hasPrefix("akshare:") ? "AKShare" : provider)
                let source = chart.source == "sina" ? " · 新浪财经" : (chart.source == "eastmoney" ? " · 东方财富" : "")
                let adjustment = chart.adjust == "none" ? " · 不复权" : ""
                Note(text: "来源：\(name)\(source)\(adjustment)" + (chart.fetchedAt.map { " · 获取于 \(cloudDateTime($0))" } ?? ""))
            }
            ForEach(Array((chart.annotations ?? []).enumerated()), id: \.offset) { _, annotation in
                if chart.points.indices.contains(annotation.index) { Note(text: chart.points[annotation.index].date + "：" + annotation.text) }
            }
            ForEach(Array((chart.trendlines ?? []).enumerated()), id: \.offset) { _, line in
                if chart.points.indices.contains(line.startIndex), chart.points.indices.contains(line.endIndex) {
                    Note(text: "虚线 \(chart.points[line.startIndex].date) — \(chart.points[line.endIndex].date)：\(line.text)")
                }
            }
        }
    }
}
