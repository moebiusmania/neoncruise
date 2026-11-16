import AVFoundation
import MediaPlayer
import Observation
import UIKit

enum PlayStatus: Equatable {
    case idle, loading, playing, paused, error
}

/// Transport, retries, sleep timer, audio session and lock-screen integration
/// (mirrors `src/lib/player.ts` and the TUI's `app.rs`).
@Observable
final class Player {
    private(set) var stationIdx: Int
    private(set) var status: PlayStatus = .idle
    /// What the user asked for; `status` is what the stream is actually doing.
    private(set) var wantPlay = false
    private(set) var sleepEnd: Date?
    private(set) var sleepMin = 0
    /// Last tape change, drives the static burst overlay and the deck slide-in.
    private(set) var burstAt: Date?
    /// Wall clock for on-screen timers, ticked once a second while the app is visible.
    private(set) var now = Date()

    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            applyVolume()
            scheduleSave()
        }
    }

    var station: Station { Stations.all[stationIdx] }
    let meta: MetaStore
    @ObservationIgnored let vis: Vis
    @ObservationIgnored let core = AudioCore()

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var source: AVAudioSourceNode?
    @ObservationIgnored private var decodeTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var loadingSince = Date()
    @ObservationIgnored private var fade = 1.0
    @ObservationIgnored private var lastVolume = 0.85
    @ObservationIgnored private var visible = true
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private static let fadeSecs = 12.0
    static let sleepOptions = [0, 15, 30, 60, 90]

    @ObservationIgnored private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: c)
    }()

    init(meta: MetaStore) {
        let s = SettingsStore.load()
        settings = s
        self.meta = meta
        stationIdx = Stations.index(of: s.station) ?? 0
        vis = Vis(hue: Stations.all[Stations.index(of: s.station) ?? 0].hue)
        lastVolume = s.volume > 0 ? s.volume : 0.85
        setUpEngine()
        setUpRemoteCommands()
        observeSession()
        applyVolume()
        observeTrack()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /* ---------------------------------------------------------------- engine */

    private func setUpEngine() {
        let node = core.makeSourceNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: node.outputFormat(forBus: 0))
        engine.prepare()
        source = node
    }

    private func startEngine() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try s.setActive(true)
            if !engine.isRunning { try engine.start() }
        } catch {
            print("[neoncruise] audio start failed: \(error)")
        }
    }

    /* ---------------------------------------------------------------- transport */

    private func startStream() {
        loadingSince = Date()
        decodeTask?.cancel()
        let generation = core.nextGeneration()
        let url = Stations.streamURL(station.id)
        let decoder = StreamDecoder(core: core, generation: generation)
        let session = session
        decodeTask = Task { [weak self] in
            // Errors and clean ends both mean "reconnect" unless a newer stream took over.
            try? await Self.decode(decoder, url: url, session: session)
            guard let self, !Task.isCancelled, self.core.currentGeneration == generation else { return }
            self.streamFailed()
        }
    }

    /// Off the main actor: parsing and decoding run on the cooperative pool.
    @concurrent
    private nonisolated static func decode(_ decoder: StreamDecoder, url: URL, session: URLSession) async throws {
        try await decoder.run(url: url, session: session)
    }

    func play() {
        retryTask?.cancel()
        retries = 0
        fade = 1
        applyVolume()
        wantPlay = true
        status = .loading
        startEngine()
        startStream()
        updateNowPlaying()
    }

    func pause() {
        retryTask?.cancel()
        decodeTask?.cancel()
        wantPlay = false
        status = .paused
        // Drop the live buffer so resuming jumps back to "now" instead of stale audio.
        core.nextGeneration()
        engine.pause()
        updateNowPlaying()
    }

    func togglePlay() { wantPlay ? pause() : play() }

    private func setStation(_ i: Int) {
        stationIdx = i
        settings.station = Stations.all[i].id
        burstAt = Date()
    }

    func tune(_ i: Int) {
        let next = Stations.wrap(i)
        if next == stationIdx && wantPlay { return }
        setStation(next)
        if wantPlay {
            core.staticBurst()
            play()
        } else {
            updateNowPlaying()
        }
    }

    func tuneBy(_ d: Int) { tune(stationIdx + d) }

    /// Change tape and start playing it.
    func insert(_ i: Int) {
        let next = Stations.wrap(i)
        if next != stationIdx {
            setStation(next)
            core.staticBurst()
        }
        play()
    }

    private func streamFailed() {
        guard wantPlay else { return }
        scheduleRetry()
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        if retries >= 6 {
            status = .error
            wantPlay = false
            core.nextGeneration()
            engine.pause()
            updateNowPlaying()
            return
        }
        status = .loading
        let delay = min(8.0, 0.6 * pow(2, Double(retries)))
        retries += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.wantPlay else { return }
            self.startStream()
        }
    }

    /* ---------------------------------------------------------------- settings */

    func setVolume(_ v: Double) { settings.volume = (min(1, max(0, v)) * 100).rounded() / 100 }

    func toggleMute() {
        let v = settings.volume
        if v > 0 { lastVolume = v }
        setVolume(v > 0 ? 0 : lastVolume)
    }

    func setSleep(_ min: Int) {
        sleepMin = min
        sleepEnd = min > 0 ? Date().addingTimeInterval(Double(min) * 60) : nil
        fade = 1
        applyVolume()
    }

    private func applyVolume() {
        core.volume = Float(settings.volume * fade)
        core.setHiss(settings.hiss && status == .playing)
    }

    /// UserDefaults writes are cheap but not free; coalesce slider drags.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            SettingsStore.save(self.settings)
        }
    }

    func flushSettings() {
        saveTask?.cancel()
        SettingsStore.save(settings)
    }

    /* ---------------------------------------------------------------- per tick */

    private func tick() {
        let t = Date()
        if visible { now = t }

        if wantPlay {
            if core.isPrimed {
                if status != .playing {
                    #if DEBUG
                    print("[neoncruise] playing \(station.id) after \(String(format: "%.1f", t.timeIntervalSince(loadingSince)))s")
                    #endif
                    status = .playing
                    retries = 0
                    applyVolume()
                    updateNowPlaying()
                }
            } else if status == .playing {
                status = .loading
                loadingSince = t
                applyVolume()
            } else if status == .loading, retryTask == nil || retryTask!.isCancelled,
                      t.timeIntervalSince(loadingSince) > 20 {
                // Stalled without an error: reconnect.
                scheduleRetry()
            }
        }

        if let end = sleepEnd {
            let left = end.timeIntervalSince(t)
            if left <= 0 {
                pause()
                setSleep(0)
            } else if left < Self.fadeSecs && wantPlay {
                fade = left / Self.fadeSecs
                applyVolume()
            }
        }
    }

    /// The app moved between foreground and background.
    func setVisible(_ on: Bool) {
        visible = on
        if on { now = Date() }
        if on { meta.resumePolling() } else { meta.pausePolling(); flushSettings() }
    }

    /* ---------------------------------------------------------------- system integration */

    private func observeSession() {
        let nc = NotificationCenter.default
        let s = AVAudioSession.sharedInstance()
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: s, queue: .main) { [weak self] n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let opts = (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            MainActor.assumeIsolated {
                guard let self else { return }
                if type == .began, self.wantPlay {
                    self.pause()
                    self.resumeAfterInterruption = true
                } else if type == .ended, self.resumeAfterInterruption {
                    self.resumeAfterInterruption = false
                    if opts?.contains(.shouldResume) == true { self.play() }
                }
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: s, queue: .main) { [weak self] n in
            let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated {
                // Headphones unplugged: pause instead of blasting the speaker.
                if reason == .oldDeviceUnavailable, self?.wantPlay == true { self?.pause() }
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: s, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildEngine() }
        })
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.wantPlay else { return }
                self.startEngine()
            }
        })
    }

    @ObservationIgnored private var resumeAfterInterruption = false

    private func rebuildEngine() {
        let was = wantPlay
        engine.stop()
        if let source { engine.detach(source) }
        setUpEngine()
        if was { play() }
    }

    private func setUpRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.play() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlay() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.tuneBy(1) }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.tuneBy(-1) }
            return .success
        }
        c.stopCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
    }

    /// Keep the lock screen in sync with track changes, also while backgrounded (where
    /// SwiftUI's `onChange` wouldn't run).
    private func observeTrack() {
        withObservationTracking {
            _ = meta.tracks[station.id]
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateNowPlaying()
                self?.observeTrack()
            }
        }
    }

    @ObservationIgnored private lazy var artwork: MPMediaItemArtwork? = {
        guard let img = UIImage(named: "NowPlayingArtwork") else { return nil }
        return MPMediaItemArtwork(boundsSize: img.size) { _ in img }
    }()

    /// Lock screen / Control Center info for the current station and track.
    func updateNowPlaying() {
        let st = station
        let t = meta.tracks[st.id]
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? "\(st.name) FM",
            MPMediaItemPropertyArtist: t.map(\.artist).flatMap { $0.isEmpty ? nil : $0 } ?? st.tag,
            MPMediaItemPropertyAlbumTitle: "\(st.name) · Nightride FM",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: status == .playing ? 1.0 : 0.0,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = wantPlay ? .playing : (status == .idle ? .stopped : .paused)
    }

    /* ---------------------------------------------------------------- labels */

    var statusLabel: String {
        switch status {
        case .loading: "TUNING"
        case .error: "NO SIGNAL"
        case .playing:
            if let end = sleepEnd { "SLEEP \(max(1, Int(ceil(end.timeIntervalSince(now) / 60))))M" } else { "ON AIR" }
        case .idle: "STANDBY"
        case .paused: "PAUSED"
        }
    }
}

func fmtTime(_ secs: Double) -> String {
    let s = max(0, Int(secs))
    let h = s / 3600, m = (s % 3600) / 60, ss = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, ss) : String(format: "%02d:%02d", m, ss)
}
