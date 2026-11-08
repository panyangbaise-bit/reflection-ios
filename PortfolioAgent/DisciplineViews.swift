import SwiftUI

struct DisciplineView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var draft = ""
    @State private var expectedAt: String?
    @State private var loaded = false
    @State private var saving = false
    @State private var saveFailed = false
    private var lineCount: Int { TradingDisciplineRules.rules(draft).count }
    private var cloud: Bool { store.cloud.enabled }
    var body: some View {
        DetailScreen {
            PageTitle(title: "交易纪律", eyebrow: cloud ? "DISCIPLINE / 云端" : "DISCIPLINE / 本地演示")
            Note(text: "每行一条规则。总览卡片一次显示一条，约每 5 秒自动切换。")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("存储位置").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    Text(store.disciplineStorageLabel).font(.system(size: 11, weight: .semibold))
                    Spacer()
                }
                Note(text: store.disciplineStorageDetail)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .font(.system(size: 16)).lineSpacing(7)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(uiColor: .systemBackground))
                    .overlay(Rectangle().stroke(Color.primary, lineWidth: 1))
                    .frame(minHeight: 280)
                    .focused($focused)
                    .accessibilityIdentifier("disciplinePageEditor")
                if draft.isEmpty {
                    Text("每行一条规则，例如：\n核心仓分批建仓，首笔不超过计划仓位的 1/3。\n卫星仓先定退出条件，跌破硬线就减仓。")
                        .font(.system(size: 15)).foregroundStyle(Palette.secondary).lineSpacing(7)
                        .padding(.horizontal, 16).padding(.vertical, 15)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Text("每行一条 · \(lineCount) 条")
                Spacer()
                Text("\(draft.count)/\(TradingDisciplineRules.maxLength)")
            }.font(Palette.mono(10)).foregroundStyle(Palette.secondary)
            Button {
                Task {
                    saving = true
                    if await store.saveDiscipline(draft, expectedAt: expectedAt) { dismiss() } else { saveFailed = true }
                    saving = false
                }
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(.white) }
                    Text(saving ? "正在保存" : "保存交易纪律")
                }
            }.buttonStyle(SquareButton(primary: true))
                .disabled(saving || store.cloud.busy)
                .accessibilityIdentifier("saveDiscipline")
        }
        .onChange(of: draft) { _, value in
            if value.count > TradingDisciplineRules.maxLength {
                draft = String(value.prefix(TradingDisciplineRules.maxLength))
            }
        }
        .task {
            if cloud {
                if store.cloud.home == nil { await store.cloud.refresh() }
                var attempts = 0
                while store.cloud.busy && attempts < 30 {
                    try? await Task.sleep(for: .milliseconds(100))
                    attempts += 1
                }
            }
            if !loaded {
                draft = store.disciplineContent
                expectedAt = store.cloud.disciplineUpdatedAt
                loaded = true
            }
            try? await Task.sleep(for: .milliseconds(400))
            focused = true
        }
        .alert("未能保存交易纪律", isPresented: $saveFailed) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(store.cloud.enabled ? (store.cloud.error ?? "请稍后重试。") : (store.error ?? "草稿仍在，请稍后重试。"))
        }
    }
}
