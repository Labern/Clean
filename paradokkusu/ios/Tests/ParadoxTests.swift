import Testing
import Foundation
@testable import Paradox

@Suite("Spotify links")
struct SpotifyLinkTests {
    @Test func parsesShareLink() {
        let link = "https://open.spotify.com/intl-en/album/1weenld61qoidwYuZ1GESA?si=abc123"
        #expect(SpotifyLink.uri(from: link) == "spotify:album:1weenld61qoidwYuZ1GESA")
    }

    @Test func keepsAURIAsIs() {
        #expect(SpotifyLink.uri(from: "spotify:playlist:37i9dQZF1DX0XUsuxWHRQd") == "spotify:playlist:37i9dQZF1DX0XUsuxWHRQd")
    }

    @Test func rejectsOtherSites() {
        #expect(SpotifyLink.uri(from: "https://example.com/album/abc") == nil)
        #expect(SpotifyLink.uri(from: "https://open.spotify.com/user/abc") == nil)
    }

    @Test func webFallback() {
        #expect(SpotifyLink.web("spotify:album:xyz") == "https://open.spotify.com/album/xyz")
        #expect(SpotifyLink.web("spotify:search:kind%20of%20blue") == "https://open.spotify.com/search/kind%20of%20blue")
    }

    @Test func kinds() {
        #expect(SpotifyLink.kind(of: "spotify:album:xyz") == "Album")
        #expect(SpotifyLink.kind(of: "spotify:search:jazz") == "Search")
    }
}

@Suite("Days")
struct DaysTests {
    @Test func shortLabels() {
        #expect(Days.short(0) == "Today")
        #expect(Days.short(12) == "12d")
        #expect(Days.short(-3) == "3d late")
    }

    @Test func phrases() {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now)!
        let later = cal.date(byAdding: .day, value: 23, to: .now)!
        #expect(Days.phrase("MOT", tomorrow) == "MOT tomorrow")
        #expect(Days.phrase("MOT", later) == "MOT in 23 days")
    }
}

@Suite("Charging")
struct ChargeTests {
    @Test func costInPounds() {
        let charge = Charge(date: .now, kWh: 40, pencePerKWh: 7.5, place: "Home")
        #expect(abs(charge.cost - 3.0) < 0.0001)
    }
}

@Suite("Ago")
struct AgoTests {
    @Test func compact() {
        let now = Date()
        #expect(Ago.short(now.addingTimeInterval(-30), from: now) == "now")
        #expect(Ago.short(now.addingTimeInterval(-48 * 60), from: now) == "48m")
        #expect(Ago.short(now.addingTimeInterval(-2 * 3600), from: now) == "2h")
        #expect(Ago.short(now.addingTimeInterval(-3 * 86_400), from: now) == "3d")
    }
}
