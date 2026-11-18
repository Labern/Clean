import Foundation

/// What a note's plain text means: a little of Markdown, read line by line.
///
///     # Heading      ## Smaller      ### Smaller still
///     • a bullet     (a dash or a star and a space becomes one as you type)
///     	• nested    (a tab, or two spaces, for each level)
///     **bold**  _italic_
///     [words](address)  and any address written out is a link
///
/// The note is stored exactly as typed. This only says how to draw it and how
/// the keyboard's bar changes it, so the same text reads the same on the site
/// and the Mac. Ranges are UTF-16, as text views count.
nonisolated enum NoteMarkup {
    static let bullet = "•"
    static let maxDepth = 6

    enum Kind: Equatable, Sendable {
        case plain
        /// 1, 2 or 3: the number of #.
        case heading(Int)
        /// How far in it is nested; 0 is the outer list.
        case bullet(Int)
    }

    struct Line: Equatable, Sendable {
        /// The line, without its line break.
        var range: NSRange
        var kind: Kind
        /// "## ", or the indent and "• ". Empty for a plain line.
        var marker: NSRange
    }

    // MARK: Reading

    static func lines(_ text: String) -> [Line] {
        let ns = text as NSString
        var found: [Line] = []
        var start = 0
        while start < ns.length {
            var lineEnd = 0, contentsEnd = 0
            ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
            let range = NSRange(location: start, length: contentsEnd - start)
            found.append(read(ns.substring(with: range), at: start))
            start = max(lineEnd, start + 1)
        }
        return found
    }

    /// One line, on its own. `offset` is where it starts in the whole note.
    static func read(_ line: String, at offset: Int = 0) -> Line {
        let ns = line as NSString
        let whole = NSRange(location: offset, length: ns.length)
        // A heading: one to three #, then a space.
        var hashes = 0
        while hashes < ns.length, hashes < 4, ns.character(at: hashes) == 35 { hashes += 1 }
        if (1...3).contains(hashes), hashes < ns.length, ns.character(at: hashes) == 32 {
            return Line(range: whole, kind: .heading(hashes), marker: NSRange(location: offset, length: hashes + 1))
        }
        // A bullet: any indent, then • - or *, then a space.
        var indent = 0, tabs = 0, spaces = 0
        while indent < ns.length {
            let character = ns.character(at: indent)
            if character == 9 { tabs += 1 } else if character == 32 { spaces += 1 } else { break }
            indent += 1
        }
        let marks: [unichar] = [0x2022, 45, 42]
        if indent + 1 < ns.length, marks.contains(ns.character(at: indent)), ns.character(at: indent + 1) == 32 {
            return Line(range: whole, kind: .bullet(min(tabs + spaces / 2, maxDepth)),
                        marker: NSRange(location: offset, length: indent + 2))
        }
        return Line(range: whole, kind: .plain, marker: NSRange(location: offset, length: 0))
    }

    struct Link: Equatable, Sendable {
        /// The words that are the link.
        var range: NSRange
        var url: URL
        /// The brackets and the address of [words](address): drawn faint.
        var faint: [NSRange]
    }

    private static let written = #"\[([^\]\n]+)\]\(([^)\s]+)\)"#
    private static let strong = #"\*\*([^*\n]+)\*\*"#
    private static let slanted = #"(?<![\w])_([^_\n]+)_(?![\w])"#

    /// Every link: the written kind, [words](address), and any address typed out in full.
    static func links(_ text: String) -> [Link] {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        var found: [Link] = []
        var taken: [NSRange] = []
        if let pattern = try? NSRegularExpression(pattern: written) {
            for match in pattern.matches(in: text, range: all) {
                let words = match.range(at: 1)
                taken.append(match.range)
                guard let url = address(ns.substring(with: match.range(at: 2))) else { continue }
                found.append(Link(range: words, url: url, faint: [
                    NSRange(location: match.range.location, length: 1),
                    NSRange(location: NSMaxRange(words), length: NSMaxRange(match.range) - NSMaxRange(words)),
                ]))
            }
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: text, range: all) {
                guard let url = match.url,
                      !taken.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
                found.append(Link(range: match.range, url: url, faint: []))
            }
        }
        return found.sorted { $0.range.location < $1.range.location }
    }

    /// An address as written, made whole: "paradoxica.co.uk" opens as https.
    static func address(_ written: String) -> URL? {
        let trimmed = written.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let full = trimmed.contains("://") || trimmed.hasPrefix("mailto:") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: full), let scheme = url.scheme else { return nil }
        guard scheme == "mailto" || url.host?.contains(".") == true else { return nil }
        return url
    }

    struct Stress: Equatable, Sendable {
        /// The words themselves.
        var range: NSRange
        var bold: Bool
        /// The ** or _ either side: drawn faint.
        var marks: [NSRange]
    }

    /// **bold** and _italic_.
    static func stresses(_ text: String) -> [Stress] {
        let all = NSRange(location: 0, length: (text as NSString).length)
        var found: [Stress] = []
        for (source, bold, width) in [(strong, true, 2), (slanted, false, 1)] {
            guard let pattern = try? NSRegularExpression(pattern: source) else { continue }
            for match in pattern.matches(in: text, range: all) {
                found.append(Stress(range: match.range(at: 1), bold: bold, marks: [
                    NSRange(location: match.range.location, length: width),
                    NSRange(location: NSMaxRange(match.range) - width, length: width),
                ]))
            }
        }
        return found.sorted { $0.range.location < $1.range.location }
    }

    /// A line as its words alone, for a note's title and summary in a list.
    static func plain(_ line: String) -> String {
        let marker = read(line).marker.length
        var words = (line as NSString).substring(from: marker)
        for pattern in [written, strong, slanted] {
            words = words.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
        }
        return words.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Changing

    /// One change to the text, and where the caret goes after it.
    struct Edit: Equatable, Sendable {
        var range: NSRange
        var replacement: String
        var caret: Int
    }

    /// Return in a list: carries the list on, or steps out of it when the line is empty.
    static func afterReturn(_ text: String, selection: NSRange) -> Edit? {
        let ns = text as NSString
        guard NSMaxRange(selection) <= ns.length else { return nil }
        let lineRange = contents(of: ns, at: selection.location)
        let line = read(ns.substring(with: lineRange), at: lineRange.location)
        guard case .bullet(let depth) = line.kind, selection.location >= NSMaxRange(line.marker) else { return nil }
        let indent = ns.substring(with: NSRange(location: line.marker.location, length: line.marker.length - 2))
        if NSMaxRange(line.marker) == NSMaxRange(lineRange), selection.length == 0 {
            // Nothing after the bullet: step out one level, or stop the list.
            guard depth > 0 else { return Edit(range: line.marker, replacement: "", caret: lineRange.location) }
            let shorter = outdented(indent)
            let lost = (indent as NSString).length - (shorter as NSString).length
            return Edit(range: NSRange(location: lineRange.location, length: (indent as NSString).length),
                        replacement: shorter, caret: selection.location - lost)
        }
        let next = "\n\(indent)\(bullet) "
        return Edit(range: selection, replacement: next, caret: selection.location + (next as NSString).length)
    }

    /// A dash or a star, then a space, at the start of a line: it becomes a bullet.
    static func afterSpace(_ text: String, caret: Int) -> Edit? {
        let ns = text as NSString
        guard caret > 0, caret <= ns.length else { return nil }
        let lineRange = contents(of: ns, at: caret)
        guard caret > lineRange.location else { return nil }
        let before = ns.substring(with: NSRange(location: lineRange.location, length: caret - lineRange.location)) as NSString
        let dashes: [unichar] = [45, 42]
        guard dashes.contains(before.character(at: before.length - 1)) else { return nil }
        for index in 0..<(before.length - 1) where before.character(at: index) != 9 && before.character(at: index) != 32 {
            return nil
        }
        // Only when nothing follows it on the line, or it would eat a star that opens **bold**.
        guard caret == NSMaxRange(lineRange) else { return nil }
        return Edit(range: NSRange(location: caret - 1, length: 1), replacement: "\(bullet) ", caret: caret + 1)
    }

    /// The bar's indent (+1) and outdent (-1), on every line the selection touches.
    /// Indenting a plain line makes it a bullet; outdenting an outer bullet makes it plain again.
    static func shift(_ text: String, selection: NSRange, by step: Int) -> Edit? {
        change(text, selection: selection) { line in
            let read = read(line)
            let words = (line as NSString).substring(from: read.marker.length)
            switch read.kind {
            case .bullet(let depth):
                if step > 0 { return depth < maxDepth ? "\t" + line : line }
                if depth == 0 { return words }
                let indent = (line as NSString).substring(to: read.marker.length - 2)
                return outdented(indent) + (line as NSString).substring(from: read.marker.length - 2)
            case .plain, .heading:
                return step > 0 ? "\(bullet) \(words)" : line
            }
        }
    }

    /// The bar's bullet button: on, or off.
    static func toggleBullet(_ text: String, selection: NSRange) -> Edit? {
        change(text, selection: selection) { line in
            let read = read(line)
            let words = (line as NSString).substring(from: read.marker.length)
            if case .bullet = read.kind { return words }
            return "\(bullet) \(words)"
        }
    }

    /// The bar's heading button: plain, then #, ##, ###, then plain again.
    static func cycleHeading(_ text: String, selection: NSRange) -> Edit? {
        change(text, selection: selection) { line in
            let read = read(line)
            let words = (line as NSString).substring(from: read.marker.length)
            switch read.kind {
            case .heading(let level): return level >= 3 ? words : String(repeating: "#", count: level + 1) + " " + words
            case .plain, .bullet: return "# " + words
            }
        }
    }

    /// The bar's link button: the selected words become [words](https://), ready for the address.
    static func link(_ text: String, selection: NSRange) -> Edit? {
        let ns = text as NSString
        guard NSMaxRange(selection) <= ns.length else { return nil }
        let words = ns.substring(with: selection)
        let whole = "[\(words)](https://)"
        // With no words yet the caret waits between the brackets; otherwise at the end of the address.
        let caret = words.isEmpty ? selection.location + 1 : selection.location + (whole as NSString).length - 1
        return Edit(range: selection, replacement: whole, caret: caret)
    }

    // MARK: Private

    /// Rewrites each line the selection touches. Nil when nothing would change.
    private static func change(_ text: String, selection: NSRange, _ rewrite: (String) -> String) -> Edit? {
        let ns = text as NSString
        guard NSMaxRange(selection) <= ns.length else { return nil }
        var start = 0, contentsEnd = 0
        ns.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: selection)
        let block = NSRange(location: start, length: contentsEnd - start)
        let old = ns.substring(with: block)
        let lines = old.components(separatedBy: "\n")
        let new = lines.map(rewrite).joined(separator: "\n")
        guard new != old else { return nil }
        let grown = (new as NSString).length - (old as NSString).length
        // One line: the caret keeps its place among the words. Several: it goes to the end of them.
        let caret = lines.count == 1
            ? min(max(start, selection.location + grown), start + (new as NSString).length)
            : start + (new as NSString).length
        return Edit(range: block, replacement: new, caret: caret)
    }

    /// The line the caret is on, without its line break.
    private static func contents(of ns: NSString, at location: Int) -> NSRange {
        var start = 0, contentsEnd = 0
        ns.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: min(location, ns.length), length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    /// An indent with one level taken off: a tab, or two spaces.
    private static func outdented(_ indent: String) -> String {
        if indent.hasPrefix("\t") { return String(indent.dropFirst()) }
        if indent.hasPrefix("  ") { return String(indent.dropFirst(2)) }
        if indent.hasPrefix(" ") { return String(indent.dropFirst()) }
        return indent
    }
}
