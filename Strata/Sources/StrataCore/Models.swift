import Foundation

public enum Role: String, Codable, Sendable { case user, assistant }

public struct ConversationMessage: Codable, Sendable {
    public let role: Role
    public let text: String
    public let timestamp: Date
    public let messageId: String?   // UUID from the API — used for deep-link anchors
    public init(role: Role, text: String, timestamp: Date, messageId: String? = nil) {
        self.role = role; self.text = text
        self.timestamp = timestamp; self.messageId = messageId
    }
}

public struct Conversation: Codable, Sendable, Identifiable {
    public let id: String
    public let source: String
    public let projectLabel: String
    public let title: String?
    public let updatedAtRaw: String?
    public let messages: [ConversationMessage]
    public let firstTimestamp: Date
    public let lastTimestamp: Date

    public init(id: String, source: String, projectLabel: String, title: String?,
                updatedAtRaw: String?, messages: [ConversationMessage],
                firstTimestamp: Date, lastTimestamp: Date) {
        self.id = id; self.source = source; self.projectLabel = projectLabel
        self.title = title; self.updatedAtRaw = updatedAtRaw; self.messages = messages
        self.firstTimestamp = firstTimestamp; self.lastTimestamp = lastTimestamp
    }

    public var combinedText: String { messages.map { $0.text }.joined(separator: "\n") }
    public var displayName: String {
        if let t = title, !t.isEmpty { return t }
        return projectLabel
    }

    /// Find the message whose text overlaps most with the given theme label words.
    /// Returns the messageId of the best match, or nil if no messages have UUIDs.
    public func bestMessageId(forTheme theme: String) -> String? {
        let themeWords = Set(theme.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 })
        var bestId: String? = nil
        var bestScore = -1
        for msg in messages {
            guard let mid = msg.messageId else { continue }
            let msgWords = Set(msg.text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 })
            let score = themeWords.intersection(msgWords).count
            if score > bestScore { bestScore = score; bestId = mid }
        }
        return bestId
    }
}

public func extractText(content: Any?) -> String {
    if let s = content as? String { return s }
    if let arr = content as? [Any] {
        var parts: [String] = []
        for case let block as [String: Any] in arr {
            if (block["type"] as? String) == "text",
               let t = block["text"] as? String, !t.isEmpty { parts.append(t) }
        }
        return parts.joined(separator: "\n")
    }
    return ""
}

public func conversation(fromClaudeDict conv: [String: Any]) -> Conversation? {
    guard let id = conv["uuid"] as? String else { return nil }
    let title = conv["name"] as? String
    let msgs = conv["chat_messages"] as? [[String: Any]] ?? []
    var messages: [ConversationMessage] = []
    for m in msgs {
        let senderStr = (m["sender"] as? String) ?? "human"
        let role: Role = (senderStr == "assistant") ? .assistant : .user
        var text = (m["text"] as? String) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = extractText(content: m["content"])
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        let ts = (m["created_at"] as? String).flatMap(parseTimestamp)
            ?? (conv["created_at"] as? String).flatMap(parseTimestamp)
            ?? Date.distantPast
        let mid = m["uuid"] as? String
        messages.append(ConversationMessage(role: role, text: text, timestamp: ts, messageId: mid))
    }
    guard !messages.isEmpty else { return nil }
    let created = (conv["created_at"] as? String).flatMap(parseTimestamp)
    let updated = (conv["updated_at"] as? String).flatMap(parseTimestamp)
    let stamps = messages.map { $0.timestamp }.filter { $0 > .distantPast }
    let first = created ?? stamps.min() ?? Date.distantPast
    let last = updated ?? stamps.max() ?? first
    return Conversation(id: id, source: "claude.ai", projectLabel: "claude.ai",
                        title: (title?.isEmpty == false) ? title : nil,
                        updatedAtRaw: conv["updated_at"] as? String,
                        messages: messages, firstTimestamp: first, lastTimestamp: last)
}
