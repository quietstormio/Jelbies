//
//  VolleyChrome.swift
//  Jelly Volleyball's screen furniture while the court is up: the score, the controls (drag the lower area to walk, the left / right buttons, a big Jump
//  button that serves, jumps, digs at a low ball and spikes when pressed again in the air), the results card and the white fade.
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
    /// The double tap on your teammate (VolleyDoubleTap): when a finger came down, and the pair of taps so far.
    @State private var tapDown: Date?
    @State private var doubleTap = VolleyDoubleTap()
    @State private var hintArmed = false
    @AppStorage("volley.hint.doubleTap") private var doubleTapHintSeen = false
    @State private var aimShown: SIMD2<Float>?
    @State private var padH: CGFloat = 0
    @State private var fxText = ""
    @State private var fxTone = 0
    @State private var fxY: CGFloat = 0
    @State private var fxOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if volley.inScene {
                if volley.phase == .playing, volley.live { courtLayer }
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if volley.showsCard { VolleyResultsCard(volley: volley, maxHeight: ResultCardMetrics.maxHeight(screenH: padH)) { volley.goHome() }.resultCardSlot().transition(.scale(scale: 0.85).combined(with: .opacity)) }
                    Spacer()
                    if volley.phase == .playing, !volley.hasResults { controls }
                }
                .padding(.horizontal, 14).padding(.bottom, compact ? 8 : 14)
                .animation(CareMenu.spring, value: volley.showsCard)
                if volley.live, volley.ui.phase == .intro { banner("Jelly Volleyball!") }
                Text(fxText).font(.system(size: fxTone == 3 ? 52 : 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(fxTone == 1 || fxTone == 3 ? Color(red: 1.0, green: 0.85, blue: 0.25) : fxTone == 2 ? Color.white.opacity(0.85) : .white)
                    .shadow(color: FocusStyle.pink.opacity(0.9), radius: 0, x: 0, y: 3).shadow(color: FocusStyle.shadow.opacity(0.35), radius: 6, y: 3)
                    .opacity(fxOpacity).offset(y: -120 + fxY).allowsHitTesting(false).accessibilityHidden(true)
                    .onChange(of: volley.ui.fxSerial) { _, _ in
                        fxText = volley.ui.fxText; fxTone = volley.ui.fxTone
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) { fxY = 10; fxOpacity = 1 }
                        withAnimation(.easeOut(duration: 1.0)) { fxY = -40; fxOpacity = 0 }
                    }
            }
            ForfeitHomeCard(care: care)
            Color.white.opacity(Double(volley.wipe)).ignoresSafeArea().allowsHitTesting(false)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { padH = $0 }
        .onChange(of: volley.ui.waitingToServe) { _, now in if !now, hintArmed { doubleTapHintSeen = true; hintArmed = false } }          // (shown through that one serve wait, then never again)
        .allowsHitTesting(volley.active)
        .accessibilityElement(children: .contain)
        .padStatusBarHidden(volley.inScene)
    }

    // MARK: top

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if volley.canForfeit { ForfeitHomePill(care: care) } else { ForfeitHomePill(care: care).hidden() }          // (only a live match shows it; the same width otherwise)
                scoreBoard.frame(maxWidth: .infinity)          // (the score is centred in the room the pill leaves: 12 pt apart, never under it)
            }
            if volley.live, !volley.ui.touchDots.isEmpty { touchDots }
            if let hint = hint { Text(hint).playFont(15, .semibold).foregroundStyle(CareMenu.brown).padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(CareMenu.cream.opacity(0.92))).transition(.opacity).onAppear { if !doubleTapHintSeen, hint == Self.doubleTapHint { hintArmed = true } } }
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
        Group {
            HStack(spacing: 12) {
                team(volley.playerName.isEmpty ? "You" : volley.playerName, u.score[0], serving: u.serveTeam == 0 && u.phase != .over)
                Text(":").playFont(20, .black).foregroundStyle(CareMenu.brown.opacity(0.6))
                team("Them", u.score[1], serving: u.serveTeam == 1 && u.phase != .over)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(CareMenu.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 6, y: 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Score. You \(u.score[0]), them \(u.score[1]). First to \(VolleyTuning.pointsToWin). Controlling \(volley.teamNames.indices.contains(u.controlled) ? volley.teamNames[u.controlled] : "your Jelmiko").")
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
        if u.humanServes { return "Your serve. Tap to toss, tap again at the top" }
        if u.waitingToServe { return doubleTapHintSeen ? "Their serve" : Self.doubleTapHint }
        return nil
    }

    private func banner(_ s: String) -> some View {
        Text(s).font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            .shadow(color: FocusStyle.pink.opacity(0.9), radius: 0, x: 0, y: 3).shadow(color: FocusStyle.shadow.opacity(0.35), radius: 6, y: 3)
            .allowsHitTesting(false).offset(y: -40).transition(.opacity)
    }

    // MARK: controls

    private var assisted: Bool { volley.sim?.autoMove == true }

    /// The whole-screen layer under the HUD: the floating stick on the left half, the double-tap that switches control, the call bubbles.
    private var courtLayer: some View {
        GeometryReader { g in
            ZStack {
                Color.clear.contentShape(Rectangle())
                    .gesture(tapWatch(g.size))
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
                            .simultaneousGesture(tapWatch(g.size))
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
                teammateElement(g.size)
                if !volley.ui.calls.isEmpty {
                    TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
                        ZStack {
                            ForEach(volley.ui.calls, id: \.self) { i in
                                if volley.bodyPos.indices.contains(i), let pt = GameCamera.screenPoint(floor: SIMD2(volley.bodyPos[i].x, volley.bodyPos[i].z), y: volley.bodyPos[i].y + 0.75, size: g.size) {
                                    Text("!").font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(.white)
                                        .frame(width: 36, height: 36).background(Circle().fill(SK.pinkStrong).shadow(color: FocusStyle.shadow.opacity(0.3), radius: 4, y: 2))
                                        .position(pt)
                                }
                            }
                        }
                    }.allowsHitTesting(false)
                }
            }
            #if targetEnvironment(simulator)
            .task {          // capture aid: `-VolleyAutoDoubleTap 1` double-taps your teammate (the same lift / pick path as a finger) 6 s into the match, then once more 4 s later
                guard UserDefaults.standard.bool(forKey: "VolleyAutoDoubleTap") else { return }
                for _ in 0..<2 {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    let mate = 1 - min(max(volley.ui.controlled, 0), 1)
                    guard volley.bodyPos.indices.contains(mate), let pt = VolleyPick.centre(volley.bodyPos[mate], size: g.size) else { continue }
                    let t = Date().timeIntervalSinceReferenceDate
                    _ = doubleTap.lift(at: pt, time: t, press: 0.08, travel: 1)
                    if doubleTap.lift(at: pt, time: t + 0.15, press: 0.08, travel: 1) { pick(pt, g.size) }
                }
            }
            #endif
        }
        .coordinateSpace(name: Self.courtSpace)
        .ignoresSafeArea()
        .defersSystemGestures(on: .bottom)          // the bottom-edge controls win over the home swipe on the first touch
    }

    static let courtSpace = "volleyCourt"
    /// Shown once, on the first serve of theirs (the line the screen already uses for "Their serve").
    static let doubleTapHint = "Double-tap your teammate to switch"

    /// Every touch that lifts is watched in the court layer's own space (not the padded left-half layer's: that was ~110 pt off, so a double tap on your teammate, who stands on the left,
    /// missed him): two short, still taps within 0.3 s on one of your Jelmiko switch to him. Whatever else the finger did (the stick) is untouched: this only listens.
    private func tapWatch(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.courtSpace))
            .onChanged { _ in if tapDown == nil { tapDown = Date() } }
            .onEnded { v in
                let down = tapDown ?? v.time
                tapDown = nil
                let travel = hypot(v.translation.width, v.translation.height)
                if doubleTap.lift(at: v.location, time: v.time.timeIntervalSinceReferenceDate, press: v.time.timeIntervalSince(down), travel: travel) { pick(v.location, size) }
            }
    }

    /// VoiceOver: an element on your teammate with the action "Switch to <name>".
    private func teammateElement(_ size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 0.25)) { _ in
            let mate = 1 - min(max(volley.ui.controlled, 0), 1)
            let name = volley.teamNames.indices.contains(mate) && !volley.teamNames[mate].isEmpty ? volley.teamNames[mate] : "your teammate"
            if volley.bodyPos.indices.contains(mate), let pt = VolleyPick.centre(volley.bodyPos[mate], size: size) {
                Color.clear.frame(width: 130, height: 150).contentShape(Rectangle()).position(pt)
                    .allowsHitTesting(false)
                    .accessibilityElement().accessibilityLabel(name).accessibilityIdentifier("volley-teammate")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Switch to \(name)") { care.volleySwitch(to: mate) }
            }
        }
    }

    /// A double tap: the nearest of your two Jelmiko to the finger takes control (see VolleyPick for the touch area). Nothing else happens on a double tap: no hit, serve or aim (those
    /// live on the Hit button). The haptic comes from the `.switched` event. Works in every match state, the serve wait included (it changes who is steered, not who serves).
    private func pick(_ at: CGPoint, _ size: CGSize) {
        guard volley.live, volley.bodyPos.count >= 2 else { return }
        doubleTapHintSeen = true
        if let i = VolleyPick.nearest(bodies: Array(volley.bodyPos.prefix(2)), at: at, size: size), i != volley.ui.controlled { care.volleySwitch(to: i) }
    }

    private var controls: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if assisted {
                Text("The Jelmiko walks for you").playFont(13, .semibold).foregroundStyle(CareMenu.brown).padding(.horizontal, 12).padding(.vertical, 6)
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
                    .shadow(color: FocusStyle.shadow.opacity(hitDown ? 0.12 : 0.28), radius: hitDown ? 4 : 6, y: hitDown ? 1 : 3)
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
                        let a = SIMD2<Float>(Float(max(-1, min(1, dx / 52))), Float(max(-1, min(1, dy / 52))))          // (on the screen: right, down)
                        aimShown = a; care.volleyAim(a)
                    }
                }
                .onEnded { _ in hitDown = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if !hitDown { aimShown = nil } } })
            .background { Button("") { care.volleyTap() }.keyboardShortcut(.space, modifiers: []).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true) }
            .accessibilityElement().accessibilityLabel(volley.ui.hitLabel).accessibilityIdentifier("volley-jump").accessibilityAddTraits(.isButton)
            .accessibilityHint("Tap to hit. The move depends on the touch: bump, set, spike, dig or block. Swipe the button to aim: up deep, down short, left or right to the sides.")
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
                .shadow(color: FocusStyle.shadow.opacity(down ? 0.12 : 0.28), radius: down ? 4 : 6, y: down ? 1 : 3))
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
    /// The tallest the card may be (the chrome measures the screen); taller content scrolls inside it with "Back home" kept in view.
    var maxHeight: CGFloat = .infinity
    let home: () -> Void
    @Environment(\.verticalSizeClass) private var vsc
    private var tight: Bool { vsc == .compact }

    private var hasSecondary: Bool { volley.pointsEarned > 0 || !volley.awards.isEmpty || volley.unlockedNow != nil }

    var body: some View {
        let s = volley.sim
        let a = s?.score[0] ?? 0, b = s?.score[1] ?? 0
        ResultCardFrame(buttonColor: SK.pink, homeID: "volley-home", maxHeight: maxHeight, hasSecondary: hasSecondary, home: home) {
            Text(s?.humanTeamWon == true ? "You won!" : "Good game!").playFont(tight ? 26 : 32, .heavy).foregroundStyle(CareMenu.brown)
                .resultText("title").accessibilityAddTraits(.isHeader)
            Text("\(a)  :  \(b)").playFont(30, .heavy).monospacedDigit().foregroundStyle(CareMenu.brown)
                .resultText("score").accessibilityLabel("Score \(a) to \(b)")
            ResultCoinsLine(coinText: volley.earned.coinText)
            if volley.assistFactor < 1 { Text("Auto play pays half").playFont(14, .medium).foregroundStyle(CareMenu.brown.opacity(0.85)).resultText("assist") }
        } secondary: {
            VStack(spacing: 8) {
                if volley.pointsEarned > 0 { ResultPointsRow(title: "Jelly Volleyball points  +\(volley.pointsEarned)", detail: "\(volley.playerName) now has \(volley.pointsAfter) to spend", id: "volley-points") }
                if volley.awards.newRibbon { ResultRewardRow(symbol: "rosette", text: "New ribbon!", id: "volley-new-ribbon", probe: "ribbon") }
                if let t = volley.awards.trophies.first {
                    ResultRewardRow(symbol: "trophy.fill", text: volley.awards.trophies.count > 1 ? "New trophy! \(t.title) +\(volley.awards.trophies.count - 1)" : "New trophy! \(t.title)", id: "volley-trophy", probe: "trophy")
                }
            }
            if let t = volley.unlockedNow { Text("\(t.title) unlocked!").playFont(15, .heavy).foregroundStyle(SK.pink).resultText("unlocked").accessibilityIdentifier("volley-unlocked") }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("volley-card")
    }

    @ViewBuilder
    private func gainRow(_ name: String, _ v: Float) -> some View {
        if v > 0.0005 {
            HStack { Text(name).playFont(16, .semibold); Spacer(); Text("+\(Int((v * 100).rounded(.up)))").playFont(16, .heavy).monospacedDigit() }
                .foregroundStyle(CareMenu.brown).frame(width: 180)
        }
    }
}

/// The volleyball half of a Jelbie's Trophies sheet.
struct VolleyTrophiesSection: View {
    let care: GameCare
    var who: Int
    var body: some View {
        let shelf = care.race.trophies.shelf(character: care.jelly(who)?.character ?? who)
        VStack(alignment: .leading, spacing: 8) {
            Text("Jelly Volleyball").font(SK.font(13, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase).accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 6) {
                ForEach(VolleyTier.allCases, id: \.rawValue) { t in
                    let n = shelf.volleyWon(t)
                    HStack(spacing: 4) {
                        Image(systemName: UIImage(systemName: "rosette") != nil ? "rosette" : "seal.fill").font(.system(size: 12, weight: .black))
                        Text("\(t.title) \u{00D7}\(n)").font(SK.font(12, .black))
                    }
                    .foregroundStyle(n > 0 ? SK.ink : SK.muted).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(n > 0 ? Color(red: 0.98, green: 0.80, blue: 0.35) : Color.white.opacity(0.5)))
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(t.title) Jelly Volleyball ribbon: \(n) win\(n == 1 ? "" : "s")")
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
