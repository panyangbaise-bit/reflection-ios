import Foundation

/// Bundled, versioned documents remain readable before authentication and offline.
/// This receipt is local to this installation; it is not a server-side consent record.
enum AppAgreements {
    static let version = "2026-11-05"
    static let storageKey = "appAgreementReceipt"

    struct Receipt: Codable, Equatable {
        let version: String
        let acceptedAt: Date
    }

    enum AcceptanceError: LocalizedError {
        case required
        var errorDescription: String? { "请先阅读并勾选同意用户协议和隐私政策。" }
    }

    static func requireAcceptance(_ accepted: Bool) throws {
        guard accepted else { throw AcceptanceError.required }
    }

    static func record(in defaults: UserDefaults = .standard, at date: Date = Date()) {
        let receipt = Receipt(version: version, acceptedAt: date)
        if let data = try? JSONEncoder().encode(receipt) { defaults.set(data, forKey: storageKey) }
    }

    static func receipt(in defaults: UserDefaults = .standard) -> Receipt? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Receipt.self, from: data)
    }
}

enum AppLegalDocument: String, Identifiable, CaseIterable {
    case terms, privacy
    var id: String { rawValue }
    var title: String { self == .terms ? "用户协议" : "隐私政策" }
    var icon: String { self == .terms ? "doc.text" : "hand.raised" }
    var sections: [(title: String, body: String)] {
        switch self {
        case .terms:
            return [
                ("关于本服务", "欢迎使用复盘了。本协议适用于当前测试版的持仓记录、投资复盘和 AI 问答功能。请阅读本协议及隐私政策，自主选择是否登录使用云端服务。"),
                ("账户与数据", "你可以使用手机号与密码登录，管理自己的云端持仓、交易及复盘。请妥善保管登录凭据，只录入你有权使用的数据。本地演示与云端账户独立，演示数据不会自动上传。"),
                ("内容与使用边界", "行情可能延迟或缺失，复盘和 AI 回答可能存在错误，请核对数据来源及时间。内容用于信息整理和辅助理解，不构成投资建议或收益承诺。应用不连接券商执行交易，也不会替你下单。"),
                ("AI 功能", "同意本协议不会自动开启 AI 数据授权。交互问答和定时报告的 AI 摘要需要分别授权；你可以在设置中的“AI 授权与隐私”查看处理方、用途并撤回授权。"),
                ("测试版", "当前版本仍在测试，功能及服务可用性可能调整。应用内的功能均可免费使用；如未来调整服务范围，会在应用内说明。"),
                ("退出与删除", "你可以退出云端账户，在设置中导出数据或申请删除账户。删除操作及其范围以确认页面说明为准；退出登录不会删除云端数据。"),
                ("版本说明", "本页为当前测试版的使用说明与协议。协议内容更新时，以应用内展示的新版本为准；登录时请阅读并确认。")
            ]
        case .privacy:
            return [
                ("本地与云端", "本地演示的持仓、交易、偏好和示例对话保存在设备中，不会自动上传。登录云端后，你提交的账户、持仓、交易、纪律、问题和对话等数据由服务端保存，用于提供对应功能。"),
                ("登录信息", "登录使用手机号与密码。密码在服务端以加盐哈希保存。登录凭据保存在设备的系统钥匙串中，用于后续身份验证。应用会在本机记录本次同意的协议版本及时间。"),
                ("AI 数据处理", "仅同意本页不会授权向 AI 服务发送个人数据。另行授权后，服务端可能将与请求相关的持仓、成本、交易、报告、纪律、记忆证据、问题及对话发送给所披露的 AI 处理方。具体处理方与披露版本可在“AI 授权与隐私”中查看。联网搜索时，生成的搜索词也可能发送给搜索服务。"),
                ("测试日志", "部分测试环境可能启用 AI 内容排查记录，包括输入、输出和工具结果，可能涉及持仓及对话。启用情况与保留说明会在 AI 授权页面展示，请在授权前查看。"),
                ("你的选择", "你可以分别管理交互 AI 和定时报告的授权，也可以撤回授权。撤回后尚未发送的请求停止外发，已发送的请求无法追回；撤回不会自动删除账本或已有报告。"),
                ("导出与删除", "登录后可在设置中导出数据或申请删除云端账户。当前删除范围及备份等处理边界会在删除确认页说明。本地演示文件随卸载移除；退出登录仅结束会话，不等同于删除云端数据。"),
                ("阅读与更新", "这份说明随应用提供，可在未登录或无网络时阅读。AI 处理方及授权状态需联网获取，加载失败时不会视为已授权。请勿在对话中提供无关的敏感个人信息。")
            ]
        }
    }
}
