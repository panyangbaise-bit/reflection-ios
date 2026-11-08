import SwiftUI

struct CloudConnectionView: View {
    @Environment(AppStore.self) private var store
    var welcome = false
    @State private var confirmingLogout = false
    private var cloud: CloudStore { store.cloud }
    private var signedIn: Bool { cloud.enabled && !cloud.requiresSignIn }
    var body: some View {
        Group {
            if !signedIn { LoginWelcomeView() }
            else if cloud.user?.passwordSetupRequired == true { PasswordSetupView() }
            else {
                List {
                    Section {
                        Label(cloud.user == nil ? "需要验证登录状态" : "已登录", systemImage: "person.crop.circle")
                        if let phone = cloud.user?.phoneMasked { Text("+86 " + phone).foregroundStyle(.secondary) }
                        Button("刷新账户") { Task { await cloud.refresh() } }
                    }
                    if cloud.busy { ProgressView("正在验证…") }
                    Section { Button("退出登录", role: .destructive) { confirmingLogout = true } }
                }
                .listStyle(.insetGrouped).navigationTitle("账户")
                .navigationBarTitleDisplayMode(.inline).disabled(cloud.busy)
            }
        }
        .confirmationDialog("退出当前账户？", isPresented: $confirmingLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await cloud.logout() } }
        } message: { Text("云端数据会保留，可随时重新登录。") }
    }
}

struct CloudHomeView: View {
    @Environment(AppStore.self) private var store
    private var cloud: CloudStore { store.cloud }
    var body: some View {
        OverviewBoard { block in
            switch block {
            case .discipline:
                TradingDisciplineCard(rules: store.disciplineRules)
            case .latest:
                OverviewNoticeCard(notice: OverviewNotice.cloud(cloud.home))
            case .holdings:
                VStack(spacing: 14) {
                    OverviewAssetsCard(value: cloud.home?.snapshot.marketValueCny,
                        holdingGain: cloud.home?.snapshot.unrealizedPnlCny,
                        yesterdayGain: cloud.home?.snapshot.yesterdayPnlCny,
                        cumulativeGain: cloud.home?.snapshot.cumulativePnlCny,
                        points: OverviewPoint.from(cloud.home?.assetHistory ?? []),
                        composition: AssetComposition.cloud(cloud.positions, complete: cloud.home?.snapshot.complete == true),
                        incomplete: cloud.home?.snapshot.complete == false).frame(height: 250)
                    if cloud.requiresSignIn {
                        NavigationLink("重新登录", value: Route.connection).buttonStyle(SquareButton(primary: true))
                    } else if cloud.home == nil {
                        Button("重新加载") { Task { await cloud.refresh() } }.buttonStyle(SquareButton())
                    } else if cloud.positions.isEmpty {
                        Button("添加第一笔持仓") { store.holdingSearchRequest = UUID() }.buttonStyle(GlassActionButton())
                    }
                }
            }
        }.task { await cloud.refresh(); await cloud.initializeLayout(store.state.overviewOrder) }
            .refreshable { await cloud.refresh() }
    }
}

struct CloudHoldingsView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var search = InstrumentSearch()
    @State private var selected: APICatalogItem?
    @State private var retry = 0
    @FocusState private var searchFocused: Bool
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !term.isEmpty {
                    HStack {
                        Text("搜索结果").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if search.loading { ProgressView().controlSize(.small) }
                    }
                    if let error = search.error {
                        Text("搜索暂时不可用").font(.headline)
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        Button("重试") { retry += 1 }
                    } else if !search.loading && search.items.isEmpty { SearchEmptyState() }
                    ForEach(search.items) { item in
                        InstrumentResultRow(name: item.name, symbol: item.symbol, detail: item.searchDetail,
                            held: store.cloud.positions.contains { $0.instrumentId == item.id }, available: item.canAdd) {
                                searchFocused = false; selected = item
                            }
                        Divider()
                    }
                    Text("选择标的后填写持仓数量与成本，保存后加入持仓。").font(.caption).foregroundStyle(.secondary)
                } else if store.cloud.requiresSignIn {
                    NavigationLink("登录后搜索并添加持仓", value: Route.connection)
                } else if store.cloud.home == nil {
                    ContentUnavailableView("暂未取得持仓", systemImage: "arrow.clockwise", description: Text("请刷新后重试。"))
                    Button("刷新持仓") { Task { await store.cloud.refresh() } }
                } else if store.cloud.positions.isEmpty {
                    ContentUnavailableView("还没有持仓", systemImage: "chart.bar.xaxis", description: Text("在上方搜索股票、ETF 或基金，添加第一笔持仓。"))
                } else {
                    ForEach(["core", "satellite"], id: \.self) { type in
                        let positions = store.cloud.positions.filter { ($0.positionType ?? "core") == type }
                        if !positions.isEmpty {
                            Text(type == "core" ? "核心仓" : "卫星仓").font(.headline)
                            ForEach(positions) { position in
                                NavigationLink { CloudPositionView(id: position.id) } label: {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack { Text(position.name).font(.headline); Spacer(); Image(systemName: "chevron.right") }
                                        ValueRow(label: position.symbol, value: cloudAmount(position.marketValueCny))
                                        ValueRow(label: "持有数量", value: position.quantity)
                                        if let change = position.navChangePct { ValueRow(label: "净值较上期", value: cloudAmount(change) + "%") }
                                        if position.quoteKind == "nav" {
                                            Note(text: sourceTimeText(position.asOf, kind: "nav").map { "基金净值 · \($0)" } ?? "基金净值 · 数据日期不可用")
                                        } else if position.quoteStatus == "close_mark" {
                                            Note(text: sourceTimeText(position.asOf, kind: position.quoteKind).map { "收盘价 · \($0)" } ?? "收盘价 · 数据时间不可用")
                                        } else if position.quoteStatus != "current" {
                                            Note(text: sourceTimeText(position.asOf, kind: position.quoteKind).map { "行情不可用 · \($0)" } ?? "行情不可用 · 无数据时间")
                                        }
                                    }.padding(.vertical, 6)
                                }.buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                }
            }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) { InstrumentSearchField(query: $query, focused: $searchFocused) }
        .scrollDismissesKeyboard(.interactively)
        .task(id: "\(term)|\(retry)") { await search.search(term, using: store.cloud) }
        .refreshable { await store.cloud.refresh() }
        .sheet(item: $selected) { item in NavigationStack { CloudAddPositionView(item: item) }.environment(store) }
        .onChange(of: store.holdingSearchRequest) { _, request in
            if request != nil { searchFocused = true; store.holdingSearchRequest = nil }
        }
        .onAppear {
            if store.holdingSearchRequest != nil { searchFocused = true; store.holdingSearchRequest = nil }
        }
    }
}

struct CloudAddPositionView: View {
    let item: APICatalogItem
    @State private var positionType = "core"
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var cost = ""
    @State private var date = Date()
    @State private var key = UUID().uuidString
    var body: some View {
        Form {
            Section {
                Text(item.name).font(.headline)
                Text("\(item.symbol) · \(item.market) · \(item.currency)").foregroundStyle(.secondary)
            }
            Section("持仓信息") {
                TextField("持有数量", text: $quantity).keyboardType(.decimalPad)
                TextField("单位成本 · \(item.currency)（可留空）", text: $cost).keyboardType(.decimalPad)
                Picker("仓位类型", selection: $positionType) { Text("核心仓").tag("core"); Text("卫星仓").tag("satellite") }
                DatePicker("持仓截至日期", selection: $date, in: ...Date(), displayedComponents: .date)
            }
            Section {
                Button(store.cloud.busy ? "正在保存…" : "保存持仓") {
                    Task { if await store.cloud.opening(item: item, quantity: quantity, price: cost, date: date, key: key, positionType: positionType) { dismiss() } }
                }.disabled(quantity.isEmpty || store.cloud.busy).accessibilityIdentifier("savePosition")
            } footer: {
                Text("记录已有持仓，不会当作今天发生的买入。成本留空时尝试使用最新报价或净值估算；报价不一定实时，无法取得时需手动填写。")
            }
            if let error = store.cloud.error { Section { Text(error).font(.subheadline).foregroundStyle(.red) } }
        }.navigationTitle("创建持仓").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.cloud.busy) } }
            .interactiveDismissDisabled(store.cloud.busy)
    }
}

struct CloudPositionView: View {
    @Environment(AppStore.self) private var store
    let id: String
    var body: some View {
        DetailScreen {
            if let p = store.cloud.positions.first(where: { $0.id == id }) {
                PageTitle(title: p.name, eyebrow: p.symbol)
                Panel(heavy: true) { Note(text: p.quoteKind == "nav" ? "单位净值 · \(p.currency)" : "价格 · \(p.currency)"); Text(cloudAmount(p.price)).font(Palette.mono(32)); Note(text: p.quoteKind == "nav" ? (sourceTimeText(p.asOf, kind: "nav").map { "基金净值 · \($0)" } ?? "基金净值") : (sourceTimeText(p.asOf, kind: p.quoteKind).map { "\(p.quoteStatusLabel) · \($0)" } ?? p.quoteStatusLabel)); if let change = p.navChangePct { ValueRow(label: "较上一净值涨跌", value: cloudAmount(change) + "%"); if let previous = p.navPreviousAsOf { Note(text: "上一净值日期：\(cloudDateTime(previous))") } } }
                Panel { ValueRow(label: "持有数量", value: p.quantity); ValueRow(label: "平均成本 · \(p.currency)", value: cloudAmount(p.averageCost)); ValueRow(label: "持仓市值 · CNY", value: cloudAmount(p.marketValueCny)); ValueRow(label: "浮动盈亏 · \(p.currency)", value: cloudAmount(p.unrealizedPnl)) }
                Picker("仓位类型", selection: Binding(get: { p.positionType ?? "core" }, set: { type in Task { await store.cloud.classify(p, type: type) } })) {
                    Text("核心仓").tag("core"); Text("卫星仓").tag("satellite")
                }.pickerStyle(.segmented).disabled(store.cloud.busy)
                HStack { NavigationLink("记录买入") { CloudTradeView(position: p, buy: true) }.buttonStyle(SquareButton(primary: true)); NavigationLink("记录卖出") { CloudTradeView(position: p, buy: false) }.buttonStyle(SquareButton()) }
                NavigationLink("查看交易记录") { CloudLedgerView(positionId: p.id) }.buttonStyle(SquareButton())
                NavigationLink("查看历史日线") { CloudInstrumentChartView(instrumentId: p.instrumentId) }.buttonStyle(SquareButton())
                if let source = p.openingCostSource, let at = p.openingQuoteAsOf { Note(text: "初始成本按添加时报价估算：\(source)，报价时间 \(cloudDateTime(at))。") }
                Note(text: "只记录已发生的交易，不向券商下单。费用计入成本与实现收益。")
            } else { Note(text: "这笔持仓已清仓，或需要刷新组合。") }
        }
    }
}
struct CloudTradeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let position: APIPosition
    let buy: Bool
    @State private var quantity = ""
    @State private var price = ""
    @State private var fee = "0"
    @State private var date = Date()
    @State private var key = UUID().uuidString
    var body: some View {
        DetailScreen {
            PageTitle(title: buy ? "记录买入" : "记录卖出", eyebrow: position.name)
            FormField(title: "成交数量", value: $quantity, numeric: true)
            FormField(title: "成交价格 · \(position.currency)", value: $price, numeric: true)
            FormField(title: "交易费用 · \(position.currency)", value: $fee, numeric: true)
            DatePicker("成交时间", selection: $date, in: ...Date())
            Note(text: "不能早于最近一笔记录。若其他设备已修改持仓，请刷新后重新打开此页面。")
            Button("保存交易记录") { Task { if await store.cloud.trade(position: position, buy: buy, quantity: quantity, price: price, fee: fee, date: date, key: key) { dismiss() } } }.buttonStyle(SquareButton(primary: true)).disabled(store.cloud.busy)
        }
    }
}

struct CloudReviewsView: View {
    @Environment(AppStore.self) private var store
    @State private var kind = "all"
    var body: some View {
        Screen {
            Picker("报告类型", selection: $kind) { Text("全部").tag("all"); Text("日报").tag("daily"); Text("周报").tag("weekly") }.pickerStyle(.segmented)
            if store.cloud.reports.isEmpty { Note(text: "暂时没有复盘。服务端生成后会显示在这里。") }
            ForEach(store.cloud.reports.filter { kind == "all" || $0.kind == kind || (kind == "daily" && $0.kind.hasPrefix("daily")) }) { report in NavigationLink { CloudReportView(report: report) } label: { Panel { Text(report.title).font(.headline); Note(text: report.period); Text(report.summary).lineLimit(3).font(.system(size: 14)) } }.buttonStyle(.plain) }
            if store.cloud.reportsCursor != nil { Button("加载更多报告") { Task { await store.cloud.moreReports() } }.buttonStyle(SquareButton()).disabled(store.cloud.busy) }
        }.refreshable { await store.cloud.refresh() }
    }
}
struct CloudAskView: View {
    var body: some View {
        NavigationStack {
            CloudChatView().toolbar { ToolbarItem(placement: .topBarLeading) { BackButton() } }
        }
    }
}

struct CloudNewsSummary: View {
    let items: [APINews]
    var body: some View {
        ForEach(items.prefix(2)) { item in
            Divider()
            Note(text: "持仓动态 · \(item.source)\(item.usageScope == "development" ? " · 开发预览" : "")")
            Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(3)
            if !item.summary.isEmpty { Note(text: item.summary) }
            if let url = URL(string: item.url), ["https", "http"].contains(url.scheme ?? "") {
                Link("查看原文 ↗", destination: url).font(.system(size: 13)).foregroundStyle(Palette.blue)
            }
        }
    }
}
