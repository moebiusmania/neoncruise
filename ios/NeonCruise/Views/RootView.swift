import SwiftUI

/// Picks the layout like the web's `(min-width: 960px) and (min-height: 560px)` query
/// (900 pt here, so iPad landscape and large split-view windows get the three panes),
/// owns the animated theme hue, the CRT overlays and the hardware-keyboard shortcuts.
struct RootView: View {
    @Environment(Player.self) private var player
    @State private var screen: PhoneScreen = .now
    @State private var sel = 0
    @State private var fxOpen = false
    @State private var hover: Int?
    @State private var hue: Double = 350

    var body: some View {
        GeometryReader { geo in
            let desktop = geo.size.width >= 900 && geo.size.height >= 560
            ZStack {
                Palette.bg.ignoresSafeArea()
                if desktop {
                    PadView(fxOpen: $fxOpen, hover: $hover)
                } else {
                    PhoneView(screen: $screen, sel: $sel)
                }
                CRTOverlays()
            }
            .onChange(of: viewHue(desktop: desktop), initial: true) { _, target in
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.9)) { hue = unwrapHue(target, from: hue) }
            }
        }
        .modifier(AnimatedTheme(hue: hue))
        .foregroundStyle(Palette.ink)
        .font(Fonts.body(15))
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .background(KeyboardShortcuts(screen: $screen, fxOpen: $fxOpen))
        .onAppear {
            sel = player.stationIdx
            #if DEBUG
            // Like the web's `?screen=shelf|fx` (PWA shortcuts): `-screen shelf|fx`, `-fx` opens the iPad panel.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-screen"), i + 1 < args.count {
                screen = args[i + 1] == "shelf" ? .shelf : args[i + 1] == "fx" ? .fx : .now
            }
            if args.contains("-fx") { fxOpen = true }
            #endif
        }
    }

    private func viewHue(desktop: Bool) -> Double {
        if desktop, let h = hover { return Stations.all[h].hue }
        if !desktop && screen == .shelf { return Stations.all[sel].hue }
        return player.station.hue
    }
}

/// Hardware keyboard on iPad: the same shortcuts as the web app.
private struct KeyboardShortcuts: View {
    @Binding var screen: PhoneScreen
    @Binding var fxOpen: Bool
    @Environment(Player.self) private var player

    var body: some View {
        ZStack {
            key(.space) { player.togglePlay() }
            key("k") { player.togglePlay() }
            key(.rightArrow) { player.tuneBy(1) }
            key("n") { player.tuneBy(1) }
            key(.leftArrow) { player.tuneBy(-1) }
            key("p") { player.tuneBy(-1) }
            key("m") { player.toggleMute() }
            key(.escape) {
                fxOpen = false
                screen = .now
            }
            ForEach(1...Stations.all.count, id: \.self) { n in
                key(KeyEquivalent(Character("\(n)"))) { player.tune(n - 1) }
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func key(_ k: KeyEquivalent, _ action: @escaping () -> Void) -> some View {
        Button("", action: action).keyboardShortcut(k, modifiers: [])
    }
}
