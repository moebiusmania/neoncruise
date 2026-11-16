import SwiftUI

/// iPad (and any window ≥ 900 pt wide): tape rack, live stage and the Signal FX panel,
/// with a title bar and status bar. A port of `DesktopApp.tsx`.
struct PadView: View {
    @Binding var fxOpen: Bool
    /// Rack row under the pointer/focus (previews that station's colour world).
    @Binding var hover: Int?

    @Environment(Player.self) private var player

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // ≥ 1180 pt: side panel always visible (web: 1240 px); otherwise it slides over.
            let wide = size.width >= 1180
            let rackW: CGFloat = size.width >= 1180 ? 300 : 280
            let viewHue = hover.map { Stations.all[$0].hue } ?? player.station.hue
            VStack(spacing: 0) {
                TitleBar(fxOpen: $fxOpen, showFx: !wide)
                HStack(spacing: 0) {
                    Rack(hover: $hover).frame(width: rackW)
                    Stage()
                    if wide { SidePanel().frame(width: 360) }
                }
                .overlay(alignment: .trailing) {
                    if !wide && fxOpen {
                        SidePanel(overlay: true)
                            .frame(width: 360)
                            .transition(.move(edge: .trailing))
                    }
                }
                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.4), value: fxOpen)
                StatusBar()
            }
            .background {
                HorizonView(hue: viewHue, horizon: 0.56, sun: min(170, size.height * 0.16))
            }
        }
    }
}

/// Frosted chrome used by the bars and panels.
private struct Chrome: ViewModifier {
    func body(content: Content) -> some View {
        content.background(.ultraThinMaterial.opacity(0.35)).background(Palette.bg.opacity(0.62))
    }
}

private struct PanelHead: View {
    var title: String
    var trailing: String = ""
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Fonts.display(11)).spacing(0.22, size: 11).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(trailing).font(Fonts.mono(18)).foregroundStyle(theme.acc)
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 12, trailing: 20))
    }
}

/* ------------------------------------------------------------------ title bar */

private struct TitleBar: View {
    @Binding var fxOpen: Bool
    var showFx: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            StatusPill()
            HStack {
                Logo(stacked: false)
                Spacer()
                if showFx {
                    Button { fxOpen.toggle() } label: {
                        HStack(spacing: 8) {
                            TripleIcon(vertical: false).scaleEffect(0.8)
                            Text("FX").font(Fonts.display(9)).spacing(0.18, size: 9)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 4).fill(fxOpen ? theme.acc.opacity(0.16) : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(fxOpen ? theme.acc : Palette.line, lineWidth: 1))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Signal FX")
                    .accessibilityAddTraits(fxOpen ? .isSelected : [])
                    .keyboardShortcut("f", modifiers: [])
                }
            }
        }
        .padding(.leading, 22)
        .padding(.trailing, 16)
        .frame(height: 52)
        .modifier(Chrome())
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
    }
}

/* ------------------------------------------------------------------ tape rack */

private struct Rack: View {
    @Binding var hover: Int?
    @Environment(Player.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            PanelHead(title: "TAPE SHELF", trailing: "\(Stations.tapeNum(player.stationIdx))/\(Stations.total)")
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(Stations.all.enumerated()), id: \.element.id) { i, x in
                        RackItem(index: i, station: x, hover: $hover)
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
            Text("Tap a tape to slot it in · ⌨ 1–7")
                .font(Fonts.body(12)).foregroundStyle(Palette.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20))
                .overlay(alignment: .top) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
        }
        .modifier(Chrome())
        .overlay(alignment: .trailing) { Rectangle().fill(theme.line).frame(width: 1) }
    }
}

private struct RackItem: View {
    var index: Int
    var station: Station
    @Binding var hover: Int?

    @Environment(Player.self) private var player
    @State private var hovering = false

    var body: some View {
        let active = index == player.stationIdx
        let playing = active && player.wantPlay
        let t = player.meta.tracks[station.id]
        let h = station.hue
        Button { player.insert(index) } label: {
            HStack(spacing: 12) {
                Spine(hue: h, code: Stations.tapeCode(index))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Stations.tapeNum(index)).font(Fonts.mono(16)).foregroundStyle(ok(0.74, 0.19, h))
                        Text(station.name).font(Fonts.display(11)).spacing(0.12, size: 11)
                            .neon(active ? ok(0.74, 0.19, h) : .clear, radius: 5)
                    }
                    Text(t.map { "\($0.artist) — \($0.title)" } ?? station.tag)
                        .font(Fonts.body(12))
                        .foregroundStyle(active ? ok(0.88, 0.13, h + 60) : .white.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if playing {
                        EqBars(hue: h)
                    } else if let n = player.meta.listeners[station.id] {
                        Text("◉ \(n)").font(Fonts.mono(15)).foregroundStyle(Palette.ink3)
                    }
                }
            }
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 12))
            .background(RoundedRectangle(cornerRadius: 6).fill(ok(0.74, 0.19, h, active ? 0.16 : hovering ? 0.1 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ok(0.74, 0.19, h, active ? 0.55 : 0), lineWidth: 1))
            .shadow(color: ok(0.6, 0.22, h, active ? 0.25 : 0), radius: 12)
            .offset(x: hovering && !active ? 4 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .hoverEffect(.highlight)
        .onHover { on in
            hovering = on
            hover = on ? index : (hover == index ? nil : hover)
        }
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.25), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tape \(index + 1), \(station.name)")
        .accessibilityValue(playing ? "Playing" : t.map { "\($0.artist), \($0.title)" } ?? station.tag)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// A cassette seen edge-on: the tape's spine with a vertical label.
private struct Spine: View {
    var hue: Double
    var code: String

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(LinearGradient(stops: [.init(color: ok(0.5, 0.2, hue), location: 0),
                                         .init(color: ok(0.76, 0.16, hue), location: 0.5),
                                         .init(color: ok(0.5, 0.2, hue), location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: 26, height: 58)
            .overlay {
                Text(code)
                    .font(.custom("Syncopate-Bold", fixedSize: 7))
                    .tracking(1)
                    .foregroundStyle(Palette.labelInk)
                    .fixedSize()
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 1).fill(ok(0.96, 0.025, hue + 40)))
                    .rotationEffect(.degrees(-90))
            }
            .shadow(color: ok(0.6, 0.22, hue, 0.4), radius: 7)
    }
}

/// Little bouncing equaliser next to the playing tape.
private struct EqBars: View {
    var hue: Double
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: phase != .active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array([(0.9, 0.0), (0.7, 0.3), (1.1, 0.5), (0.8, 0.15)].enumerated()), id: \.offset) { _, d in
                    let ph = ((t + d.1) / d.0).truncatingRemainder(dividingBy: 2)
                    let tri = ph < 1 ? ph : 2 - ph
                    let e = 0.5 - 0.5 * cos(tri * .pi)
                    Rectangle().fill(ok(0.74, 0.19, hue)).frame(width: 3, height: 3 + 13 * e)
                        .shadow(color: ok(0.74, 0.19, hue), radius: 3)
                }
            }
            .frame(height: 16, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

/* ------------------------------------------------------------------ stage */

private struct Stage: View {
    @Environment(Player.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let tapeW = min(520, max(260, min(w * 0.42, h * 0.46 * 300 / 190)))
            let i = player.stationIdx
            let st = player.station
            let n = player.meta.listeners[st.id]
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    (Text("TAPE \(Stations.tapeNum(i)) / \(Stations.total) · SIDE A")
                        + Text(n.map { " · \($0) TUNED IN" } ?? "").foregroundStyle(Palette.ink3))
                        .font(Fonts.mono(19)).spacing(0.16, size: 19).foregroundStyle(theme.acc)
                    StationName(name: st.name, size: min(76, max(34, w * 0.052)))
                    Text(st.tag).font(Fonts.body(15)).foregroundStyle(Palette.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 18) {
                    Spacer(minLength: 0)
                    DeckSlot(width: tapeW, height: 14).opacity(0.85)
                    DeckTape(width: tapeW, tilt: 14)
                }
                .padding(.bottom, 8)

                Console().frame(maxWidth: 720)
            }
            .padding(.horizontal, min(64, max(24, w * 0.04)))
            .padding(.top, min(40, max(20, h * 0.035)))
            .padding(.bottom, min(32, max(16, h * 0.03)))
        }
    }
}

private struct Console: View {
    @Environment(Player.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        let st = player.station
        let t = player.meta.tracks[st.id]
        VStack(spacing: 14) {
            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t?.title.nonEmpty ?? "Tuning in…").font(Fonts.body(22, weight: .semibold)).lineLimit(1)
                    Text(t?.artist.nonEmpty ?? "Waiting for the signal").font(Fonts.body(15)).foregroundStyle(theme.acc2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                HStack(spacing: 16) {
                    RoundButton(forward: false)
                    PlayButton()
                    RoundButton(forward: true)
                }
            }
            Timeline(stationID: st.id, bars: 64, height: 26, font: 16)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial.opacity(0.4)))
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.bg.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1))
    }
}

/* ------------------------------------------------------------------ side panel */

private struct SidePanel: View {
    var overlay = false
    @Environment(Player.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        let st = player.station
        let log = player.meta.history[st.id] ?? []
        VStack(spacing: 0) {
            PanelHead(title: "SIGNAL FX")
            ScrollView {
                VStack(spacing: 12) {
                    Card { FxToggles() }
                    Card(title: "SLEEP TIMER", padded: true) { SleepTimerPanel() }
                    Card(title: "AUDIO") { AudioSettingsPanel() }
                    Card(title: "ON-AIR LOG · \(st.name)") {
                        if log.isEmpty {
                            Text("Listening for track changes…").font(Fonts.body(13)).foregroundStyle(Palette.ink3)
                                .padding(.top, 4).padding(.bottom, 12)
                        } else {
                            Rows {
                                ForEach(Array(log.enumerated()), id: \.offset) { k, x in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(k == 0 ? "NOW" : String(format: "%02d", k))
                                            .font(Fonts.mono(15))
                                            .foregroundStyle(k == 0 ? theme.acc : Palette.ink3)
                                            .neon(k == 0 ? theme.acc : .clear, radius: 4)
                                            .frame(width: 36, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(x.title).font(Fonts.body(13, weight: .medium)).lineLimit(1)
                                            Text(x.artist).font(Fonts.body(12)).foregroundStyle(theme.acc2).lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, 8)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .background(overlay ? Palette.bg.opacity(0.86) : .clear)
        .modifier(Chrome())
        .overlay(alignment: .leading) { Rectangle().fill(theme.line).frame(width: 1) }
        .shadow(color: overlay ? .black.opacity(0.5) : .clear, radius: 25, x: -20)
    }
}

/* ------------------------------------------------------------------ status bar */

private struct StatusBar: View {
    @Environment(Player.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        let st = player.status
        let total = player.meta.totalListeners
        HStack(spacing: 22) {
            Item(ok: st == .playing, text: "STREAM " + (st == .playing ? "320 KBPS · MP3" : "\(st)".uppercased()))
            Item(ok: player.meta.online, text: "META " + (player.meta.online ? "LIVE" : "OFFLINE"))
            if total > 0 { Text("\(total) LISTENERS ON THE NETWORK") }
            if player.sleepEnd != nil { Text("SLEEP ARMED").foregroundStyle(theme.acc2) }
            Spacer(minLength: 0)
            Text("SPACE PLAY · ← → TUNE · M MUTE").foregroundStyle(Palette.ink3.opacity(0.8))
        }
        .font(Fonts.mono(15))
        .spacing(0.08, size: 15)
        .foregroundStyle(Palette.ink3)
        .lineLimit(1)
        .padding(.horizontal, 20)
        .frame(height: 32)
        .modifier(Chrome())
        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
    }

    private struct Item: View {
        var ok: Bool
        var text: String
        var body: some View {
            HStack(spacing: 6) {
                Circle().fill(ok ? Palette.good : .white.opacity(0.3)).frame(width: 6, height: 6)
                    .shadow(color: ok ? Palette.good : .clear, radius: 3)
                Text(text)
            }
        }
    }
}
