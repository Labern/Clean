import Foundation
import SwiftData

// Every stored property has a default so the store can move to CloudKit
// later without a migration. Schema changes are additive only.

@Model final class Todo {
    var spineRaw: Int = 1
    var title: String = ""
    var tag: String = ""
    var done: Bool = false
    var created: Date = Date()
    var completed: Date? = nil

    init(spine: Spine, title: String, tag: String = "", done: Bool = false, created: Date = .now) {
        self.spineRaw = spine.rawValue
        self.title = title
        self.tag = tag
        self.done = done
        self.created = created
        self.completed = done ? created : nil
    }
}

@Model final class Deadline {
    var title: String = ""
    var symbol: String = "calendar"
    var date: Date = Date()
    var everyMonths: Int = 12

    init(title: String, symbol: String, date: Date, everyMonths: Int) {
        self.title = title
        self.symbol = symbol
        self.date = date
        self.everyMonths = everyMonths
    }
}

@Model final class Charge {
    var date: Date = Date()
    var kWh: Double = 0
    var pencePerKWh: Double = 0
    var place: String = ""

    var cost: Double { kWh * pencePerKWh / 100 }

    init(date: Date, kWh: Double, pencePerKWh: Double, place: String) {
        self.date = date
        self.kWh = kWh
        self.pencePerKWh = pencePerKWh
        self.place = place
    }
}

@Model final class Camera {
    var name: String = ""
    var battery: Double = 1
    var batteryChanged: Date = Date()
    var lastMotion: Date? = nil
    var order: Int = 0

    init(name: String, battery: Double, batteryChanged: Date, lastMotion: Date?, order: Int) {
        self.name = name
        self.battery = battery
        self.batteryChanged = batteryChanged
        self.lastMotion = lastMotion
        self.order = order
    }
}

@Model final class Pin {
    var title: String = ""
    var subtitle: String = ""
    var uri: String = ""
    var symbol: String = "music.note"
    var hue: Double = 0
    var isMood: Bool = false
    var order: Int = 0
    var lastOpened: Date? = nil

    init(title: String, subtitle: String, uri: String, symbol: String, hue: Double, isMood: Bool, order: Int) {
        self.title = title
        self.subtitle = subtitle
        self.uri = uri
        self.symbol = symbol
        self.hue = hue
        self.isMood = isMood
        self.order = order
    }
}

@Model final class Entry {
    var day: Date = Date()
    var text: String = ""
    var stars: Int = 0

    init(day: Date, text: String = "", stars: Int = 0) {
        self.day = day
        self.text = text
        self.stars = stars
    }
}
