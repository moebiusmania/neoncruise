import MediaPlayer
import SwiftUI

/// Lock screen / Control Center artwork: a still of the outrun scene in the station's
/// colours with its cassette and name. Rendered once per station (≈1200 px) and cached.
enum NowPlayingArt {
    private static var cache: [String: MPMediaItemArtwork] = [:]

    static func artwork(for index: Int) -> MPMediaItemArtwork? {
        let st = Stations.all[index]
        if let a = cache[st.id] { return a }
        let renderer = ImageRenderer(content: ArtView(station: st, index: index).frame(width: 400, height: 400))
        renderer.scale = 3
        renderer.isOpaque = true
        guard let img = renderer.uiImage else { return nil }
        let a = makeArtwork(img)
        cache[st.id] = a
        return a
    }

    /// MediaPlayer calls the handler off the main thread, so it must not be main-actor isolated.
    nonisolated private static func makeArtwork(_ img: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: img.size) { _ in img }
    }
}

private struct ArtView: View {
    let station: Station
    let index: Int

    var body: some View {
        let theme = Theme(hue: station.hue)
        ZStack {
            Canvas { ctx, size in
                // First frame of the live scene: no easing (dt = 0), no motion, no beat.
                SceneState().draw(&ctx, size: size, t: 0, vis: Vis(hue: station.hue),
                                  target: (station.hue, 0.56, 80), playing: false, motion: 0)
            }
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("NEON CRUISE")
                        .font(.custom("VT323-Regular", fixedSize: 22))
                        .tracking(22 * 0.2)
                        .foregroundStyle(theme.acc2)
                        .neon(theme.acc, radius: 4)
                    Text(station.name)
                        .font(.custom("Syncopate-Bold", fixedSize: 30))
                        .tracking(30 * 0.06)
                        .foregroundStyle(Palette.ink)
                        .neon(theme.acc)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(.horizontal, 28)
                .padding(.top, 34)
                Spacer()
                CassetteView(hue: station.hue, name: station.name, code: Stations.tapeCode(index))
                    .frame(width: 226)
                    .padding(.bottom, 22)
            }
        }
        .background(Palette.bg)
        .environment(\.theme, theme)
    }
}
