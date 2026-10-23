//
//  DrillChrome.swift
//  The screen of the practice drill (the mockup Train.dc.html): the X, the title and lap, the stat card (Waddle bar, +N, Streak / Perfect / Stumbles chips),
//  the L / R prompts scrolling toward the ring, "Perfect!", the two big foot buttons, and the results card with the bar filling.
//  Drawn over the 3D track by RaceChrome while `race.isDrill`.
//

import SwiftUI

struct DrillChrome: View {
    let care: GameCare
    private var race: RaceFlow { care.race }
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    @Environment(\.verticalSizeClass) private var vsc
    private var compact: Bool { vsc == .compact }

    var body: some View {
        ZStack {
            if compact { landscapeBody } else { portraitBody }
            if race.showsCountdown { numeral(race.ui.countdown == 0 ? "" : "\(race.ui.countdown)") }
            if race.showsGo { numeral("GO!") }
            SK.cream.opacity(Double(race.dip)).ignoresSafeArea().allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drill-screen")
    }

    /// A phone on its side: the X and the title top left, the stat card top right, the foot buttons at the two lower corners with the prompt strip between them,
    /// so the Jelly (centre of the screen, a little above the middle) stays clear.
    private var landscapeBody: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                topBar.frame(maxWidth: 330)
                if race.drill != nil, race.drillResult == nil { Spacer(minLength: 0); statCard.frame(maxWidth: 330) }
                else if race.showsCountdown || race.drill == nil { Spacer(minLength: 0); hintPill(race.ui.phase == .countdown ? "Tap the foot that lights up, on the beat" : "") }
                else { Spacer(minLength: 0) }
            }
            if let r = race.drillResult {
                Spacer(minLength: 0)
                DrillResultCard(result: r, care: care) { race.goHome() }
                    .frame(maxWidth: 520).transition(.scale(scale: 0.88).combined(with: .opacity))
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                if race.assist == .oneButton || race.assist == .auto {
                    VStack(spacing: 6) {
                        if race.drill != nil { ZStack { flash.padding(.bottom, 58); promptRow.padding(.top, 26) }.frame(height: 110) }
                        drillInput(landscapeWidth: nil).frame(height: 110).padding(.horizontal, 60)
                    }
                } else {
                    HStack(alignment: .bottom, spacing: 12) {
                        FootButton(title: "Left", id: "drill-left", symbol: "shoeprints.fill", flip: false, live: race.buttonsLive, key: .leftArrow) { press(0) }.frame(width: 170, height: 140)
                        if race.drill != nil {
                            ZStack { flash.padding(.bottom, 58); promptRow.padding(.top, 26) }.frame(height: 110)
                        } else { Spacer(minLength: 0) }
                        FootButton(title: "Right", id: "drill-right", symbol: "shoeprints.fill", flip: true, live: race.buttonsLive, key: .rightArrow) { press(1) }.frame(width: 170, height: 140)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
        .animation(CareMenu.spring, value: race.drillResult != nil)
    }

    private var portraitBody: some View {
        ZStack {
            VStack(spacing: 10) {
                topBar
                if race.drill != nil, race.drillResult == nil { statCard }
                else if race.showsCountdown || race.drill == nil { hintPill(race.ui.phase == .countdown ? "Tap the foot that lights up, on the beat" : "") }
                Spacer(minLength: 0)
                if race.drillResult == nil, race.drill != nil {
                    ZStack {
                        flash
                        promptRow.padding(.top, 34)
                    }
                    .frame(height: 124)
                }
                if let r = race.drillResult {
                    DrillResultCard(result: r, care: care) { race.goHome() }
                        .padding(.horizontal, 8).transition(.scale(scale: 0.88).combined(with: .opacity))
                    Spacer(minLength: 0)
                } else { footButtons }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
            .animation(CareMenu.spring, value: race.drillResult != nil)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { AudioHub.shared.uiTap(); race.quitDrill() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .black)).foregroundStyle(SK.ink)
                    .frame(width: 44, height: 44).background(Circle().fill(SK.cream))
            }
            .buttonStyle(.plain).accessibilityLabel("Stop practice").accessibilityIdentifier("drill-quit")
            VStack(spacing: 2) {
                Text("Rhythm Steps").font(SK.font(17, .black)).foregroundStyle(SK.ink)
                Text("Builds Waddle · lap \(min(race.drillUI.lap, race.drillUI.laps)) of \(race.drillUI.laps)").font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
                    .accessibilityIdentifier("drill-lap")
            }
            .padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SK.cream))
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private func hintPill(_ s: String) -> some View {
        Group {
            if !s.isEmpty {
                Text(s).font(SK.font(15, .bold)).foregroundStyle(SK.ink)
                    .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(SK.cream.opacity(0.92)))
            }
        }
    }

    // MARK: stat card

    private var statCard: some View {
        let st = race.stats
        let d = race.drill
        let w = st?.waddle ?? 0
        let gain = st?.practiceGain(accuracy: d?.accuracy ?? 0, steadiness: d?.steadiness ?? 0).waddle ?? 0
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("Waddle").font(SK.font(15, .black)).foregroundStyle(SK.ink).frame(width: 62, alignment: .leading)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0xE6D8C6))
                        Capsule().fill(Color(hex: 0xFFD1BF)).frame(width: max(14, g.size.width * CGFloat(min(1, w + gain))))
                        Capsule().fill(SK.pink).frame(width: max(14, g.size.width * CGFloat(w)))
                    }
                }.frame(height: 14)
                Text("+\(DrillResultCard.points(gain))").font(SK.font(14, .black)).foregroundStyle(Color(hex: 0xC0603D)).monospacedDigit()
                    .frame(minWidth: 34, alignment: .trailing).accessibilityIdentifier("drill-gain")
            }
            HStack(spacing: 8) {
                chip("Streak \(race.drillUI.streak)", bg: Color(hex: 0xFFE7A8), fg: Color(hex: 0x6B4A00))
                chip("Perfect \(race.drillUI.perfects)", bg: Color(hex: 0xE3F4DD), fg: Color(hex: 0x2E6B26))
                chip("Stumbles \(race.drillUI.misses)", bg: Color(hex: 0xF2ECE6), fg: SK.muted)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SK.cream.opacity(0.94)))
        .accessibilityElement(children: .contain).accessibilityIdentifier("drill-stats")
    }

    private func chip(_ s: String, bg: Color, fg: Color) -> some View {
        Text(s).font(SK.font(13, .black)).foregroundStyle(fg).padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(bg))
    }

    // MARK: prompts

    private var flash: some View {
        VStack {
            Group {
                switch race.drillUI.flash {
                case .perfect?: Text("Perfect!")
                case .good?: Text("Good")
                case .miss?: Text("Oops")
                case nil: Text(" ")
                }
            }
            .font(SK.font(24, .black)).foregroundStyle(.white)
            .shadow(color: SK.ink.opacity(0.5), radius: 4, y: 2)
            .id(race.drillUI.flashSerial)
            .transition(.scale(scale: 1.4).combined(with: .opacity))
            .accessibilityIdentifier("drill-flash")
            Spacer()
        }
        .animation(.easeOut(duration: 0.12), value: race.drillUI.flashSerial)
        .allowsHitTesting(false)
    }

    private var promptRow: some View {
        TimelineView(.animation) { _ in
            let song = AudioHub.shared.trainingSongTime() ?? race.drillState.song
            let items = race.drill?.visible(at: song) ?? []
            ZStack(alignment: .leading) {
                Capsule().fill(SK.ink.opacity(0.72))
                Circle().strokeBorder(Color(hex: 0xFFF6EC), lineWidth: 4).frame(width: 60, height: 60).padding(.leading, 14)
                ForEach(items, id: \.prompt.index) { it in
                    let near = it.ahead < 0.5
                    Text(it.prompt.foot == 0 ? "L" : "R").font(SK.font(near ? 22 : 18, .black)).foregroundStyle(.white)
                        .frame(width: near ? 54 : 46, height: near ? 54 : 46)
                        .background(Circle().fill(it.prompt.foot == 0 ? SK.sky : SK.pink))
                        .opacity(max(0.4, 1 - 0.13 * max(it.ahead, 0)))
                        .offset(x: 14 + 30 - (near ? 27 : 23) + CGFloat(max(it.ahead, -0.3)) * 62)
                }
            }
            .frame(height: 84)
            .clipShape(Capsule())
        }
        .accessibilityElement().accessibilityLabel("Prompts").accessibilityIdentifier("drill-prompts")
        .accessibilityValue(nextPromptWord)
    }

    /// "Next: left" for a screen reader (the lane is also cued by sound under VoiceOver / relaxed timing).
    private var nextPromptWord: String {
        guard let p = race.drill?.visible(at: race.drillState.song).first?.prompt else { return "" }
        return race.assist == .oneButton ? "Next step" : "Next: \(p.foot == 0 ? "left" : "right")"
    }

    private var footButtons: some View {
        drillInput(landscapeWidth: nil).frame(height: 150)
    }

    /// The drill's input for the chosen assist: two feet, one Step button (judged on the beat whichever foot), or nothing to tap while he practises by himself.
    @ViewBuilder
    private func drillInput(landscapeWidth: CGFloat?) -> some View {
        switch race.assist {
        case .oneButton:
            FootButton(title: "Step", id: "drill-step", symbol: "shoeprints.fill", flip: false, live: race.buttonsLive, key: .space) { press(0) }
        case .auto:
            FootButton(title: "Cheer", id: "drill-cheer", symbol: "hands.clap.fill", flip: false, live: true, key: .space) { AudioHub.shared.chirp(jelly: race.playerID, .happy) }
        default:
            HStack(spacing: 14) {
                FootButton(title: "Left", id: "drill-left", symbol: "shoeprints.fill", flip: false, live: race.buttonsLive, key: .leftArrow) { press(0) }
                FootButton(title: "Right", id: "drill-right", symbol: "shoeprints.fill", flip: true, live: race.buttonsLive, key: .rightArrow) { press(1) }
            }
        }
    }

    private func press(_ foot: Int) {
        light.impactOccurred(intensity: 0.5)
        race.tap(foot: foot)          // (the one-button Step is foot 0: the drill judges the beat whichever foot it is)
    }

    private func numeral(_ s: String) -> some View {
        Text(s)
            .font(.system(size: s == "GO!" ? 96 : 120, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: SK.pink.opacity(0.9), radius: 0, x: 0, y: 5)
            .shadow(color: SK.shadow.opacity(0.35), radius: 10, y: 6)
            .id(race.cueSerial)
            .transition(.scale(scale: 1.6).combined(with: .opacity))
            .allowsHitTesting(false)
            .offset(y: compact ? 40 : 70)          // below the (closer) Jelly, above the prompt strip
    }
}

struct DrillResultCard: View {
    let result: DrillResult
    let care: GameCare
    var done: () -> Void
    @State private var shown = false
    @Environment(\.verticalSizeClass) private var vsc

    static func points(_ v: Float) -> String {
        let p = v * 100
        return p >= 9.95 ? String(format: "%.0f", p) : String(format: "%.1f", max(p, 0))
    }

    var body: some View {
        let r = result
        VStack(spacing: vsc == .compact ? 6 : 12) {
            Text(r.accuracy >= 0.75 ? "Great practice!" : r.accuracy >= 0.45 ? "Nice practice!" : "Keep practising!")
                .font(SK.font(vsc == .compact ? 22 : 28, .black)).foregroundStyle(SK.ink)
            HStack(spacing: 8) {
                chip("Perfect \(r.perfects)", bg: Color(hex: 0xE3F4DD), fg: Color(hex: 0x2E6B26))
                chip("Good \(r.goods)", bg: Color(hex: 0xFFE7A8), fg: Color(hex: 0x6B4A00))
                chip("Stumbles \(r.misses)", bg: Color(hex: 0xF2ECE6), fg: SK.muted)
            }
            bar("Waddle", before: r.waddleBefore, after: r.waddleAfter, color: SK.pink, gain: r.waddleGain)
            if r.focusGain > 0.0004 { bar("Focus", before: r.focusBefore, after: r.focusAfter, color: SK.sky, gain: r.focusGain) }
            HStack(spacing: 6) {
                ForEach(0..<TrainingTuning.fullSessions, id: \.self) { i in
                    Circle().fill(i < r.pepLeft ? SK.honey : SK.ink.opacity(0.12)).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(SK.honeyDeep.opacity(i < r.pepLeft ? 1 : 0), lineWidth: 1.5))
                }
                Text(r.pepLeft > 0 ? "Pep left today" : "Pep used up. Practice still helps, just less.").font(SK.font(12, .bold)).foregroundStyle(SK.muted)
            }
            Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); done() } label: {
                Text("Done").font(SK.font(20, .black)).foregroundStyle(.white)
                    .padding(.horizontal, 44).padding(.vertical, vsc == .compact ? 8 : 12).background(Capsule().fill(SK.pink))
            }
            .buttonStyle(.plain).accessibilityIdentifier("drill-home")
        }
        .padding(.horizontal, 20).padding(.vertical, vsc == .compact ? 10 : 18)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.3), radius: 16, y: 8))
        .accessibilityElement(children: .contain).accessibilityIdentifier("drill-card")
        .onAppear { withAnimation(.easeOut(duration: 1.3).delay(0.35)) { shown = true } }
    }

    private func chip(_ s: String, bg: Color, fg: Color) -> some View {
        Text(s).font(SK.font(13, .black)).foregroundStyle(fg).padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(bg))
    }

    private func bar(_ name: String, before: Float, after: Float, color: Color, gain: Float) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(name).font(SK.font(16, .black)).foregroundStyle(SK.ink)
                Spacer()
                Text("+\(Self.points(gain)) \(name)").font(SK.font(16, .black)).foregroundStyle(Color(hex: 0xC0603D)).monospacedDigit()
                    .accessibilityIdentifier("drill-result-\(name.lowercased())")
            }
            GeometryReader { g in
                let v = shown ? after : before
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xE6D8C6))
                    Capsule().fill(color).frame(width: max(14, g.size.width * CGFloat(min(max(v, 0), 1))))
                    Capsule().fill(Color.white.opacity(0.55)).frame(width: 3, height: 14).offset(x: max(14, g.size.width * CGFloat(before)) - 3)
                }
            }.frame(height: 16)
        }
    }
}
