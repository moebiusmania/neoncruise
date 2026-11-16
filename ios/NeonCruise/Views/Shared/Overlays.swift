import SwiftUI
import UIKit

/// CRT effects stacked over the whole app: scanlines, flicker, grain, the static burst on
/// tape change and a vignette. None of them take touches.
struct CRTOverlays: View {
    @Environment(Player.self) private var player
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let s = player.settings
        ZStack {
            if s.scan { Scanlines().opacity(0.5) }
            if s.flicker && !reduceMotion { Flicker(paused: phase != .active) }
            Grain(on: s.noise, burstAt: player.burstAt, paused: phase != .active)
            Vignette()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 1 pt dark line every 3 pt. Drawn once per size, then cached in a layer.
private struct Scanlines: View {
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var y = 0.0
            while y < size.height {
                p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                y += 3
            }
            ctx.fill(p, with: .color(.black.opacity(0.4)))
        }
        .drawingGroup()
    }
}

/// Unstable tube brightness: the web's 3.7 s stepped keyframes.
private struct Flicker: View {
    var paused: Bool
    private static let keys: [(Double, Double)] = [
        (0, 0), (0.04, 0.06), (0.08, 0), (0.41, 0), (0.43, 0.09), (0.45, 0.02), (0.70, 0), (0.72, 0.05),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: paused)) { tl in
            let p = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.7) / 3.7
            let o = Self.keys.last { $0.0 <= p }?.1 ?? 0
            Color.black.opacity(o)
        }
    }
}

/// Analog grain: a pre-rendered noise tile, jumped around with a cheap offset.
private struct Grain: View {
    var on: Bool
    var burstAt: Date?
    var paused: Bool

    private static let tile: UIImage = {
        let n = 160
        var px = [UInt8](repeating: 0, count: n * n * 4)
        var g = SystemRandomNumberGenerator()
        for i in 0..<(n * n) {
            let v = UInt8.random(in: 0...255, using: &g)
            px[i * 4] = 255
            px[i * 4 + 1] = 255
            px[i * 4 + 2] = 255
            px[i * 4 + 3] = v > 150 ? v : 0
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return UIImage(cgImage: ctx.makeImage()!)
    }()

    private static let offsets: [CGSize] = [.zero, CGSize(width: -37, height: 22), CGSize(width: 18, height: -41), CGSize(width: -9, height: 33)]

    var body: some View {
        // Idle (no timeline ticks) when grain is off and no burst is running.
        let bursting = burstAt.map { Date().timeIntervalSince($0) < 0.5 } ?? false
        TimelineView(.animation(minimumInterval: 0.12, paused: paused || !(on || bursting))) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let burst = burstAt.map { tl.date.timeIntervalSince($0) < 0.32 } ?? false
            let step = Int(t / (burst ? 0.12 : 0.4)) % Self.offsets.count
            Image(uiImage: Self.tile)
                .resizable(resizingMode: .tile)
                .padding(-48)
                .offset(Self.offsets[step])
                .opacity(burst ? 0.3 : on ? 0.12 : 0)
                .blendMode(burst ? .overlay : .normal)
        }
    }
}

private struct Vignette: View {
    var body: some View {
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height) * 0.75
            RadialGradient(stops: [.init(color: .clear, location: 0.58), .init(color: .black.opacity(0.55), location: 1)],
                           center: .center, startRadius: 0, endRadius: r)
        }
    }
}
