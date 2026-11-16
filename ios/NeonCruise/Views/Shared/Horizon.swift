import SwiftUI

/// Live outrun scene: sky, stars, striped sun, mountains and a scrolling neon grid.
/// A port of `Horizon.tsx`, drawn with `Canvas` once per display frame.
struct HorizonView: View {
    /// Target hue of the scene.
    var hue: Double
    /// Horizon position as a fraction of the height.
    var horizon: Double
    /// Sun radius in points.
    var sun: Double

    @Environment(Player.self) private var player
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = SceneState()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: phase != .active)) { tl in
            Canvas(rendersAsynchronously: true) { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                player.vis.step(time: t, core: player.core,
                                real: player.settings.reactive && player.status == .playing,
                                playing: player.wantPlay)
                scene.draw(&ctx, size: size, t: t, vis: player.vis, target: (hue, horizon, sun),
                           playing: player.wantPlay, motion: reduceMotion ? 0.25 : 1)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Per-frame scene state (eased values and the random layout), kept across frames.
final class SceneState {
    private struct Star { var x, y, r, p, sp: Double }

    private var stars: [Star]
    private let far: [CGPoint]
    private let near: [CGPoint]
    private var hy: Double?
    private var radius: Double?
    private var spd = 0.5
    private var phase = 0.0

    init() {
        var g = SystemRandomNumberGenerator()
        stars = (0..<420).map { _ in
            Star(x: .random(in: 0...1, using: &g), y: .random(in: 0...1, using: &g),
                 r: Double.random(in: 0...1, using: &g) < 0.15 ? 2 : 1,
                 p: .random(in: 0...6, using: &g), sp: 0.5 + .random(in: 0...2, using: &g))
        }
        far = Self.ridge(44, lo: 0.25)
        near = Self.ridge(26, lo: 0.1)
    }

    private static func ridge(_ n: Int, lo: Double) -> [CGPoint] {
        (0...n).map { k in
            let x = Double(k) / Double(n)
            let e = pow(abs(x - 0.5) * 2, 1.5)
            let y = (k % 2 == 1 ? 0.55 + 0.45 * .random(in: 0...1) : lo + 0.3 * .random(in: 0...1)) * (0.1 + 0.9 * e)
            return CGPoint(x: x, y: y)
        }
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double, vis: Vis,
              target: (hue: Double, horizon: Double, sun: Double), playing: Bool, motion: Double) {
        let W = size.width, H = size.height
        guard W > 0, H > 0 else { return }
        let ease = { (k: Double) in 1 - pow(1 - k, vis.dt * 60) }

        vis.hue = Vis.approachHue(vis.hue, target.hue, ease(0.07))
        let hy = (self.hy ?? target.horizon) + (target.horizon - (self.hy ?? target.horizon)) * ease(0.06)
        let R = (radius ?? target.sun) + (target.sun - (radius ?? target.sun)) * ease(0.06)
        self.hy = hy
        radius = R
        spd += ((playing ? 1 : 0.12) - spd) * ease(0.04)
        phase += vis.dt * spd * 1.3 * motion

        let beat = vis.beat * motion
        let h = vis.hue
        let Y = H * hy

        // Sky.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: Y)), with: .linearGradient(
            Gradient(stops: [.init(color: Color(red: 4 / 255, green: 2 / 255, blue: 10 / 255), location: 0),
                             .init(color: ok(0.17, 0.09, h + 30), location: 0.55),
                             .init(color: ok(0.45, 0.2, h + 10), location: 1)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: Y)))
        let cy = Y - R * 0.62
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: Y)), with: .radialGradient(
            Gradient(colors: [ok(0.62, 0.24, h, 0.5 + vis.level * 0.25), ok(0.62, 0.24, h, 0)]),
            center: CGPoint(x: W / 2, y: cy), startRadius: R * 0.6, endRadius: R * 2.8))

        // Stars: one colour, per-star opacity.
        let count = min(stars.count, Int((W * H / 2700).rounded()))
        let starColor = Color(red: 1, green: 240 / 255, blue: 1)
        for st in stars.prefix(count) {
            let y = st.y * Y * 0.85
            var c = ctx
            c.opacity = (0.25 + 0.75 * abs(sin(t * st.sp + st.p))) * (1 - y / Y)
            c.fill(Path(CGRect(x: st.x * W, y: y, width: st.r, height: st.r)), with: .color(starColor))
        }

        // Sun with scrolling cut-out stripes and a beat-driven glow.
        do {
            var c = ctx
            c.clip(to: Path(CGRect(x: 0, y: 0, width: W, height: Y)))
            c.addFilter(.shadow(color: ok(0.72, 0.26, h), radius: (36 + beat * 30) / 2))
            c.drawLayer { l in
                let sunRect = CGRect(x: W / 2 - R, y: cy - R, width: R * 2, height: R * 2)
                l.fill(Path(ellipseIn: sunRect), with: .linearGradient(
                    Gradient(stops: [.init(color: ok(0.94, 0.12, h + 75), location: 0),
                                     .init(color: ok(0.8, 0.19, h + 35), location: 0.5),
                                     .init(color: ok(0.62, 0.26, h), location: 1)]),
                    startPoint: CGPoint(x: 0, y: cy - R), endPoint: CGPoint(x: 0, y: cy + R)))
                l.blendMode = .destinationOut
                let stp = R * 0.13
                let off = (t * 8 * motion).truncatingRemainder(dividingBy: stp)
                var cut = Path()
                for k in -1..<9 {
                    let y = cy + R * 0.02 + Double(k) * stp + off
                    let dy = y - cy
                    if dy < 0 { continue }
                    cut.addRect(CGRect(x: W / 2 - R - 2, y: y, width: R * 2 + 4, height: 1 + dy * 0.075))
                }
                l.fill(cut, with: .color(.black))
            }
        }

        // Mountains.
        let mh = max(R, min(W, 900) * 0.25)
        func mountain(_ pts: [CGPoint], _ hm: Double, fill: Color, stroke: Color, lw: Double) {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: Y))
            for q in pts { p.addLine(to: CGPoint(x: q.x * W, y: Y - q.y * hm)) }
            p.addLine(to: CGPoint(x: W, y: Y))
            p.closeSubpath()
            ctx.fill(p, with: .color(fill))
            ctx.stroke(p, with: .color(stroke), lineWidth: lw)
        }
        mountain(far, mh * 0.62, fill: ok(0.2, 0.1, h + 40), stroke: ok(0.66, 0.2, h + 20, 0.6), lw: 1)
        mountain(near, mh * 0.42, fill: Color(red: 7 / 255, green: 3 / 255, blue: 13 / 255), stroke: ok(0.76, 0.22, h, 0.9), lw: 1.2)

        // Floor and grid.
        let floor = CGRect(x: 0, y: Y, width: W, height: H - Y)
        ctx.fill(Path(floor), with: .linearGradient(
            Gradient(colors: [ok(0.22, 0.13, h), Color(red: 4 / 255, green: 2 / 255, blue: 10 / 255)]),
            startPoint: CGPoint(x: 0, y: Y), endPoint: CGPoint(x: 0, y: H)))
        do {
            var c = ctx
            c.clip(to: Path(floor))
            let line = ok(0.76, 0.22, h)
            let ph = phase.truncatingRemainder(dividingBy: 1)
            for k in 0..<44 {
                let y = Y + ((H - Y) * 1.2) / (Double(k) + 1 - ph)
                if y > H + 2 { continue }
                if y - Y < 0.6 { break }
                let a = min(1, ((y - Y) / (H - Y)) * 2.2)
                var lc = c
                lc.opacity = a * (0.7 + 0.3 * beat)
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: W, y: y))
                lc.stroke(p, with: .color(line), lineWidth: 0.6 + a * 1.1 + beat * a * 0.9)
            }
            let n = Int(ceil(W / 2 / 62)) + 4
            var v = Path()
            for j in -n...n {
                v.move(to: CGPoint(x: W / 2 + Double(j) * 1.5, y: Y))
                v.addLine(to: CGPoint(x: W / 2 + Double(j) * 62, y: H))
            }
            c.stroke(v, with: .linearGradient(
                Gradient(stops: [.init(color: ok(0.76, 0.22, h, 0), location: 0),
                                 .init(color: ok(0.76, 0.22, h, 0.5), location: 0.35),
                                 .init(color: ok(0.76, 0.22, h, 0.95), location: 1)]),
                startPoint: CGPoint(x: 0, y: Y), endPoint: CGPoint(x: 0, y: H)), lineWidth: 1.2)
        }

        // Glowing horizon line.
        var g = ctx
        g.addFilter(.shadow(color: ok(0.8, 0.22, h), radius: 7))
        g.fill(Path(CGRect(x: 0, y: Y - 1, width: W, height: 1.5)), with: .color(ok(0.9, 0.15, h + 40)))
    }
}
