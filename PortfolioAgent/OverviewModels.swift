import Foundation

/// The data source's own update time (never the fetch/sync time), for honest labels.
func sourceTimeText(_ asOf: String?, kind: String? = nil) -> String? {
    guard let date = overviewDate(asOf) else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = .current
    if kind == "nav" || kind == "close" {
        formatter.dateFormat = "yyyy年M月d日"
        return "数据日期 " + formatter.string(from: date)
    }
    formatter.dateFormat = "yyyy年M月d日 HH:mm"
    return "数据时间 " + formatter.string(from: date)
}

func cloudDateTime(_ value: String) -> String {
    guard let date = overviewDate(value) else { return "时间不可用" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy年M月d日 HH:mm zzz"
    return formatter.string(from: date)
}

func overviewDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: value) { return date }
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: value) { return date }
    let day = DateFormatter()
    day.locale = Locale(identifier: "en_US_POSIX")
    day.timeZone = TimeZone(identifier: "Asia/Shanghai")
    day.dateFormat = "yyyy-MM-dd"
    return day.date(from: value)
}

enum OverviewBlock: String, CaseIterable, Codable, Identifiable, Sendable {
    case discipline, latest, holdings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .discipline: "交易纪律"
        case .latest: "复盘 / 新闻"
        case .holdings: "持仓"
        }
    }
    static let defaultOrder: [Self] = [.discipline, .latest, .holdings]
    /// Preserve the stored order, drop unknown/duplicate entries and append blocks added later.
    static func normalized(_ raw: [String]?) -> [Self] {
        var seen = Set<Self>()
        var order = (raw ?? []).compactMap { Self(rawValue: $0) }.filter { seen.insert($0).inserted }
        order += defaultOrder.filter { seen.insert($0).inserted }
        return order
    }
    /// Move one block to the slot of the block it was dropped on.
    static func moving(_ source: Self, onto target: Self, in order: [Self]) -> [Self] {
        guard source != target, let from = order.firstIndex(of: source), let to = order.firstIndex(of: target) else { return order }
        var next = order
        let item = next.remove(at: from)
        next.insert(item, at: min(to, next.count))
        return next
    }
}

enum TradingDisciplineRules {
    static let maxLength = 2000
    static func normalize(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return String(lines.joined(separator: "\n").prefix(maxLength))
    }
    static func rules(_ text: String?) -> [String] {
        guard let text else { return [] }
        return normalize(text).components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}

struct OverviewNotice: Identifiable {
    enum Destination { case localReport(String), localNews, report(APIReport), article(URL), none }
    let id: String
    let kind: String
    let icon: String
    let title: String
    let summary: String
    let date: Date?
    let action: String
    let destination: Destination

    static func latest(_ notices: [Self]) -> Self? {
        notices.max {
            let lhs = $0.date ?? .distantPast, rhs = $1.date ?? .distantPast
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
    }

    static func cloud(_ home: APIHome?) -> Self? {
        guard let home else { return nil }
        var notices: [Self] = []
        if let report = home.latestContent {
            notices.append(Self(id: report.id, kind: report.kind == "weekly" ? "每周复盘" : "收盘总结",
                icon: report.kind == "weekly" ? "calendar" : "sunset", title: report.title,
                summary: report.summary, date: overviewDate(report.createdAt) ?? overviewDate(report.period),
                action: "查看复盘", destination: .report(report)))
        }
        notices += (home.news ?? []).compactMap { news in
            guard let url = URL(string: news.url), ["https", "http"].contains(url.scheme ?? "") else { return nil }
            return Self(id: news.id, kind: "持仓新闻", icon: "newspaper", title: news.title,
                summary: news.summary.isEmpty ? news.source : news.summary,
                date: overviewDate(news.createdAt) ?? overviewDate(news.publishedAt),
                action: "\(news.source) · 查看原文", destination: .article(url))
        }
        return latest(notices)
    }

    static func demo(reports: [Report]) -> Self? {
        var notices = reports.map { report in
            Self(id: report.id, kind: "AI \(report.kind.rawValue)", icon: report.kind == .daily ? "sunset" : "calendar",
                title: report.title.replacingOccurrences(of: "\n", with: ""), summary: report.summary,
                date: report.deliveredAt, action: "查看复盘", destination: .localReport(report.id))
        }
        notices.append(Self(id: "demo-news", kind: "持仓新闻", icon: "newspaper",
            title: "财报更新，回看持有理由", summary: "持仓公司的财报已更新，关注经营变化与原有投资判断。",
            date: SampleData.date.addingTimeInterval(60), action: "查看动态", destination: .localNews))
        return latest(notices)
    }
}

struct OverviewPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double // Rendering only; financial values remain Decimal strings on the wire.
    static func from(_ points: [APIAssetPoint]) -> [Self] {
        points.compactMap {
            guard let date = overviewDate($0.asOf), let value = Double($0.marketValueCny), value.isFinite, value >= 0 else { return nil }
            return Self(date: date, value: value)
        }.sorted { $0.date < $1.date }
    }
    static let demo: [Self] = [149600.0, 151200, 150400, 153300, 152800, 155600, 156200, 154900, 157700, 158900, 158200, 160000]
        .enumerated().map { Self(date: SampleData.date.addingTimeInterval(Double($0.offset - 11) * 86400), value: $0.element) }
}

struct AssetSlice: Identifiable, Equatable {
    let title: String
    let value: Double
    var id: String { title }
}

enum AssetComposition {
    static func grouped(_ values: [(String, Double)]) -> [AssetSlice] {
        Dictionary(grouping: values.filter { $0.1.isFinite && $0.1 > 0 }, by: { $0.0 })
            .map { AssetSlice(title: $0.key, value: $0.value.reduce(0) { $0 + $1.1 }) }
            .sorted { $0.value == $1.value ? $0.title < $1.title : $0.value > $1.value }
    }
    static func cloud(_ positions: [APIPosition], complete: Bool) -> [AssetSlice] {
        // Never imply a full allocation when quotes or FX are missing.
        guard complete else { return [] }
        let active = positions.filter { (Decimal(string: $0.quantity) ?? 0) > 0 }
        // NAV holdings are priced for coverage but excluded from the live market
        // total by product rule; skip them here instead of blanking the chart.
        let priced = active.compactMap { position -> (APIPosition, Double)? in
            guard let raw = position.marketValueCny,
                  let value = Double(raw), value.isFinite, value > 0 else { return nil }
            return (position, value)
        }
        guard !priced.isEmpty else { return [] }
        return grouped(priced.map { position, value in
            let label: String
            switch position.assetClass {
            case "fund": label = "基金"
            case "listed_fund": label = "场内基金"
            case "etf": label = "ETF"
            case "gold": label = "黄金"
            default:
                switch position.market {
                case "CN": label = position.quoteKind == "nav" ? "基金" : "A 股"
                case "HK": label = "港股"
                case "US": label = "美股"
                default: label = "其他资产"
                }
            }
            return (label, value)
        })
    }
}
