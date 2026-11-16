import SwiftUI

/* ------------------------------------------------------------------ icons (from Icons.tsx) */

nonisolated struct PlayGlyph: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

nonisolated struct PauseGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width * 7 / 20
        return Path { p in
            p.addRect(CGRect(x: r.minX, y: r.minY, width: w, height: r.height))
            p.addRect(CGRect(x: r.maxX - w, y: r.minY, width: w, height: r.height))
        }
    }
}

/// ◀◀ / ▶▶ skip glyph.
nonisolated struct SkipGlyph: Shape {
    var forward: Bool
    func path(in r: CGRect) -> Path {
        let half = r.width / 2
        return Path { p in
            for i in 0..<2 {
                let x0 = r.minX + Double(i) * half
                if forward {
                    p.move(to: CGPoint(x: x0, y: r.minY))
                    p.addLine(to: CGPoint(x: x0 + half, y: r.midY))
                    p.addLine(to: CGPoint(x: x0, y: r.maxY))
                } else {
                    p.move(to: CGPoint(x: x0 + half, y: r.minY))
                    p.addLine(to: CGPoint(x: x0, y: r.midY))
                    p.addLine(to: CGPoint(x: x0 + half, y: r.maxY))
                }
                p.closeSubpath()
            }
        }
    }
}

/// Three tape spines (SHELF) or three slider lines (FX); the middle one takes the accent.
struct TripleIcon: View {
    var vertical: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let layout = vertical ? AnyLayout(HStackLayout(spacing: 3)) : AnyLayout(VStackLayout(spacing: 3))
        layout {
            ForEach(0..<3, id: \.self) { i in
                Rectangle().fill(i == 1 ? theme.acc : .white)
                    .frame(width: vertical ? 5 : 18, height: vertical ? 16 : 3)
            }
        }
    }
}

struct SpeakerIcon: View {
    var level: Double
    var body: some View {
        Image(systemName: level == 0 ? "speaker.slash.fill" : level > 0.5 ? "speaker.wave.2.fill" : "speaker.wave.1.fill")
            .font(.system(size: 17, weight: .semibold))
    }
}

/* ------------------------------------------------------------------ transport */

/// Big round play/pause with the accent gradient and glow; spinner ring while tuning.
struct PlayButton: View {
    var size: CGFloat = 76
    var small = false

    @Environment(Player.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        let playing = player.wantPlay
        let loading = player.status == .loading
        Button(action: player.togglePlay) {
            ZStack {
                Circle().fill(small ? AnyShapeStyle(theme.acc)
                    : AnyShapeStyle(LinearGradient(colors: [theme.acc2, theme.acc], startPoint: .topLeading, endPoint: UnitPoint(x: 0.75, y: 1))))
                Group {
                    if playing {
                        PauseGlyph().frame(width: size * 0.26, height: size * 0.26 * 26 / 20)
                    } else {
                        PlayGlyph().frame(width: size * 0.31, height: size * 0.31 * 28 / 24).offset(x: size * 0.04)
                    }
                }
                .foregroundStyle(Palette.bg)
                if loading {
                    Spinner(color: theme.acc2).padding(-5)
                }
            }
            .frame(width: size, height: size)
            .shadow(color: small ? .clear : theme.glow, radius: 17)
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .accessibilityLabel(playing ? "Pause" : "Play")
        .accessibilityValue(player.statusLabel)
        .sensoryFeedback(.impact(weight: .medium), trigger: playing)
    }
}

private struct Spinner: View {
    var color: Color
    @State private var on = false
    var body: some View {
        Circle().trim(from: 0, to: 0.25).stroke(color, lineWidth: 2)
            .rotationEffect(.degrees(on ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: on)
            .onAppear { on = true }
    }
}

struct RoundButton: View {
    var forward: Bool
    @Environment(Player.self) private var player

    var body: some View {
        Button { player.tuneBy(forward ? 1 : -1) } label: {
            SkipGlyph(forward: forward).frame(width: 18, height: 12)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Palette.bg.opacity(0.5)))
                .overlay(Circle().stroke(Palette.line, lineWidth: 1))
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .accessibilityLabel(forward ? "Next station" : "Previous station")
    }
}

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/* ------------------------------------------------------------------ status */

struct StatusPill: View {
    @Environment(Player.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        let st = player.status
        HStack(spacing: 8) {
            Dot(status: st)
            Text(player.statusLabel)
                .font(Fonts.mono(16))
                .spacing(0.12, size: 16)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 3).fill(Palette.bg.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.acc.opacity(0.55), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(player.statusLabel)")
    }

    private struct Dot: View {
        var status: PlayStatus
        @State private var dim = false
        var body: some View {
            let c: Color = switch status {
            case .playing: ok(0.7, 0.24, 25)
            case .loading: ok(0.86, 0.17, 90)
            case .error: ok(0.6, 0.22, 25)
            default: .white.opacity(0.4)
            }
            let blinks = status == .playing || status == .loading
            Circle().fill(c).frame(width: 7, height: 7)
                .shadow(color: blinks ? c : .clear, radius: 4)
                .opacity(blinks && dim ? 0.15 : 1)
                .task(id: status) {
                    dim = false
                    guard blinks else { return }
                    let half = status == .loading ? 0.2 : 0.6
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(half))
                        dim.toggle()
                    }
                }
        }
    }
}

/// "NEON CRUISE" over "NIGHTRIDE FM".
struct Logo: View {
    var stacked = true
    @Environment(\.theme) private var theme

    var body: some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 14))
        layout {
            Text("NEON CRUISE")
                .font(Fonts.mono(stacked ? 15 : 20))
                .spacing(0.2, size: stacked ? 15 : 20)
                .foregroundStyle(theme.acc2)
                .neon(theme.acc, radius: 4)
            if !stacked { Rectangle().fill(theme.line).frame(width: 1, height: 18) }
            (Text("NIGHTRIDE") + Text(" FM").foregroundStyle(theme.acc))
                .font(Fonts.display(13))
                .spacing(0.22, size: 13)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Neon Cruise, Nightride FM")
    }
}

/// Elapsed time since the track started; only this text re-renders each second.
struct TrackClock: View {
    var stationID: String
    @Environment(Player.self) private var player

    var body: some View {
        let at = player.meta.tracks[stationID]?.at
        Text(at.map { fmtTime(player.now.timeIntervalSince1970 - $0 / 1000) } ?? "--:--")
            .accessibilityLabel("Elapsed")
    }
}
