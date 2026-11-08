import SwiftUI

/// A dedicated conversation surface: no portfolio header or tab bar.
struct AskView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var conversationID: UUID?
    @State private var suggestionSet = 0
    @State private var showingHistory = false
    @State private var restoredConversation = false
    @FocusState private var inputFocused: Bool

    private var messages: [Reply] {
        (store.state.agentConversations ?? []).first { $0.id == conversationID }?.replies ?? []
    }
    private var suggestions: [String] {
        let name = store.positions.first.flatMap { PortfolioMath.instrument($0.instrumentID)?.name } ?? "当前组合"
        let sets = [
            ["帮我分析一下当前的持仓配置", "\(name)在组合中占比多少？", "汇率变化会怎样影响我的组合？"],
            ["我的组合是否过于集中？", "帮我回顾最近的投资变化", "这份组合还需要关注哪些信息？"],
            ["不同市场的持仓如何分布？", "怎么看基金净值与股票收盘价？", "我应该怎样记录持有理由？"]
        ]
        return sets[suggestionSet % sets.count]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.line).frame(height: 1)
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if messages.isEmpty {
                                welcome.frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 40), alignment: .bottom)
                            } else {
                                ForEach(messages) { reply in
                                    conversationPair(reply)
                                }
                            }
                            Color.clear.frame(height: 1).id("conversation-end")
                        }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("conversation-end", anchor: .bottom) }
                    }
                    .onChange(of: inputFocused) { _, focused in
                        if focused && !messages.isEmpty { withAnimation { proxy.scrollTo("conversation-end", anchor: .bottom) } }
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground)).foregroundStyle(.primary)
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .onAppear {
            guard !restoredConversation else { return }
            conversationID = store.state.activeAgentConversationID
            restoredConversation = true
        }
        .sheet(isPresented: $showingHistory) { history }
        .alert("未能保存对话", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { inputFocused = false; dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 20)).frame(width: 44, height: 44)
            }.accessibilityLabel("返回投资页面").accessibilityIdentifier("agent-close")
            HStack(spacing: 10) {
                Text("Ask").font(Palette.mono(20, medium: true))
                AgentMark(color: .primary).frame(width: 38)
            }
            Spacer(minLength: 0)
            Menu {
                Button("新对话", systemImage: "square.and.pencil", action: newConversation)
                Button("历史会话", systemImage: "clock") { inputFocused = false; showingHistory = true }
            } label: {
                Image(systemName: "line.3.horizontal").font(.system(size: 20)).frame(width: 44, height: 44)
            }.accessibilityLabel("会话菜单").accessibilityIdentifier("agent-menu")
        }.foregroundStyle(.primary).padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 12) {
                BrandMark().frame(width: 28, height: 28).padding(.top, 4)
                Text("今天想聊聊\n哪一笔投资？")
                    .font(.system(size: 29, weight: .bold)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { send(suggestion) } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Text(suggestion).font(.system(size: 15, weight: .medium)).lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.left").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        }.padding(16).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                            .background(Color(white: 0.98)).overlay(Rectangle().stroke(Palette.line))
                    }.buttonStyle(.plain)
                }
                Button { suggestionSet += 1 } label: {
                    Label("换一换", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary).frame(minHeight: 44)
                }.accessibilityIdentifier("agent-refresh-suggestions")
            }
        }
    }

    private func conversationPair(_ reply: Reply) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer(minLength: 36)
                Text(reply.question).font(.system(size: 16)).lineSpacing(5).textSelection(.enabled)
                    .padding(16).background(Color(white: 0.96)).overlay(Rectangle().stroke(Palette.line))
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    BrandMark().frame(width: 15, height: 15)
                    Text("复盘了").font(.system(size: 12, weight: .semibold))
                }
                Text(reply.answer).font(.system(size: 16)).lineSpacing(7).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.bottom, 8)
    }

    private var composer: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    shortcut("持仓分析", icon: "chart.pie", draft: "帮我分析一下当前的持仓配置")
                    shortcut("收益复盘", icon: "chart.xyaxis.line", draft: "帮我回顾最近的投资变化")
                    shortcut("汇率影响", icon: "arrow.left.arrow.right", draft: "汇率变化会怎样影响我的组合？")
                }.padding(.horizontal, 20)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("聊聊你的投资…", text: $question, axis: .vertical)
                    .font(.system(size: 16)).lineLimit(1...5).focused($inputFocused)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.vertical, 12).accessibilityIdentifier("agent-input")
                    .onChange(of: question) { _, newValue in
                        if newValue.count > 500 { question = String(newValue.prefix(500)) }
                    }
                Button { send(question) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44).foregroundStyle(.white)
                        .background(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : .black)
                }.disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("发送提问").accessibilityIdentifier("agent-send")
            }.padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground)).overlay(Rectangle().stroke(Color.primary, lineWidth: 1))
                .padding(.horizontal, 20)
            Text("本地演示 · 未连接 AI")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }.padding(.top, 12).padding(.bottom, 8).background(Color(uiColor: .systemBackground))
    }

    private func shortcut(_ title: String, icon: String, draft: String) -> some View {
        Button { question = draft; inputFocused = true } label: {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Color(uiColor: .systemBackground)).overlay(Rectangle().stroke(Palette.line))
        }.buttonStyle(.plain)
    }

    private var history: some View {
        NavigationStack {
            List {
                if (store.state.agentConversations ?? []).isEmpty {
                    Text("还没有历史会话").foregroundStyle(Palette.secondary)
                }
                ForEach((store.state.agentConversations ?? []).sorted { $0.updatedAt > $1.updatedAt }) { conversation in
                    Button {
                        if store.update({ $0.activeAgentConversationID = conversation.id }) {
                            conversationID = conversation.id
                            question = ""
                            showingHistory = false
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(conversation.title).font(.system(size: 16)).foregroundStyle(.primary)
                            Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        }.padding(.vertical, 6)
                    }
                }
            }.listStyle(.plain).navigationTitle("历史会话").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showingHistory = false } } }
        }.tint(Palette.blue)
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let id = store.ask(trimmed, conversationID: conversationID) {
            conversationID = id
            question = ""
            inputFocused = false
        }
    }
    private func newConversation() {
        if store.update({ $0.activeAgentConversationID = nil }) {
            conversationID = nil
            question = ""
            inputFocused = false
        }
    }
}
