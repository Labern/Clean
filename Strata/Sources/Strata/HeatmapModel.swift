import Foundation
import SwiftUI
import StrataCore

@MainActor
final class HeatmapModel: ObservableObject {
    @Published var bubbles: [ThemeBubble] = []
    @Published var matrix: HeatmapMatrix?
    @Published var bucket: BucketSize = .week
    @Published var topThemeCount: Int = 200
    @Published var themeSort: ThemeSort = .frequencyDesc
    @Published var isSyncing = false
    @Published var needsLogin = false
    @Published var statusText = "Starting…"
    @Published var selected: SelectedBubble?

    private var conversations: [Conversation] = []
    private var themes: [ConversationThemes] = []
    private let extractor = LexicalThemeExtractor(topTermsPerConversation: 20)
    private var cache = loadConversationCache()
    private var autoTask: Task<Void, Never>?

    struct SelectedBubble: Identifiable {
        let id = UUID()
        let theme: String
        let conversations: [Conversation]
    }

    func start() {
        needsLogin = !isAuthenticated()
        rebuildFromSources()
        Task { await syncFromWeb() }
        scheduleAutoRefresh()
    }

    private func scheduleAutoRefresh() {
        autoTask?.cancel()
        autoTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                guard let self else { return }
                await self.syncFromWeb()
            }
        }
    }

    // MARK: - data assembly

    private func rebuildFromSources() {
        var convs = loadCodeTranscripts()
        convs.append(contentsOf: cache.conversations.values)
        conversations = convs.sorted { $0.lastTimestamp < $1.lastTimestamp }

        if !conversations.isEmpty {
            let stamps = conversations.map(\.lastTimestamp).filter { $0 > .distantPast }
            if let lo = stamps.min(), let hi = stamps.max() {
                let days = hi.timeIntervalSince(lo) / 86_400
                if days > 0 { bucket = days > 140 ? .month : (days > 21 ? .week : .day) }
            }
        }

        themes = extractor.extractThemes(from: conversations)
        rebuildMatrix()
        updateStatus()
    }

    func rebuildMatrix() {
        guard !conversations.isEmpty else { matrix = nil; bubbles = []; return }
        let m = buildMatrix(conversations: conversations, themes: themes, bucket: bucket, topThemeCount: topThemeCount)
        matrix = m
        bubbles = buildBubbles(from: m)
    }

    func changeBucket(_ b: BucketSize) { bucket = b; rebuildMatrix() }
    func changeTopThemeCount(_ n: Int) { topThemeCount = n; rebuildMatrix() }
    func changeThemeSort(_ s: ThemeSort) { themeSort = s }

    private func updateStatus() {
        let web = cache.conversations.count
        let code = conversations.filter { $0.source == "claude-code" }.count
        if needsLogin {
            statusText = "\(code) Code sessions · connect claude.ai to include all conversations"
        } else if isSyncing && web == 0 {
            statusText = "Syncing claude.ai…"
        } else {
            statusText = "\(web + code) conversations (\(web) claude.ai · \(code) Code)"
        }
    }

    // MARK: - sync

    func syncFromWeb() async {
        guard !isSyncing else { return }
        guard isAuthenticated() else { needsLogin = true; updateStatus(); return }
        isSyncing = true; needsLogin = false
        defer { isSyncing = false }
        statusText = "Connecting…"
        do {
            let orgId = try await resolveOrgId()
            statusText = "Fetching conversation list…"
            let summaries = try await fetchConversationSummaries(orgId: orgId)
            var fetched = 0
            for s in summaries {
                if let existing = cache.conversations[s.id],
                   let u = s.updatedAt, existing.updatedAtRaw == u { continue }
                if let conv = try? await fetchConversationDetail(orgId: orgId, id: s.id) {
                    cache.conversations[conv.id] = conv
                    fetched += 1
                    if fetched % 25 == 0 {
                        statusText = "Synced \(fetched) of \(summaries.count)…"
                        rebuildFromSources()
                    }
                }
            }
            saveConversationCache(cache)
            rebuildFromSources()
        } catch is NotAuthenticated {
            needsLogin = true; updateStatus()
        } catch {
            statusText = "Sync error: \(error.localizedDescription)"
        }
    }

    func showLogin() {
        LoginWindowController.shared.onDone = { [weak self] in
            guard let self else { return }
            self.needsLogin = false
            Task { await self.syncFromWeb() }
        }
        LoginWindowController.shared.show()
    }

    // MARK: - selection

    func select(bubble: ThemeBubble) {
        let ids = Set(bubble.allContributorIds)
        let convs = conversations.filter { ids.contains($0.id) }
            .sorted { $0.lastTimestamp > $1.lastTimestamp }
        guard !convs.isEmpty else { return }
        selected = SelectedBubble(theme: bubble.theme, conversations: convs)
    }

    func select(row: Int, col: Int) {
        guard let m = matrix, row < m.cells.count, col < m.cells[row].count else { return }
        let ids = Set(m.cells[row][col].contributors)
        let convs = conversations.filter { ids.contains($0.id) }
            .sorted { $0.lastTimestamp > $1.lastTimestamp }
        guard !convs.isEmpty else { return }
        selected = SelectedBubble(
            theme: "\(m.themes[row])  ·  \(m.buckets[col].label)",
            conversations: convs
        )
    }
}
