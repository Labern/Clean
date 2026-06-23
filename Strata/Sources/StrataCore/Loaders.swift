import Foundation

/// Turn a project directory name like
/// "-Users-labern-Desktop-Clean--claude-worktrees-obsidian-guide" into a label.
public func humanizeProjectLabel(_ dirName: String) -> String {
    var name = dirName
    if let r = name.range(of: "Desktop-", options: .backwards) {
        name = String(name[r.upperBound...])
    }
    name = name.replacingOccurrences(of: "--", with: " / ")
    name = name.replacingOccurrences(of: "-", with: " ")
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? dirName : trimmed
}

/// Read every local Claude Code transcript under ~/.claude/projects/**/*.jsonl
/// as a Conversation (natural-language text only).
public func loadCodeTranscripts() -> [Conversation] {
    let fm = FileManager.default
    let projectsDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    guard let projectDirs = try? fm.contentsOfDirectory(
        at: projectsDir, includingPropertiesForKeys: [.isDirectoryKey]
    ) else { return [] }

    var result: [Conversation] = []
    for dir in projectDirs {
        let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        guard isDir else { continue }
        let label = humanizeProjectLabel(dir.lastPathComponent)
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
        for file in files where file.pathExtension == "jsonl" {
            if let conv = loadCodeSession(file: file, projectLabel: label) { result.append(conv) }
        }
    }
    return result
}

private func loadCodeSession(file: URL, projectLabel: String) -> Conversation? {
    guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }
    var messages: [ConversationMessage] = []
    var title: String?
    var seen = Set<String>()

    for line in content.split(separator: "\n") {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        let type = obj["type"] as? String

        if type == "ai-title" || type == "custom-title" {
            if let t = (obj["aiTitle"] as? String) ?? (obj["customTitle"] as? String) ?? (obj["title"] as? String) {
                title = t
            }
            continue
        }

        guard type == "user" || type == "assistant" else { continue }
        if let uuid = obj["uuid"] as? String {
            if seen.contains(uuid) { continue }
            seen.insert(uuid)
        }
        guard let message = obj["message"] as? [String: Any] else { continue }
        let text = extractText(content: message["content"])
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        let ts = (obj["timestamp"] as? String).flatMap(parseTimestamp) ?? Date.distantPast
        let role: Role = (type == "user") ? .user : .assistant
        messages.append(ConversationMessage(role: role, text: text, timestamp: ts))
    }

    guard !messages.isEmpty else { return nil }
    let stamps = messages.map { $0.timestamp }.filter { $0 > .distantPast }
    let first = stamps.min() ?? Date()
    let last = stamps.max() ?? first
    let id = "code:" + file.deletingPathExtension().lastPathComponent
    return Conversation(id: id, source: "claude-code", projectLabel: projectLabel,
                        title: title, updatedAtRaw: nil, messages: messages,
                        firstTimestamp: first, lastTimestamp: last)
}

/// Fallback path: load a claude.ai `conversations.json` export file directly.
public func loadClaudeExportFile(at url: URL) -> [Conversation] {
    guard let data = try? Data(contentsOf: url),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
    return arr.compactMap { conversation(fromClaudeDict: $0) }
}
