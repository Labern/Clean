import Foundation

/// On-disk cache of fetched claude.ai conversations, keyed by id. Lets auto-sync
/// only re-fetch new or changed conversations (by `updated_at`).
public struct ConversationCache: Codable, Sendable {
    public var conversations: [String: Conversation]
    public init(conversations: [String: Conversation] = [:]) {
        self.conversations = conversations
    }
}

public func strataSupportDir() -> URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Strata")
    do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    catch { print("[Strata] Failed to create app support dir: \(error)") }
    return dir
}

public func cacheFileURL() -> URL { strataSupportDir().appendingPathComponent("conversations.json") }

public func loadConversationCache() -> ConversationCache {
    guard let data = try? Data(contentsOf: cacheFileURL()),
          let cache = try? JSONDecoder().decode(ConversationCache.self, from: data) else {
        return ConversationCache()
    }
    return cache
}

public func saveConversationCache(_ cache: ConversationCache) {
    guard let data = try? JSONEncoder().encode(cache) else { return }
    try? data.write(to: cacheFileURL())
}
