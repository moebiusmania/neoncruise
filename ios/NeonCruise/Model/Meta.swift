import Foundation
import Observation

nonisolated struct Track: Equatable, Sendable {
    var title: String
    var artist: String
    /// Epoch ms when the track started, if known.
    var at: Double?
    var id: String?

    func same(as o: Track) -> Bool {
        if let a = id, let b = o.id, a == b { return true }
        return title.caseInsensitiveCompare(o.title) == .orderedSame
            && artist.caseInsensitiveCompare(o.artist) == .orderedSame
    }
}

/// Pure parsing helpers for the third-party feeds (kept free of I/O so they're testable).
nonisolated enum MetaParse {
    static let textMax = 300
    static let historyMax = 15

    /// Printable text only (no control or bidi-override characters), capped in length.
    static func clean(_ s: String) -> String {
        let bidi: ClosedRange<UInt32> = 0x202A...0x202E
        let isolates: ClosedRange<UInt32> = 0x2066...0x2069
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            if out.count >= textMax { break }
            if u.properties.generalCategory == .control || bidi.contains(u.value) || isolates.contains(u.value) { continue }
            out.append(u)
        }
        return String(out).trimmingCharacters(in: .whitespaces)
    }

    static func splitTitle(_ s: String) -> Track {
        if let r = s.range(of: " - "), r.lowerBound > s.startIndex {
            return Track(title: clean(String(s[r.upperBound...])), artist: clean(String(s[..<r.lowerBound])))
        }
        return Track(title: clean(s), artist: "")
    }

    /// Items from one SSE `data:` payload: `[{station,title,artist,track_id,at}]`.
    static func events(_ data: String) -> [(String, Track)] {
        guard let json = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [Any] else { return [] }
        return json.compactMap { item in
            guard let m = item as? [String: Any],
                  let station = m["station"] as? String, Stations.ids.contains(station)
            else { return nil }
            let title = clean(m["title"] as? String ?? "")
            let artist = clean(m["artist"] as? String ?? "")
            if title.isEmpty && artist.isEmpty { return nil }
            let at = (m["at"] as? NSNumber)?.doubleValue
            return (station, Track(title: title, artist: artist,
                                   at: at.flatMap { $0.isFinite ? $0 : nil },
                                   id: (m["track_id"] as? String).map(clean)))
        }
    }

    struct Status: Sendable {
        var listeners: [String: Int] = [:]
        var history: [String: [Track]] = [:]
        var tracks: [String: Track] = [:]
    }

    /// Icecast `status-json.xsl`: listener counts per station, plus seed history and tracks.
    static func status(_ data: Data) -> Status? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ice = json["icestats"] as? [String: Any] else { return nil }
        let sources: [[String: Any]] = (ice["source"] as? [[String: Any]])
            ?? ((ice["source"] as? [String: Any]).map { [$0] } ?? [])
        var out = Status()
        for src in sources {
            guard let url = src["listenurl"] as? String,
                  let file = url.split(separator: "/").last,
                  let dot = file.lastIndex(of: ".") else { continue }
            let id = String(file[..<dot]), ext = file[file.index(after: dot)...]
            guard Stations.ids.contains(id), ["mp3", "ogg", "m4a"].contains(ext) else { continue }
            let n = (src["listeners"] as? NSNumber)?.intValue ?? 0
            out.listeners[id, default: 0] += max(0, n)
            guard ext == "mp3" else { continue }
            let list = ((src["playlist"] as? [String: Any])?["trackList"] as? [[String: Any]] ?? [])
                .prefix(historyMax * 4)
                .map { splitTitle($0["title"] as? String ?? "") }
                .filter { !$0.title.isEmpty }
            if !list.isEmpty { out.history[id] = Array(list.reversed().prefix(historyMax)) }
            let title = clean(src["title"] as? String ?? ""), artist = clean(src["artist"] as? String ?? "")
            if !title.isEmpty || !artist.isEmpty {
                out.tracks[id] = artist.isEmpty ? splitTitle(title) : Track(title: title, artist: artist)
            }
        }
        return out
    }
}

/// Splits an SSE byte stream into events (spec-compliant: multi-line `data:`, blank-line
/// dispatch, CRLF, comments) with hard size limits so a broken feed can't exhaust memory.
nonisolated struct SSEParser {
    static let lineMax = 64 * 1024
    private var line: [UInt8] = []
    private var data = ""

    enum Failure: Error { case lineTooLong }

    /// Feed one byte; returns a complete event payload when one ends.
    mutating func feed(_ b: UInt8) throws -> String? {
        if b != 0x0A {
            if line.count >= Self.lineMax { throw Failure.lineTooLong }
            line.append(b)
            return nil
        }
        if line.last == 0x0D { line.removeLast() }
        defer { line.removeAll(keepingCapacity: true) }
        if line.isEmpty {
            guard !data.isEmpty else { return nil }
            defer { data = "" }
            return data
        }
        let s = String(decoding: line, as: UTF8.self)
        guard s.hasPrefix("data:") else { return nil }
        var d = s.dropFirst(5)
        if d.first == " " { d = d.dropFirst() }
        if data.count + d.count > Self.lineMax { throw Failure.lineTooLong }
        if !data.isEmpty { data += "\n" }
        data += d
        return nil
    }
}

/// Now-playing metadata for every station: the Nightride SSE feed plus Icecast status.
@Observable
final class MetaStore {
    private(set) var tracks: [String: Track] = [:]
    private(set) var history: [String: [Track]] = [:]
    private(set) var listeners: [String: Int] = [:]
    private(set) var online = false

    var totalListeners: Int { listeners.values.reduce(0, +) }

    private var sseTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var seeded = false

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpAdditionalHeaders = ["User-Agent": userAgent]
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    func start() {
        guard sseTask == nil else { return }
        sseTask = Task { [weak self] in await self?.runSSE() }
        resumePolling()
    }

    /// Listener counts are only shown on screen, so poll them only while the app is active.
    func resumePolling() {
        guard statusTask == nil else { return }
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                let ok = await self?.fetchStatus() ?? false
                let seeded = self?.seeded ?? true
                try? await Task.sleep(for: .seconds(ok || seeded ? 60 : 10))
            }
        }
    }

    func pausePolling() {
        statusTask?.cancel()
        statusTask = nil
    }

    private func push(_ station: String, _ t: Track) {
        if let cur = tracks[station], cur.same(as: t), cur.at != nil { return }
        tracks[station] = t
        var list = history[station, default: []].filter { !$0.same(as: t) }
        list.insert(t, at: 0)
        history[station] = Array(list.prefix(MetaParse.historyMax))
    }

    private func runSSE() async {
        var fails = 0
        while !Task.isCancelled {
            let started = Date()
            do {
                var req = URLRequest(url: Stations.metaURL)
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                // Idle timeout: reconnect if the feed goes completely silent (dead NAT, Wi-Fi switch).
                req.timeoutInterval = 300
                let (bytes, resp) = try await session.bytes(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                online = true
                var parser = SSEParser()
                for try await b in bytes {
                    if let payload = try parser.feed(b) {
                        for (station, t) in MetaParse.events(payload) { push(station, t) }
                    }
                }
            } catch {}
            online = false
            fails = Date().timeIntervalSince(started) > 60 ? 0 : fails + 1
            try? await Task.sleep(for: .seconds(min(60, 3 << min(fails, 4))))
        }
    }

    private func fetchStatus() async -> Bool {
        do {
            var req = URLRequest(url: Stations.statusURL)
            req.timeoutInterval = 20
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let s = MetaParse.status(data) else { return false }
            listeners = s.listeners
            if !seeded {
                seeded = true
                for (id, list) in s.history where history[id]?.isEmpty ?? true { history[id] = list }
                for (id, t) in s.tracks where tracks[id] == nil { tracks[id] = t }
            }
            return true
        } catch {
            return false
        }
    }
}
