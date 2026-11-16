import Foundation

/// One Nightride FM station and its colour world (mirrors `src/lib/stations.ts`).
nonisolated struct Station: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let tag: String
    /// Base oklch hue for the station's colour world.
    let hue: Double
}

nonisolated enum Stations {
    static let all: [Station] = [
        Station(id: "nightride", name: "NIGHTRIDE", tag: "Synthwave · Retrowave · Outrun", hue: 350),
        Station(id: "chillsynth", name: "CHILLSYNTH", tag: "Chillsynth · Chillwave · Instrumental", hue: 195),
        Station(id: "datawave", name: "DATAWAVE", tag: "Glitchy Synthwave · IDM · Retro Computing", hue: 150),
        Station(id: "spacesynth", name: "SPACESYNTH", tag: "Spacesynth · Space Disco · Vocoder Italo", hue: 255),
        Station(id: "darksynth", name: "DARKSYNTH", tag: "Darksynth · Cyberpunk · Synthmetal", hue: 25),
        Station(id: "horrorsynth", name: "HORRORSYNTH", tag: "Horrorsynth · Witch House", hue: 305),
        Station(id: "ebsm", name: "EBSM", tag: "EBSM · Industrial · Clubbing", hue: 75),
    ]

    static let ids: Set<String> = Set(all.map(\.id))

    nonisolated static let streamHost = URL(string: "https://stream.nightride.fm")!
    nonisolated static let metaURL = URL(string: "https://nightride.fm/meta")!
    nonisolated static let statusURL = URL(string: "https://stream.nightride.fm/status-json.xsl")!

    nonisolated static func streamURL(_ id: String) -> URL {
        streamHost.appendingPathComponent("\(id).mp3")
    }

    static var total: String { String(format: "%02d", all.count) }
    static func tapeNum(_ i: Int) -> String { String(format: "%02d", i + 1) }
    static func tapeCode(_ i: Int) -> String { "NRF-0\(i + 1)" }

    static func wrap(_ i: Int) -> Int {
        let n = all.count
        return ((i % n) + n) % n
    }

    static func index(of id: String) -> Int? { all.firstIndex { $0.id == id } }
}

/// Identifies the app to Nightride's servers.
nonisolated let userAgent: String = {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    return "NeonCruise-iOS/\(v)"
}()
