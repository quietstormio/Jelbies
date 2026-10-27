//
//  OpeningStory.swift
//  The game opening: a ~30 s animated story that plays on a NEW game (title screen -> this -> the species picker) and from Settings > "Watch the
//  opening" (which replays it and returns to the room; no picker, no save changes). Seven beats on one camera (OpeningArt.swift):
//    1 night sky, drifting down through clouds   2 the clouds part on Wobble Isle, dawn   3 push in to the Jelly Spring, dewdrops fall
//    4 the four coloured drops shiver; "Tap to giggle" (auto-continues after ~4 s)   5 each drop pops into its real 3D Jelbie (ShowcaseStage cutout)
//    6 they turn to the player, blink and hop   7 "Which one will you take home?" and a cross-fade into the picker's blue page.
//  A tap anywhere moves on; "Skip" (top right) always leaves. Reduce Motion: no camera travel, no drifting, plain fades. VoiceOver reads each
//  caption. Audio: Resources/opening_underscore (piano + strings) and opening_twinkle / dew_chime / giggle / pop plus the app's sparkles.
//  Simulator-only capture flag: -OpeningBeat 1...7 starts at that beat (and holds it: no auto-advance) for screenshots.
//

import SwiftUI

enum OpeningScript {
    /// Each caption is split into word groups that fade in one after the other. Joined with spaces they are the exact story text.
    static let captions: [[String]] = [
        ["High above", "the clouds…"],
        ["…floats a little island", "called Wobble Isle."],
        ["Every morning,", "dewdrops gather", "in the Jelly Spring."],
        ["And when a drop", "hears someone laugh…"],
        ["…it wobbles awake", "as a Jelbie!"],
        ["Jelbies never grow up.", "So they need someone", "to look after them."],
        ["Which one will you", "take home?"],
    ]
    /// Seconds each beat lasts on its own (beat 4 also ends ~2 s after the giggle).
    static let durations: [Double] = [5.2, 5.4, 5.0, 4.0, 5.6, 5.0, 3.6]
    /// The Jelbies, in the picker's order (blue, yellow, purple, green): character ids.
    static let characters = [0, 1, 3, 2]
    static let names = ["Blueberry", "Lemon Drop", "Taro", "Matcha"]
    static let popTimes: [Double] = [0.5, 1.4, 2.3, 3.2]
    static func full(_ beat: Int) -> String { captions[beat].joined(separator: " ") }
}

@MainActor @Observable final class OpeningState {
    var beat = 0
    var beatStart = Date()
    var beatEnd = Date().addingTimeInterval(5)
    var storyStart = Date()
    var camFrom = OpeningCam()
    var camTo = OpeningCam()
    var camT0 = Date()
    var camDur = 1.0
    var dropStart: Date?
    var giggleAt: Date?
    var popAt: [Date?] = [nil, nil, nil, nil]
    var appearAt: [Date?] = [nil, nil, nil, nil]
    var mounted = [false, false, false, false]
    var models: [MelonModel?] = [nil, nil, nil, nil]
    var mountStarted = false
    var leaving = false
    var sceneOpacity = 1.0
    var token = 0
    var beatTask: Task<Void, Never>?
    var stageTask: Task<Void, Never>?
    var soundCaption: (text: String, at: Date)?
    var snapshot: [String: Any] = [:]
}

struct OpeningStoryView: View {
    @State private var st = OpeningState()
    let replay: Bool
    var finished: () -> Void

    @State private var cameraRig = PickerCamera()          // the same close-up framing the species picker uses (PhotoCam, process-wide)
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv

    private var motion: Bool { !(reduceMotionEnv || A11ySettings.shared.reduceMotion) }
    private var holdBeat: Int? {
        #if targetEnvironment(simulator)
        let d = UserDefaults.standard
        return d.object(forKey: "OpeningBeat") != nil ? min(max(d.integer(forKey: "OpeningBeat"), 1), 7) - 1 : nil
        #else
        return nil
        #endif
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                OArt.mix(0x070A2B, 0x7DB0EC, 0).ignoresSafeArea()
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                    frame(now: tl.date, size: size)
                }
                Color.clear.contentShape(Rectangle()).onTapGesture { tapped() }.accessibilityHidden(true)
                skipPill(geo)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .opacity(st.leaving ? 0 : 1)
        .animation(.easeOut(duration: 0.4), value: st.leaving)
        .task { begin() }
        .onDisappear { teardown() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("opening-story")
    }

    // MARK: one frame

    private func frame(now: Date, size: CGSize) -> some View {
        let cam = camera(at: now)
        let pr = OpeningProjector(size: size, cam: cam)
        let local = now.timeIntervalSince(st.beatStart)
        var d = OpeningDraw()
        d.motion = motion
        d.t = motion ? now.timeIntervalSince(st.storyStart) : 0
        d.dropT = st.dropStart.map { motion ? now.timeIntervalSince($0) : 9 }
        d.giggleT = st.giggleAt.map { now.timeIntervalSince($0) }
        d.shiver = st.beat == 3 ? OArt.smooth(local / 0.9) * (st.giggleAt == nil ? 1 : 0.2) : 0
        for k in 0..<4 {
            d.gone[k] = st.popAt[k] != nil
            if st.beat == 4, st.popAt[k] == nil { d.swell[k] = OArt.smooth(1 - (OpeningScript.popTimes[k] - local) / 0.45) }
        }
        let bob = d.bob
        return ZStack {
            Canvas { ctx, _ in OArt.scene(ctx, pr, d) }
                .opacity(st.sceneOpacity)
            if cam.hand > 0.001 {
                PickerBackdrop(top: SpeciesLook.of(0).top, bottom: SpeciesLook.of(0).bottom, calm: !motion, rayOriginY: size.height > size.width ? 0.38 : 0.45)
                    .opacity(cam.hand)
            }
            scrim(size)
            Canvas { ctx, _ in shadows(ctx, pr, now: now, bob: bob) }
            jelbies(now: now, pr: pr, bob: bob)
            Canvas { ctx, _ in bursts(ctx, pr, now: now, local: local, bob: bob) }
            overlayTexts(now: now, local: local, size: size, pr: pr)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func scrim(_ size: CGSize) -> some View {
        LinearGradient(colors: [Color(hex: 0x2A2060).opacity(0), Color(hex: 0x2A2060).opacity(0.42)], startPoint: .top, endPoint: .bottom)
            .frame(height: size.height * 0.42)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: the camera

    private func camera(at now: Date) -> OpeningCam {
        let u = min(max(now.timeIntervalSince(st.camT0) / max(st.camDur, 0.01), 0), 1)
        let e = u * u * u * (u * (u * 6 - 15) + 10)          // smootherstep
        return OpeningCam.mix(st.camFrom, st.camTo, e)
    }

    private func target(_ b: Int, size: CGSize) -> OpeningCam {
        let land = size.width > size.height
        switch b {
        case 0: return OpeningCam(cy: 500, zoom: 1, warm: 0.03, part: 0, hand: 0)
        case 1: return OpeningCam(cy: 818, zoom: 1, warm: 1, part: 1, hand: 0)
        case 2: return OpeningCam(cy: 790, zoom: land ? 2.1 : 2.3, warm: 1, part: 1, hand: 0)
        case 3: return OpeningCam(cy: 790, zoom: land ? 2.3 : 2.55, warm: 1, part: 1, hand: 0)
        case 4: return OpeningCam(cy: 800, zoom: land ? 2.15 : 1.75, warm: 1, part: 1, hand: 0)
        case 5: return OpeningCam(cy: 800, zoom: land ? 2.2 : 1.8, warm: 1, part: 1, hand: 0.15)
        default: return OpeningCam(cy: 800, zoom: land ? 2.2 : 1.8, warm: 1, part: 1, hand: 1)
        }
    }

    // MARK: 3D Jelbies

    private func restPoint(_ k: Int, _ pr: OpeningProjector, bob: Double) -> CGPoint {
        pr.island(200 + (Double(k) - 1.5) * 58, 140 + (k == 1 || k == 2 ? -4 : 4), bob: bob)
    }
    private func orbPoint(_ k: Int, _ pr: OpeningProjector, bob: Double) -> CGPoint {
        pr.island(OArt.orbX[k], OArt.orbY[k] - 10, bob: bob)
    }

    private func jelbies(now: Date, pr: OpeningProjector, bob: Double) -> some View {
        let f = 58 * pr.zs * 1.5                  // the frame is ~1.5 x the spacing between them (the picker's close-up framing fills it)
        return ZStack {
            ForEach(0..<4, id: \.self) { k in
                if st.mounted[k] {
                    let st = pose(k, now: now, pr: pr, bob: bob, f: f)
                    ShowcaseStage(roster: [OpeningScript.characters[k]], focusFirst: true, fullScreen: false, cutout: true, onReady: { m in ready(k, m) })
                        .frame(width: f, height: f)
                        .scaleEffect(st.scale, anchor: .init(x: 0.5, y: 0.73))
                        .position(x: st.feet.x, y: st.feet.y - 0.23 * f)
                        .opacity(st.opacity)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where the k-th Jelbie is: hidden in its drop, then leaping out of it to its spot on the grass.
    private func pose(_ k: Int, now: Date, pr: OpeningProjector, bob: Double, f: Double) -> (feet: CGPoint, scale: Double, opacity: Double) {
        guard let a = st.appearAt[k] else { return (restPoint(k, pr, bob: bob), 0.01, 0) }
        let rest = restPoint(k, pr, bob: bob)
        let age = now.timeIntervalSince(a)
        guard motion else { return (rest, 1, OArt.smooth(age / 0.5)) }
        let dur = 0.62
        let p = min(max(age / dur, 0), 1)
        let from = orbPoint(k, pr, bob: bob)
        let e = 1 - pow(1 - p, 2.2)
        let arc = -sin(p * .pi) * 0.9 * (pr.zs * 62)
        let feet = CGPoint(x: from.x + (rest.x - from.x) * e, y: from.y + (rest.y - from.y) * e + arc)
        // a squishy pop: from a speck, overshoot, settle
        let u = min(age / 0.5, 1)
        let c1 = 1.70158, c3 = c1 + 1
        let back = 1 + c3 * pow(u - 1, 3) + c1 * pow(u - 1, 2)
        let land = age > dur ? max(0, 1 - (age - dur) / 0.5) : 0
        let squash = 1 - 0.07 * sin(land * .pi * 3) * land
        return (feet, max(0.05, 0.12 + 0.88 * back) * squash, min(1, age / 0.1))
    }

    private func ready(_ k: Int, _ m: MelonModel) {
        st.models[k] = m
        if st.popAt[k] != nil, st.appearAt[k] == nil { appear(k) }
    }

    private func appear(_ k: Int) {
        st.appearAt[k] = Date()
        guard motion else { perform(k, [.blink]); return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 760_000_000)
            guard !Task.isCancelled else { return }
            switch k {
            case 0: perform(k, [.idle(.look)])
            case 1: perform(k, [.idle(.tail)])
            case 2: perform(k, [.hop, .idle(.stretch)])
            default: perform(k, [.idle(.flapHop)])
            }
        }
    }

    /// Asks the Jelbie for the first of these moves it is free to take (the same rules as the picker's).
    private func perform(_ k: Int, _ moves: [StageMove]) {
        guard let m = st.models[k], !m.paused, let b = m.care.brainFor(0) else { return }
        for move in moves {
            switch move {
            case .blink: b.blinkRequested = true
            case .face(let f): b.face(f, hold: 2.2)
            case .hop: b.wantJoy()
            case .idle(let kind):
                guard b.commandedIdle == nil, b.idleState.kind == nil, case .none = b.script else { continue }
                if kind == .flapHop, b.feature != .wings || b.wingsFolded { b.wantJoy(); return }
                b.commandedIdle = kind
                return
            }
        }
    }

    // MARK: shadows, sparkles

    private func shadows(_ ctx: GraphicsContext, _ pr: OpeningProjector, now: Date, bob: Double) {
        for k in 0..<4 {
            guard let a = st.appearAt[k] else { continue }
            let age = now.timeIntervalSince(a)
            let u = motion ? OArt.smooth((age - 0.35) / 0.35) : OArt.smooth(age / 0.5)
            let p = restPoint(k, pr, bob: bob)
            let r = 17 * pr.zs
            ctx.fill(OArt.ell(p.x, p.y + 1, r * 1.9, r * 0.62), with: .radialGradient(Gradient(colors: [OArt.C(0xFFFFFF, 0.35 * pr.cam.hand * u), OArt.C(0xFFFFFF, 0)]), center: CGPoint(x: p.x, y: p.y), startRadius: 0, endRadius: r * 1.9))
            ctx.fill(OArt.ell(p.x, p.y + 1, r * 0.95, r * 0.28), with: .color(Color(hex: 0x2E4A2E).opacity(0.22 * u)))
        }
    }

    private func bursts(_ ctx: GraphicsContext, _ pr: OpeningProjector, now: Date, local: Double, bob: Double) {
        let u = pr.zs
        for k in 0..<4 {
            guard let pa = st.popAt[k] else { continue }
            let col = OArt.orbColors[k]
            let age = now.timeIntervalSince(pa)
            if age >= 0, age < 1.1 {
                let c = orbPoint(k, pr, bob: bob)
                let g = age / 1.1
                ctx.stroke(OArt.ell(c.x, c.y, 8 * u + g * 46 * u, 8 * u + g * 46 * u), with: .color(OArt.C(0xFFFFFF, 0.85 * (1 - g))), lineWidth: 3 * (1 - g) + 0.5)
                ctx.fill(OArt.ell(c.x, c.y, 30 * u * (1 - g), 30 * u * (1 - g)), with: .radialGradient(Gradient(colors: [OArt.C(0xFFFFFF, 0.9 * (1 - g)), OArt.C(col, 0)]), center: c, startRadius: 0, endRadius: 30 * u * (1 - g) + 1))
                for i in 0..<14 {
                    let a = Double(i) / 14 * .pi * 2 + Double(k) * 0.7
                    let sp = 0.6 + OArt.hash(i, 60 + k) * 0.8
                    let d = (14 + 62 * sp * (1 - pow(1 - g, 2))) * u
                    let pt = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d + g * g * 18 * u)
                    let r = (2.0 + OArt.hash(i, 70) * 2.4) * (1 - g * 0.7) * max(0.8, u)
                    ctx.fill(i % 3 == 0 ? OArt.star4(pt, r * 2.2) : OArt.ell(pt.x, pt.y, r, r), with: .color(i % 2 == 0 ? OArt.C(0xFFFFFF, 1 - g) : OArt.C(col, 1 - g)))
                }
            }
            // a second small sparkle where it lands
            if let a = st.appearAt[k], motion {
                let la = now.timeIntervalSince(a) - 0.6
                if la > 0, la < 0.8 {
                    let c = restPoint(k, pr, bob: bob)
                    let g = la / 0.8
                    for i in 0..<8 {
                        let an = Double(i) / 8 * .pi * 2
                        let d = (10 + 30 * g) * u
                        ctx.fill(OArt.star4(CGPoint(x: c.x + cos(an) * d, y: c.y - 6 * u + sin(an) * d * 0.5), (2.6 * (1 - g) + 0.5) * max(1, u)), with: .color(OArt.C(i % 2 == 0 ? 0xFFFFFF : col, 1 - g)))
                    }
                }
            }
        }
        // beats 6 and 7: little twinkles over the Jelbies' heads
        if st.beat >= 5, motion {
            let t = now.timeIntervalSince(st.storyStart)
            for k in 0..<4 {
                let base = restPoint(k, pr, bob: bob)
                for j in 0..<3 {
                    let ph = (t * 0.6 + Double(k) * 0.37 + Double(j) / 3).truncatingRemainder(dividingBy: 1)
                    let pt = CGPoint(x: base.x + (Double(j) - 1) * 24 * u + sin(t + Double(k)) * 4, y: base.y - (62 + 38 * ph) * u)
                    let a = sin(ph * .pi)
                    ctx.fill(OArt.star4(pt, (2 + 3.6 * a) * max(1, u * 0.8)), with: .color(OArt.C(0xFFFFFF, 0.9 * a)))
                }
            }
        }
    }

    // MARK: text

    @ViewBuilder
    private func overlayTexts(now: Date, local: Double, size: CGSize, pr: OpeningProjector) -> some View {
        let portrait = size.height >= size.width
        ZStack {
            captionView(now: now, local: local, size: size, portrait: portrait)
            if st.beat == 3 { giggleHint(now: now, local: local, size: size, portrait: portrait) }
            if A11ySettings.shared.captions, let sc = st.soundCaption, now.timeIntervalSince(sc.at) < 2.2 {
                Text(sc.text).font(SK.font(15, .semibold)).foregroundStyle(SK.ink)
                    .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(Color.white.opacity(0.85)))
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, size.height * 0.1)
            }
        }
    }

    private func captionView(now: Date, local: Double, size: CGSize, portrait: Bool) -> some View {
        let groups = OpeningScript.captions[st.beat]
        let fontSize: CGFloat = portrait ? min(34, size.width * 0.087) : min(32, size.height * 0.085)
        let out = st.beatEnd.timeIntervalSince(now)
        let outFade = holdBeat != nil ? 1 : OArt.smooth(out / 0.5)
        let pieces: [Text] = groups.enumerated().map { i, g in
            let a = motion ? OArt.smooth((local - 0.35 - Double(i) * 0.95) / 0.7) : (local > 0.2 + Double(i) * 0.5 ? 1 : 0)
            return Text(g).foregroundStyle(Color.white.opacity(a))
        }
        let joined = pieces.dropFirst().reduce(pieces[0]) { Text("\($0) \($1)") }
        return joined
            .font(SK.font(fontSize, .heavy))
            .multilineTextAlignment(.center)
            .lineSpacing(fontSize * 0.1)
            .shadow(color: Color(hex: 0x2A2060).opacity(0.65), radius: 7, y: 2)
            .shadow(color: Color(hex: 0x2A2060).opacity(0.35), radius: 1, y: 1)
            .padding(.horizontal, size.width * (portrait ? 0.08 : 0.16))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, size.height * (portrait ? 0.10 : 0.075))
            .opacity(outFade)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(OpeningScript.full(st.beat))
            .accessibilityAddTraits(.isHeader)
            .id(st.beat)
    }

    private func giggleHint(now: Date, local: Double, size: CGSize, portrait: Bool) -> some View {
        let show = local > 1.0 && st.giggleAt == nil
        let pulse = motion ? 1 + 0.06 * sin(now.timeIntervalSinceReferenceDate * 5) : 1
        let heeAge = st.giggleAt.map { now.timeIntervalSince($0) } ?? 9
        return ZStack {
            if show {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill").font(.system(size: 18, weight: .bold))
                    Text("Tap to giggle").font(SK.font(20, .heavy))
                }
                .foregroundStyle(SK.ink)
                .padding(.horizontal, 20).frame(minHeight: 48)
                .background(Capsule().fill(Color.white.opacity(0.92)).shadow(color: Color(hex: 0xBFF2FF).opacity(0.9), radius: 12 * pulse))
                .scaleEffect(pulse)
                .transition(.opacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tap to giggle")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { giggle() }
            }
            if heeAge < 1.6 {
                Text("hee hee!").font(SK.font(26, .black)).foregroundStyle(.white)
                    .shadow(color: Color(hex: 0x2A2060).opacity(0.6), radius: 5, y: 2)
                    .opacity(1 - OArt.smooth(heeAge / 1.6))
                    .offset(y: -heeAge * 26)
                    .rotationEffect(.degrees(sin(heeAge * 9) * 4))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: size.height * (portrait ? 0.20 : 0.17))
    }

    private func skipPill(_ geo: GeometryProxy) -> some View {
        Button { skip() } label: {
            HStack(spacing: 5) {
                Text("Skip").font(SK.font(17, .heavy))
                Image(systemName: "forward.fill").font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(SK.ink)
            .padding(.horizontal, 16).frame(minWidth: 72, minHeight: 44)
            .background(Capsule().fill(Color.white.opacity(0.78)).shadow(color: Color(hex: 0x2A2060).opacity(0.25), radius: 6, y: 2))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip the opening")
        .accessibilityIdentifier("opening-skip")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, max(geo.safeAreaInsets.top, Self.windowInsets.top, 14) + 6).padding(.trailing, max(geo.safeAreaInsets.trailing, Self.windowInsets.right, 0) + 16)
    }

    private static var windowInsets: UIEdgeInsets {
        (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow })?.safeAreaInsets ?? .zero
    }

    // MARK: flow

    private func begin() {
        if replay { st.snapshot = Self.saveSnapshot(); AudioHub.shared.earsDancing(true) }
        st.storyStart = Date()
        let size = UIScreen.main.bounds.size
        let first = holdBeat ?? 0
        Task { @MainActor in for _ in 0..<6 { LaunchGate.shared.stageTicked(); try? await Task.sleep(nanoseconds: 800_000_000) } }          // a cold launch straight into the story: let the curtain go
        st.camFrom = first == 0 ? OpeningCam() : target(first - 1, size: size)
        AudioHub.shared.playOpening("opening_underscore", volume: 0.85, music: true, fadeIn: 1.5)
        enter(first, tapped: false, initial: true)
    }

    private func enter(_ b: Int, tapped: Bool, initial: Bool = false) {
        st.beatTask?.cancel()
        st.token += 1
        let now = Date()
        let size = UIScreen.main.bounds.size
        st.camFrom = initial && b == 0 ? OpeningCam() : camera(at: now)
        st.camTo = target(b, size: size)
        st.camT0 = now
        st.camDur = !motion ? 0.01 : (initial && b > 0 ? 0.01 : (tapped ? 1.3 : [6.2, 6.0, 3.4, 4.0, 3.2, 3.5, 3.6][b]))
        if initial && b > 0 { st.camFrom = st.camTo }
        st.beat = b
        st.beatStart = now
        let vo = UIAccessibility.isVoiceOverRunning ? 1.7 : 1
        let dur = OpeningScript.durations[b] * vo
        st.beatEnd = now.addingTimeInterval(dur)
        if !motion && !initial { st.sceneOpacity = 0; withAnimation(.easeInOut(duration: 0.6)) { st.sceneOpacity = 1 } }
        if b >= 2 && st.dropStart == nil { st.dropStart = now.addingTimeInterval(initial && holdBeat != nil && b >= 3 ? -5 : 0) }
        if b >= 2 { mountStages(fast: b >= 4) }
        if b >= 5 { for k in 0..<4 where st.popAt[k] == nil { popOrb(k, loud: false) } }
        A11yAnnounce.say(OpeningScript.full(b), priority: .high)
        schedule(b, token: st.token)
        if holdBeat == nil { startTimer(after: dur) }
    }

    private func startTimer(after s: Double) {
        st.beatTask?.cancel()
        let b = st.beat
        st.beatEnd = Date().addingTimeInterval(s)
        st.beatTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
            guard !Task.isCancelled, st.beat == b else { return }
            advance(tapped: false)
        }
    }

    private func advance(tapped: Bool) {
        if st.beat >= 6 { finish(); return }
        enter(st.beat + 1, tapped: tapped)
    }

    private func tapped() {
        guard !st.leaving else { return }
        if st.beat == 3 && st.giggleAt == nil { giggle(); return }
        if holdBeat != nil { return }
        advance(tapped: true)
    }

    private func giggle() {
        guard st.giggleAt == nil, st.beat == 3 else { return }
        st.giggleAt = Date()
        sfx("opening_giggle", "A giggle", 1)
        sfx("opening_dew_chime", "A soft chime", 0.7, after: 0.15)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if holdBeat == nil { startTimer(after: 2.3) }
    }

    private func skip() {
        guard !st.leaving else { return }
        finish()
    }

    private func finish() {
        guard !st.leaving else { return }
        st.leaving = true
        st.beatTask?.cancel(); st.stageTask?.cancel()
        st.token += 1
        AudioHub.shared.stopOpening(fade: 0.8)
        let r = replay
        cameraRig.release()          // before the picker (or the room) engages its own
        if r { AudioHub.shared.earsDancing(false); Self.restoreSnapshot(st.snapshot); st.snapshot = [:] }          // before the room reads its save again
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            finished()
        }
    }

    private func teardown() {
        st.beatTask?.cancel(); st.stageTask?.cancel()
        st.token += 1
        AudioHub.shared.stopOpening(fade: 0.4)
        if replay { AudioHub.shared.earsDancing(false); Self.restoreSnapshot(st.snapshot); st.snapshot = [:] }
    }

    // MARK: audio cues and stage moves per st.beat

    private func sfx(_ name: String, _ caption: String, _ volume: Float, after: Double = 0) {
        st.soundCaption = (caption, Date())
        if after <= 0 { AudioHub.shared.playOpening(name, volume: volume) }
        else { Task { @MainActor in try? await Task.sleep(nanoseconds: UInt64(after * 1e9)); AudioHub.shared.playOpening(name, volume: volume) } }
    }

    private func cue(_ delay: Double, _ t: Int, _ action: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, st.token == t else { return }
            action()
        }
    }

    private func schedule(_ b: Int, token t: Int) {
        switch b {
        case 0:
            cue(0.5, t) { sfx("opening_twinkle", "Twinkling stars", 0.8) }
            cue(2.9, t) { sfx("opening_twinkle", "Twinkling stars", 0.5) }
        case 1:
            cue(0.8, t) { sfx("sparkle_2", "A soft sparkle", 0.5) }
        case 2:
            for (i, tm) in OArt.orbLand.enumerated() { cue(tm + 0.05, t) { sfx("opening_dew_chime", "A dew chime", 0.5 + 0.1 * Float(i)) } }
        case 3:
            cue(0.4, t) { sfx("opening_twinkle", "A tingly shimmer", 0.45) }
        case 4:
            for k in 0..<4 { cue(OpeningScript.popTimes[k], t) { popOrb(k, loud: true) } }
        case 5:
            for k in 0..<4 {
                cue(0.4 + Double(k) * 0.3, t) {
                    perform(k, [.blink])
                    cue(0.3, t) { perform(k, [.hop]); perform(k, [.face(.happy)]) }
                }
            }
            cue(0.3, t) { sfx("sparkle_1", "A sparkle", 0.6) }
        default:
            cue(0.5, t) { sfx("perk_sparkle_1", "A sparkle", 0.55) }
        }
    }

    private func popOrb(_ k: Int, loud: Bool) {
        guard st.popAt[k] == nil else { return }
        st.popAt[k] = Date()
        if loud {
            sfx("opening_pop", "Pop!", 1)
            sfx("sparkle_\(k % 2 + 1)", "A sparkle", 0.6, after: 0.05)
        }
        if st.models[k] != nil { appear(k) }
    }

    private func mountStages(fast: Bool) {
        guard !st.mountStarted else { return }
        st.mountStarted = true
        cameraRig.engage()
        st.stageTask = Task { @MainActor in
            var count = 4
            #if targetEnvironment(simulator)
            if UserDefaults.standard.object(forKey: "OpeningMount") != nil { count = UserDefaults.standard.integer(forKey: "OpeningMount") }          // capture aid: fewer live stages (the simulator is slow)
            #endif
            for k in 0..<count {                      // one at a time: each builds a real 3D room, so wait for the last one to be standing before the next
                guard !Task.isCancelled else { return }
                st.mounted[k] = true
                for _ in 0..<(fast ? 20 : 60) where st.models[k] == nil && !Task.isCancelled { try? await Task.sleep(nanoseconds: 100_000_000) }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    // MARK: replay keeps the save as it was (the previews write their Jelbies' needs / stats while they stand on the stage)

    private static func keys() -> [String] {
        (0..<4).flatMap { c in [JellyKeys.needs(c), JellyKeys.grime(c), JellyKeys.words(c), JellyKeys.stats(c), JellyKeys.perks(c)] }
    }
    private static func saveSnapshot() -> [String: Any] {
        var s: [String: Any] = [:]
        for k in keys() { if let v = UserDefaults.standard.object(forKey: k) { s[k] = v } }
        return s
    }
    private static func restoreSnapshot(_ s: [String: Any]) {
        for k in keys() { if let v = s[k] { UserDefaults.standard.set(v, forKey: k) } else { UserDefaults.standard.removeObject(forKey: k) } }
    }
}
