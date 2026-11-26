import Foundation
import SwiftData

/// The first real contents of My list and the notebook, added once.
/// Anything with the same title already there is left alone.
enum Starter {
    static let key = "starter-1"

    static let todos: [(String, [String])] = [
        ("Stripe setup", ["Paste the live key into PARADOX", "Turn on Apple Pay, Google Pay and Link",
                          "Test a £1 payment end to end", "Check the first payout lands"]),
        ("Hire people", ["Write the first role: Swift developer", "Decide contract or employee",
                         "Post it", "Shortlist five", "First calls"]),
        ("Study Unreal", ["Install Unreal Engine 5", "Blueprints: the basics", "Build the third-person template",
                          "Materials and lighting", "Package a build for the Mac"]),
        ("Create a game in Unreal", ["One-page idea", "Greybox the first level", "Core loop playable",
                                     "Art pass", "Show five people"]),
        ("Sort the Apple Developer account", ["Use an Apple Account that isn't managed by Business Manager",
                                              "Enrol as the organisation with the same D-U-N-S",
                                              "Ask Apple Developer Support if it still refuses"]),
        ("Turn on PARADOX backups", ["Company › Backup › choose a folder in iCloud Drive"]),
        ("Focus launch", ["Final pass on the site", "Launch film", "Post it everywhere"]),
        ("Year-end accounts", ["Book the accountant", "Gather receipts", "File with Companies House"]),
    ]

    /// (text, filed under the project with this feed id)
    static let notes: [(String, String?)] = [
        ("Focus launch plan\nSite first, then the film, then the post. Keep the launch to one day and one message: it gets you out of your own way.", "focus"),
        ("Focus pricing\nAnnual reads best next to monthly. Round prices only, fives and noughts. Keep the anchor struck through beside the real price.", "focus"),
        ("Unreal learning plan\nWeek 1: editor and Blueprints. Week 2: the third-person template, taken apart. Week 3: materials and light. Week 4: package a build.", nil),
        ("Game idea\nSmall, finishable, one mechanic done beautifully. Hit stop on every impact.", nil),
        ("Hiring: first role\nSwift developer who cares about polish. Paid trial project first. Look for taste before speed.", nil),
        ("Stripe checklist\nLive key into PARADOX. Wallets on. Webhook to the site. A real £1 payment, refunded. Payout date known.", "company"),
        ("Apple Developer account\nBusiness Manager accounts are managed and can't join the Developer Program. Enrol the organisation with an ordinary Apple Account and the same D-U-N-S.", "company"),
        ("Ideas for PARADOX\nA board of the whole company on one screen. Links to everything. Backups to iCloud Drive. Icons in the style of the hoodie.", "hq"),
    ]

    @MainActor
    static func run(_ context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        let mine = Seed.personal(context)
        let have = Set(mine.items.map { $0.title.lowercased() })
        var order = mine.nextOrder
        for (title, subs) in todos where !have.contains(title.lowercased()) {
            let item = FocusItem(title: title, order: order)
            context.insert(item)
            item.project = mine
            item.collapsed = true
            for sub in subs { _ = item.add(sub, in: context) }
            item.collapsed = true
            order += 1
        }
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let written = Set(((try? context.fetch(FetchDescriptor<Note>())) ?? []).map { NoteText.title($0.text).lowercased() })
        for (index, (text, owner)) in notes.enumerated() where !written.contains(NoteText.title(text).lowercased()) {
            let made = Date.now.addingTimeInterval(-Double(index) * 3600 * 5)
            let note = Note(text: text, project: owner.flatMap { id in projects.first { $0.remoteID == id } }, created: made)
            context.insert(note)
        }
        try? context.save()
        defaults.set(true, forKey: key)
    }
}
