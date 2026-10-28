//
//  VolleyChrome.swift
//  Jelly Volleyball's screen furniture while the court is up: the score, the controls (drag the lower area to walk, the left / right buttons, a big Jump
//  button that serves, jumps, digs at a low ball and spikes when pressed again in the air), drill read-outs, the results card and the white fade.
//  Portrait: the arrows bottom left, Jump bottom right. Landscape: the same corners, bigger. Everything has VoiceOver labels and keyboard shortcuts.
//

import SwiftUI

struct VolleyChrome: View {
    let care: GameCare
    private var volley: VolleyFlow { care.volley }
    @Environment(\.verticalSizeClass) private var vsc
    private var compact: Bool { vsc == .compact }
    @State private var stickOrigin: CGPoint?
    @State private var stickKnob: CGSize = .zero
    @State private var hitDown = false
    @State private var aimShown: SIMD2<Float>?
    @State private var fxText = ""
    @State private var fxTone = 0
    @State private var fxY: CGFloat = 0
    @State private var fxOpacity: Double = 0

    var body: some View {
        ZStack {
            if volley.inScene {
                if volley.phase == .playing, volley.live { courtLayer }
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if volley.showsCard { VolleyResultsCard(volley: volley) { volley.goHome() }.padding(.horizontal, 24).transition(.scale(scale: 0.85).combined(with: .opacity)) }
                    Spacer()
                    if volley.phase == .playing, !volley.hasResults { controls }
                }
                .padding(.horizontal, 14).padding(.bottom, compact ? 8 : 14)
                .animation(CareMenu.spring, value: volley.showsCard)
                if volley.live, volley.ui.phase == .intro { banner(volley.isDrill ? "Ready?" : "Beach volley!") }
                Text(fxText).font(.system(size: fxTone == 3 ? 52 : 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(fxTone == 1 || fxTone == 3 ? Color(red: 1.0, green: 0.85, blue: 0.25) : fxTone == 2 ? Color.white.opacity(0.85) : .white)
                    .shadow(color: FocusStyle.pink.opacity(0.9), radius: 0, x: 0, y: 3).shadow(color: FocusStyle.shadow.opacity(0.35), radius: 6, y: 4)
                    .opacity(fxOpacity).offset(y: -120 + fxY).allowsHitTesting(false).accessibilityHidden(true)
                    .onChange(of: volley.ui.fxSerial) { _, _ in
                        fxText = volley.ui.fxText; fxTone = volley.ui.fxTone
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) { fxY = 10; fxOpacity = 1 }
                        withAnimation(.easeOut(duration: 1.0)) { fxY = -40; fxOpacity = 0 }
                    }
            }
            Color.white.opacity(Double(volley.wipe)).ignoresSafeArea().allowsHitTesting(false)
        }
        .allowsHitTesting(volley.active)
        .accessibilityElement(children: .contain)
    }

    // MARK: top

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                Button { AudioHub.shared.uiTap(); volley.goHome() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .black)).foregroundStyle(CareMenu.brown)
                        .frame(width: 44, height: 44).background(Circle().fill(CareMenu.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 5, y: 2))
                }.buttonStyle(.plain).accessibilityLabel("Leave the beach").accessibilityIdentifier("volley-leave")
                Spacer()
                scoreBoard
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            if volley.live, !volley.isDrill, !volley.ui.touchDots.isEmpty { touchDots }
            if let hint = hint { Text(hint).playFont(15, .semibold).foregroundStyle(CareMenu.brown).padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(CareMenu.cream.opacity(0.92))).transition(.opacity) }
            if let t = volley.toast { Text(t).playFont(14, .semibold).foregroundStyle(CareMenu.brown).padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(CareMenu.cream)) }
        }
        .padding(.top, 8)
    }

    /// 1 · 2 · 3: your side's touches this rally (gold = Perfect).
    private var touchDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<VolleyTuning.maxTouches, id: \.self) { k in
                let v = volley.ui.touchDots.indices.contains(k) ? volley.ui.touchDots[k] : 0
                Circle().fill(v == 2 ? Color(red: 1.0, green: 0.8, blue: 0.2) : v == 1 ? FocusStyle.pink : Color.white.opacity(0.5))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5)).frame(width: 15, height: 15)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(CareMenu.cream.opacity(0.85)))
        .accessibilityElement(children: .ignore).accessibilityLabel("Touch \(volley.ui.touchDots.filter { $0 > 0 }.count) of 3")
    }

    @ViewBuilder
    private var scoreBoard: some View {
        let u = volley.ui
        if case .drill(let k) = volley.mode {
            HStack(spacing: 10) {
                Text(k.title).playFont(15, .heavy)
                switch k {
                case .bonk: Text("\(u.drillCount) hits").playFont(17, .bold).monospacedDigit()
                case .block: Text("Ball \(min(u.drillFeeds, VolleySim.blockFeeds))/\(VolleySim.blockFeeds) · \(u.drillGood) blocked").playFont(15, .bold).monospacedDigit()
                case .spike: Text("Ball \(min(u.drillFeeds, VolleySim.spikeFeeds))/\(VolleySim.spikeFeeds) · \(u.drillGood) hit").playFont(15, .bold).monospacedDigit()
                case .sprint: Text("Flags \(u.drillFlags)/\(VolleySim.sprintFlags)").playFont(17, .bold).monospacedDigit()
                }
            }
            .foregroundStyle(CareMenu.brown).padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(CareMenu.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 6, y: 2))
            .accessibilityElement(children: .combine).accessibilityIdentifier("volley-score")
        } else {
            HStack(spacing: 12) {
                team(volley.playerName.isEmpty ? "You" : volley.playerName, u.score[0], serving: u.serveTeam == 0 && u.phase != .over)
                Text(":").playFont(20, .black).foregroundStyle(CareMenu.brown.opacity(0.6))
                team("Them", u.score[1], serving: u.serveTeam == 1 && u.phase != .over)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(CareMenu.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 6, y: 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Score. You \(u.score[0]), them \(u.score[1]). First to \(VolleyTuning.pointsToWin), win by 2. Controlling \(volley.teamNames.indices.contains(u.controlled) ? volley.teamNames[u.controlled] : "your Jelbie").")
            .accessibilityIdentifier("volley-score")
        }
    }

    private func team(_ name: String, _ pts: Int, serving: Bool) -> some View {
        HStack(spacing: 6) {
            if serving { Circle().fill(FocusStyle.pink).frame(width: 9, height: 9) }
            Text(name).playFont(14, .semibold).lineLimit(1)
            Text("\(pts)").playFont(34, .black).monospacedDigit()
        }.foregroundStyle(CareMenu.brown)
    }

    private var hint: String? {
        let u = volley.ui
        guard volley.live else { return nil }
        if volley.isDrill {
            if u.phase == .intro { return nil }
            switch volley.mode {
            case .drill(.bonk): return "Bump, set, bump! Hit when the ring meets the marker"
            case .drill(.spike): return "Tap to spike. Swipe the button to aim at the pink cushion"
            case .drill(.block): return "Tap at the net to block the spike"
            case .drill(.sprint): return "Run to the pink flag"
            default: return nil }
        }
        if u.humanServes { return "Your serve. Tap to toss, tap again at the top" }
        if u.waitingToServe { return "Their serve" }
        return nil
    }

    private func banner(_ s: String) -> some View {
        Text(s).font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            .shadow(color: FocusStyle.pink.opacity(0.9), radius: 0, x: 0, y: 4).shadow(color: FocusStyle.shadow.opacity(0.35), radius: 8, y: 5)
            .allowsHitTesting(false).offset(y: -40).transition(.opacity)
    }

    // MARK: controls

    private var assisted: Bool { volley.sim?.autoMove == true }

    /// The whole-screen layer under the HUD: the floating stick on the left half, the double-tap that switches control, the call bubbles.
    private var courtLayer: some View {
        GeometryReader { g in
            ZStack {
                Color.clear.contentShape(Rectangle())
                    .gesture(SpatialTapGesture(count: 2).onEnded { v in pick(v.location, g.size) })
                // the left half: the floating stick (it appears where the thumb lands)
                HStack(spacing: 0) {
                    ZStack {
                        Color.clear.contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    guard !assisted else { return }
                                    if stickOrigin == nil { stickOrigin = v.startLocation }
                                    let o = stickOrigin ?? v.startLocation
                                    var d = CGSize(width: v.location.x - o.x, height: v.location.y - o.y)
                                    let m = hypot(d.width, d.height), R: CGFloat = 54
                                    if m > R { d = CGSize(width: d.width / m * R, height: d.height / m * R) }
                                    stickKnob = d
                                    care.volleyStick(SIMD2(Float(d.width / R), Float(d.height / R)))
                                }
                                .onEnded { _ in stickOrigin = nil; stickKnob = .zero; care.volleyStick(.zero) })
                            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { v in pick(v.location, g.size) })
                            .padding(.top, 110)
                        if let o = stickOrigin {
                            ZStack {
                                Circle().fill(Color.white.opacity(0.22)).frame(width: 118, height: 118)
                                Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 2.5).frame(width: 118, height: 118)
                                Circle().fill(CareMenu.cream).frame(width: 52, height: 52).shadow(color: FocusStyle.shadow.opacity(0.25), radius: 4, y: 2).offset(stickKnob)
                            }.position(o).allowsHitTesting(false)
                        }
                    }
                    .frame(width: g.size.width * 0.5)
                    Spacer(minLength: 0).allowsHitTesting(false)
                }
                if !volley.ui.calls.isEmpty {
                    TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
                        ZStack {
                            ForEach(volley.ui.calls, id: \.self) { i in
                                if volley.bodyPos.indices.contains(i), let pt = GameCamera.screenPoint(floor: SIMD2(volley.bodyPos[i].x, volley.bodyPos[i].z), y: volley.bodyPos[i].y + 0.75, size: g.size) {
                                    Text("!").font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(.white)
                                        .frame(width: 36, height: 36).background(Circle().fill(FocusStyle.pink).shadow(color: FocusStyle.shadow.opacity(0.3), radius: 4, y: 2))
                                        .position(pt)
                                }
                            }
                        }
                    }.allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// A double-tap: the nearest of your two Jelbies to the finger takes control.
    private func pick(_ at: CGPoint, _ size: CGSize) {
        guard volley.live, !volley.isDrill else { return }
        var best: (Int, CGFloat)?
        for i in 0..<min(2, volley.bodyPos.count) {
            let p = volley.bodyPos[i]
            guard let pt = GameCamera.screenPoint(floor: SIMD2(p.x, p.z), y: p.y * 0.5, size: size) else { continue }
            let d = hypot(pt.x - at.x, pt.y - at.y)
            if d < 110, d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        if let (i, _) = best {
            if i != volley.ui.controlled { care.volleySwitch(to: i) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private var controls: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if assisted {
                Text("The Jelbie walks for you").playFont(13, .semibold).foregroundStyle(CareMenu.brown).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(CareMenu.cream.opacity(0.9))).padding(.bottom, 8)
            } else if stickOrigin == nil {
                Text("Hold the left side to move").playFont(12, .semibold).foregroundStyle(CareMenu.brown.opacity(0.85)).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(CareMenu.cream.opacity(0.75))).padding(.bottom, 10).allowsHitTesting(false)
            }
            Spacer(minLength: 0)
            hit
        }
        .frame(maxWidth: .infinity)
    }

    private var hit: some View {
        let serving = volley.ui.humanServes || volley.ui.serveMeter >= 0
        let size: CGFloat = compact ? 108 : 138
        return VStack(spacing: 6) {
            if volley.ui.serveMeter >= 0 { serveArc.frame(width: size + 10, height: 46) }
            ZStack {
                Circle().fill(hitDown ? FocusStyle.pink.opacity(0.6) : CareMenu.cream)
                    .shadow(color: FocusStyle.shadow.opacity(hitDown ? 0.12 : 0.28), radius: hitDown ? 4 : 9, y: hitDown ? 1 : 4)
                Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                VStack(spacing: 2) {
                    Image(systemName: serving ? "figure.volleyball" : "hand.tap.fill").font(.system(size: compact ? 26 : 34, weight: .bold))
                    Text(volley.ui.hitLabel).playFont(compact ? 18 : 22, .heavy)
                }.foregroundStyle(CareMenu.brown)
                if let a = aimShown {
                    // the ghost aim line: from the button's centre out toward where the hit will go
                    Path { p in p.move(to: CGPoint(x: size / 2, y: size / 2)); p.addLine(to: CGPoint(x: size / 2 + CGFloat(a.x) * size * 0.34, y: size / 2 + CGFloat(a.y) * size * 0.34)) }
                        .stroke(FocusStyle.pink.opacity(0.7), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [1, 9]))
                        .frame(width: size, height: size)
                    Circle().fill(FocusStyle.pink).frame(width: 14, height: 14).offset(x: CGFloat(a.x) * size * 0.34, y: CGFloat(a.y) * size * 0.34)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(hitDown ? 0.96 : 1)
            .opacity(volley.live ? 1 : 0.55)
            .animation(.easeOut(duration: 0.08), value: hitDown)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !hitDown { hitDown = true; aimShown = nil; care.volleyTap(touched: v.time) }
                    let dx = v.translation.width, dy = v.translation.height
                    if hypot(dx, dy) > 20 {
                        let a = SIMD2<Float>(Float(max(-1, min(1, dx / 52))), Float(max(-1, min(1, dy / 52))))
                        aimShown = a; care.volleyAim(a)
                    }
                }
                .onEnded { _ in hitDown = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if !hitDown { aimShown = nil } } })
            .background { Button("") { care.volleyTap() }.keyboardShortcut(.space, modifiers: []).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true) }
            .accessibilityElement().accessibilityLabel(volley.ui.hitLabel).accessibilityIdentifier("volley-jump").accessibilityAddTraits(.isButton)
            .accessibilityHint("Tap to hit. The move depends on the touch: bump, set, spike, dig or block. Swipe the button to aim: left short, right deep, up far, down near.")
            .accessibilityAction { care.volleyTap() }
        }
    }

    /// The serve meter: a small arc with the sweet spot marked; tap again when the dot is in it.
    private var serveArc: some View {
        let u = volley.ui
        let lo: Double = 200 + 140 * Double(u.serveSweet - u.serveHalf)
        let hi: Double = 200 + 140 * Double(u.serveSweet + u.serveHalf)
        let t: Double = Double(min(max(u.serveMeter, 0), 1))
        return GeometryReader { g in
            let r: CGFloat = g.size.width / 2
            let c = CGPoint(x: g.size.width / 2, y: g.size.height + r * 0.2)
            let ang: Double = Angle.degrees(200 + 140 * t).radians
            let dot = CGPoint(x: c.x + CGFloat(cos(ang)) * r, y: c.y + CGFloat(sin(ang)) * r)
            ZStack {
                ServeArcShape(from: 200, to: 340).stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                ServeArcShape(from: lo, to: hi).stroke(Color(red: 1.0, green: 0.8, blue: 0.2), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                Circle().fill(FocusStyle.pink).frame(width: 16, height: 16).position(dot)
            }
        }.allowsHitTesting(false)
    }
}

struct ServeArcShape: SwiftUI.Shape {
    var from: Double, to: Double
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.height + r * 0.2), radius: r, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
        return p
    }
}

/// A button that reports press and release (the arrows hold).
struct HoldButton: View {
    let symbol: String
    let title: String
    let id: String
    var key: KeyEquivalent?
    var size: CGFloat = 84
    let change: (Bool) -> Void
    @State private var down = false
    var body: some View {
        Image(systemName: symbol).font(.system(size: 34, weight: .black)).foregroundStyle(CareMenu.brown)
            .frame(width: size, height: size * 0.95)
            .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(down ? FocusStyle.pink.opacity(0.55) : CareMenu.cream)
                .shadow(color: FocusStyle.shadow.opacity(down ? 0.12 : 0.28), radius: down ? 4 : 9, y: down ? 1 : 4))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
            .scaleEffect(down ? 0.96 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !down { down = true; change(true) } }
                .onEnded { _ in down = false; change(false) })
            .background { if let key { Button("") { change(true); DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { change(false) } }.keyboardShortcut(key, modifiers: []).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true) } }
            .accessibilityElement().accessibilityLabel(title).accessibilityIdentifier(id).accessibilityAddTraits(.isButton)
            .accessibilityAction { change(true); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { change(false) } }
    }
}

struct VolleyResultsCard: View {
    let volley: VolleyFlow
    let home: () -> Void
    @Environment(\.verticalSizeClass) private var vsc
    private var tight: Bool { vsc == .compact }

    private func chip(_ text: String, _ symbol: String, _ id: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: UIImage(systemName: symbol) != nil ? symbol : "star.fill").font(.system(size: 14, weight: .black))
            Text(text).playFont(14, .heavy)
        }.foregroundStyle(CareMenu.brown).padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(Color(red: 0.98, green: 0.80, blue: 0.35))).accessibilityElement(children: .combine).accessibilityIdentifier(id)
    }

    var body: some View {
        let s = volley.sim
        VStack(spacing: tight ? 6 : 12) {
            if case .drill(let k) = volley.mode {
                Text("\(k.title) done!").playFont(tight ? 22 : 28, .heavy).foregroundStyle(CareMenu.brown)
                Text(summary(s)).playFont(18, .semibold).foregroundStyle(CareMenu.brown)
                VStack(spacing: 4) {
                    gainRow("Speed", volley.gain.speed); gainRow("Power", volley.gain.power); gainRow("Hops", volley.gain.hops); gainRow("Timing", volley.gain.timing)
                    if volley.gain.speed + volley.gain.power + volley.gain.hops + volley.gain.timing < 0.0005 { Text("Tired legs: a rest helps. Pep comes back tomorrow.").playFont(13, .medium).foregroundStyle(CareMenu.brown.opacity(0.85)) }
                }
            } else {
                Text(s?.humanTeamWon == true ? "You won!" : "Good game!").playFont(tight ? 24 : 32, .heavy).foregroundStyle(CareMenu.brown)
                Text("\(s?.score[0] ?? 0)  :  \(s?.score[1] ?? 0)").playFont(30, .heavy).monospacedDigit().foregroundStyle(CareMenu.brown)
                HStack(spacing: 8) {
                    JellyCoinIcon(size: 22)
                    Text("+\(volley.earned) JellyCoins").playFont(20, .bold).foregroundStyle(CareMenu.brown)
                }
                if volley.assistFactor < 1 { Text("Auto play pays half").playFont(14, .medium).foregroundStyle(CareMenu.brown.opacity(0.85)) }
                if !volley.awards.isEmpty {
                    HStack(spacing: 8) {
                        if volley.awards.newRibbon { chip("New ribbon!", "rosette", "volley-new-ribbon") }
                        if let t = volley.awards.trophies.first { chip("Trophy! \(t.title)", "trophy.fill", "volley-trophy") }
                    }
                }
                if let t = volley.unlockedNow { Text("\(t.title) unlocked!").playFont(15, .heavy).foregroundStyle(SK.pink).accessibilityIdentifier("volley-unlocked") }
            }
            Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); home() } label: {
                Text("Back home").playFont(20, .bold).foregroundStyle(.white).padding(.horizontal, 30).padding(.vertical, tight ? 8 : 12)
                    .background(Capsule().fill(SK.pink).shadow(color: FocusStyle.shadow.opacity(0.25), radius: 6, y: 3))
            }.buttonStyle(.plain).accessibilityIdentifier("volley-home")
        }
        .padding(.horizontal, 22).padding(.vertical, tight ? 10 : 20)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(CareMenu.cream).shadow(color: FocusStyle.shadow.opacity(0.3), radius: 16, y: 8))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
        .accessibilityElement(children: .contain).accessibilityIdentifier("volley-card")
    }

    private func summary(_ s: VolleySim?) -> String {
        guard let s else { return "" }
        switch s.drillKind {
        case .bonk?: return "\(s.drillCount) hits, \(s.drillPerfect) Perfect"
        case .block?: return "\(s.drillGood) of \(VolleySim.blockFeeds) blocked"
        case .spike?: return "\(s.drillGood) of \(VolleySim.spikeFeeds) on the cushion"
        case .sprint?: return "\(s.flagIndex) of \(VolleySim.sprintFlags) flags"
        case nil: return ""
        }
    }
    @ViewBuilder
    private func gainRow(_ name: String, _ v: Float) -> some View {
        if v > 0.0005 {
            HStack { Text(name).playFont(16, .semibold); Spacer(); Text("+\(Int((v * 100).rounded(.up)))").playFont(16, .heavy).monospacedDigit() }
                .foregroundStyle(CareMenu.brown).frame(width: 180)
        }
    }
}

// MARK: - The Town screen: pick a Jelbie, a tier, play or train

struct VolleyLobby: View {
    let care: GameCare
    @Binding var who: Int
    var back: () -> Void
    var play: (VolleyTier) -> Void
    var drill: (VolleyDrillKind) -> Void
    @Environment(\.verticalSizeClass) private var vsc
    private var book: VolleyBook { care.volley.book }

    var body: some View {
        let prof = care.jelly(who)
        let compact = vsc == .compact
        VStack(spacing: compact ? 8 : 14) {
            HStack(spacing: 10) {
                Button { AudioHub.shared.uiTap(); back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .black)).foregroundStyle(SK.ink)
                        .frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.85)))
                }.buttonStyle(.plain).accessibilityLabel("Back").accessibilityIdentifier("volley-back")
                Text("Beach Volleyball").font(SK.font(28, .black)).foregroundStyle(SK.ink)
                Spacer()
                DropsPill(wallet: care.bath.wallet)
            }
            ScrollView {
                if compact {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 10) { matchCard(prof); tiers }
                        VStack(spacing: 10) { statCard(prof); drills(prof) }
                    }
                } else {
                    VStack(spacing: 12) { matchCard(prof); tiers; statCard(prof); drills(prof) }
                }
            }.scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        .background(SK.cream.ignoresSafeArea())
        .accessibilityElement(children: .contain).accessibilityIdentifier("volley-lobby")
    }

    private var blocker: String? { care.volleyBlocker(jelly: who) }

    private func matchCard(_ prof: JellyProfile?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "figure.volleyball").font(.system(size: 26, weight: .heavy)).foregroundStyle(SK.ink)
                    .frame(width: 62, height: 62).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SK.honey))
                VStack(alignment: .leading, spacing: 3) {
                    Text("2 vs 2 on the sand").font(SK.font(20, .black)).foregroundStyle(SK.ink)
                    Text("Bump, set, spike: three touches a side. Time your tap to the ring for a Perfect. Double-tap a Jelbie to steer him. First to \(VolleyTuning.pointsToWin), win by 2.").font(SK.font(12, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            if care.jellies.count > 1 { WhoRow(care: care, who: $who) }
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiConfirm(); play(book.chosen)
            } label: {
                Text("Play \(book.chosen.title)").font(SK.font(18, .black)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(blocker == nil ? SK.pink : SK.muted.opacity(0.45)))
            }.buttonStyle(.plain).disabled(blocker != nil).accessibilityIdentifier("volley-play")
            if let b = blocker { Text(b).font(SK.font(12, .bold)).foregroundStyle(SK.muted) }
            if care.jellies.count > 1, let p2 = care.jellies.first(where: { $0.id != who }) { Text("Team: \(prof?.name ?? "Bob") + \(p2.name)").font(SK.font(12, .bold)).foregroundStyle(SK.muted) }
            else { Text("Team: your Jelbie + a Park friend").font(SK.font(12, .bold)).foregroundStyle(SK.muted) }
            Toggle(isOn: Binding(get: { book.autoSwitch }, set: { book.autoSwitch = $0 })) {
                Text("Auto-switch Jelbies").font(SK.font(14, .heavy)).foregroundStyle(SK.ink)
            }.tint(SK.pink).accessibilityIdentifier("volley-autoswitch")
            Toggle(isOn: Binding(get: { book.slowBall }, set: { book.slowBall = $0 })) {
                Text("Slower ball").font(SK.font(14, .heavy)).foregroundStyle(SK.ink)
            }.tint(SK.pink).accessibilityIdentifier("volley-slow")
            if A11ySettings.shared.raceAssist != .off { Text("Play assist is on (Settings > Accessibility): the Jelbie walks to the ball for you.").font(SK.font(11, .bold)).foregroundStyle(SK.muted) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
    }

    private var tiers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Courts").font(SK.font(12, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase)
            ForEach(VolleyTier.allCases, id: \.rawValue) { t in
                let open = book.unlocked(t), on = book.chosen == t
                Button { AudioHub.shared.uiTap(); if open { book.chosen = t; book.save() } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: open ? (on ? "checkmark.circle.fill" : "circle") : "lock.fill").font(.system(size: 18, weight: .heavy)).foregroundStyle(SK.ink)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(t.title) · \(t.className)").font(SK.font(15, .black)).foregroundStyle(SK.ink)
                            Text(open ? t.blurb : "Win a match (or three close ones) at \(t.below?.title ?? "") to open").font(SK.font(11, .bold)).foregroundStyle(SK.muted)
                        }
                        Spacer()
                        HStack(spacing: 3) { JellyCoinIcon(size: 15); Text("\(VolleyTuning.drops(win: true, tier: t))").font(SK.font(15, .black)).foregroundStyle(SK.ink) }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? SK.honey : Color.white.opacity(0.6)))
                    .opacity(open ? 1 : 0.6)
                }.buttonStyle(.plain).accessibilityIdentifier("volley-tier-\(t.rawValue)").accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
    }

    private func statCard(_ prof: JellyProfile?) -> some View {
        let st = book.stats(character: prof?.character ?? who)
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(prof?.name ?? "Bob") on the sand").font(SK.font(20, .black)).foregroundStyle(SK.ink)
            VolleyStatBar(name: "Speed", value: st.speed, sub: "Quicker feet, longer steps", color: SK.sky)
            VolleyStatBar(name: "Power", value: st.power, sub: "Harder hits and spikes", color: SK.pink)
            VolleyStatBar(name: "Hops", value: st.hops, sub: "Higher jumps", color: SK.mint)
            VolleyStatBar(name: "Timing", value: st.timing, sub: "A bigger hit window, a truer aim", color: SK.honeyDeep)
            Text("\(st.wins) wins in \(st.matches) matches").font(SK.font(12, .bold)).foregroundStyle(SK.muted)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
        .accessibilityIdentifier("volley-stats")
    }

    private func drills(_ prof: JellyProfile?) -> some View {
        let left = book.sessionsLeft(prof?.character ?? who)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Training").font(SK.font(12, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase)
                Spacer()
                HStack(spacing: 5) {
                    Text("Pep").font(SK.font(12, .heavy)).foregroundStyle(SK.ink)
                    ForEach(0..<VolleyTraining.fullSessions, id: \.self) { i in Capsule().fill(i < left ? SK.mint : Color(hex: 0xE6D8C6)).frame(width: 22, height: 10) }
                }.accessibilityElement(children: .ignore).accessibilityLabel("Pep: \(left) of \(VolleyTraining.fullSessions) full practices left today")
            }
            ForEach(VolleyDrillKind.allCases, id: \.rawValue) { k in
                Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiConfirm(); drill(k) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: UIImage(systemName: k.symbol) != nil ? k.symbol : "figure.walk").font(.system(size: 20, weight: .heavy)).foregroundStyle(SK.ink)
                            .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SK.sky.opacity(0.7)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(k.title).font(SK.font(15, .black)).foregroundStyle(SK.ink)
                            Text(k.blurb).font(SK.font(11, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Text("Train").font(SK.font(13, .black)).foregroundStyle(.white).padding(.horizontal, 12).frame(minHeight: 36)
                            .background(Capsule().fill(blocker == nil ? SK.pink : SK.muted.opacity(0.45)))
                    }
                    .padding(8).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.6)))
                }.buttonStyle(.plain).disabled(blocker != nil).accessibilityIdentifier("volley-drill-\(k.rawValue)")
            }
            Text("Practice raises the stats a little each time. Pep refills overnight; after that it still helps, just less.").font(SK.font(11, .bold)).foregroundStyle(SK.muted)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
    }
}

struct VolleyStatBar: View {
    let name: String, value: Float, sub: String, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(name).font(SK.font(15, .heavy)).foregroundStyle(SK.ink); Spacer(); Text("\(Int((value * 100).rounded()))").font(SK.font(15, .black)).foregroundStyle(SK.ink).monospacedDigit() }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(SK.ink.opacity(0.1))
                    Capsule().fill(color).frame(width: max(14, g.size.width * CGFloat(min(max(value, 0), 1))))
                }
            }.frame(height: 14)
            Text(sub).font(SK.font(11, .bold)).foregroundStyle(SK.muted)
        }.accessibilityElement(children: .combine)
    }
}

/// The volleyball half of a Jelbie's Trophies sheet.
struct VolleyTrophiesSection: View {
    let care: GameCare
    var who: Int
    var body: some View {
        let shelf = care.race.trophies.shelf(character: care.jelly(who)?.character ?? who)
        VStack(alignment: .leading, spacing: 8) {
            Text("Beach volleyball").font(SK.font(13, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase).accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 6) {
                ForEach(VolleyTier.allCases, id: \.rawValue) { t in
                    let n = shelf.volleyWon(t)
                    HStack(spacing: 4) {
                        Image(systemName: UIImage(systemName: "rosette") != nil ? "rosette" : "seal.fill").font(.system(size: 12, weight: .black))
                        Text("\(t.title) \u{00D7}\(n)").font(SK.font(12, .black))
                    }
                    .foregroundStyle(n > 0 ? SK.ink : SK.muted).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(n > 0 ? Color(red: 0.98, green: 0.80, blue: 0.35) : Color.white.opacity(0.5)))
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(t.title) volleyball ribbon: \(n) win\(n == 1 ? "" : "s")")
                }
                ForEach(Trophy.allVolley.filter { $0.id.hasPrefix("vwins") }) { t in
                    let has = shelf.has(t)
                    HStack(spacing: 4) {
                        Image(systemName: has ? "trophy.fill" : "lock.fill").font(.system(size: 11, weight: .black))
                        Text(has ? t.title : t.detail).font(SK.font(12, .black))
                    }
                    .foregroundStyle(has ? SK.ink : SK.muted).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(has ? Color(red: 0.98, green: 0.80, blue: 0.35) : Color.white.opacity(0.5)))
                    .accessibilityElement(children: .ignore).accessibilityLabel(has ? "\(t.title), earned" : "\(t.detail), not yet")
                }
            }
        }.accessibilityIdentifier("volley-trophies")
    }
}
