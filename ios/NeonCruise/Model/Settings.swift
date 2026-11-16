import Foundation

/// Persisted user preferences (mirrors `src/lib/settings.ts`).
nonisolated struct Settings: Codable, Equatable, Sendable {
    var station = "nightride"
    var volume = 0.85
    var scan = true
    var flicker = true
    var noise = true
    /// Drive the grid and spectrum from the real audio instead of a simulated beat.
    var reactive = true
    /// Mix a faint analog tape hiss over the stream.
    var hiss = false

    init() {}

    /// Decodes leniently: any missing or mistyped key falls back to its default, and the
    /// volume is clamped, so a corrupted value can never break playback.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        func get<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback
        }
        station = get(.station, d.station)
        let v = get(.volume, d.volume)
        volume = v.isFinite ? min(1, max(0, v)) : d.volume
        scan = get(.scan, d.scan)
        flicker = get(.flicker, d.flicker)
        noise = get(.noise, d.noise)
        reactive = get(.reactive, d.reactive)
        hiss = get(.hiss, d.hiss)
    }
}

nonisolated enum SettingsStore {
    private static let key = "neoncruise.settings.v1"

    static func load(from defaults: UserDefaults = .standard) -> Settings {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return s
    }

    static func save(_ s: Settings, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: key) }
    }
}
