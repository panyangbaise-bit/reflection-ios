import SwiftUI

struct HoldingsView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var selected: Instrument?
    @FocusState private var searchFocused: Bool
    private var term: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [Instrument] {
        SampleData.instruments.filter { $0.id.localizedCaseInsensitiveContains(term) || $0.name.localizedCaseInsensitiveContains(term) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !term.isEmpty {
                    Text("搜索结果 · 本地示例").font(.caption).foregroundStyle(.secondary)
                    if matches.isEmpty { SearchEmptyState() }
                    ForEach(matches) { item in
                        InstrumentResultRow(name: item.name, symbol: item.id, detail: "\(item.category) · \(item.currency)",
                            held: store.positions.contains { $0.instrumentID == item.id }, available: item.available) { selected = item }
                        Divider()
                    }
                    Text("选择标的后填写持仓数量与成本，保存后加入持仓。").font(.caption).foregroundStyle(.secondary)
                } else if store.positions.isEmpty {
                    ContentUnavailableView("还没有持仓", systemImage: "chart.bar.xaxis", description: Text("在上方搜索股票、ETF 或基金，添加第一笔持仓。"))
                } else {
                    HoldingsTypeSection(type: .core, positions: store.positions.filter { $0.type == .core })
                    HoldingsTypeSection(type: .satellite, positions: store.positions.filter { $0.type == .satellite })
                }
            }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) { InstrumentSearchField(query: $search, focused: $searchFocused) }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $selected) { item in NavigationStack { AddPositionView(item: item) }.environment(store) }
        .onChange(of: store.holdingSearchRequest) { _, request in
            if request != nil { searchFocused = true; store.holdingSearchRequest = nil }
        }
        .onAppear {
            if store.holdingSearchRequest != nil { searchFocused = true; store.holdingSearchRequest = nil }
        }
    }
}

struct InstrumentSearchField: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索名称 / 代码，添加自选", text: $query)
                .focused(focused).textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).accessibilityIdentifier("instrumentSearch")
                .onChange(of: query) { _, value in if value.count > 80 { query = String(value.prefix(80)) } }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("清空搜索").frame(minWidth: 32, minHeight: 40)
            }
        }.padding(.horizontal, 12).frame(minHeight: 48)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line.opacity(0.6)))
            .padding(.horizontal, 16).padding(.vertical, 10).background(.background)
    }
}

struct InstrumentResultRow: View {
    let name: String
    let symbol: String
    let detail: String
    let held: Bool
    let available: Bool
    let add: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(name).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                Text("\(symbol) · \(detail)").font(.caption).foregroundStyle(.secondary)
                if held { Text("已持有").font(.caption).foregroundStyle(Palette.chalkBlue) }
            }
            Spacer(minLength: 6)
            Button(action: add) {
                Label(available ? "自选" : "暂不可添加", systemImage: available ? "plus" : "minus.circle")
                    .font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Palette.chalkBlue.opacity(0.08), in: Capsule())
            }.buttonStyle(.plain).foregroundStyle(Palette.chalkBlue).disabled(!available)
                .accessibilityLabel("\(available ? "添加自选并创建持仓" : "暂不可添加")：\(name)")
        }.padding(.vertical, 5)
    }
}

struct SearchEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("没有找到匹配标的").font(.headline)
            Text("试试完整代码或名称。搜索覆盖范围取决于当前数据源，换用其他关键词后会自动更新。")
                .font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 16)
    }
}

struct PositionTypeSummary: View {
    let type: PositionType
    let positions: [Position]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Rectangle().fill(type == .core ? .primary : Palette.blue).frame(width: 5, height: 5)
                Text(type.title).font(.system(size: 11))
            }
            Text("¥\(amount(PortfolioMath.marketValue(positions)))")
                .font(Palette.mono(14, medium: true)).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(positions.count) 项").font(.system(size: 10)).foregroundStyle(Palette.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .overlay(Rectangle().stroke(Palette.line, lineWidth: 1))
            .accessibilityIdentifier("position-summary-\(type.rawValue)")
    }
}

struct PositionTypePicker: View {
    @Binding var selection: PositionType
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(PositionType.allCases.enumerated()), id: \.element.id) { index, type in
                Button { selection = type } label: {
                    Text(type.title).font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selection == type ? Color(uiColor: .systemBackground) : Color.primary)
                        .background(selection == type ? Color.primary : Color(uiColor: .systemBackground))
                        .overlay(alignment: .trailing) {
                            if index < PositionType.allCases.count - 1 {
                                Rectangle().fill(Color.primary).frame(width: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("positionType-\(type.rawValue)")
                .accessibilityAddTraits(selection == type ? .isSelected : [])
            }
        }
        .overlay(Rectangle().stroke(Color.primary, lineWidth: 1))
        .accessibilityIdentifier("positionTypePicker")
    }
}

struct HoldingsTypeSection: View {
    let type: PositionType
    let positions: [Position]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Rectangle().fill(type == .core ? .primary : Palette.blue).frame(width: 8, height: 8)
                Text(type.title).font(.system(size: 15, weight: .semibold))
                Text("\(positions.count) 项").font(Palette.mono(10)).foregroundStyle(Palette.secondary)
                Spacer()
                Text("¥\(amount(PortfolioMath.marketValue(positions)))").font(Palette.mono(11))
            }.padding(.top, 4)
            if positions.isEmpty {
                Text(type == .core ? "暂无核心仓持仓。" : "暂无卫星仓持仓。")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.vertical, 2)
            } else {
                ForEach(positions) { position in
                    if let instrument = PortfolioMath.instrument(position.instrumentID) {
                        NavigationLink(value: Route.position(position.id)) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(instrument.name).font(.system(size: 16, weight: .semibold))
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 12))
                                }
                                ValueRow(label: instrument.id, value: "¥\(amount(position.quantity * instrument.quote * instrument.cnyRate))")
                                ValueRow(label: "持有数量", value: quantityText(position.quantity))
                            }.padding(.vertical, 6)
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }.accessibilityIdentifier("holdings-\(type.rawValue)")
    }
}

struct AddPositionView: View {
    let item: Instrument
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var cost = ""
    @State private var date = Date()
    @State private var positionType: PositionType = .core
    var body: some View {
        Form {
            Section {
                Text(item.name).font(.headline)
                Text("\(item.id) · \(item.currency)").foregroundStyle(.secondary)
            }
            Section("持仓信息") {
                TextField("持有数量", text: $quantity).keyboardType(.decimalPad)
                TextField("单位成本 · \(item.currency)", text: $cost).keyboardType(.decimalPad)
                Picker("仓位类型", selection: $positionType) { ForEach(PositionType.allCases) { Text($0.title).tag($0) } }
                DatePicker("持仓截至日期", selection: $date, in: ...Date(), displayedComponents: .date)
            }
            Section {
                Button("保存持仓") {
                    if store.add(item, account: "默认持仓", quantity: parseNumber(quantity), cost: parseNumber(cost), date: date, positionType: positionType) { dismiss() }
                }.disabled(quantity.isEmpty || cost.isEmpty).accessibilityIdentifier("savePosition")
            } footer: { Text("记录已有持仓，不会当作今天发生的买入。本地演示数据仅保存在此设备。") }
            if let error = store.error { Section { Text(error).foregroundStyle(.red) } }
        }.navigationTitle("创建持仓").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }
}

func parseNumber(_ text: String) -> Double {
    // Do not silently reinterpret separators or partially parsed input.
    Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .nan
}

struct PositionView: View {
    @Environment(AppStore.self) private var store
    let id: UUID
    var body: some View {
        DetailScreen {
            if let position = store.state.positions.first(where: { $0.id == id }), let instrument = PortfolioMath.instrument(position.instrumentID) {
                PageTitle(title: instrument.name, eyebrow: "\(instrument.id) / \(instrument.category) / \(position.type.title)")
                Panel(heavy: true) {
                    Note(text: "示例\(instrument.quoteKind) · \(instrument.currency)")
                    Text(amount(instrument.quote)).font(Palette.mono(32, medium: true))
                    Note(text: "\(instrument.quoteDate) · 尚未连接实时行情")
                }
                Panel {
                    Text("仓位归类").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    PositionTypePicker(selection: Binding(get: {
                        store.state.positions.first(where: { $0.id == id })?.type ?? .core
                    }, set: { store.setPositionType($0, for: id) }))
                    Note(text: "核心仓：长期持有，重逻辑与配置比例。卫星仓：主题与波段，先定退出条件。")
                }
                Panel {
                    ValueRow(label: "持有数量", value: quantityText(position.quantity))
                    ValueRow(label: "单位成本 · \(instrument.currency)", value: amount(position.unitCost))
                    ValueRow(label: "持仓市值 · CNY", value: "¥\(amount(position.quantity * instrument.quote * instrument.cnyRate))")
                    ValueRow(label: "浮动盈亏 · CNY", value: amount(position.quantity * (instrument.quote - position.unitCost) * instrument.cnyRate))
                }
                HStack(spacing: 12) {
                    NavigationLink("记录买入", value: Route.trade(id, true)).buttonStyle(SquareButton(primary: true))
                    NavigationLink("记录卖出", value: Route.trade(id, false)).buttonStyle(SquareButton()).disabled(position.quantity == 0)
                }
                Note(text: "这里只记录已发生的交易，不向券商下单。MVP 暂不计手续费、分红与现金余额。")
                SettingLink(title: "手动记录历史", route: .history)
            } else { Note(text: "这笔持仓不存在。") }
        }
    }
}

struct TradeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    let buy: Bool
    @State private var quantity = ""
    @State private var price = ""
    @State private var date = Date()
    var body: some View {
        DetailScreen {
            if let position = store.state.positions.first(where: { $0.id == id }), let item = PortfolioMath.instrument(position.instrumentID) {
                PageTitle(title: buy ? "记录买入" : "记录卖出", eyebrow: item.name)
                Note(text: "当前持有 \(quantityText(position.quantity)) 份。记录实际成交，不执行交易。")
                FormField(title: "成交数量", value: $quantity, numeric: true)
                FormField(title: "成交价格 · \(item.currency)", value: $price, numeric: true)
                DatePicker("成交日期", selection: $date, in: ...Date(), displayedComponents: .date)
                Note(text: "本地 MVP 按录入顺序计算成本，暂不支持补录早于最近一笔记录的交易。")
                Button("保存交易记录") {
                    if store.trade(position, buy: buy, quantity: parseNumber(quantity), price: parseNumber(price), date: date) { dismiss() }
                }.buttonStyle(SquareButton(primary: true))
            }
        }
    }
}

struct HistoryView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        DetailScreen {
            PageTitle(title: "手动记录", eyebrow: "LOCAL LEDGER")
            if store.state.ledger.isEmpty { Note(text: "还没有新增记录。添加持仓或记录买卖后会保存在这里。") }
            ForEach(store.state.ledger) { entry in
                Panel {
                    HStack { Text(entry.name).font(.headline); Spacer(); Text(entry.action).font(.system(size: 13)) }
                    ValueRow(label: "数量 / 单价", value: "\(quantityText(entry.quantity)) / \(amount(entry.price))")
                    Note(text: entry.date.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
    }
}
