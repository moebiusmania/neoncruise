import SwiftUI

/// The big glowing station name, with the stepped "tune in" animation on change.
struct StationName: View {
    var name: String
    var size: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        Text(name)
            .font(Fonts.display(size, relativeTo: .largeTitle))
            .foregroundStyle(Color(red: 1, green: 245 / 255, blue: 252 / 255))
            .neon(theme.acc, radius: size * 0.4)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .id(name)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: -10)).animation(.easeOut(duration: 0.4)),
                                    removal: .identity))
            .accessibilityAddTraits(.isHeader)
    }
}

/// The black deck slot above the tape, glowing in the accent colour.
struct DeckSlot: View {
    var width: CGFloat
    var height: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        Capsule().fill(.black)
            .frame(width: width, height: height)
            .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
            .shadow(color: theme.acc, radius: 11)
            .accessibilityHidden(true)
    }
}

/// The current tape in the deck, tilted back, sliding in when the station changes.
struct DeckTape: View {
    var width: CGFloat
    var tilt: Double

    @Environment(Player.self) private var player

    var body: some View {
        let st = player.station
        CassetteView(hue: st.hue, name: st.name, code: Stations.tapeCode(player.stationIdx),
                     progress: tapeProgress, spinning: player.wantPlay)
            .frame(width: width)
            .id(st.id)
            .transition(.asymmetric(
                insertion: .modifier(active: SlideIn(p: 1), identity: SlideIn(p: 0)).animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.65)),
                removal: .identity))
            .rotation3DEffect(.degrees(tilt), axis: (1, 0, 0), anchor: .bottom, perspective: 0.5)
    }

    /// Tape wind estimate (live radio has no duration), quantised so the reels only
    /// re-render when the pack visibly changes.
    private var tapeProgress: Double {
        guard let at = player.meta.tracks[player.station.id]?.at else { return 0.5 }
        let e = player.now.timeIntervalSince1970 - at / 1000
        return (min(1, max(0, e / 300)) * 40).rounded() / 40
    }

    private struct SlideIn: ViewModifier {
        var p: Double
        func body(content: Content) -> some View {
            content
                .rotation3DEffect(.degrees(70 * p), axis: (1, 0, 0), perspective: 0.5)
                .scaleEffect(1 - 0.3 * p)
                .offset(y: -60 * p)
                .opacity(1 - p)
        }
    }
}

/// Elapsed time · spectrum · LIVE.
struct Timeline: View {
    var stationID: String
    var bars: Int
    var height: CGFloat
    var font: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            TrackClock(stationID: stationID)
            SpectrumView(bars: bars).frame(height: height)
            Text("LIVE").foregroundStyle(theme.acc).spacing(0.1, size: font)
        }
        .font(Fonts.mono(font))
        .foregroundStyle(Palette.ink3)
    }
}
