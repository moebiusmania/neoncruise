import Foundation
import Testing
@testable import NeonCruise

@Suite struct SettingsTests {
    @Test func lenientDecodingFallsBackAndClamps() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"volume":7.5,"hiss":true,"scan":"yes"}"#.utf8))
        #expect(s.volume == 1)
        #expect(s.hiss && s.scan)
        #expect(s.station == "nightride")
    }

    @Test func roundTripsThroughDefaults() throws {
        let d = try #require(UserDefaults(suiteName: "neoncruise.tests"))
        d.removePersistentDomain(forName: "neoncruise.tests")
        var s = Settings()
        s.station = "ebsm"
        s.volume = 0.3
        SettingsStore.save(s, to: d)
        #expect(SettingsStore.load(from: d) == s)
    }
}

@Suite struct HelperTests {
    @Test func wrapsStationIndex() {
        #expect(Stations.wrap(-1) == Stations.all.count - 1)
        #expect(Stations.wrap(Stations.all.count) == 0)
    }

    @Test func formatsTime() {
        #expect(fmtTime(65.9) == "01:05")
        #expect(fmtTime(3725) == "1:02:05")
        #expect(fmtTime(-4) == "00:00")
    }

    @Test func hueTakesTheShortWayRound() {
        #expect(abs(Vis.approachHue(350, 10, 0.5) - 0) < 1e-9)
        #expect(unwrapHue(25, from: 350) == 385)
    }

    @Test func oklchMatchesTheWebAccent() {
        // oklch(0.74 0.19 350), the NIGHTRIDE accent: a pink around #ff6bb0.
        let c = RGB.oklch(0.74, 0.19, 350)
        #expect(c.r > 0.95 && c.g > 0.35 && c.g < 0.5 && c.b > 0.6 && c.b < 0.75)
    }
}

@Suite struct AudioCoreTests {
    @Test func generationsInvalidateAndFlush() {
        let core = AudioCore()
        var samples = [Float](repeating: 0.5, count: 1000)
        samples.withUnsafeBufferPointer { _ = core.write($0.baseAddress!, count: $0.count) }
        #expect(core.buffered == 1000)
        let g = core.nextGeneration()
        #expect(core.currentGeneration == g)
        #expect(core.buffered == 0)
        #expect(!core.isPrimed)
    }

    @Test func volumeIsClamped() {
        let core = AudioCore()
        core.volume = 3
        #expect(core.volume == 1)
        core.volume = -1
        #expect(core.volume == 0)
    }
}
