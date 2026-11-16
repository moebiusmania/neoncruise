import AudioToolbox
import AVFoundation

/// Streams one MP3 URL: bytes → `AudioFileStream` (packet parsing) → `AVAudioConverter`
/// (MP3 → 44.1 kHz stereo float) → `AudioCore`'s ring buffer, with back-pressure.
nonisolated final class StreamDecoder: @unchecked Sendable {
    enum Failure: Error { case http(Int), parser(OSStatus), converter }

    private let core: AudioCore
    private let generation: UInt64
    private var stream: AudioFileStreamID?
    private var inFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var maxPacketSize: UInt32 = 2048
    private let outFormat = AVAudioFormat(standardFormatWithSampleRate: AudioCore.rate, channels: 2)!
    private let interleaved = UnsafeMutablePointer<Float>.allocate(capacity: 65_536)
    private var failure: Error?

    init(core: AudioCore, generation: UInt64) {
        self.core = core
        self.generation = generation
    }

    deinit {
        if let stream { AudioFileStreamClose(stream) }
        interleaved.deallocate()
    }

    private var live: Bool { core.currentGeneration == generation }

    /// Runs until the stream ends, fails, the task is cancelled or a newer stream takes over.
    func run(url: URL, session: URLSession) async throws {
        let me = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioFileStreamOpen(me, { client, _, prop, _ in
            Unmanaged<StreamDecoder>.fromOpaque(client).takeUnretainedValue().onProperty(prop)
        }, { client, bytes, packets, data, descs in
            Unmanaged<StreamDecoder>.fromOpaque(client).takeUnretainedValue()
                .onPackets(bytes: bytes, packets: packets, data: data, descs: descs)
        }, kAudioFileMP3Type, &stream)
        guard status == noErr, let stream else { throw Failure.parser(status) }

        var req = URLRequest(url: url)
        // Idle timeout: a live stream that sends nothing for this long is dead, so error out
        // (and let the player reconnect) instead of hanging forever on a stalled socket.
        req.timeoutInterval = 15
        let (bytes, resp) = try await session.bytes(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 { throw Failure.http(http.statusCode) }

        var chunk = [UInt8]()
        chunk.reserveCapacity(4096)
        for try await b in bytes {
            chunk.append(b)
            guard chunk.count == 4096 else { continue }
            let st = chunk.withUnsafeBytes { AudioFileStreamParseBytes(stream, UInt32($0.count), $0.baseAddress!, []) }
            chunk.removeAll(keepingCapacity: true)
            if st != noErr { throw Failure.parser(st) }
            if let failure { throw failure }
            while live && core.buffered >= AudioCore.maxBuffered {
                try await Task.sleep(for: .milliseconds(25))
            }
            guard live else { return }
            try Task.checkCancellation()
        }
    }

    private func onProperty(_ prop: AudioFileStreamPropertyID) {
        guard let stream else { return }
        switch prop {
        case kAudioFileStreamProperty_ReadyToProducePackets:
            var asbd = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout.size(ofValue: asbd))
            guard AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_DataFormat, &size, &asbd) == noErr,
                  let fmt = AVAudioFormat(streamDescription: &asbd),
                  let conv = AVAudioConverter(from: fmt, to: outFormat)
            else {
                failure = Failure.converter
                return
            }
            var maxSize: UInt32 = 0
            size = UInt32(MemoryLayout<UInt32>.size)
            if AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_PacketSizeUpperBound, &size, &maxSize) == noErr,
               maxSize > 0 { maxPacketSize = maxSize }
            inFormat = fmt
            converter = conv
        default:
            break
        }
    }

    private func onPackets(bytes: UInt32, packets: UInt32, data: UnsafeRawPointer,
                           descs: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard live, let inFormat, let converter, let descs, packets > 0 else { return }
        let input = AVAudioCompressedBuffer(format: inFormat, packetCapacity: AVAudioPacketCount(packets),
                                            maximumPacketSize: Int(max(maxPacketSize, bytes)))
        input.data.copyMemory(from: data, byteCount: Int(bytes))
        input.byteLength = bytes
        input.packetCount = AVAudioPacketCount(packets)
        input.packetDescriptions?.update(from: descs, count: Int(packets))

        let ratio = AudioCore.rate / inFormat.sampleRate
        let frames = AVAudioFrameCount(Double(packets) * 1152 * ratio) + 2048
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: frames) else { return }
        var fed = false
        var err: NSError?
        let st = converter.convert(to: out, error: &err) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return input
        }
        guard st != .error, let ch = out.floatChannelData else { return }

        // Interleave and hand to the ring (back-pressure in `run` keeps it from overflowing).
        let n = Int(out.frameLength)
        var off = 0
        while off < n {
            let m = min(n - off, 32_768)
            for i in 0..<m {
                interleaved[i * 2] = ch[0][off + i]
                interleaved[i * 2 + 1] = ch[1][off + i]
            }
            core.write(interleaved, count: m * 2)
            off += m
        }
    }
}
