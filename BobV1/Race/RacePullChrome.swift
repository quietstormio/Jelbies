//
//  RacePullChrome.swift
//  Jelly Circuit, the on-screen pull control (stage B2): the player pulls a finger DOWN anywhere on the screen and lets go, and the Jelbie hops.
//  The look (gauge, zone colours, labels, pops) is the Waddle Sprint prototype's own (prototype_waddle_sprint.html, the drag overlay and `computePull`), in the game's fonts.
//
//    RacePullGesture    the pure maths: how far a drag can go, the pull of a drag, the zone of a pull (unit-tested).
//    RacePullSurface    the full-screen touch surface + the gauge + the thumb demo + the keyboard / VoiceOver hop.
//    RacePullTopRow     the ONE slot under the title pill: a pop, else a hint, else the streak chip.
//

import SwiftUI
import UIKit

// MARK: - the pure maths

enum RacePullGesture {
    enum Zone: Equatable { case weak, green, over }

    /// The drag length (points) that is a full pull: 36 % of the short side, between 110 and 230.
    static func dragMax(size: CGSize) -> CGFloat {
        min(max(min(size.width, size.height) * 0.36, 110), 230)
    }

    /// A thumb that starts low on a landscape phone has no room to pull: the drag length never needs more than the room under the start point (at least 80 pt).
    /// `scale` = 1.3 on iPad (every length of the control).
    static func dragMaxFor(size: CGSize, startY: CGFloat, bottomInset: CGFloat, scale: CGFloat = 1) -> CGFloat {
        min(dragMax(size: size) * scale, max(80, size.height - bottomInset - startY - 8))
    }

    /// The pull of a drag of (`dx`, `dy`) points (dy positive = down the screen): length over `dragMax`, cut down when the drag is not downward (an upward drag gives about 0).
    static func pull(dx: CGFloat, dy: CGFloat, dragMax: CGFloat) -> Float {
        let len = hypot(dx, dy)
        guard len > 0, dragMax > 0 else { return 0 }
        var raw = len / dragMax
        let down = dy / len
        if down < 0.3 { raw *= min(max((down / 0.3) * 0.7 + 0.3, 0), 1) }
        return Float(min(max(raw, 0), 1.1))
    }

    /// weak below `lo`, green up to `hi`, over past it.
    static func zone(pull: Float, lo: Float, hi: Float) -> Zone {
        pull < lo ? .weak : (pull <= hi ? .green : .over)
    }
}

// MARK: - colours

private func hexColor(_ v: UInt32, _ a: Double = 1) -> Color {
    Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a)
}

private enum PullInk {
    static let weak = hexColor(0xFFF4E2), green = hexColor(0x34C39A), over = hexColor(0xEC7D59)
    static let brown = hexColor(0x5B4334)
    static let letGo = hexColor(0x1D6A5A), tooFar = hexColor(0x963720)
    static let cream = hexColor(0xFFFBF4, 0.95)
    static func zone(_ z: RacePullGesture.Zone) -> Color { z == .green ? green : z == .over ? over : weak }
}

// MARK: - the gauge

/// What the gauge shows: the anchor, the finger, the pull and the green zone.
struct RacePullGaugeState: Equatable {
    var anchor: CGPoint
    var finger: CGPoint
    var pull: Float
    var lo: Float
    var hi: Float
    var pullMin: Float
    var pullMax: Float
    var zone: RacePullGesture.Zone { RacePullGesture.zone(pull: pull, lo: lo, hi: hi) }
}

/// The prototype's overlay, drawn in a Canvas. `k` = 1.3 on iPad (every length).
private struct RacePullGauge: View {
    let g: RacePullGaugeState
    let k: CGFloat
    let safeTop: CGFloat

    var body: some View {
        ZStack {
            Canvas { ctx, _ in draw(&ctx) }
            if g.zone != .weak { label }
        }
        .allowsHitTesting(false)
    }

    private var ringR: CGFloat { 34 * k }

    /// Clockwise from 12 o'clock over 86 % of the circle; a pull of 0 ... pullMax maps onto it.
    private func arcPoint(_ p: Float) -> CGPoint {
        let a = -Double.pi / 2 + Double.pi * 2 * 0.86 * Double(p / g.pullMax)
        return CGPoint(x: g.anchor.x + CGFloat(cos(a)) * ringR, y: g.anchor.y + CGFloat(sin(a)) * ringR)
    }

    private func arc(from: Float, to: Float) -> Path {
        var path = Path()
        let steps = max(2, Int(ceil(Double(to - from) / Double(g.pullMax) * 96)))
        for i in 0...steps {
            let p = from + (to - from) * Float(i) / Float(steps)
            let pt = arcPoint(p)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        return path
    }

    private func draw(_ ctx: inout GraphicsContext) {
        let zone = g.zone, col = PullInk.zone(zone)
        let band = g.pull < g.pullMin ? 0.5 : 1.0          // (a release under the weakest accepted pull does nothing: the band says so)
        var line = Path(); line.move(to: g.anchor); line.addLine(to: g.finger)
        ctx.opacity = band
        ctx.stroke(line, with: .color(hexColor(0x5B4334, 0.32)), style: StrokeStyle(lineWidth: 14 * k, lineCap: .round))
        ctx.stroke(line, with: .color(col), style: StrokeStyle(lineWidth: 8 * k, lineCap: .round))
        ctx.opacity = 1
        let butt = StrokeStyle(lineWidth: 12 * k, lineCap: .butt)
        ctx.stroke(arc(from: 0, to: g.pullMax), with: .color(hexColor(0x5B4334, 0.34)), style: butt)
        let seg = StrokeStyle(lineWidth: 7 * k, lineCap: .butt)
        ctx.stroke(arc(from: 0, to: g.lo), with: .color(hexColor(0xFFF8EC, 0.9)), style: seg)
        ctx.stroke(arc(from: g.lo, to: g.hi), with: .color(hexColor(0x34C39A)), style: seg)
        ctx.stroke(arc(from: g.hi, to: g.pullMax), with: .color(hexColor(0xEC7D59, 0.95)), style: seg)
        // the knob at the current pull
        let kp = arcPoint(min(g.pull, g.pullMax))
        let knob = Path(ellipseIn: CGRect(x: kp.x - 7 * k, y: kp.y - 7 * k, width: 14 * k, height: 14 * k))
        ctx.fill(knob, with: .color(.white)); ctx.stroke(knob, with: .color(PullInk.brown), lineWidth: 3 * k)
        // the anchor dot and the finger dot
        let a = Path(ellipseIn: CGRect(x: g.anchor.x - 9 * k, y: g.anchor.y - 9 * k, width: 18 * k, height: 18 * k))
        ctx.fill(a, with: .color(Color.white.opacity(0.6))); ctx.stroke(a, with: .color(PullInk.brown), lineWidth: 3 * k)
        let f = Path(ellipseIn: CGRect(x: g.finger.x - 16 * k, y: g.finger.y - 16 * k, width: 32 * k, height: 32 * k))
        ctx.fill(f, with: .color(col)); ctx.stroke(f, with: .color(.white), lineWidth: 3 * k)
    }

    /// "Let go!" in the green, "Too far" past it: above the ring, kept under the safe area.
    private var label: some View {
        let green = g.zone == .green
        let y = max(g.anchor.y - ringR - 12 * k - 11 * k, safeTop + 14)
        return RacePullOutlinedText(text: green ? "Let go!" : "Too far", ink: green ? PullInk.letGo : PullInk.tooFar, size: 16 * k)
            .position(x: g.anchor.x, y: y)
    }
}

/// A label with the cream outline that reads on grass and on track.
private struct RacePullOutlinedText: View {
    let text: String
    let ink: Color
    let size: CGFloat
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) * .pi / 4
                Text(text).playFont(size, .heavy).foregroundStyle(PullInk.cream).offset(x: CGFloat(cos(a)) * size * 0.16, y: CGFloat(sin(a)) * size * 0.16)
            }
            Text(text).playFont(size, .heavy).foregroundStyle(ink)
        }
        .fixedSize()
    }
}

// MARK: - the surface

struct RacePullSurface: View {
    let race: RaceFlow

    private struct Touch: Equatable { var start: CGPoint; var cur: CGPoint }
    @GestureState private var touch: Touch? = nil
    @State private var size: CGSize = .zero
    @State private var goAt: Date?
    @State private var stalledAt: Date?
    @State private var lastTouchAt: Date?
    @State private var lastGreenBuzz = Date.distantPast
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)

    private var k: CGFloat { PadLayout.isPad ? 1.3 : 1 }
    private var ui: RaceUI { race.ui }
    private var gaugeOn: Bool { ui.phase == .countdown || race.buttonsLive }

    private static var safeInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets ?? .zero
    }

    private func dragMax(startY: CGFloat) -> CGFloat {
        RacePullGesture.dragMaxFor(size: size, startY: startY, bottomInset: Self.safeInsets.bottom, scale: k)
    }

    private func pull(_ t: Touch) -> Float {
        let dm = dragMax(startY: t.start.y)
        return RacePullGesture.pull(dx: t.cur.x - t.start.x, dy: t.cur.y - t.start.y, dragMax: dm)
    }

    /// The gauge to draw: the finger's, or (capture aid) the stepping demo's.
    private func gauge(at date: Date) -> RacePullGaugeState? {
        guard gaugeOn else { return nil }
        if let t = touch {
            return RacePullGaugeState(anchor: t.start, finger: t.cur, pull: pull(t), lo: ui.zoneLo, hi: ui.zoneHi, pullMin: ui.pullMin, pullMax: ui.pullMax)
        }
        #if targetEnvironment(simulator)
        if Self.demoGauge {
            let steps: [Float] = [0.45, 0.80, 1.05]
            let p = steps[Int(date.timeIntervalSinceReferenceDate / 2) % 3]
            let a = CGPoint(x: size.width * 0.5, y: size.height * 0.42)
            let len = CGFloat(p) * RacePullGesture.dragMax(size: size) * k
            return RacePullGaugeState(anchor: a, finger: CGPoint(x: a.x, y: a.y + len), pull: p, lo: ui.zoneLo, hi: ui.zoneHi, pullMin: ui.pullMin, pullMax: ui.pullMax)
        }
        #endif
        return nil
    }

    #if targetEnvironment(simulator)
    /// -RacePullDemo 1 (simulator only, read once): the gauge without a finger, pull 0.45 -> 0.80 -> 1.05, two seconds each.
    private static let demoGauge = UserDefaults.standard.integer(forKey: "RacePullDemo") != 0
    #endif

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($touch) { v, state, _ in state = Touch(start: v.startLocation, cur: v.location) }
                        .onChanged { v in if v.translation == .zero { lastTouchAt = Date() } }
                        .onEnded { v in
                            let dm = dragMax(startY: v.startLocation.y)
                            let p = RacePullGesture.pull(dx: v.location.x - v.startLocation.x, dy: v.location.y - v.startLocation.y, dragMax: dm)
                            if race.release(pull: p) != .ignored { light.impactOccurred(intensity: 0.6) }
                        }
                )
            // the gauge (and the thumb demo) are only drawn: the touches go to the surface
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !gaugeOn && !demoMayShow)) { tl in
                ZStack {
                    if let g = gauge(at: tl.date) {
                        RacePullGauge(g: g, k: k, safeTop: Self.safeInsets.top)
                            .opacity(ui.stumbling ? 0.4 : 1)
                    }
                    if demoShows(at: tl.date), touch == nil {
                        RacePullThumbDemo(size: size, k: k, lo: ui.zoneLo, hi: ui.zoneHi, pullMin: ui.pullMin, pullMax: ui.pullMax, at: tl.date)
                    }
                }
            }
            .allowsHitTesting(false)
            // keyboard: space and the up arrow hop (hidden buttons, the way FootButton does it)
            Group {
                Button("") { keyHop() }.keyboardShortcut(.space, modifiers: [])
                Button("") { keyHop() }.keyboardShortcut(.upArrow, modifiers: [])
            }
            .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onChange(of: race.buttonsLive) { _, live in if live, goAt == nil { goAt = Date() } }
        .onChange(of: ui.stalled) { _, s in stalledAt = s ? Date() : nil }
        .onChange(of: zoneKey) { old, new in
            if new == 1, old != 1, Date().timeIntervalSince(lastGreenBuzz) > 0.12 { lastGreenBuzz = Date(); light.impactOccurred(intensity: 0.5) }
            else if new == 2, old != 2 { rigid.impactOccurred(intensity: 0.4) }
        }
        .accessibilityElement()
        .accessibilityLabel("Hop pad")
        .accessibilityHint("Double tap to hop")
        .accessibilityValue("\(ui.hopSerial) hops")
        .accessibilityIdentifier("race-pull")
        .accessibilityAction { keyHop() }
    }

    private func keyHop() {
        if race.hopAssist() != .ignored { light.impactOccurred(intensity: 0.6) }
    }

    /// -1 no finger / no gauge, 0 weak, 1 green, 2 over (the haptics watch it).
    private var zoneKey: Int {
        guard gaugeOn, let t = touch else { return -1 }
        switch RacePullGesture.zone(pull: pull(t), lo: ui.zoneLo, hi: ui.zoneHi) { case .weak: return 0; case .green: return 1; case .over: return 2 }
    }

    // MARK: the thumb demo's schedule

    private var demoMayShow: Bool { race.pullDemoThisRace || stalledAt != nil }

    /// During the countdown and until the first touch or 10 s after GO, in the first three pull races; and after the player has stood still for 4 s, until his next touch.
    private func demoShows(at now: Date) -> Bool {
        guard ui.phase == .countdown || race.buttonsLive else { return false }
        if race.pullDemoThisRace, lastTouchAt == nil, ui.phase == .countdown || goAt.map({ now.timeIntervalSince($0) < 10 }) ?? true { return true }
        if let s = stalledAt, now.timeIntervalSince(s) >= 4, lastTouchAt.map({ $0 < s }) ?? true { return true }
        return false
    }
}

// MARK: - the thumb demo

/// A ghost of the control that teaches the move: a hand slides down, the ghost band stretches and the knob runs into the green, "Let go!", it vanishes, repeat.
private struct RacePullThumbDemo: View {
    let size: CGSize
    let k: CGFloat
    let lo: Float, hi: Float, pullMin: Float, pullMax: Float
    let at: Date
    private var reduceMotion: Bool { A11ySettings.shared.reduceMotion }

    var body: some View {
        // one cycle: 0.9 s slide, 0.3 s hold ("Let go!"), 0.4 s gone
        let t = reduceMotion ? 1.0 : at.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6)
        let slide = min(t / 0.9, 1)
        let eased = slide * slide * (3 - 2 * slide)
        let target: Float = 0.8
        let pull = reduceMotion ? target : target * Float(eased)
        let opacity = reduceMotion ? 0.85 : (t < 0.15 ? t / 0.15 : (t < 1.2 ? 1 : max(0, 1 - (t - 1.2) / 0.4))) * 0.85
        let anchor = CGPoint(x: size.width / 2, y: size.height * 0.62)
        let len = CGFloat(pull) * RacePullGesture.dragMax(size: size) * k
        let finger = CGPoint(x: anchor.x, y: anchor.y + len)
        return ZStack {
            RacePullGauge(g: RacePullGaugeState(anchor: anchor, finger: finger, pull: pull, lo: lo, hi: hi, pullMin: pullMin, pullMax: pullMax), k: k, safeTop: 0)
            Image(systemName: "hand.point.up.fill")
                .font(.system(size: 44 * k))
                .foregroundStyle(.white)
                .shadow(color: PullInk.brown.opacity(0.55), radius: 3 * k, y: 2 * k)
                .position(x: finger.x + 6 * k, y: finger.y + 26 * k)
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - the top row: pop, else hint, else streak chip

/// What the one slot under the title pill says (pure, so it can be tested).
enum RacePullTopText {
    /// The hint for the state, nil for none. `barHints`: the bar hints shown so far this race (the first three bars only).
    static func hint(_ ui: RaceUI, assist: RaceAssist, autoJump: Bool, barHints: Int) -> String? {
        if ui.stumbling, ui.tripped { return ui.playerName.isEmpty ? "Whoops! A trip!" : "Whoops! \(ui.playerName) tripped" }
        let button = assist == .oneButton          // (the one-button assist: there is no pull, the Hop button is the control)
        if ui.stalled { return assist == .auto ? nil : button ? "Press Hop!" : "Pull down and let go!" }
        if ui.hurdleAhead, assist != .auto, !autoJump, barHints <= 3 { return button ? "Hop to clear the bar!" : "Green clears the bar!" }
        if ui.phase == .countdown { return assist == .auto ? nil : button ? "Press Hop to hop along!" : "Pull down anywhere. Let go in the green!" }
        return nil          // (no bend hint: the pull model has no reason to ease off in a bend for the player)
    }
}

struct RacePullTopRow: View {
    let race: RaceFlow
    @State private var pop: Pop?
    @State private var barHints = 0

    private struct Pop: Equatable { var id: Int; var text: String; var bg: Color; var ink: Color; var born: Date }
    @State private var popID = 0

    var body: some View {
        let ui = race.ui
        Group {
            if let p = pop {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSince(p.born)
                    let reduce = A11ySettings.shared.reduceMotion
                    Text(p.text)
                        .playFont(17, .heavy)
                        .foregroundStyle(p.ink)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(p.bg).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 5, y: 2))
                        .offset(y: reduce ? 0 : -6 * CGFloat(min(t / 0.95, 1)))
                        .opacity(t > 0.7 ? max(0, 1 - (t - 0.7) / 0.25) : 1)
                }
                .id(p.id)
                .accessibilityHidden(true)
            } else if let h = RacePullTopText.hint(ui, assist: race.assist, autoJump: A11ySettings.shared.autoJump, barHints: barHints) {
                Text(h)
                    .playFont(15, .semibold)
                    .foregroundStyle(CareMenu.brown)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(CareMenu.cream.opacity(0.92)))
                    .transition(.opacity)
            } else if ui.streak >= 2 {
                Text("Perfect streak ×\(ui.streak)")
                    .playFont(13, .bold)
                    .foregroundStyle(hexColor(0x1D6A5A))
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(hexColor(0xD5F2EA)))
                    .transition(.opacity)
            }
        }
        .onChange(of: ui.hopSerial) { _, _ in
            let u = race.ui
            if race.assist == .auto { return }          // (he hops by himself: no grade to cheer or scold)
            switch u.hopGrade {
            case .perfect: show(u.streak >= 2 ? "Perfect ×\(u.streak)" : "Perfect!", bg: hexColor(0xD5F2EA), ink: hexColor(0x1D6A5A))
            case .over: show("Too far!", bg: hexColor(0xFFF0D2), ink: hexColor(0x7A500C))
            default: break          // (a weak hop pops nothing)
            }
        }
        .onChange(of: ui.bonkSerial) { _, _ in show("Bonk!", bg: hexColor(0xFBE0D6), ink: hexColor(0x963720)) }
        .onChange(of: ui.hurdleAhead) { _, ahead in if ahead { barHints += 1 } }
        .task(id: pop?.id) {
            guard pop != nil else { return }
            try? await Task.sleep(for: .seconds(0.95))
            if !Task.isCancelled { pop = nil }
        }
    }

    private func show(_ text: String, bg: Color, ink: Color) {
        popID += 1
        pop = Pop(id: popID, text: text, bg: bg, ink: ink, born: Date())
    }
}
