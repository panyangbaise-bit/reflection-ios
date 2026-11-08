import SwiftUI

struct LegalDocumentView: View {
    let document: AppLegalDocument
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("复盘了 · 测试版").font(.headline)
                    Text("版本 \(AppAgreements.version) · 可离线阅读")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
            ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                Section(section.title) {
                    Text(section.body).font(.body).lineSpacing(6)
                        .textSelection(.enabled).padding(.vertical, 6)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

struct AgreementCheckbox: View {
    @Binding var accepted: Bool
    @State private var reading: AppLegalDocument?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { accepted.toggle() } label: {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: accepted ? "checkmark.square.fill" : "square")
                        .font(.system(size: 23)).foregroundStyle(accepted ? Palette.chalkBlue : .secondary)
                    Text("我已阅读并同意以下协议").font(.subheadline).foregroundStyle(.primary)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("同意用户协议和隐私政策")
            .accessibilityValue(accepted ? "已勾选" : "未勾选")
            .accessibilityIdentifier("agreementCheckbox")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { documentLinks }
                VStack(alignment: .leading, spacing: 0) { documentLinks }
            }.padding(.leading, 33)
            Text("AI 数据处理将在使用相关功能时另行征求授权。")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
        }
        .sheet(item: $reading) { document in
            NavigationStack {
                LegalDocumentView(document: document)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { reading = nil }
                        }
                    }
            }
        }
    }
    @ViewBuilder private var documentLinks: some View {
        ForEach(AppLegalDocument.allCases) { document in
            Button { reading = document } label: {
                Text("《\(document.title)》").font(.subheadline).frame(minHeight: 44)
            }.buttonStyle(.borderless).foregroundStyle(Palette.chalkBlue)
        }
    }
}
