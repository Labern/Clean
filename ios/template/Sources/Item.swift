import Foundation
import SwiftData

/// Additive-only schema: add properties with defaults, never rename or remove.
/// A user's data must survive every update.
@Model
final class Item {
    var title: String = ""
    var done: Bool = false
    var created: Date = Date.now

    init(title: String, done: Bool = false, created: Date = .now) {
        self.title = title
        self.done = done
        self.created = created
    }
}
