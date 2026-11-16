import Foundation
import Testing
@testable import NeonCruise

@Suite struct MetaParseTests {
    @Test func cleanStripsControlAndBidiAndCaps() {
        #expect(MetaParse.clean(" a\u{1b}]52;c;x\u{07}b\u{202e}c\u{9b} ") == "a]52;c;xbc")
        #expect(MetaParse.clean(String(repeating: "x", count: 1000)).count == MetaParse.textMax)
    }

    @Test func splitsArtistAndTitle() {
        let t = MetaParse.splitTitle("Artist - Song - Remix")
        #expect(t.artist == "Artist" && t.title == "Song - Remix")
        #expect(MetaParse.splitTitle("Just a title").artist.isEmpty)
    }

    @Test func eventsKeepKnownStationsAndValidFields() {
        let json = #"[{"station":"nightride","title":"T","artist":"A","at":5,"track_id":"x"},{"station":"nope","title":"X"},{"station":"ebsm","title":42,"artist":""},"junk"]"#
        let ev = MetaParse.events(json)
        #expect(ev.count == 1)
        #expect(ev[0].0 == "nightride")
        #expect(ev[0].1 == Track(title: "T", artist: "A", at: 5, id: "x"))
        #expect(MetaParse.events("not json").isEmpty)
    }

    @Test func statusParsesListenersHistoryAndTracks() throws {
        let json = #"{"icestats":{"source":[{"listenurl":"https://s/nightride.mp3","listeners":7,"title":"Song","artist":"Band","playlist":{"trackList":[{"title":"A - One"},{"title":"B - Two"}]}},{"listenurl":"https://s/nightride.ogg","listeners":3},{"listenurl":"https://s/other.mp3","listeners":99}]}}"#
        let s = try #require(MetaParse.status(Data(json.utf8)))
        #expect(s.listeners == ["nightride": 10])
        #expect(s.history["nightride"]?.map(\.title) == ["Two", "One"])
        #expect(s.tracks["nightride"] == Track(title: "Song", artist: "Band"))
    }

    @Test func trackIdentity() {
        #expect(Track(title: "a", artist: "b", id: "1").same(as: Track(title: "x", artist: "y", id: "1")))
        #expect(Track(title: "Song", artist: "Band").same(as: Track(title: "SONG", artist: "band")))
        #expect(!Track(title: "Song", artist: "Band").same(as: Track(title: "Other", artist: "Band")))
    }
}

@Suite struct SSEParserTests {
    private func feed(_ s: String) throws -> [String] {
        var p = SSEParser()
        return try s.utf8.compactMap { try p.feed($0) }
    }

    @Test func dispatchesOnBlankLinesAndJoinsMultilineData() throws {
        #expect(try feed("data: one\n\n: comment\ndata: a\r\ndata: b\r\n\r\nevent: x\n\n") == ["one", "a\nb"])
    }

    @Test func rejectsEndlessLines() {
        #expect(throws: SSEParser.Failure.self) {
            _ = try feed("data: " + String(repeating: "x", count: SSEParser.lineMax + 10))
        }
    }
}
