import Accelerate
import Foundation

/// Shared per-frame visual state: spectrum bins, beat pulse and loudness.
/// Mirrors the web analyser (fftSize 512, smoothing 0.78, -100…-30 dB byte scale) and
/// `src/lib/ticker.ts`'s beat detection, so the visuals feel identical.
final class Vis {
    static let bins = AudioCore.analysisLen / 2

    /// Current (interpolated) scene hue.
    var hue: Double
    /// 0…1 pulse that spikes on kicks (or a simulated 110 BPM beat).
    var beat: Double = 0
    /// 0…1 overall loudness.
    var level: Double = 0
    /// Frequency bins 0…1.
    private(set) var bins = [Float](repeating: 0, count: bins)
    /// True when `bins` holds real audio data this frame.
    private(set) var live = false
    private(set) var t: Double = 0
    private(set) var dt: Double = 0

    private var last: Double = 0
    private var bassAvg: Float = 0.2
    private var smooth = [Float](repeating: 0, count: bins)
    private var samples = [Float](repeating: 0, count: AudioCore.analysisLen)
    private var windowed = [Float](repeating: 0, count: AudioCore.analysisLen)
    private let window: [Float]
    private let dft: vDSP.DiscreteFourierTransform<Float>?
    private var re = [Float](repeating: 0, count: AudioCore.analysisLen)
    private var im = [Float](repeating: 0, count: AudioCore.analysisLen)
    private let zeros = [Float](repeating: 0, count: AudioCore.analysisLen)

    init(hue: Double) {
        self.hue = hue
        window = vDSP.window(ofType: Float.self, usingSequence: .blackman, count: AudioCore.analysisLen, isHalfWindow: false)
        dft = try? vDSP.DiscreteFourierTransform(count: AudioCore.analysisLen, direction: .forward,
                                                 transformType: .complexComplex, ofType: Float.self)
    }

    /// Advance once per display frame (several canvases may call it; only the first counts).
    func step(time: Double, core: AudioCore?, real: Bool, playing: Bool) {
        guard time != t else { return }
        dt = min(0.05, last == 0 ? 0 : time - last)
        last = time
        t = time
        if real, let core, let dft {
            samples.withUnsafeMutableBufferPointer { core.copyAnalysis(into: $0.baseAddress!) }
            vDSP.multiply(samples, window, result: &windowed)
            dft.transform(inputReal: windowed, inputImaginary: zeros, outputReal: &re, outputImaginary: &im)
            let n = Float(AudioCore.analysisLen)
            for k in 0..<Self.bins {
                let mag = (re[k] * re[k] + im[k] * im[k]).squareRoot() / n
                smooth[k] = 0.78 * smooth[k] + 0.22 * mag
                let db = 20 * log10(max(smooth[k], 1e-12))
                bins[k] = min(1, max(0, (db + 100) / 70))
            }
            let bass = bins[1..<7].reduce(0, +) / 6
            level = Double(bins[0..<96].reduce(0, +) / 96)
            bassAvg += (bass - bassAvg) * 0.04
            let kick = Double(max(0, (bass - bassAvg * 1.06) * 6))
            beat = max(beat * 0.88, min(1, kick))
            live = true
        } else {
            live = false
            beat = playing ? pow(1 - (t * 1.833).truncatingRemainder(dividingBy: 1), 3) : beat * 0.9
            level += ((playing ? 0.35 : 0) - level) * 0.05
            if smooth[0] != 0 || smooth[1] != 0 { for i in smooth.indices { smooth[i] = 0 } }
        }
    }

    /// Shortest-path hue interpolation (wraps around 360).
    static func approachHue(_ from: Double, _ to: Double, _ k: Double) -> Double {
        let d = (to - from + 540).truncatingRemainder(dividingBy: 360) - 180
        return (from + d * k + 360).truncatingRemainder(dividingBy: 360)
    }
}
