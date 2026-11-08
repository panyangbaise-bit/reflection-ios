import Foundation
import Observation

@MainActor protocol CloudChatClient {
    var requiresSignIn: Bool { get }
    func chatRequest<T: Decodable & Sendable>(_ path: String, method: String, body: [String: Any]?, key: String?) async throws -> T
}
extension CloudChatClient {
    func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: [String: Any]? = nil, key: String? = nil) async throws -> T {
        try await chatRequest(path, method: method, body: body, key: key)
    }
}

@MainActor @Observable final class CloudChatModel {
    var conversations: [APIConversation] = []
    var conversationCursor: String?
    var conversationId: String?
    var messages: [APIMessage] = []
    var messagesCursor: String?
    var runId: String?
    var runStatus = ""
    var charts: [APIChart] = []
    var error: String?
    var busy = false
    var pendingText: String?
    private var pendingKey = UUID().uuidString
    private var selection = UUID()
    let reportId: String?
    init(reportId: String? = nil) { self.reportId = reportId }

    func history(_ cloud: any CloudChatClient, more: Bool = false) async {
        let scope = selection
        do {
            let page: APIPage<APIConversation> = try await cloud.request(apiPath("conversations", ["paged": "true", "report_id": reportId, "cursor": more ? conversationCursor : nil]))
            guard scope == selection, !Task.isCancelled else { return }
            if more { let ids = Set(conversations.map(\.id)); conversations += page.items.filter { !ids.contains($0.id) } }
            else { conversations = page.items }
            conversationCursor = page.nextCursor
            if let reportId, conversationId == nil, let first = conversations.first(where: { $0.reportId == reportId }) { await select(first.id, cloud) }
        } catch { self.error = error.localizedDescription }
    }
    func select(_ id: String?, _ cloud: any CloudChatClient) async {
        guard pendingText == nil else { error = "请先重试当前未确认的发送，再切换对话。"; return }
        selection = UUID(); conversationId = id; messages = []; messagesCursor = nil; runId = nil; charts = []; error = nil
        guard let id else { return }
        busy = true; defer { busy = false }
        let scope = selection
        do {
            try await loadMessages(cloud)
            let active: APIActiveRun = try await cloud.request("conversations/\(id)/active-run")
            guard scope == selection, !Task.isCancelled else { return }
            if let rid = active.runId {
                let run: APIRun = try await cloud.request("runs/\(rid)")
                guard scope == selection, !Task.isCancelled else { return }
                charts = run.charts ?? []
                if ["queued", "running"].contains(run.status) { runId = rid; runStatus = run.status }
                else if run.status == "failed" { error = "上次回答未完成，追问额度已释放。\(run.errorCode ?? "")" }
            }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func loadMessages(_ cloud: any CloudChatClient, more: Bool = false) async throws {
        guard let id = conversationId else { return }
        let scope = selection
        let page: APIPage<APIMessage> = try await cloud.request(apiPath("conversations/\(id)/messages", ["paged": "true", "cursor": more ? messagesCursor : nil]))
        guard scope == selection, !Task.isCancelled else { return }
        let chronological = Array(page.items.reversed())
        if more { let ids = Set(messages.map(\.id)); messages = chronological.filter { !ids.contains($0.id) } + messages }
        else { messages = chronological }
        messagesCursor = page.nextCursor
    }
    func older(_ cloud: any CloudChatClient) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await loadMessages(cloud, more: true) } catch { self.error = error.localizedDescription }
    }
    func send(_ text: String, _ cloud: any CloudChatClient) async -> Bool {
        guard !busy, runId == nil else { return false }
        let content = pendingText ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, content.count <= 4000 else { error = "请输入 1–4000 字的问题。"; return false }
        busy = true; defer { busy = false }; error = nil; pendingText = content
        do {
            if reportId == nil && conversationId == nil {
                let created: APIConversation = try await cloud.request("conversations", method: "POST", body: ["title": String(content.prefix(40))], key: pendingKey + "-conversation")
                conversationId = created.id
            }
            let path = reportId.map { "reports/\($0)/questions" } ?? "conversations/\(conversationId!)/messages"
            let queued: APIQueuedRun = try await cloud.request(path, method: "POST", body: ["content": content], key: pendingKey)
            conversationId = queued.conversationId; runId = queued.runId; runStatus = queued.status
            pendingText = nil; pendingKey = UUID().uuidString
            try? await loadMessages(cloud)
            return true
        } catch {
            // A transport error has an unknown outcome; retain the exact intent/key for retry.
            if let apiError = error as? APIError, (400..<500).contains(apiError.status) {
                pendingText = nil; pendingKey = UUID().uuidString
            }
            self.error = error.localizedDescription
            return false
        }
    }
    func poll(_ cloud: any CloudChatClient) async {
        guard let id = runId else { return }
        while !Task.isCancelled && runId == id {
            do {
                let run: APIRun = try await cloud.request("runs/\(id)")
                guard !Task.isCancelled, runId == id else { return }
                runStatus = run.status; error = nil
                if ["succeeded", "failed"].contains(run.status) {
                    charts = run.charts ?? []
                    try await loadMessages(cloud)
                    runId = nil
                    if run.status == "failed" { error = "回答未完成，追问额度已释放。\(run.errorCode ?? "请稍后重试")" }
                    return
                }
                try await Task.sleep(for: .seconds(1))
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                self.error = "连接中断，正在重连。" + error.localizedDescription
                if cloud.requiresSignIn { return }
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
            }
        }
    }
}
