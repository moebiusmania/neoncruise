import SwiftUI

struct Card<Content: View>: View {
    var title: String?
    var padded = false
    @ViewBuilder var content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(Fonts.display(11))
                    .spacing(0.16, size: 11)
                    .lineLimit(1)
                    .padding(.top, padded ? 0 : 16)
                    .padding(.bottom, padded ? 12 : 4)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, padded ? 18 : 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial.opacity(0.5)))
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.glass))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
    }
}

struct NeonSwitch: View {
    var on: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        Capsule().fill(on ? theme.acc : .white.opacity(0.16))
            .frame(width: 50, height: 28)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 22, height: 22).padding(3)
                    .shadow(color: on ? theme.acc : .clear, radius: 5)
            }
            .animation(.spring(duration: 0.25), value: on)
    }
}

struct ToggleRow: View {
    var label: String
    var desc: String
    var on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(Fonts.display(11)).spacing(0.16, size: 11)
                    Text(desc).font(Fonts.body(13)).foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                NeonSwitch(on: on)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.capitalized)
        .accessibilityHint(desc)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .sensoryFeedback(.selection, trigger: on)
    }
}

/// Rows separated by hairlines (the web's `.rows > * + *` border).
struct Rows<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Group(subviews: content) { subviews in
            VStack(spacing: 0) {
                ForEach(subviews.indices, id: \.self) { i in
                    if i > 0 { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
                    subviews[i]
                }
            }
        }
    }
}

struct FxToggles: View {
    @Environment(Player.self) private var player

    var body: some View {
        @Bindable var p = player
        Rows {
            ToggleRow(label: "SCANLINES", desc: "CRT raster across the app", on: p.settings.scan) { p.settings.scan.toggle() }
            ToggleRow(label: "FLICKER", desc: "Unstable tube brightness", on: p.settings.flicker) { p.settings.flicker.toggle() }
            ToggleRow(label: "NOISE", desc: "Analog grain on screen", on: p.settings.noise) { p.settings.noise.toggle() }
        }
    }
}

struct SleepTimerPanel: View {
    @Environment(Player.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        let end = player.sleepEnd
        let left = end.map { max(0, $0.timeIntervalSince(player.now)) } ?? 0
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(String(format: "%03d", end == nil ? 0 : Int(ceil(left / 60))))
                    .font(Fonts.mono(72))
                    .foregroundStyle(theme.acc2)
                    .neon(theme.acc, radius: 8)
                    .contentTransition(.numericText())
                Text("MIN").font(Fonts.mono(18)).spacing(0.12, size: 18).foregroundStyle(Palette.ink3)
            }
            .accessibilityElement(children: .combine)
            Text(end.map { "Tape fades out at \($0.formatted(date: .omitted, time: .shortened)) · \(fmtTime(left)) left" }
                 ?? "Plays until you stop it")
                .font(Fonts.body(13))
                .foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 6) {
                ForEach(Player.sleepOptions, id: \.self) { m in
                    let on = player.sleepMin == m
                    Button { player.setSleep(m) } label: {
                        Text(m == 0 ? "OFF" : "\(m)")
                            .font(Fonts.mono(18)).spacing(0.08, size: 18)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(on ? Palette.bg : .white.opacity(0.8))
                            .background(RoundedRectangle(cornerRadius: 3).fill(on ? theme.acc : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(on ? theme.acc : Palette.line, lineWidth: 1))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(m == 0 ? "Sleep timer off" : "\(m) minutes")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

struct AudioSettingsPanel: View {
    @Environment(Player.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var p = player
        let vol = p.settings.volume
        Rows {
            HStack(spacing: 12) {
                Button(action: player.toggleMute) {
                    SpeakerIcon(level: vol).foregroundStyle(theme.acc2).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(vol > 0 ? "Mute" : "Unmute")
                NeonSlider(value: Binding(get: { p.settings.volume }, set: { player.setVolume($0) }))
                    .accessibilityLabel("Volume")
                Text(String(format: "%03d", Int((vol * 100).rounded())))
                    .font(Fonts.mono(18)).foregroundStyle(Palette.ink3)
                    .frame(width: 34, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 14)
            ToggleRow(label: "REACTIVE", desc: "Grid and spectrum follow the real audio", on: p.settings.reactive) {
                p.settings.reactive.toggle()
            }
            ToggleRow(label: "TAPE HISS",
                      desc: p.settings.reactive ? "Mix faint analog hiss into the stream" : "Needs REACTIVE on",
                      on: p.settings.hiss && p.settings.reactive) {
                if p.settings.reactive { p.settings.hiss.toggle() } else {
                    p.settings.reactive = true
                    p.settings.hiss = true
                }
            }
        }
    }
}

/// Thin neon track with a glowing white thumb.
struct NeonSlider: View {
    @Binding var value: Double
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16)).frame(height: 4)
                Capsule().fill(theme.acc).frame(width: max(4, w * value), height: 4)
                    .shadow(color: theme.acc.opacity(0.4), radius: 4)
                Circle().fill(.white).frame(width: 18, height: 18)
                    .shadow(color: theme.acc, radius: 5)
                    .offset(x: (w - 18) * value)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = min(1, max(0, (g.location.x - 9) / max(1, w - 18)))
            })
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: value = min(1, value + 0.05)
            case .decrement: value = max(0, value - 0.05)
            @unknown default: break
            }
        }
    }
}

struct MiniPlayer: View {
    @Environment(Player.self) private var player

    var body: some View {
        let st = player.station
        let t = player.meta.tracks[st.id]
        HStack(spacing: 12) {
            HStack {
                Circle().fill(Palette.deep).frame(width: 8, height: 8)
                Spacer()
                Circle().fill(Palette.deep).frame(width: 8, height: 8)
            }
            .padding(.horizontal, 6)
            .frame(width: 44, height: 28)
            .background(RoundedRectangle(cornerRadius: 4).fill(
                LinearGradient(colors: [ok(0.76, 0.16, st.hue), ok(0.5, 0.2, st.hue)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 2) {
                Text(t?.title.nonEmpty ?? "Tuning in…").font(Fonts.body(14, weight: .semibold)).lineLimit(1)
                Text("\(st.name) FM · \(t?.artist.nonEmpty ?? "Waiting for the signal")")
                    .font(Fonts.body(12)).foregroundStyle(Palette.ink3).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PlayButton(size: 44, small: true)
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 10))
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.bg.opacity(0.8)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1), lineWidth: 1))
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
