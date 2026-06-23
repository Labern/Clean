import Foundation

public enum Stopwords {
    /// Common English words + conversational filler + Claude/coding domain noise.
    /// This is the single highest-leverage knob for theme quality; tune freely.
    public static let all: Set<String> = [
        // articles / conjunctions / prepositions
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "had",
        "her", "was", "one", "our", "out", "his", "has", "him", "how", "man", "new",
        "now", "old", "see", "two", "way", "who", "boy", "did", "its", "let", "put",
        "say", "she", "too", "use", "with", "this", "that", "from", "they", "them",
        "then", "than", "have", "been", "were", "what", "when", "your", "into", "over",
        "also", "such", "only", "very", "just", "some", "more", "most", "much", "many",
        "each", "both", "few", "other", "same", "about", "above", "after", "again",
        "before", "between", "during", "through", "under", "while", "would", "could",
        "should", "there", "their", "these", "those", "which", "whom", "whose", "where",
        "why", "because", "being", "doing", "does", "done", "here", "off", "down", "out",
        // pronouns / aux / contractions
        "i", "im", "ive", "id", "me", "my", "we", "us", "he", "it", "is", "am", "be",
        "do", "if", "or", "so", "to", "as", "at", "by", "of", "on", "in", "an", "a",
        "youre", "youve", "youll", "dont", "didnt", "doesnt", "cant", "wont", "wasnt",
        "werent", "isnt", "arent", "havent", "hasnt", "thats", "theres", "theyre",
        "weve", "well", "ill", "lets", "gonna", "wanna", "kinda",
        // conversational filler
        "yeah", "yes", "okay", "ok", "sure", "right", "really", "actually", "maybe",
        "like", "just", "want", "wanted", "need", "needs", "needed", "know", "think",
        "thought", "look", "looks", "looking", "see", "make", "makes", "made", "making",
        "thing", "things", "stuff", "lot", "lots", "bit", "way", "ways", "going", "got",
        "get", "gets", "getting", "good", "great", "nice", "cool", "thanks", "thank",
        "please", "sorry", "hey", "hi", "hello", "yep", "nope", "huh", "hmm", "well",
        "even", "still", "back", "around", "something", "anything", "everything",
        "nothing", "someone", "anyone", "everyone", "people", "person",
        // claude / coding domain noise
        "claude", "code", "file", "files", "function", "functions", "error", "errors",
        "run", "running", "ran", "swift", "line", "lines", "app", "apps", "build",
        "building", "change", "changes", "changed", "fix", "fixed", "fixes", "user",
        "add", "added", "adding", "create", "created", "update", "updated", "using",
        "used", "set", "value", "data", "type", "name", "test", "tests", "work",
        "works", "working", "use", "new", "old", "default", "current", "version",
        "let", "sure", "okay", "want", "make", "use", "based", "via", "etc",
    ]
}
