import Foundation

private let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

/// Normalize a timestamp's fractional seconds to exactly 3 digits, since
/// ISO8601DateFormatter is picky and exports can carry microsecond precision.
private func normalizeFraction(_ s: String) -> String {
    guard let dot = s.firstIndex(of: ".") else { return s }
    var i = s.index(after: dot)
    var digits = ""
    while i < s.endIndex, s[i].isNumber {
        digits.append(s[i])
        i = s.index(after: i)
    }
    let rest = String(s[i...])
    let frac3 = String((digits + "000").prefix(3))
    return String(s[..<dot]) + "." + frac3 + rest
}

/// Parse the ISO8601 timestamps found in both Claude Code transcripts and
/// claude.ai exports. Tolerant of 0/3/6 fractional digits.
public func parseTimestamp(_ s: String) -> Date? {
    if let d = isoFractional.date(from: s) { return d }
    if let d = isoPlain.date(from: s) { return d }
    let normalized = normalizeFraction(s)
    if let d = isoFractional.date(from: normalized) { return d }
    return nil
}
