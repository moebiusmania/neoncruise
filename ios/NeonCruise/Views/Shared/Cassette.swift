import SwiftUI

/// A cassette that scales with its width: everything is laid out on the web's 300 × 190 grid.
struct CassetteView: View {
    var hue: Double
    var name: String
    var code: String
    /// 0…1 how far the tape has wound from the left reel to the right.
    var progress = 0.5
    var spinning = false
    /// Screws and head details (off for distant shelf tapes).
    var detailed = true

    var body: some View {
        GeometryReader { geo in
            let u = geo.size.width / 300
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12 * u)
                    .fill(LinearGradient(colors: [ok(0.76, 0.16, hue), ok(0.5, 0.2, hue)],
                                         startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1)))
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 12 * u).stroke(.white.opacity(0.45), lineWidth: 0.5).mask(
                            LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.04)))
                    }
                    .shadow(color: .black.opacity(0.6), radius: 20 * u, y: 18 * u)
                    .shadow(color: ok(0.6, 0.22, hue, 0.45), radius: 22 * u)

                if detailed {
                    ForEach(0..<4, id: \.self) { i in
                        Circle().fill(.black.opacity(0.35)).frame(width: 7 * u, height: 7 * u)
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing][i])
                            .padding(5 * u)
                    }
                }

                label(u)
                    .padding(.horizontal, 14 * u)
                    .padding(.top, 12 * u)

                head(u)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .aspectRatio(300 / 190, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func label(_ u: CGFloat) -> some View {
        VStack(spacing: 6 * u) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.custom("Syncopate-Bold", fixedSize: 11 * u))
                    .tracking(11 * u * 0.12)
                    .foregroundStyle(Palette.labelInk)
                    .lineLimit(1)
                Spacer(minLength: 4 * u)
                Text(code)
                    .font(.custom("VT323-Regular", fixedSize: 14 * u))
                    .foregroundStyle(ok(0.52, 0.22, hue))
            }
            Canvas { ctx, size in
                let bands: [(Double, Double, Color)] = [
                    (0, 0.3, ok(0.72, 0.19, hue)),
                    (0.42, 0.66, ok(0.84, 0.14, hue + 50)),
                    (0.78, 1, ok(0.6, 0.22, hue - 20)),
                ]
                for (a, b, c) in bands {
                    ctx.fill(Path(CGRect(x: 0, y: a * size.height, width: size.width, height: (b - a) * size.height)), with: .color(c))
                }
            }
            .frame(height: 10 * u)
            HStack {
                ReelView(pack: 2 + (1 - progress) * 8, spinning: spinning).frame(width: 52 * u, height: 52 * u)
                Spacer()
                ReelView(pack: 2 + progress * 8, spinning: spinning).frame(width: 52 * u, height: 52 * u)
            }
            .padding(.horizontal, 5 * u)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 22 * u).fill(Palette.deep)
                .overlay(RoundedRectangle(cornerRadius: 22 * u).stroke(.black.opacity(0.8), lineWidth: 2).blur(radius: 2).clipped()))
            .padding(.horizontal, 22 * u)
        }
        .padding(.horizontal, 10 * u)
        .padding(.vertical, 8 * u)
        .frame(height: 122 * u)
        .background(RoundedRectangle(cornerRadius: 6 * u).fill(ok(0.96, 0.025, hue + 40)))
    }

    private func head(_ u: CGFloat) -> some View {
        HStack {
            if detailed {
                Circle().fill(Palette.deep).frame(width: 9 * u, height: 9 * u)
                Spacer()
                Rectangle().fill(Palette.deep).frame(width: 12 * u, height: 8 * u)
                Spacer()
                Rectangle().fill(Palette.deep).frame(width: 12 * u, height: 8 * u)
                Spacer()
                Circle().fill(Palette.deep).frame(width: 9 * u, height: 9 * u)
            }
        }
        .padding(.horizontal, 34 * u)
        .padding(.top, 8 * u)
        .frame(width: 176 * u, height: 40 * u)
        .background(Trapezoid().fill(ok(0.36, 0.15, hue)))
    }
}

/// The head opening at the bottom of the cassette (CSS `clip-path` polygon).
nonisolated struct Trapezoid: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX + r.width * 0.09, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - r.width * 0.09, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

/// Cassette reel: hub, six spokes and a ring, with the tape pack wound around it.
struct ReelView: View {
    var pack: Double
    var spinning: Bool

    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0
    @State private var lastT: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !spinning || phase != .active)) { tl in
            Canvas { ctx, size in
                let s = min(size.width, size.height) / 52
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.scaleBy(x: s, y: s)
                func circle(_ r: Double) -> Path { Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)) }
                ctx.fill(circle(15 + pack), with: .color(Color(red: 43 / 255, green: 27 / 255, blue: 24 / 255)))
                ctx.fill(circle(15), with: .color(Palette.deep))
                // 1.8 s per turn, like the CSS animation.
                let t = tl.date.timeIntervalSinceReferenceDate
                let a = spinning && !reduceMotion ? (t / 1.8).truncatingRemainder(dividingBy: 1) * 2 * .pi : 0
                ctx.rotate(by: .radians(a))
                let ink = Color(red: 239 / 255, green: 231 / 255, blue: 243 / 255)
                for k in 0..<6 {
                    var c = ctx
                    c.rotate(by: .degrees(Double(k) * 60))
                    var sp = Path()
                    sp.move(to: CGPoint(x: -0.8, y: -7))
                    sp.addLine(to: CGPoint(x: 0.8, y: -7))
                    sp.addLine(to: CGPoint(x: 1.6, y: -15))
                    sp.addLine(to: CGPoint(x: -1.6, y: -15))
                    sp.closeSubpath()
                    c.fill(sp, with: .color(ink))
                }
                ctx.stroke(circle(12.5), with: .color(ink), lineWidth: 1)
                ctx.stroke(circle(5.5), with: .color(ink), lineWidth: 3)
                ctx.fill(circle(4), with: .color(Palette.deep))
            }
        }
        .animation(.linear(duration: 1), value: pack)
    }
}
