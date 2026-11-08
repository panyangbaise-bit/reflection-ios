import SwiftUI

enum AppTab: String, CaseIterable {
    case home = "总览", holdings = "持仓", reviews = "复盘", me = "我的"
    var icon: String { switch self { case .home: "rectangle.split.2x2"; case .holdings: "square.3.layers.3d"; case .reviews: "doc.text"; case .me: "person" } }
}
enum Route: Hashable {
    case connection, position(UUID), trade(UUID, Bool), report(String), chat(String), sources(String), news, notifications, history, discipline
}

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = AppTab.home
    @State private var paths: [AppTab: [Route]] = [:]
    @State private var showingAgent = false
    @State private var notifications = NotificationCoordinator.shared
    var body: some View {
        Group {
            if !store.cloud.restorationFinished { ProgressView("正在验证登录状态…") }
            else if !store.cloud.canEnterHome {
                NavigationStack { CloudConnectionView(welcome: true) }
            } else { mainTabs }
        }
        .task { await store.cloud.restore() }
        .task(id: store.cloud.canEnterHome) { await notifications.prepare(cloud: store.cloud) }
        .fullScreenCover(isPresented: $notifications.showOnboarding) { NotificationOnboardingView() }
        .onChange(of: store.cloud.canEnterHome) { _, _ in paths = [:]; tab = .home; showingAgent = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && store.cloud.restorationFinished && store.cloud.enabled && !store.cloud.busy {
                Task { await store.cloud.refresh(); await notifications.prepare(cloud: store.cloud) }
            }
        }
        .alert("云端操作未完成", isPresented: Binding(get: { store.cloud.error != nil && !showingAgent }, set: { if !$0 { store.cloud.error = nil } })) {
            Button("知道了", role: .cancel) { store.cloud.error = nil }
        } message: { Text(store.cloud.error ?? "") }
    }
    private var mainTabs: some View {
        TabView(selection: $tab) {
            ForEach(AppTab.allCases, id: \.self) { item in
                NavigationStack(path: Binding(get: { paths[item] ?? [] }, set: { paths[item] = $0 })) {
                    root(item)
                        .navigationDestination(for: Route.self) { route in destination(route) }
                }
                .tabItem { Label(item.rawValue, systemImage: item.icon) }
                .tag(item)
                .accessibilityIdentifier("tab-\(item)")
            }
        }
        .tint(Palette.chalkBlue)
            .fullScreenCover(isPresented: $showingAgent) {
                Group { if store.cloud.enabled { CloudAskView() } else { AskView() } }.environment(store)
            }
            .onChange(of: store.cloud.user?.id) { _, _ in paths = [:]; tab = .home; showingAgent = false }
            .onChange(of: store.holdingSearchRequest) { _, request in
                guard request != nil else { return }
                paths[.holdings] = []; tab = .holdings
            }
            .onChange(of: store.cloud.enabled) { _, _ in
                paths = [:]; tab = .home
            }
            .alert("未能完成操作", isPresented: Binding(get: { store.error != nil && !showingAgent }, set: { if !$0 { store.error = nil } })) {
                Button("知道了", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
    }
    @ViewBuilder private func root(_ item: AppTab) -> some View {
        Group {
            switch item {
            case .home: if store.cloud.enabled { CloudHomeView() } else { HomeView() }
            case .holdings: if store.cloud.enabled { CloudHoldingsView() } else { HoldingsView() }
            case .reviews: if store.cloud.enabled { CloudReviewsView() } else { ReviewsView() }
            case .me: SettingsView()
            }
        }
        .navigationTitle(item == .me ? "设置" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if item != .me {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("复盘了").font(Palette.wordmark(25)).fixedSize()
                            .accessibilityAddTraits(.isHeader)
                    }.sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("复盘了").font(Palette.wordmark(25)).fixedSize()
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAgent = true } label: {
                        AgentMark(color: .primary).frame(width: 27, height: 27)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Ask Agent，智能助手")
                    .accessibilityIdentifier("askAgent")
                }
            }
        }
    }
    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .connection: CloudConnectionView()
        case .position(let id): PositionView(id: id)
        case .trade(let id, let buy): TradeView(id: id, buy: buy)
        case .report(let id): if let r = store.reports.first(where: { $0.id == id }) { ReportView(report: r) }
        case .chat(let id): if let r = store.reports.first(where: { $0.id == id }) { ReportChatView(report: r) }
        case .sources(let id): if let r = store.reports.first(where: { $0.id == id }) { EvidenceView(report: r) }
        case .news: NewsDetailView()
        case .notifications: NotificationPreferencesView()
        case .history: HistoryView()
        case .discipline: DisciplineView()
        }
    }
}

struct HomeView: View {
    @Environment(AppStore.self) private var store
    private var groups: [(String, Double)] {
        Dictionary(grouping: store.positions, by: { PortfolioMath.instrument($0.instrumentID)?.category ?? "其他" })
            .map { ($0.key, PortfolioMath.marketValue($0.value)) }.sorted { $0.1 > $1.1 }
    }
    var body: some View {
        OverviewBoard { block in
            switch block {
            case .discipline:
                TradingDisciplineCard(rules: store.disciplineRules)
            case .latest:
                OverviewNoticeCard(notice: OverviewNotice.demo(reports: store.reports), demo: true)
            case .holdings:
                VStack(spacing: 14) {
                    OverviewAssetsCard(value: String(store.total), holdingGain: String(store.pnl),
                        yesterdayGain: nil, cumulativeGain: nil, points: store.positions.isEmpty ? [] : OverviewPoint.demo,
                        composition: AssetComposition.grouped(groups), demo: true).frame(height: 250)
                    if store.positions.isEmpty {
                        Button("添加第一笔持仓") { store.holdingSearchRequest = UUID() }.buttonStyle(GlassActionButton())
                    }
                }
            }
        }
    }
}
func gainColor(_ value: Double, redIsGain: Bool) -> Color {
    (value >= 0) == redIsGain ? Palette.red : Palette.green
}
struct AllocationView: View {
    @Environment(AppStore.self) private var store
    private var groups: [(String, Double)] {
        let grouped = Dictionary(grouping: store.positions, by: { PortfolioMath.instrument($0.instrumentID)?.category ?? "其他" })
        return grouped.map { ($0.key, PortfolioMath.marketValue($0.value)) }.sorted { $0.0 < $1.0 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("资产配置").font(.system(size: 19, weight: .bold))
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        Rectangle().fill(Palette.series[index % Palette.series.count]).frame(width: max(0, (geometry.size.width - CGFloat(max(0, groups.count - 1)) * 2) * group.1 / max(store.total, 1)))
                    }
                }
            }.frame(height: 8).accessibilityLabel("组合资产配置")
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                HStack {
                    Rectangle().fill(Palette.series[index % Palette.series.count]).frame(width: 7, height: 7)
                    Text(group.0).font(.system(size: 13)); Spacer()
                    Text((group.1 / max(store.total, 1)).formatted(.percent.precision(.fractionLength(1)))).font(Palette.mono(12))
                }
            }
        }
    }
}
