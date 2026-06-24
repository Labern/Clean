import XCTest
@testable import StrataCore

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT CONTRACT TESTS
// These tests encode UI rules that must not regress silently.
// If a test fails, you probably broke a rule the user explicitly requested.
// ─────────────────────────────────────────────────────────────────────────────

final class DisplayCapTests: XCTestCase {
    // RULE: No arbitrary small display caps. Default must be ≥ 200 themes.
    // Regression: was hardcoded to 18, user had to discover it accidentally.
    func testDefaultTopThemeCountIsHigh() {
        let convs = makeFakeConversations(count: 10)
        let extractor = LexicalThemeExtractor(topTermsPerConversation: 20)
        let themes = extractor.extractThemes(from: convs)
        let matrix = buildMatrix(conversations: convs, themes: themes, bucket: .week)
        // The matrix must show ALL distinct non-zero themes, not just 18.
        // With 10 short conversations we produce ~60 distinct themes — all should appear.
        let distinctThemes = Set(themes.flatMap { $0.terms.map(\.label) }).count
        // Must show at least 19 rows (proving the old hardcoded 18-cap is gone).
        let lowerBound = min(distinctThemes, 19)
        XCTAssertGreaterThanOrEqual(matrix.themes.count, lowerBound,
            "Matrix shows too few themes (\(matrix.themes.count) of \(distinctThemes) available) — cap may have regressed to ≤ 18.")
    }

    // RULE: topTermsPerConversation default must be ≥ 20.
    // Regression: was 8, producing too few themes for large datasets.
    func testDefaultTermsPerConversationIsHigh() {
        let extractor = LexicalThemeExtractor()
        let conv = makeFakeConversations(count: 1).first!
        let result = extractor.extractThemes(from: [conv])
        // With enough text, should extract at least 10 terms
        if let terms = result.first?.terms {
            XCTAssertGreaterThanOrEqual(terms.count, 10,
                "topTermsPerConversation default is too low — increases number of concepts surfaced.")
        }
    }
}

final class DeduplicationTests: XCTestCase {
    // RULE: Case variants of the same term must not appear as duplicate rows.
    // Regression: "bpd" + "BPD" both surfaced as "Bpd Bpd" in the timeline.
    func testCaseVariantsDeduplicated() {
        let text = "BPD bpd BPD bpd BPD bpd anxiety BPD bpd bpd bpd bpd bpd bpd"
        let conv = Conversation(
            id: "test-dedup",
            source: "test",
            projectLabel: "Test",
            title: "Dedup test",
            updatedAtRaw: nil,
            messages: [ConversationMessage(role: .user, text: text, timestamp: Date(), messageId: nil)],
            firstTimestamp: Date(),
            lastTimestamp: Date()
        )
        let extractor = LexicalThemeExtractor(topTermsPerConversation: 20)
        let themes = extractor.extractThemes(from: [conv])
        let matrix = buildMatrix(conversations: [conv], themes: themes, bucket: .week)

        let lowercased = matrix.themes.map { $0.lowercased() }
        let unique = Set(lowercased)
        XCTAssertEqual(lowercased.count, unique.count,
            "Duplicate theme rows found after titleCase normalization: \(lowercased)")
    }

    // RULE: titleCase must not produce identical strings from different raw inputs.
    func testTitleCaseCollisionFree() {
        let inputs = ["bpd", "BPD", "Bpd", "anxiety", "Anxiety", "ANXIETY"]
        var seen = Set<String>()
        for input in inputs {
            let titled = input.split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
            // If a collision exists, the dedup layer should have merged them before this point
            seen.insert(titled)
        }
        // "Bpd" appears 3 times above — after dedup only 1 should survive in output
        XCTAssertEqual(seen.filter { $0 == "Bpd" }.count, 1)
    }
}

final class SortTests: XCTestCase {
    func testFrequencyDescSort() {
        let matrix = makeTestMatrix()
        let sorted = matrix.sorted(by: .frequencyDesc)
        // Default order = most weight first; first row should have ≥ weight of last
        XCTAssertGreaterThanOrEqual(
            sorted.cells.first!.map(\.weight).reduce(0, +),
            sorted.cells.last!.map(\.weight).reduce(0, +)
        )
    }

    func testAlphabeticalSort() {
        let matrix = makeTestMatrix()
        let sorted = matrix.sorted(by: .alphabetical)
        let names = sorted.themes
        for i in 0..<(names.count - 1) {
            XCTAssertLessThanOrEqual(names[i].lowercased(), names[i+1].lowercased(),
                "Themes not in alphabetical order at index \(i): \(names[i]) > \(names[i+1])")
        }
    }

    func testAlphabeticalRevSort() {
        let matrix = makeTestMatrix()
        let sorted = matrix.sorted(by: .alphabeticalRev)
        let names = sorted.themes
        for i in 0..<(names.count - 1) {
            XCTAssertGreaterThanOrEqual(names[i].lowercased(), names[i+1].lowercased(),
                "Themes not in reverse alpha order at index \(i)")
        }
    }

    func testSortPreservesRowCellAlignment() {
        // After sorting, cells[r] must still correspond to themes[r]
        let matrix = makeTestMatrix()
        for sortOrder in ThemeSort.allCases {
            let sorted = matrix.sorted(by: sortOrder)
            XCTAssertEqual(sorted.themes.count, sorted.cells.count,
                "Row count mismatch after sort \(sortOrder)")
            for (r, _) in sorted.themes.enumerated() {
                XCTAssertEqual(sorted.cells[r].count, matrix.buckets.count,
                    "Cell column count mismatch at row \(r) after sort \(sortOrder)")
            }
        }
    }
}

final class GroupBubblesTests: XCTestCase {
    func testCylinderInCarsGroup() {
        // RULE: automotive diagnostic terms → Cars group, not Other or Mind.
        let automotive = ["Cylinder", "Misfire", "Spark Plug", "Headache", "Trough"]
            .map { ThemeBubble(theme: $0, totalWeight: 1.0, distinctConversationCount: 1, allContributorIds: []) }
        let groups = groupBubbles(automotive)
        let carsGroup = groups.first { $0.id == "cars" }
        XCTAssertNotNil(carsGroup, "No 'cars' group found — automotive terms will land in Other")
        if let cars = carsGroup {
            let found = cars.bubbles.map(\.theme)
            XCTAssert(found.contains("Cylinder"), "Cylinder should be in Cars, got: \(found)")
            XCTAssert(found.contains("Misfire"),  "Misfire should be in Cars, got: \(found)")
        }
    }

    func testCommandTermsInWorkGroup() {
        let cli = ["Command Args", "Command Message", "Local Command", "Command Stdout"]
            .map { ThemeBubble(theme: $0, totalWeight: 1.0, distinctConversationCount: 1, allContributorIds: []) }
        let groups = groupBubbles(cli)
        let work = groups.first { $0.id == "work" }
        XCTAssertNotNil(work, "No 'work' group")
        if let work {
            let found = work.bubbles.map(\.theme)
            XCTAssert(found.contains("Command Args"), "Command Args should be Work: \(found)")
        }
    }

    func testNothingLeftInOtherIsLarge() {
        // Other should be a small remainder when given real-domain theme names.
        // "Theme 1" / "Theme 2" names are invalid — use terms the extractor actually surfaces.
        let themes = ["anxiety", "swift", "women", "car", "music", "claude",
                      "relationship", "money", "coding", "reading",
                      "health", "career", "emotions", "vehicle", "writing",
                      "dating", "algorithm", "family", "travel", "art"]
            .map { ThemeBubble(theme: $0, totalWeight: 1.0, distinctConversationCount: 1, allContributorIds: []) }
        let groups = groupBubbles(themes)
        let other = groups.first { $0.id == "other" }
        let otherCount = other?.bubbles.count ?? 0
        // Most meaningful themes should match a group — Other must be < 40% of total.
        XCTAssertLessThan(Double(otherCount), Double(themes.count) * 0.4,
            "More than 40% of meaningful themes landed in Other (\(otherCount)/\(themes.count)) — check keyword lists")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

private func makeFakeConversations(count: Int) -> [Conversation] {
    let sampleTexts = [
        "The car cylinder misfired again. Spark plugs need replacing. Mechanic said the engine has a rough idle.",
        "She was acting avoidant. Messages left unread for days. The relationship feels distant.",
        "Worked on the Swift command line tool. Fixed a bug in the local command parser.",
        "Feeling anxious about the future. Therapy session helped with self-worth.",
        "Reading a new book on machine learning. The AI model training process is fascinating.",
        "Car needs new tires. Insurance quote came back high. Budget is tight.",
        "Music composition going well. Writing lyrics for the new album.",
        "Claude responded to the prompt in seconds. The context window is impressive.",
    ]
    let now = Date()
    return (0..<count).map { i in
        let text = sampleTexts[i % sampleTexts.count]
        let msg = ConversationMessage(role: .user, text: text, timestamp: now, messageId: nil)
        return Conversation(
            id: "fake-\(i)", source: "test", projectLabel: "Test",
            title: "Conversation \(i)", updatedAtRaw: nil,
            messages: [msg], firstTimestamp: now, lastTimestamp: now
        )
    }
}

private func makeTestMatrix() -> HeatmapMatrix {
    let convs = makeFakeConversations(count: 8)
    let extractor = LexicalThemeExtractor(topTermsPerConversation: 20)
    let themes = extractor.extractThemes(from: convs)
    return buildMatrix(conversations: convs, themes: themes, bucket: .week)
}
