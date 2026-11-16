import AVFoundation
import Synchronization

/// State shared between the decoder task, the main actor and the real-time render thread.
///
/// Rules for the render thread (`render`): no allocation, no Swift runtime locks it could wait
/// on, no actor hops. It only uses `Atomic`s and `Mutex.withLockIfAvailable`, so a producer
/// that's mid-write can never make it miss its deadline (it plays silence for that cycle).
nonisolated final class AudioCore: @unchecked Sendable {
    static let rate: Double = 44_100
    static let analysisLen = 512
    /// Interleaved stereo samples to hold before starting playback (0.5 s).
    static let prime = Int(rate)
    /// Back-pressure ceiling for the decoder (4 s).
    static let maxBuffered = Int(rate) * 2 * 4
    private static let capacity = Int(rate) * 2 * 6
    private static let maxFrames = 8192

    /// Bumped on every new stream; decoders exit when theirs is stale.
    private let generation = Atomic<UInt64>(0)
    /// True while real audio is reaching the speakers.
    private let primed = Atomic<Bool>(false)

    var currentGeneration: UInt64 { generation.load(ordering: .relaxed) }
    var isPrimed: Bool { primed.load(ordering: .relaxed) }

    /// Invalidate the current stream (its decoder stops) and drop buffered audio.
    @discardableResult
    func nextGeneration() -> UInt64 {
        let g = generation.add(1, ordering: .relaxed).newValue
        flush()
        return g
    }
    private let volumeBits = Atomic<UInt32>(Float(0.85).bitPattern)
    private let hissOn = Atomic<Bool>(false)
    private let burstFlag = Atomic<Bool>(false)

    private let ring = Mutex(Ring(capacity: capacity))
    private let analysis = Mutex(Analysis(len: analysisLen))

    // Render-thread-only state (never touched elsewhere).
    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames * 2)
    private let tap = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
    private var gain: Float = 0
    private var hissGain: Float = 0
    private var hissLP: Float = 0, hissHP: Float = 0
    private var burstEnv: Float = 0, burstLP: Float = 0, burstBP: Float = 0
    private var rng: UInt32 = 0x9E37_79B9
    private let burstDecay = Float(exp(log(0.0001) / (0.45 * rate)))

    deinit {
        scratch.deallocate()
        tap.deallocate()
    }

    var volume: Float {
        get { Float(bitPattern: volumeBits.load(ordering: .relaxed)) }
        set { volumeBits.store(min(1, max(0, newValue)).bitPattern, ordering: .relaxed) }
    }

    func setHiss(_ on: Bool) { hissOn.store(on, ordering: .relaxed) }
    func staticBurst() { burstFlag.store(true, ordering: .relaxed) }

    /// Samples currently buffered (interleaved).
    var buffered: Int { ring.withLock { $0.count } }

    func flush() {
        ring.withLock { $0.clear() }
        primed.store(false, ordering: .relaxed)
    }

    /// Producer side: append interleaved stereo samples. Returns how many were taken.
    @discardableResult
    func write(_ src: UnsafePointer<Float>, count: Int) -> Int {
        nonisolated(unsafe) let src = src
        return ring.withLock { $0.write(src, count) }
    }

    /// Copy the most recent mono samples (oldest first) for the spectrum analyser.
    func copyAnalysis(into out: UnsafeMutablePointer<Float>) {
        nonisolated(unsafe) let out = out
        analysis.withLock { $0.copy(into: out) }
    }

    /// A source node that pulls from the ring and mixes hiss and the static burst.
    func makeSourceNode() -> AVAudioSourceNode {
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 2)!
        return AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, abl -> OSStatus in
            self.render(frames: Int(frameCount), abl: UnsafeMutableAudioBufferListPointer(abl))
            return noErr
        }
    }

    @inline(__always)
    private func noise() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(rng) / Float(UInt32.max) * 2 - 1
    }

    private func render(frames: Int, abl: UnsafeMutableAudioBufferListPointer) {
        guard abl.count >= 2,
              let left = abl[0].mData?.assumingMemoryBound(to: Float.self),
              let right = abl[1].mData?.assumingMemoryBound(to: Float.self) else { return }
        let n = min(frames, Self.maxFrames)
        let target = volume
        if burstFlag.exchange(false, ordering: .relaxed) { burstEnv = 1 }

        // Pull stream audio, or silence while (re)buffering or if the producer holds the lock.
        let got = ring.withLockIfAvailable { r -> Int in
            var isPrimed = primed.load(ordering: .relaxed)
            if !isPrimed && r.count >= Self.prime {
                isPrimed = true
                primed.store(true, ordering: .relaxed)
            }
            guard isPrimed else { return 0 }
            let taken = r.read(into: scratch, n * 2) / 2
            if taken < n { primed.store(false, ordering: .relaxed) }
            return taken
        } ?? 0

        let hissTarget: Float = hissOn.load(ordering: .relaxed) && got > 0 ? 0.018 * target : 0
        for f in 0..<n {
            gain += (target - gain) * 0.002
            hissGain += (hissTarget - hissGain) * 0.0005
            let (l, r) = f < got ? (scratch[f * 2], scratch[f * 2 + 1]) : (0, 0)
            tap[f] = (l + r) * 0.5

            // Hiss: white noise, high-passed around 3.8 kHz and softened on top.
            let w = noise()
            hissHP += (w - hissHP) * 0.42
            hissLP += ((w - hissHP) - hissLP) * 0.8
            let hiss = hissLP * hissGain

            // Static burst: band-passed noise with a fast exponential decay.
            var burst: Float = 0
            if burstEnv > 0.0001 {
                let b = noise()
                burstLP += (b - burstLP) * 0.3
                burstBP += (burstLP - burstBP) * 0.1
                burst = (burstLP - burstBP) * burstEnv * 0.27 * target
                burstEnv *= burstDecay
            }
            left[f] = l * gain + hiss + burst
            right[f] = r * gain + hiss + burst
        }
        for f in n..<frames {
            left[f] = 0
            right[f] = 0
        }
        // The spectrum is cosmetic: skip this cycle rather than wait for the UI.
        _ = analysis.withLockIfAvailable { $0.push(tap, n) }
    }
}

/// Fixed-capacity FIFO of interleaved samples (accessed only under `AudioCore.ring`).
private nonisolated struct Ring: ~Copyable, @unchecked Sendable {
    private let buf: UnsafeMutablePointer<Float>
    private let cap: Int
    private var head = 0
    private(set) var count = 0

    init(capacity: Int) {
        cap = capacity
        buf = .allocate(capacity: capacity)
    }

    deinit { buf.deallocate() }

    mutating func clear() {
        head = 0
        count = 0
    }

    mutating func write(_ src: UnsafePointer<Float>, _ n: Int) -> Int {
        let n = min(n, cap - count)
        var tail = (head + count) % cap
        var done = 0
        while done < n {
            let chunk = min(n - done, cap - tail)
            (buf + tail).update(from: src + done, count: chunk)
            done += chunk
            tail = (tail + chunk) % cap
        }
        count += n
        return n
    }

    mutating func read(into dst: UnsafeMutablePointer<Float>, _ n: Int) -> Int {
        let n = min(n, count)
        var done = 0
        while done < n {
            let chunk = min(n - done, cap - head)
            (dst + done).update(from: buf + head, count: chunk)
            done += chunk
            head = (head + chunk) % cap
        }
        count -= n
        return n
    }
}

/// Rolling window of the last `len` mono samples that went to the speakers.
private nonisolated struct Analysis: ~Copyable, @unchecked Sendable {
    private let buf: UnsafeMutablePointer<Float>
    private let len: Int
    private var pos = 0

    init(len: Int) {
        self.len = len
        buf = .allocate(capacity: len)
        buf.initialize(repeating: 0, count: len)
    }

    deinit { buf.deallocate() }

    mutating func push(_ src: UnsafePointer<Float>, _ n: Int) {
        let start = max(0, n - len)
        for i in start..<n {
            buf[pos] = src[i]
            pos = (pos + 1) % len
        }
    }

    func copy(into out: UnsafeMutablePointer<Float>) {
        let first = len - pos
        out.update(from: buf + pos, count: first)
        (out + first).update(from: buf, count: pos)
    }
}
