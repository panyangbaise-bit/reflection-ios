import SwiftUI
import Charts

/// Shared trailing slot so the discipline plus, news arrow and holdings eye sit on one axis.
private let overviewTrailingActionWidth: CGFloat = 44

/// The overview is a small, user-orderable board: rules, latest context, then holdings.
/// Long press a block and drag it onto another block to move it; the order is saved locally.
struct OverviewBoard<Content: View>: View {
    @Environment(AppStore.self) private var store
    @ViewBuilder let content: (OverviewBlock) -> Content
    @State private var targeted: OverviewBlock?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.overviewBlocks != OverviewBlock.defaultOrder {
                    HStack {
                        Spacer()
                        Button("恢复默认") {
                            withAnimation(.easeInOut(duration: 0.2)) { _ = store.resetOverviewOrder() }
                        }.font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.blue)
                            .accessibilityIdentifier("resetOverviewOrder")
                    }.padding(.horizontal, 2)
                }

                ForEach(store.overviewBlocks) { block in
                    draggableContent(block)
                        .overlay {
                            if targeted == block {
                                RoundedRectangle(cornerRadius: 26).stroke(Palette.blue, lineWidth: 2).allowsHitTesting(false)
                            }
                        }
                        .accessibilityIdentifier("overview-block-\(block.rawValue)")
                        .accessibilityHint(block == .holdings ? "左右滑动切换内容，长按标题可调整板块顺序" : "长按并拖动，可调整这个板块的顺序")
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first, let source = OverviewBlock(rawValue: raw) else { return false }
                            let current = store.overviewBlocks
                            let next = OverviewBlock.moving(source, onto: block, in: current)
                            guard next != current else { return false }
                            targeted = nil
                            withAnimation(.easeInOut(duration: 0.2)) { _ = store.setOverviewOrder(next) }
                            return true
                        } isTargeted: { isTargeted in
                            if isTargeted { targeted = block }
                            else if targeted == block { targeted = nil }
                        }
                }
            }
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder private func draggableContent(_ block: OverviewBlock) -> some View {
        // Keep the paging area free of the board's long-press drag interaction.
        // The asset card can still be reordered by dragging its title.
        if block == .holdings {
            content(block)
        } else {
            content(block).draggable(block.rawValue) { OverviewDragPreview(block: block) }
        }
    }
}

private struct OverviewDragPreview: View {
    let block: OverviewBlock
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
            Text(block.title).font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .foregroundStyle(.primary).background(Color(uiColor: .systemBackground))
        .overlay(Rectangle().stroke(Color.primary, lineWidth: 1.5))
    }
}

struct TradingDisciplineCard: View {
    let rules: [String]
    var body: some View {
        Group {
            if rules.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("还没有交易纪律。").font(.system(size: 16, weight: .semibold))
                        Text("先写下不想在盘中忘掉的规则，比如核心仓的建仓节奏。")
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4)
                    }.padding(.vertical, 2)
                }.padding(16)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    TradingDisciplineRulesWindow(rules: rules)
                        .padding(.top, 16)
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassCard())
        .accessibilityIdentifier("tradingDiscipline")
    }
    private var header: some View {
        HStack {
            Label("交易纪律", systemImage: "checklist").font(.system(size: 12))
            Spacer()
            NavigationLink(value: Route.discipline) {
                Image(systemName: "plus").font(.system(size: 17, weight: .medium))
                    .frame(width: overviewTrailingActionWidth, height: 32)
            }.buttonStyle(.plain).foregroundStyle(Palette.blue)
                .accessibilityLabel(rules.isEmpty ? "添加交易纪律" : "编辑交易纪律")
                .accessibilityIdentifier("editDiscipline")
        }
    }
}

struct TradingDisciplineRulesWindow: View {
    let rules: [String]
    private let windowHeight: CGFloat = 64
    @State private var index = 0
    private var safeIndex: Int { rules.isEmpty ? 0 : min(max(index, 0), rules.count - 1) }
    var body: some View {
        ZStack {
            if !rules.isEmpty {
                rulePage(rules[safeIndex])
                    .id(safeIndex)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: windowHeight)
        .clipped()
        .onChange(of: rules) { _, _ in index = 0 }
        .task(id: rules) {
            guard rules.count > 1 else { return }
            await autoAdvance()
        }
        .accessibilityIdentifier("disciplineRulesWindow")
    }
    private func rulePage(_ rule: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(rule).font(.system(size: 14)).lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: windowHeight, alignment: .center)
        }
    }
    private func autoAdvance() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                index = (index + 1) % rules.count
            }
        }
    }
}

struct OverviewNoticeCard: View {
    let notice: OverviewNotice?
    var demo = false
    var compact = false
    var body: some View {
        Group {
            if let notice {
                switch notice.destination {
                case .localReport(let id): NavigationLink(value: Route.report(id)) { content(notice) }
                case .localNews: NavigationLink(value: Route.news) { content(notice) }
                case .report(let report): NavigationLink { CloudReportView(report: report) } label: { content(notice) }
                case .article(let url): Link(destination: url) { content(notice) }
                case .none: content(notice)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("最新动态", systemImage: "sparkles").font(.system(size: 12))
                    Text("新的回顾，会在这里与你见面。").font(.system(size: 18, weight: .semibold))
                    Text("收盘总结、周复盘与持仓新闻，按时间送达。")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(2)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(16)
            }
        }.buttonStyle(.plain).foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
            .modifier(GlassCard())
            .accessibilityIdentifier("overview-latest")
    }
    private func content(_ item: OverviewNotice) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            HStack {
                Label(item.kind, systemImage: item.icon).font(.system(size: 12))
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.system(size: 13)).foregroundStyle(Palette.blue)
                    .frame(width: overviewTrailingActionWidth, height: 20, alignment: .center)
            }
            Text(item.title.replacingOccurrences(of: "\n", with: ""))
                .font(.system(size: compact ? 17 : 20, weight: .bold)).lineLimit(2).minimumScaleFactor(0.85)
            Text(item.summary).font(.system(size: compact ? 12 : 13)).lineSpacing(3)
                .lineLimit(compact ? 1 : 2).foregroundStyle(Palette.secondary)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let date = item.date {
                    Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits)).font(Palette.mono(10))
                        .foregroundStyle(Palette.secondary)
                    Text("·").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Text(demo ? "本地演示 · \(item.action)" : item.action).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 0)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(compact ? 12 : 16)
            .contentShape(Rectangle())
    }
}

struct OverviewAssetsCard: View {
    @Environment(AppStore.self) private var store
    @State private var page = 0
    @State private var swipeStartPage: Int?
    let value: String?
    let holdingGain: String?
    let yesterdayGain: String?
    let cumulativeGain: String?
    let points: [OverviewPoint]
    var composition: [AssetSlice] = []
    var demo = false
    var compact = false
    var incomplete = false
    private var hidden: Bool { store.state.preferences.hideAmounts }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(["持仓总市值 · CNY", "资产变化 · CNY", "资产构成"][page])
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .contentShape(Rectangle())
                    .draggable(OverviewBlock.holdings.rawValue) { OverviewDragPreview(block: .holdings) }
                Button { store.update { $0.preferences.hideAmounts.toggle() } } label: {
                    Image(systemName: hidden ? "eye.slash" : "eye").font(.system(size: 18)).frame(width: overviewTrailingActionWidth, height: 36)
                }.accessibilityLabel(hidden ? "显示金额" : "隐藏金额")
            }.padding(.horizontal, 16).padding(.top, 6)
            TabView(selection: $page) {
                summary.tag(0)
                trend.tag(1)
                allocation.tag(2)
            }.tabViewStyle(.page(indexDisplayMode: .never)).contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 20)
                    .onChanged { _ in if swipeStartPage == nil { swipeStartPage = page } }
                    .onEnded { gesture in
                        defer { swipeStartPage = nil }
                        let dx = gesture.translation.width, dy = gesture.translation.height
                        guard abs(dx) > 44, abs(dx) > abs(dy) * 1.5 else { return }
                        let destination = min(2, max(0, (swipeStartPage ?? page) + (dx < 0 ? 1 : -1)))
                        withAnimation(.easeInOut(duration: 0.2)) { page = destination }
                    })
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Button { withAnimation(.easeInOut(duration: 0.2)) { page = index } } label: {
                        Capsule().fill(page == index ? Palette.blue : Color.secondary.opacity(0.25)).frame(width: page == index ? 22 : 10, height: 3).padding(.vertical, 10)
                    }.accessibilityLabel(["市值与收益", "资产变化图表", "资产构成饼图"][index])
                        .accessibilityAddTraits(page == index ? .isSelected : [])
                        .accessibilityIdentifier("overview-assets-page-\(index)")
                }
            }.frame(height: 25)
        }.foregroundStyle(.primary).modifier(GlassCard())
    }
    private var summary: some View {
        VStack(spacing: compact ? 8 : 14) {
            Text(hidden ? "••••••" : value.map { "¥\(cloudAmount($0))" } ?? "—")
                .font(Palette.mono(compact ? 27 : 34, medium: true)).minimumScaleFactor(0.55).lineLimit(1)
                .frame(maxWidth: .infinity).padding(.top, compact ? 0 : 5)
            Spacer(minLength: 0).frame(maxHeight: 20)
            HStack(spacing: 4) {
                metric("昨日收益", yesterdayGain)
                metric("持有收益", holdingGain)
                metric("累计收益", cumulativeGain)
            }
            Text(incomplete ? "行情或汇率不完整" : demo ? "本地演示 · 历史收益待补全" : "缺少完整收益记录的项目显示 —")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }.padding(.horizontal, 14).padding(.vertical, compact ? 4 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func metric(_ label: String, _ amount: String?) -> some View {
        let number = amount.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        let positive = (number ?? 0) >= 0
        let color = number == nil ? Palette.secondary : (positive == store.state.preferences.redIsGain ? Palette.red : Palette.green)
        return VStack(spacing: compact ? 5 : 9) {
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            Text(hidden ? "••••" : number.map { ($0 > 0 ? "+" : "") + cloudAmount(amount) } ?? "—")
                .font(Palette.mono(compact ? 12 : 14, medium: true)).foregroundStyle(hidden ? Palette.secondary : color)
                .lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity)
    }
    private var trend: some View {
        VStack(spacing: 6) {
            if hidden {
                Spacer(minLength: 0)
                Label("金额已隐藏", systemImage: "eye.slash").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
            } else if points.isEmpty {
                Spacer(minLength: 0)
                Image(systemName: "chart.xyaxis.line").font(.system(size: 25)).foregroundStyle(Palette.blue)
                Text("等待资产快照").font(.system(size: 14, weight: .medium))
                Text("生成复盘后，逐步形成资产变化曲线。")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
            } else {
                Chart(points) { point in
                    LineMark(x: .value("日期", point.date), y: .value("市值", point.value)).foregroundStyle(Palette.blue).lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("日期", point.date), y: .value("市值", point.value)).foregroundStyle(Palette.blue).symbolSize(10)
                }.chartXAxis(.hidden).chartYScale(domain: chartDomain)
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { mark in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(Color(white: 0.85))
                            AxisValueLabel {
                                if let value = mark.as(Double.self) {
                                    Text(value >= 10000 ? "\((value / 10000).formatted(.number.precision(.fractionLength(1))))万" : value.formatted(.number.precision(.fractionLength(0))))
                                        .font(Palette.mono(9)).foregroundStyle(Palette.secondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 6).accessibilityLabel(demo ? "示例资产变化曲线" : "历史复盘资产快照")
                HStack {
                    if let first = points.first { Text(first.date, format: .dateTime.month(.twoDigits).day(.twoDigits)) }
                    Spacer()
                    if let last = points.last { Text(last.date, format: .dateTime.month(.twoDigits).day(.twoDigits)) }
                }.font(Palette.mono(10)).foregroundStyle(Palette.secondary)
                Text(demo ? "示例走势 · 非当前持仓历史" : "复盘快照 · 市值变化不等于收益")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(1)
            }
        }.padding(.horizontal, 18).padding(.bottom, 4)
    }
    private var allocation: some View {
        Group {
            if hidden {
                Label("金额与占比已隐藏", systemImage: "eye.slash")
                    .font(.subheadline).foregroundStyle(Palette.secondary)
            } else if incomplete || composition.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.pie").font(.system(size: 28)).foregroundStyle(Palette.blue)
                    Text(incomplete ? "补齐行情后显示资产构成" : "添加持仓后查看资产构成").font(.subheadline)
                    Text("按持仓市值计算各类资产占比").font(.caption).foregroundStyle(Palette.secondary)
                }
            } else {
                HStack(spacing: 16) {
                    Chart(Array(composition.enumerated()), id: \.element.id) { index, slice in
                        SectorMark(angle: .value("市值", slice.value), angularInset: 1.5)
                            .foregroundStyle(Palette.series[index % Palette.series.count])
                            .accessibilityLabel(slice.title)
                            .accessibilityValue((slice.value / totalComposition).formatted(.percent.precision(.fractionLength(1))))
                    }.chartLegend(.hidden).frame(width: compact ? 110 : 130, height: compact ? 110 : 130)
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(Array(composition.enumerated()), id: \.element.id) { index, slice in
                                HStack(spacing: 6) {
                                    Circle().fill(Palette.series[index % Palette.series.count]).frame(width: 6, height: 6)
                                    Text(slice.title).font(.system(size: 12))
                                    Spacer(minLength: 4)
                                    Text((slice.value / totalComposition).formatted(.percent.precision(.fractionLength(1))))
                                        .font(Palette.mono(11)).lineLimit(1).minimumScaleFactor(0.8)
                                }
                            }
                        }.padding(.vertical, 5)
                    }.frame(maxHeight: 140)
                }.padding(.horizontal, 16)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var totalComposition: Double { composition.reduce(0) { $0 + $1.value } }
    private var chartDomain: ClosedRange<Double> {
        let low = points.map(\.value).min() ?? 0, high = points.map(\.value).max() ?? 1
        let padding = max((high - low) * 0.15, max(high * 0.01, 1))
        return max(0, low - padding)...(high + padding)
    }
}

struct OverviewAllocation: View {
    let groups: [(String, Double)]
    var body: some View {
        let total = groups.reduce(0) { $0 + $1.1 }
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("资产分布").font(.system(size: 13, weight: .semibold)); Spacer(); Text("按市值").font(.system(size: 10)).foregroundStyle(Palette.secondary) }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, item in
                        Rectangle().fill(Palette.series[index % Palette.series.count]).frame(width: max(0, (geometry.size.width - CGFloat(max(groups.count - 1, 0) * 2)) * item.1 / max(total, 1)))
                    }
                }
            }.frame(height: 6)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 7) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 4) {
                        Rectangle().fill(Palette.series[index % Palette.series.count]).frame(width: 5, height: 5)
                        Text("\(item.0) \(Int((item.1 / max(total, 1) * 100).rounded()))%").font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
        }.padding(.top, 2)
    }
}

struct OverviewPositionMix: View {
    let core: Double
    let satellite: Double
    var body: some View {
        let total = core + satellite
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("仓位结构").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("核心仓 / 卫星仓").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            GeometryReader { geometry in
                let available = max(0, geometry.size.width - (core > 0 && satellite > 0 ? 2 : 0))
                HStack(spacing: 2) {
                    if core > 0 { Rectangle().fill(Color.primary).frame(width: available * core / max(total, 1)) }
                    if satellite > 0 { Rectangle().fill(Palette.blue).frame(width: available * satellite / max(total, 1)) }
                }
            }.frame(height: 6)
            HStack(spacing: 16) {
                legend(color: .primary, title: "核心仓", value: core, total: total)
                legend(color: Palette.blue, title: "卫星仓", value: satellite, total: total)
                Spacer()
            }
        }.padding(.top, 2).accessibilityIdentifier("overviewPositionMix")
    }
    private func legend(color: Color, title: String, value: Double, total: Double) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 5, height: 5)
            Text("\(title) \(Int((value / max(total, 1) * 100).rounded()))%").font(.system(size: 10))
        }
    }
}
