import SwiftUI

struct CloudReportView: View {
    @Environment(AppStore.self) private var store
    let report: APIReport
    @State private var detail: APIReportDetail?
    @State private var error: String?
    var body: some View {
        DetailScreen {
            PageTitle(title: report.title, eyebrow: report.period)
            Text(.init(detail?.summary ?? report.summary)).font(.system(size: 16)).lineSpacing(9).textSelection(.enabled)
            Note(text: report.analysisKind == "ai" ? "摘要由 AI 生成；下面为生成时的事实快照。" : "事实报告；快照不会随之后的交易改变。")
            if let detail {
                Panel {
                    ValueRow(label: "快照时间", value: cloudDateTime(detail.snapshot.asOf))
                    ValueRow(label: "行情覆盖", value: "\(detail.snapshot.coverage.priced) / \(detail.snapshot.coverage.total)")
                    ValueRow(label: "持仓市值 · CNY", value: cloudAmount(detail.snapshot.marketValueCny))
                    ValueRow(label: "浮动盈亏 · CNY", value: cloudAmount(detail.snapshot.unrealizedPnlCny))
                    if !detail.snapshot.complete { Note(text: "行情或汇率缺失，估值不完整；缺失数据未按 0 计算。") }
                    Note(text: "已回顾")
                }
                Text("数据依据").font(.headline)
                ForEach(Array((detail.snapshot.analysis?.charts ?? []).enumerated()), id: \.offset) { _, chart in CloudPriceChart(chart: chart) }
                ForEach(detail.snapshot.positions) { p in
                    Panel {
                        Text(p.name).font(.headline)
                        ValueRow(label: "数量", value: p.quantity)
                        ValueRow(label: "成本 · \(p.currency)", value: cloudAmount(p.averageCost))
                        ValueRow(label: "报价 · \(p.currency)", value: cloudAmount(p.price))
                        Note(text: "\(p.symbol) · " + (sourceTimeText(p.asOf, kind: p.quoteKind).map { "\(p.quoteStatusLabel) · \($0)" } ?? p.quoteStatusLabel))
                    }
                }
                NavigationLink("围绕这份报告提问") { CloudChatView(reportId: report.id) }.buttonStyle(SquareButton(primary: true))
            } else if error == nil { ProgressView() }
            if let error { Note(text: error).foregroundStyle(Palette.red); Button("重试") { Task { await load() } } }
        }.task { await load() }
    }
    private func load() async {
        do {
            let value: APIReportDetail = try await store.cloud.request("reports/\(report.id)")
            let _: APIAck = try await store.cloud.request("reports/\(report.id)/read", method: "POST")
            detail = value; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct CloudLedgerView: View {
    @Environment(AppStore.self) private var store
    var positionId: String? = nil
    var accountId: String? = nil
    @State private var items: [APILedgerEvent] = []
    @State private var cursor: String?
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        DetailScreen {
            PageTitle(title: "交易记录", eyebrow: "LEDGER / 账本")
            Note(text: "按实际发生时间从近到远排列。初始持仓快照不计作买入。")
            ForEach(items) { item in
                Panel {
                    Text(item.kindLabel).font(.headline)
                    if let p = store.cloud.home?.snapshot.positions.first(where: { $0.id == item.positionId }) { Note(text: "\(p.name) · \(p.currency)") }
                    ValueRow(label: "数量", value: item.quantity)
                    ValueRow(label: "单价 · 原币", value: cloudAmount(item.price))
                    ValueRow(label: "费用 · 原币", value: cloudAmount(item.fee))
                    Note(text: cloudDateTime(item.occurredAt))
                }
            }
            if loaded && items.isEmpty { Note(text: "暂无交易记录。") }
            if let error { Note(text: error).foregroundStyle(Palette.red); Button("重试") { Task { await load(more: loaded) } } }
            if cursor != nil { Button("加载更多记录") { Task { await load(more: true) } }.buttonStyle(SquareButton()).disabled(busy) }
            if busy { ProgressView() }
        }.task { await load() }.refreshable { await load() }
    }
    private func load(more: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let page: APIPage<APILedgerEvent> = try await store.cloud.request(apiPath("ledger-events", ["cursor": more ? cursor : nil, "position_id": positionId, "account_id": accountId]))
            if more { let ids = Set(items.map(\.id)); items += page.items.filter { !ids.contains($0.id) } }
            else { items = page.items }
            cursor = page.nextCursor; loaded = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct CloudPrivacyView: View {
    @Environment(AppStore.self) private var store
    @State private var privacy: APIPrivacy?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Text("你决定哪些数据可以交给 AI")
                    .font(.headline)
                Text("交互问答与定时报告分别授权。同意用户协议不会自动开启以下权限。")
                    .font(.subheadline).foregroundStyle(.secondary)
                NavigationLink("阅读隐私政策") { LegalDocumentView(document: .privacy) }
            }
            if let privacy {
                Section("数据处理说明") {
                    LabeledContent("处理方", value: privacy.aiProvider ?? "尚未配置")
                    LabeledContent("披露版本", value: privacy.disclosureVersion)
                    Text("授权后，服务端会将相关持仓、成本、交易、问题和对话，以及获准处理的数据发送给上述 AI 服务，用于生成回答。联网搜索时，模型生成的搜索词也会发送给 DeepSeek 搜索服务；请勿在问题中提供不希望外发的个人信息。工具可读取你的报告、纪律和记忆证据；只有明确要求时才修改监察表，不会下单。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if privacy.traceCaptureContent == true {
                        Text("当前测试环境会保存 AI 输入、输出和工具结果供授权管理员排查，可能包含你的持仓和对话；默认保留 30 天，并随账户删除清除。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section {
                    consentRow("交互 AI 问答", purpose: "interactive_ai", privacy: privacy)
                    consentRow("定时报告 AI 摘要", purpose: "scheduled_ai", privacy: privacy)
                } header: { Text("授权管理") } footer: {
                    Text("撤回后尚未发送的请求停止外发，已发出的请求不能追回。撤回不会删除账本或已有报告。")
                }
            }
            if busy { Section { ProgressView("正在更新授权…") } }
            if error != nil {
                Section {
                    Label("暂时无法同步授权状态", systemImage: "wifi.exclamationmark")
                    Text("请检查网络后重试。隐私政策仍可阅读，当前授权状态以同步结果为准。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("重新加载") { Task { await load() } }.disabled(busy)
                }
            }
        }
        .navigationTitle("AI 授权与隐私").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar).tint(Palette.chalkBlue)
        .task { await load() }
    }
    private func consentRow(_ title: String, purpose: String, privacy: APIPrivacy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                Text(privacy.granted(purpose) ? "已授权" : "未授权")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button(privacy.granted(purpose) ? "撤回授权" : "同意上述说明并授权") {
                Task { await change(purpose, !privacy.granted(purpose)) }
            }.disabled(busy || privacy.aiProvider == nil)
        }.padding(.vertical, 5)
    }
    private func load() async {
        busy = true; defer { busy = false }
        do { privacy = try await store.cloud.request("me/privacy"); error = nil } catch { self.error = error.localizedDescription }
    }
    private func change(_ purpose: String, _ granted: Bool) async {
        guard let privacy, let provider = privacy.aiProvider else { return }
        busy = true; defer { busy = false }
        do {
            let _: APIAck = try await store.cloud.request("me/consents/\(purpose)", method: "PUT", body: ["granted": granted, "provider": provider, "disclosure_version": privacy.disclosureVersion])
            self.privacy = try await store.cloud.request("me/privacy"); error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct CloudPreferencesView: View {
    @Environment(AppStore.self) private var store
    @State private var daily = false
    @State private var weekly = false
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var saved = false
    var body: some View {
        Form {
            Section {
                Toggle("生成每日复盘", isOn: $daily)
                Toggle("生成每周复盘", isOn: $weekly)
            } header: { Text("报告生成") } footer: {
                Text("偏好保存在云端。报告在应用内阅读，目前未启用系统推送；AI 摘要须另行授权。")
            }.disabled(!loaded || busy)
            Section {
                Button("保存偏好") { Task { await save() } }.disabled(!loaded || busy)
                if saved { Label("已保存到云端", systemImage: "checkmark.circle").foregroundStyle(.green) }
            }
            if let error {
                Section {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    if !loaded { Button("重新加载") { Task { await load() } }.disabled(busy) }
                }
            }
            if busy { Section { ProgressView("正在同步…") } }
        }.navigationTitle("报告偏好").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).tint(Palette.chalkBlue)
            .onChange(of: daily) { _, _ in saved = false }
            .onChange(of: weekly) { _, _ in saved = false }
            .task { await load() }
    }
    private func load() async {
        busy = true; defer { busy = false }
        do { let p: APIPreferences = try await store.cloud.request("me/preferences"); daily = p.dailyReport; weekly = p.weeklyReport; loaded = true; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do { let _: APIAck = try await store.cloud.request("me/preferences", method: "PATCH", body: ["daily_report": daily, "weekly_report": weekly]); saved = true; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct CloudDeletionView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmation = ""
    @State private var receipt: String?
    @State private var status: String?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Text("删除会立即撤销登录，并清除本版本数据库中的持仓、交易、对话、纪律、记忆和工具轨迹。")
                Text("Apple 授权及备份的跨系统删除尚待接入。")
                    .foregroundStyle(.secondary)
            } header: { Text("删除范围") }
            if receipt == nil {
                Section {
                    NavigationLink("重新登录以验证身份") { CloudConnectionView() }
                    TextField("输入 DELETE 确认", text: $confirmation)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("永久删除云端账户", role: .destructive) { Task { await remove() } }
                        .disabled(confirmation != "DELETE" || busy)
                } footer: { Text("需要最近 5 分钟内重新登录。此操作无法撤销。") }
            } else {
                Section {
                    Label(status == "completed" ? "数据库私有数据已清除" : "删除请求已提交", systemImage: "checkmark.circle")
                    Text("本机登录凭据已清除。删除进度凭据仅安全保存在本机。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("刷新删除进度") { Task { await check() } }.disabled(busy)
                }
            }
            if let error { Section { Text(error).font(.subheadline).foregroundStyle(.red) } }
            if busy { Section { ProgressView("正在处理…") } }
        }.navigationTitle("删除云端账户").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            if store.cloud.user == nil, let saved = try? DeletionReceiptVault.load() { receipt = saved.receipt; await check() }
        }
    }
    private func remove() async {
        busy = true; defer { busy = false }
        do { let result = try await store.cloud.deleteAccount(); receipt = result.receipt; status = result.status; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func check() async {
        guard let receipt else { return }; busy = true; defer { busy = false }
        do { status = try await store.cloud.deletionStatus(receipt).status; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct CloudExportView: View {
    @State private var exportTask: Task<Void, Never>?
    @Environment(AppStore.self) private var store
    @State private var file: URL?
    @State private var busy = false
    @State private var progress = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Label("你的数据，由你保管", systemImage: "square.and.arrow.up")
                    .font(.headline)
                Text("导出账户、账本、报告、对话、纪律、偏好、监察表、记忆及工具轨迹为 JSON 文件，不包含登录凭据。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                Button(busy ? "正在导出…" : "准备数据文件") { exportTask = Task { await export() } }.disabled(busy)
                if busy { ProgressView(); Text(progress).font(.subheadline).foregroundStyle(.secondary) }
                if let file { ShareLink("保存或分享 JSON", item: file) }
            } footer: { Text("逐页读取期间请避免编辑数据。文件包含个人财务信息，请选择可信的保存位置。") }
            if let error { Section { Text(error).font(.subheadline).foregroundStyle(.red) } }
        }.navigationTitle("导出我的数据").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .onDisappear { exportTask?.cancel(); if let file { try? FileManager.default.removeItem(at: file) }; file = nil }
            .onChange(of: store.cloud.user?.id) { _, _ in exportTask?.cancel(); if let file { try? FileManager.default.removeItem(at: file) }; file = nil }
    }
    private func export() async {
        busy = true; error = nil; defer { busy = false }
        if let file { try? FileManager.default.removeItem(at: file) }; file = nil
        let user = store.cloud.user?.id
        let sections = ["portfolios", "accounts", "positions", "ledger_events", "reports", "conversations", "messages", "consents", "preferences", "trading_discipline", "watchlist_items", "memory_evidence", "ai_runs", "agent_tool_calls"]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("复盘了数据-\(UUID().uuidString).json")
        do {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete])
            let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
            try handle.write(contentsOf: Data("{\"schema_version\":1,\"consistency\":\"per_page\",\"pages\":[".utf8))
            let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
            var first = true
            for (index, section) in sections.enumerated() {
                progress = "正在整理数据（\(index + 1) / \(sections.count)）"
                var cursor: String? = nil
                var seen = Set<String>()
                repeat {
                    try Task.checkCancellation()
                    guard user == store.cloud.user?.id else { throw CancellationError() }
                    let page: APIExportPage = try await store.cloud.request(apiPath("me/export", ["section": section, "cursor": cursor]))
                    if !first { try handle.write(contentsOf: Data(",".utf8)) }; first = false
                    try handle.write(contentsOf: encoder.encode(page))
                    cursor = page.nextCursor
                    if let cursor, !seen.insert(cursor).inserted { throw URLError(.cannotParseResponse) }
                } while cursor != nil
            }
            try handle.write(contentsOf: Data("]}".utf8))
            try handle.synchronize()
            try Task.checkCancellation()
            guard user == store.cloud.user?.id else { throw CancellationError() }
            file = url
        } catch { try? FileManager.default.removeItem(at: url); self.error = error.localizedDescription }
    }
}

struct CloudInstrumentChartView: View {
    @Environment(AppStore.self) private var store
    let instrumentId: String
    @State private var chart: APIChart?
    @State private var error: String?
    var body: some View {
        DetailScreen {
            PageTitle(title: "历史日线")
            Note(text: "显示已取得的历史收盘价或基金净值；图表不构成投资建议。")
            if let chart { CloudPriceChart(chart: chart) }
            else if let error { Note(text: error).foregroundStyle(Palette.red); Button("重试") { Task { await load() } } }
            else { ProgressView() }
        }.task { await load() }
    }
    private func load() async {
        do { chart = try await store.cloud.request("instruments/\(instrumentId)/kline"); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct CloudWatchlistView: View {
    @Environment(AppStore.self) private var store
    @State private var items: [APIWatchlistItem] = []
    @State private var nextOffset: Int?
    @State private var error: String?
    @State private var loaded = false
    @State private var editing: APIWatchlistItem?
    @State private var showAdd = false
    var body: some View {
        DetailScreen {
            PageTitle(title: "监察表", eyebrow: "WATCHLIST / 观察记录")
            Note(text: "记录你关注的标的及观察备注；目标价仅供个人记录，不代表交易建议。")
            Button("添加标的") { showAdd = true }.buttonStyle(SquareButton(primary: true))
            ForEach(items) { item in
                Panel {
                    Text(item.name).font(.headline)
                    Note(text: "\(item.ticker) · \(item.market) · 优先级 \(item.priority)")
                    if let target = item.targetPrice { ValueRow(label: "记录的目标价", value: cloudAmount(target)) }
                    if !item.note.isEmpty { Note(text: item.note) }
                    HStack {
                        Button("编辑") { editing = item }.buttonStyle(SquareButton())
                        Button("移除") { Task { await remove(item) } }.buttonStyle(SquareButton())
                    }
                    NavigationLink("查看历史日线") { CloudInstrumentChartView(instrumentId: item.instrumentId) }
                }
            }
            if loaded && items.isEmpty { Note(text: "监察表还是空的。") }
            if let nextOffset { Button("加载更多") { Task { await load(offset: nextOffset) } }.buttonStyle(SquareButton()) }
            if let error { Note(text: error).foregroundStyle(Palette.red); Button("重试") { Task { await load() } } }
        }.task { await load() }
            .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) { NavigationStack { CloudWatchlistEditor(existing: nil) } }
            .sheet(item: $editing, onDismiss: { Task { await load() } }) { item in NavigationStack { CloudWatchlistEditor(existing: item) } }
    }
    private func load(offset: Int = 0) async {
        do {
            let page: APIOffsetPage<APIWatchlistItem> = try await store.cloud.request(apiPath("watchlist", ["offset": String(offset)]))
            if offset == 0 { items = page.items }
            else { let ids = Set(items.map(\.id)); items += page.items.filter { !ids.contains($0.id) } }
            nextOffset = page.nextOffset; loaded = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func remove(_ item: APIWatchlistItem) async {
        do { let _: APIAck = try await store.cloud.request("watchlist/\(item.instrumentId)", method: "DELETE"); await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct CloudWatchlistEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let existing: APIWatchlistItem?
    @State private var query = ""
    @State private var selected: APICatalogItem?
    @State private var priority = 3
    @State private var target = ""
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        DetailScreen {
            PageTitle(title: existing == nil ? "添加关注标的" : "编辑观察记录")
            if let existing { Text("\(existing.name) · \(existing.ticker)").font(.headline) }
            else if let selected { Text("\(selected.name) · \(selected.symbol)").font(.headline); Button("重新选择") { self.selected = nil } }
            else {
                FormField(title: "代码或名称", value: $query)
                ForEach(store.cloud.catalog) { item in
                    Button("\(item.name) · \(item.symbol)") { selected = item }.disabled(!item.canAdd)
                }
                if store.cloud.catalogCursor != nil { Button("加载更多") { Task { await store.cloud.moreCatalog() } } }
            }
            if existing != nil || selected != nil {
                Stepper("优先级：\(priority)", value: $priority, in: 1...5)
                FormField(title: "目标价（可选）", value: $target, numeric: true)
                FormField(title: "观察备注（可选）", value: $note)
                Button("保存") { Task { await save() } }.buttonStyle(SquareButton(primary: true)).disabled(busy)
            }
            if let error { Note(text: error).foregroundStyle(Palette.red) }
        }.toolbar { Button("关闭") { dismiss() } }
            .task { if let existing { priority = existing.priority; target = existing.targetPrice ?? ""; note = existing.note } }
            .task(id: query) {
                guard existing == nil, selected == nil, !query.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(250)); guard !Task.isCancelled else { return }
                await store.cloud.search(query)
            }
    }
    private func save() async {
        guard let id = existing?.instrumentId ?? selected?.id else { return }
        busy = true; defer { busy = false }
        do {
            var body: [String: Any] = ["instrument_id": id, "priority": priority, "note": note]
            if !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["target_price"] = try wireDecimal(target) }
            let _: APIAck = try await store.cloud.request("watchlist", method: "PUT", body: body)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
