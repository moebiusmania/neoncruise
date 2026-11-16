import SwiftUI

/// Cold-launch intro, over the live app. It starts from the launch screen's flat
/// background: the horizon line draws out, the striped sun rises into the same spot as
/// the Now screen's, the grid rolls in and the logo types on. Then it dissolves into
/// the real scene. Tap to skip; Reduce Motion shows the finished frame briefly.
struct SplashView: View {
    var station: Station
    var index: Int
    /// Must match `PhoneView`'s Now screen so the hand-off lines up.
    var horizon: Double
    var sun: Double
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var leaving = false

    private static let duration = 2.2
    private static let title = Array("NEON CRUISE")

    var body: some View {
        TimelineView(.animation(paused: leaving)) { tl in
            let t = reduceMotion ? 10 : tl.date.timeIntervalSince(start)
            GeometryReader { geo in
                ZStack {
                    Canvas { ctx, size in
                        Self.drawScene(&ctx, size: size, t: t, hue: station.hue, horizon: horizon, sunR: sun)
                    }
                    VStack(spacing: 14) {
                        typed(t)
                        (Text("NIGHTRIDE") + Text(" FM").foregroundStyle(Theme(hue: station.hue).acc))
                            .font(.custom("Syncopate-Bold", fixedSize: 15))
                            .tracking(15 * 0.3)
                            .opacity(clamp((t - 1.25) / 0.35))
                    }
                    .position(x: geo.size.width / 2, y: geo.size.height * (horizon + (1 - horizon) * 0.36))

                    Text("TUNING \(Stations.tapeCode(index)) · \(station.name)")
                        .font(.custom("VT323-Regular", fixedSize: 18))
                        .tracking(18 * 0.16)
                        .foregroundStyle(Palette.ink2)
                        .opacity(clamp((t - 1.45) / 0.3) * (0.55 + 0.45 * abs(sin(t * 5))))
                        .position(x: geo.size.width / 2, y: geo.size.height - geo.safeAreaInsets.bottom - 44)
                }
            }
        }
        .ignoresSafeArea()
        .background(Palette.bg)
        .foregroundStyle(Palette.ink)
        .opacity(leaving ? 0 : 1)
        .scaleEffect(leaving ? 1.06 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.8 : Self.duration))
            finish()
        }
        .accessibilityElement()
        .accessibilityLabel("Neon Cruise, Nightride FM")
        .accessibilityAction { finish() }
    }

    /// "NEON CRUISE" typing on with a block cursor; hidden letters keep their space.
    private func typed(_ t: Double) -> some View {
        let n = min(Self.title.count, max(0, Int((t - 0.7) / 0.045)))
        let done = n == Self.title.count
        let cursorOn = t > 0.55 && (!done || Int(t * 3) % 2 == 0)
        let acc = Theme(hue: station.hue)
        return (Text(String(Self.title[..<n]))
            + Text(String(Self.title[n...])).foregroundStyle(.clear)
            + Text("█").foregroundStyle(cursorOn ? acc.acc : .clear))
            .font(.custom("VT323-Regular", fixedSize: 46))
            .tracking(46 * 0.14)
            .foregroundStyle(acc.acc2)
            .neon(acc.acc, radius: 6)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 24)
    }

    private func finish() {
        guard !leaving else { return }
        withAnimation(.easeIn(duration: 0.45)) { leaving = true } completion: { onFinish() }
    }

    /* ---------------------------------------------------------------- scene */

    private static func clampT(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - clampT(x), 3) }

    /// The intro's own pared-down version of `SceneState.draw`: same colours and geometry,
    /// each layer driven by the timeline instead of the audio.
    private static func drawScene(_ ctx: inout GraphicsContext, size: CGSize, t: Double,
                                  hue h: Double, horizon: Double, sunR R: Double) {
        let W = size.width, H = size.height
        guard W > 0, H > 0 else { return }
        let Y = H * horizon
        let line = easeOut(t / 0.55)
        let rise = easeOut((t - 0.25) / 0.9)
        let grid = clampT((t - 0.5) / 0.7)
        let sky = Path(CGRect(x: 0, y: 0, width: W, height: Y))

        // Sky glow comes up with the sun.
        var s = ctx
        s.opacity = rise
        s.fill(sky, with: .linearGradient(
            Gradient(stops: [.init(color: Palette.bg, location: 0),
                             .init(color: ok(0.17, 0.09, h + 30), location: 0.55),
                             .init(color: ok(0.45, 0.2, h + 10), location: 1)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: Y)))
        let cy = Y - R * 0.62 + (1 - rise) * R * 1.7
        s.fill(sky, with: .radialGradient(
            Gradient(colors: [ok(0.62, 0.24, h, 0.5), ok(0.62, 0.24, h, 0)]),
            center: CGPoint(x: W / 2, y: cy), startRadius: R * 0.6, endRadius: R * 2.8))

        // Sun, rising from behind the horizon.
        do {
            var c = ctx
            c.clip(to: sky)
            c.addFilter(.shadow(color: ok(0.72, 0.26, h), radius: 18 + 10 * rise))
            c.drawLayer { l in
                l.fill(Path(ellipseIn: CGRect(x: W / 2 - R, y: cy - R, width: R * 2, height: R * 2)), with: .linearGradient(
                    Gradient(stops: [.init(color: ok(0.94, 0.12, h + 75), location: 0),
                                     .init(color: ok(0.8, 0.19, h + 35), location: 0.5),
                                     .init(color: ok(0.62, 0.26, h), location: 1)]),
                    startPoint: CGPoint(x: 0, y: cy - R), endPoint: CGPoint(x: 0, y: cy + R)))
                l.blendMode = .destinationOut
                let stp = R * 0.13
                let off = (t * 8).truncatingRemainder(dividingBy: stp)
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

        // Floor and grid: horizontal lines arrive from the horizon outwards, then scroll.
        do {
            let floor = CGRect(x: 0, y: Y, width: W, height: H - Y)
            var c = ctx
            c.opacity = grid
            c.fill(Path(floor), with: .linearGradient(
                Gradient(colors: [ok(0.22, 0.13, h), Palette.bg]),
                startPoint: CGPoint(x: 0, y: Y), endPoint: CGPoint(x: 0, y: H)))
            c.clip(to: Path(floor))
            let ph = (max(0, t - 0.5) * 0.5).truncatingRemainder(dividingBy: 1)
            let shown = Int(grid * 44)
            for k in 0..<shown {
                let y = Y + ((H - Y) * 1.2) / (Double(k) + 1 - ph)
                if y > H + 2 { continue }
                if y - Y < 0.6 { break }
                let a = min(1, ((y - Y) / (H - Y)) * 2.2)
                var lc = c
                lc.opacity = a * 0.7
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: W, y: y))
                lc.stroke(p, with: .color(ok(0.76, 0.22, h)), lineWidth: 0.6 + a * 1.1)
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

        // Horizon line drawing out from the centre.
        var g = ctx
        g.addFilter(.shadow(color: ok(0.8, 0.22, h), radius: 7))
        let lw = W * line
        g.fill(Path(CGRect(x: (W - lw) / 2, y: Y - 1, width: lw, height: 1.5)), with: .color(ok(0.9, 0.15, h + 40)))
    }
}

private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
