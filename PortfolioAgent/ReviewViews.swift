import SwiftUI

struct ReportSummary: View {
    let report: Report
    var body: some View {
        NavigationLink(value: Route.report(report.id)) {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Label("AI \(report.kind.rawValue)", systemImage: report.kind == .daily ? "sunset" : "doc.text").font(.system(size: 12)); Spacer(); Text(report.date).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
                Text(report.title).font(.system(size: 22, weight: .bold)).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
                Text(report.summary).font(.system(size: 14)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                HStack { Note(text: "查看复盘"); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 13)) }
            }.padding(18).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
    }
}
struct NewsSummary: View {
    var body: some View {
        NavigationLink(value: Route.news) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Note(text: "持仓动态 · 示例推送"); Spacer(); Note(text: "16:06") }
                Text("持仓公司的财报已更新，关注经营变化与原有投资判断。").font(.system(size: 14)).lineSpacing(5)
                HStack { Note(text: "公司公告 · 关联持仓"); Spacer(); Image(systemName: "arrow.up.right") }
            }.foregroundStyle(.primary)
        }.buttonStyle(.plain)
    }
}
struct ReviewsView: View {
    @Environment(AppStore.self) private var store
    @State private var filter = "全部"
    var body: some View {
        Screen {
            Picker("报告类型", selection: $filter) {
                ForEach(["全部"] + Report.Kind.allCases.map(\.rawValue), id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            if filter == "全部" { Panel { NewsSummary() } }
            ForEach(store.reports.filter { filter == "全部" || $0.kind.rawValue == filter }) { report in
                ReportSummary(report: report).overlay(Rectangle().stroke(Color.primary))
            }
            Note(text: "日报、周报到时进入同一复盘窗口，历史内容在这里查看。当前为固定示例，尚未接入服务端自动生成。")
        }
    }
}
struct ReportView: View {
    @Environment(AppStore.self) private var store
    let report: Report
    var body: some View {
        DetailScreen {
            PageTitle(title: report.title, eyebrow: "AI \(report.kind.rawValue) / \(report.date)")
            Note(text: "示例报告 · 固定组合快照，非当前持仓的实时分析")
            Panel(heavy: true) {
                Note(text: report.kind == .daily ? "本轮估值变化" : "本周组合收益")
                Text("+¥\(amount(report.gain))").font(Palette.mono(28)).foregroundStyle(gainColor(report.gain, redIsGain: store.state.preferences.redIsGain))
                Note(text: "示例期间无资金进出 · 覆盖 5 项持仓")
            }
            Text("变化来自哪里").font(.title3.bold())
            ForEach(report.contributions) { contribution in
                VStack(spacing: 8) {
                    HStack { Text(contribution.name).font(.system(size: 14)); Spacer(); Text("\(contribution.amount >= 0 ? "+" : "")\(amount(contribution.amount))").font(Palette.mono(14)).foregroundStyle(gainColor(contribution.amount, redIsGain: store.state.preferences.redIsGain)) }
                    GeometryReader { g in
                        Rectangle().fill(contribution.amount >= 0 ? Palette.blue : Palette.red)
                            .frame(width: g.size.width * abs(contribution.amount) / (report.contributions.map { abs($0.amount) }.max() ?? 1))
                    }.frame(height: 4)
                }
            }
            Text(report.evidence).font(.system(size: 15)).lineSpacing(6)
            SettingLink(title: "查看计算依据与数据范围", route: .sources(report.id))
            HStack(spacing: 12) {
                Button(store.state.reviewedReportIDs.contains(report.id) ? "已回顾" : "标记已回顾") {
                    store.update { if $0.reviewedReportIDs.contains(report.id) { $0.reviewedReportIDs.remove(report.id) } else { $0.reviewedReportIDs.insert(report.id) } }
                }.buttonStyle(SquareButton())
                NavigationLink("追问这份报告", value: Route.chat(report.id)).buttonStyle(SquareButton(primary: true))
            }
        }
    }
}
struct EvidenceView: View {
    let report: Report
    var body: some View {
        DetailScreen {
            PageTitle(title: "复盘依据", eyebrow: "\(report.kind.rawValue) / \(report.date)")
            Panel {
                ValueRow(label: "期初市值", value: "¥\(amount(report.startValue))")
                ValueRow(label: "期末市值", value: "¥160,000.00")
                ValueRow(label: "期间净流入", value: "¥0.00")
                ValueRow(label: "变化", value: "¥\(amount(report.gain))")
            }
            Text(report.evidence).font(.system(size: 15)).lineSpacing(6)
            Note(text: "这些数值来自已确认 UI 的虚构样例，并非真实行情。正式报告必须附带服务端生成的持仓快照、报价来源及时间戳。")
        }
    }
}
struct ReportChatView: View {
    @Environment(AppStore.self) private var store
    let report: Report
    @State private var question = ""
    var body: some View {
        DetailScreen {
            PageTitle(title: "追问报告", eyebrow: "\(report.kind.rawValue) / \(report.date)")
            Note(text: "本地演示 · 回答为预置内容，未调用 AI")
            ForEach(store.state.replies[report.id] ?? []) { reply in
                VStack(alignment: .leading, spacing: 14) {
                    Text(reply.question).font(.system(size: 15, weight: .medium)).padding(14).frame(maxWidth: .infinity, alignment: .trailing).background(Color(white: 0.96))
                    Panel {
                        HStack(spacing: 6) {
                            BrandMark().frame(width: 14, height: 14)
                            Text("复盘了").font(.headline)
                        }
                        Text(reply.answer).font(.system(size: 15)).lineSpacing(6); NavigationLink("查看报告依据", value: Route.sources(report.id)).font(.system(size: 13))
                    }
                }
            }
            if (store.state.replies[report.id] ?? []).isEmpty {
                Button("这份报告用了哪天的价格和净值？") { _ = store.reply("这份报告用了哪天的价格和净值？", report: report) }.buttonStyle(SquareButton())
            }
            FormField(title: "围绕这份报告提问", value: $question)
            Button("发送提问") { if store.reply(question, report: report) { question = "" } }
                .buttonStyle(SquareButton(primary: true)).disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
struct NewsDetailView: View {
    var body: some View {
        DetailScreen {
            PageTitle(title: "财报更新，回看持有理由", eyebrow: "持仓动态 / 示例推送")
            Note(text: "虚构事件演示 · 未接入真实新闻")
            Panel {
                Text("发生了什么").font(.title3.bold())
                Text("一家持仓公司公布了新一期财报。摘要提取经营表现、现金流和管理层展望的变化。").font(.system(size: 15)).lineSpacing(6)
                Text("与你的持仓有什么关系").font(.headline)
                Text("对照最初的买入理由，检查经营变化是否影响长期判断。事件本身不等于买卖指令。").font(.system(size: 15)).lineSpacing(6)
            }
            Note(text: "正式版由服务端决定推送时机，并提供相关标的、事件时间与原始来源链接。当前示例不附虚构外链。")
        }
    }
}
