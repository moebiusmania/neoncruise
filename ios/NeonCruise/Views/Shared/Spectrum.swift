import SwiftUI

/// Live spectrum strip: real analyser bins in REACTIVE mode, otherwise a gentle simulated meter.
struct SpectrumView: View {
    var bars = 48

    @Environment(Player.self) private var player
    @Environment(\.scenePhase) private var phase
    @State private var state = SpectrumState()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: phase != .active)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let vis = player.vis
                vis.step(time: t, core: player.core,
                         real: player.settings.reactive && player.status == .playing, playing: player.wantPlay)
                state.draw(&ctx, size: size, t: t, vis: vis, bars: bars, playing: player.wantPlay)
            }
        }
        .accessibilityHidden(true)
    }
}

final class SpectrumState {
    private var heights: [Double] = []
    private var seeds: [Double] = []

    func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double, vis: Vis, bars: Int, playing: Bool) {
        let W = size.width, H = size.height
        guard W > 0, H > 0 else { return }
        if heights.count != bars {
            heights = Array(repeating: 0, count: bars)
            seeds = (0..<bars).map { _ in .random(in: 0...10) }
        }
        let n = vis.bins.count
        for i in 0..<bars {
            var v = 0.0
            if vis.live && n > 0 {
                // Log-ish mapping so the low end isn't crammed into two bars.
                let f0 = Int(pow(Double(i) / Double(bars), 1.7) * Double(n) * 0.7)
                let f1 = max(f0 + 1, Int(pow(Double(i + 1) / Double(bars), 1.7) * Double(n) * 0.7))
                var sum: Float = 0
                for k in f0..<min(f1, n) { sum += vis.bins[k] }
                v = Double(sum) / Double(f1 - f0)
            } else if playing {
                let env = 1 - Double(i) / Double(bars)
                v = (0.25 + 0.35 * abs(sin(t * 2.3 + seeds[i]))) * (0.4 + 0.6 * env) * (0.6 + 0.4 * vis.beat)
            }
            heights[i] += (v - heights[i]) * (v > heights[i] ? 0.6 : 0.15)
        }

        let gap = 2.0
        let bw = (W - gap * Double(bars - 1)) / Double(bars)
        let h = vis.hue
        // One glow pass for the whole strip instead of a shadow per bar.
        ctx.addFilter(.shadow(color: ok(0.74, 0.19, h, 0.8), radius: 4))
        ctx.drawLayer { l in
            for i in 0..<bars {
                let hv = heights[i]
                let bh = max(2, hv * H)
                l.fill(Path(CGRect(x: Double(i) * (bw + gap), y: H - bh, width: bw, height: bh)),
                       with: .color(ok(0.7 + hv * 0.2, 0.19, h, 0.45 + hv * 0.55)))
            }
        }
    }
}
