import Foundation

public struct ThemeTerm: Codable, Sendable {
    public let label: String     // human-readable, e.g. "menu bar"
    public let weight: Double    // 0...1 normalized within the conversation
    public init(label: String, weight: Double) {
        self.label = label
        self.weight = weight
    }
}

public struct ConversationThemes: Codable, Sendable, Identifiable {
    public let id: String        // == Conversation.id
    public let terms: [ThemeTerm]
    public init(id: String, terms: [ThemeTerm]) {
        self.id = id
        self.terms = terms
    }
}

/// The swap seam: a future APIThemeExtractor (Claude API) drops in here without
/// touching anything downstream.
public protocol ThemeExtractor: Sendable {
    var identifier: String { get }
    func extractThemes(from conversations: [Conversation]) -> [ConversationThemes]
}

/// v1: local TF-IDF over the whole corpus, with adjacent bigrams for readable
/// labels. Zero external dependencies / credentials.
public struct LexicalThemeExtractor: ThemeExtractor, Sendable {
    public let identifier = "lexical-tfidf-v1"
    public let topTermsPerConversation: Int
    public init(topTermsPerConversation: Int = 20) {
        self.topTermsPerConversation = topTermsPerConversation
    }

    public func extractThemes(from conversations: [Conversation]) -> [ConversationThemes] {
        // 1. per-document term counts (unigrams + frequent bigrams)
        let docs: [(id: String, counts: [String: Int])] = conversations.map {
            ($0.id, termCounts(cleanedTokens($0.combinedText)))
        }

        // 2. document frequency for IDF
        var df: [String: Int] = [:]
        for d in docs { for term in d.counts.keys { df[term, default: 0] += 1 } }
        let n = Double(max(1, docs.count))

        // 3. score, pick top terms per doc, prefer bigrams over their parts
        var results: [ConversationThemes] = []
        for d in docs {
            var scored: [(term: String, score: Double)] = []
            for (term, count) in d.counts {
                let tf = 1.0 + log(Double(count))
                let idf = log((1.0 + n) / (1.0 + Double(df[term] ?? 1))) + 1.0
                scored.append((term, tf * idf))
            }
            scored.sort { $0.score > $1.score }

            let top = Array(scored.prefix(topTermsPerConversation * 2))
            let bigramWords = Set(
                top.filter { $0.term.contains(" ") }
                    .flatMap { $0.term.split(separator: " ").map(String.init) }
            )
            var chosen: [(term: String, score: Double)] = []
            for entry in top {
                let isUnigram = !entry.term.contains(" ")
                if isUnigram && bigramWords.contains(entry.term) { continue }
                chosen.append(entry)
                if chosen.count >= topTermsPerConversation { break }
            }

            let maxScore = chosen.map { $0.score }.max() ?? 1.0
            let terms = chosen.map {
                ThemeTerm(label: $0.term, weight: maxScore > 0 ? $0.score / maxScore : 0)
            }
            results.append(ConversationThemes(id: d.id, terms: terms))
        }
        return results
    }

    // MARK: - tokenization

    private func cleanedTokens(_ text: String) -> [String] {
        // Mix lowercased tokens (concepts) + preserved-case tokens (names/people).
        // Proper nouns are emitted as-is so "Sarah" stays distinct from "safari".
        let lower = tokenizeLower(text).filter {
            $0.count >= 3 && !$0.allSatisfy(\.isNumber) && !Stopwords.all.contains($0)
        }
        // Exclude proper nouns whose lowercase form is already captured in `lower`
        // to prevent duplicates like "bpd" + "BPD" both making it into the term counts
        // (titleCase() later renders both identically, producing "Bpd Bpd"-style labels).
        let lowerSet = Set(lower)
        let proper = tokenizeProperNouns(text).filter {
            $0.count >= 2
            && !Stopwords.all.contains($0.lowercased())
            && !lowerSet.contains($0.lowercased())
        }
        return lower + proper
    }

    private func tokenizeLower(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber { current.append(ch) }
            else if !current.isEmpty { tokens.append(current); current = "" }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Extract words that are capitalised mid-sentence — likely proper nouns / names.
    /// Skips the first word of each sentence (after . ! ?) to avoid false positives.
    private func tokenizeProperNouns(_ text: String) -> [String] {
        var result: [String] = []
        var afterSentenceBoundary = true
        var current = ""
        var currentIsCapitalized = false

        for ch in text {
            if ch.isLetter {
                if current.isEmpty { currentIsCapitalized = ch.isUppercase }
                current.append(ch)
            } else {
                if !current.isEmpty {
                    if currentIsCapitalized && !afterSentenceBoundary {
                        result.append(current)
                    }
                    afterSentenceBoundary = false
                    current = ""
                }
                if ch == "." || ch == "!" || ch == "?" || ch == "\n" {
                    afterSentenceBoundary = true
                }
            }
        }
        if !current.isEmpty && currentIsCapitalized && !afterSentenceBoundary {
            result.append(current)
        }
        return result
    }

    private func termCounts(_ toks: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for t in toks { counts[t, default: 0] += 1 }
        if toks.count >= 2 {
            var bi: [String: Int] = [:]
            for i in 0..<(toks.count - 1) { bi[toks[i] + " " + toks[i + 1], default: 0] += 1 }
            for (k, v) in bi where v >= 2 { counts[k] = v }   // only repeated bigrams
        }
        return counts
    }
}
