import SwiftUI

enum PhoneScreen: Hashable { case now, shelf, fx }

/// iPhone (and narrow iPad windows): Now Playing, Tape Shelf and Signal FX screens over
/// the live outrun scene. A port of `MobileApp.tsx`.
struct PhoneView: View {
    @Binding var screen: PhoneScreen
    /// Highlighted tape on the shelf (drives the scene hue while browsing).
    @Binding var sel: Int

    @Environment(Player.self) private var player

    private static let scene: [PhoneScreen: (horizon: Double, sun: Double)] = [
        .now: (0.5, 100), .shelf: (0.64, 120), .fx: (0.3, 80),
    ]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let scale = min(1.25, min(size.width, size.height * 0.55) / 402)
            let sc = Self.scene[screen]!
            let viewHue = screen == .shelf ? Stations.all[sel].hue : player.station.hue
            // Bigger tape on large phones and iPad portrait, same proportions as the web.
            let tapeW = min(size.width > 600 ? 420 : 300, size.width * 0.78, size.height * 0.34 * 300 / 190)
            ZStack {
                HorizonView(hue: viewHue, horizon: sc.horizon, sun: sc.sun * scale)
                Group {
                    switch screen {
                    case .now:
                        NowScreen(tapeW: tapeW, compact: size.height < 640) {
                            sel = player.stationIdx
                            screen = .shelf
                        } onFx: { screen = .fx }
                    case .shelf:
                        ShelfScreen(sel: $sel, tapeW: tapeW) { screen = .now }
                    case .fx:
                        FxScreen { screen = .now }
                    }
                }
                .frame(maxWidth: size.width > 700 ? 640 : .infinity)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity))
            }
            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45), value: screen)
        }
    }
}

/* ------------------------------------------------------------------ now playing */

private struct NowScreen: View {
    var tapeW: CGFloat
    var compact: Bool
    var onShelf: () -> Void
    var onFx: () -> Void

    @Environment(Player.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        let i = player.stationIdx
        let st = player.station
        let t = player.meta.tracks[st.id]
        VStack(spacing: 0) {
            HStack {
                Logo()
                Spacer()
                StatusPill()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("TAPE \(Stations.tapeNum(i)) / \(Stations.total) · SIDE A")
                    .font(Fonts.mono(17)).spacing(0.16, size: 17).foregroundStyle(theme.acc)
                StationName(name: st.name, size: 30)
                Text(st.tag).font(Fonts.body(15)).foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, compact ? 8 : 18)

            Spacer(minLength: 8)

            Button(action: onShelf) {
                DeckTape(width: tapeW, tilt: 16)
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .accessibilityLabel("Open tape shelf")

            VStack(spacing: 4) {
                Text(t?.title.nonEmpty ?? "Tuning in…").font(Fonts.body(20, weight: .semibold)).lineLimit(1)
                Text(t?.artist.nonEmpty ?? "Waiting for the signal").font(Fonts.body(14)).foregroundStyle(theme.acc2).lineLimit(1)
                Timeline(stationID: st.id, bars: 36, height: 18, font: 15)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 28)
            .padding(.top, compact ? 12 : 20)
            .accessibilityElement(children: .combine)

            HStack {
                SideButton(title: "SHELF", vertical: true, action: onShelf)
                Spacer()
                RoundButton(forward: false)
                Spacer()
                PlayButton()
                Spacer()
                RoundButton(forward: true)
                Spacer()
                SideButton(title: "FX", vertical: false, action: onFx)
            }
            .padding(.horizontal, 22)
            .padding(.top, compact ? 10 : 16)
            .padding(.bottom, 18)
        }
    }
}

private struct SideButton: View {
    var title: String
    var vertical: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                TripleIcon(vertical: vertical).frame(height: 16)
                Text(title).font(Fonts.display(7.5)).spacing(0.14, size: 7.5).foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 56, height: 56)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title == "FX" ? "Signal FX" : "Tape shelf")
    }
}

/* ------------------------------------------------------------------ shelf */

private struct ShelfScreen: View {
    @Binding var sel: Int
    var tapeW: CGFloat
    var onBack: () -> Void

    @Environment(Player.self) private var player
    @Environment(\.theme) private var theme
    @State private var inserting = false
    @State private var drag: CGFloat = 0

    private func clamp(_ i: Int) -> Int { max(0, min(Stations.all.count - 1, i)) }

    private func doInsert() {
        guard !inserting else { return }
        player.insert(sel)
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.55)) { inserting = true }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            onBack()
        }
    }

    var body: some View {
        let selSt = Stations.all[sel]
        let selTrack = player.meta.tracks[selSt.id]
        let inDeck = sel == player.stationIdx && player.wantPlay
        VStack(spacing: 0) {
            SubBar(title: "TAPE SHELF", trailing: "\(Stations.tapeNum(sel))/\(Stations.total)", onBack: onBack)

            VStack(spacing: 8) {
                DeckSlot(width: tapeW, height: 16)
                Text("DECK SLOT · TAP CENTER TAPE TO INSERT")
                    .font(Fonts.mono(14)).spacing(0.16, size: 14).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.top, 14)

            // Coverflow.
            ZStack {
                ForEach(Array(Stations.all.enumerated()), id: \.element.id) { i, x in
                    let d = Double(i - sel) + drag / (tapeW * 0.667)
                    let center = i == sel
                    Button {
                        center ? doInsert() : withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.55)) { sel = i }
                    } label: {
                        CassetteView(hue: x.hue, name: x.name, code: Stations.tapeCode(i), detailed: abs(i - sel) < 2)
                            .frame(width: tapeW)
                    }
                    .buttonStyle(.plain)
                    .rotation3DEffect(.degrees(inserting && center ? 80 : -28 * max(-3, min(3, d))), axis: (inserting && center ? 1 : 0, inserting && center ? 0 : 1, 0), perspective: 0.6)
                    .scaleEffect(inserting && center ? 0.6 : (abs(d) < 0.01 ? 1 : 0.82))
                    .offset(x: inserting && center ? 0 : d * tapeW * 0.667, y: inserting && center ? -tapeW * 1.1 : 0)
                    .opacity(inserting && center ? 0.2 : abs(d) >= 2.6 ? 0 : abs(d) < 0.01 ? 1 : 0.55)
                    .zIndex(10 - abs(d))
                    .allowsHitTesting(abs(i - sel) < 3)
                    .accessibilityLabel(center ? "Insert \(x.name)" : "Select \(x.name)")
                    .accessibilityHidden(abs(i - sel) > 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 12)
                .onChanged { drag = $0.translation.width }
                .onEnded { g in
                    let steps = Int((-g.predictedEndTranslation.width / (tapeW * 0.667)).rounded())
                    withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.55)) {
                        sel = clamp(sel + max(-2, min(2, steps)))
                        drag = 0
                    }
                })
            .sensoryFeedback(.selection, trigger: sel)
            .accessibilityElement(children: .contain)
            .accessibilityAdjustableAction { dir in
                withAnimation { sel = clamp(sel + (dir == .increment ? 1 : -1)) }
            }

            VStack(spacing: 6) {
                StationName(name: selSt.name, size: 26)
                Text(selSt.tag).font(Fonts.body(15)).foregroundStyle(Palette.ink2)
                Text("ON AIR · \(selTrack.map { "\($0.artist) — \($0.title)" } ?? "tuning…")")
                    .font(Fonts.mono(16)).spacing(0.06, size: 16).foregroundStyle(theme.acc2).lineLimit(1)
                HStack(spacing: 8) {
                    ForEach(Array(Stations.all.enumerated()), id: \.element.id) { i, x in
                        Button { withAnimation { sel = i } } label: {
                            Capsule().fill(ok(0.74, 0.19, x.hue))
                                .frame(width: i == sel ? 22 : 6, height: 6)
                                .opacity(i == sel ? 1 : 0.45)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(x.name)
                    }
                }
                .animation(.easeOut(duration: 0.3), value: sel)
            }
            .padding(.horizontal, 24)
            .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                SquareButton(forward: false) { withAnimation { sel = clamp(sel - 1) } }
                Button(action: doInsert) {
                    Text(inserting ? "LOADING…" : inDeck ? "IN DECK · REPLAY" : "INSERT TAPE")
                        .font(Fonts.display(11)).spacing(0.2, size: 11)
                        .foregroundStyle(Color(red: 10 / 255, green: 5 / 255, blue: 16 / 255))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 4).fill(
                            LinearGradient(colors: [theme.acc2, theme.acc], startPoint: .topLeading, endPoint: UnitPoint(x: 0.7, y: 1))))
                        .shadow(color: theme.acc.opacity(0.55), radius: 14)
                }
                .buttonStyle(PressStyle(scale: 0.98))
                SquareButton(forward: true) { withAnimation { sel = clamp(sel + 1) } }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 18)
        }
    }
}

private struct SquareButton: View {
    var forward: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 4).fill(Palette.bg.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.line, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(forward ? "Next tape" : "Previous tape")
    }
}

/* ------------------------------------------------------------------ fx */

private struct FxScreen: View {
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SubBar(title: "SIGNAL FX", trailing: "", onBack: onBack)
            ScrollView {
                VStack(spacing: 14) {
                    Card { FxToggles() }
                    Card(title: "SLEEP TIMER", padded: true) { SleepTimerPanel() }
                    Card(title: "AUDIO") { AudioSettingsPanel() }
                }
                .padding(EdgeInsets(top: 18, leading: 16, bottom: 14, trailing: 16))
            }
            .scrollIndicators(.hidden)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                                         .init(color: .black, location: 0.96), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            MiniPlayer().padding(.horizontal, 16).padding(.bottom, 18)
        }
    }
}

/* ------------------------------------------------------------------ shared bits */

private struct SubBar: View {
    var title: String
    var trailing: String
    var onBack: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Text(title).font(Fonts.display(12)).spacing(0.22, size: 12).accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                        Text("DECK").font(Fonts.mono(18)).spacing(0.1, size: 18)
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(height: 44)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Back to deck")
                Spacer()
                Text(trailing).font(Fonts.mono(18)).foregroundStyle(theme.acc).padding(.trailing, 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}
