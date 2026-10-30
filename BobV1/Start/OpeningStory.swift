//
//  OpeningStory.swift
//  The game opening: a ~30 s animated story that plays on a NEW game (title screen -> this -> the species picker) and from Settings > "Watch the
//  opening" (which replays it, then the picker as a preview and the first-day scene, and returns to the room with the save untouched: StartFlow.replaying).
//  Every Jelbie in the story is drawn bare (ShowcaseStage `bare`): the plain species look, never the player's saved wear. Seven beats on one camera (OpeningArt.swift):
//    1 night sky, drifting down through clouds   2 the clouds part on Wobble Isle, dawn   3 push in to the Jelly Spring, dewdrops fall
//    (the four coloured drops shimmer at the end of beat 3)   4 each drop pops into its real 3D Jelbie (ShowcaseStage cutout)
//    6 they turn to the player, blink and hop   7 "Which one will you take home?" and a cross-fade into the picker's blue page.
//  A tap anywhere moves on; "Skip" (top right) always leaves. Reduce Motion: no camera travel, no drifting, plain fades. VoiceOver reads each
//  caption. Audio: Resources/opening_underscore (piano + strings) and opening_twinkle / dew_chime / pop plus the app's sparkles.
//  The four stages are built hidden from the first seconds (beats 1-3 have time), so each Jelbie is standing when its drop pops; a slow device
//  holds the drop until its Jelbie is ready rather than popping it empty.
//  The reveal (beat 4) is strictly one Jelbie at a time, in the picker's order, driven by RevealSequencer (below): a drop swells and wobbles,
//  pops, its Jelbie leaps out and lands, settles, and only then does the next drop start to swell. A tap in the reveal only hurries it; the
//  next beat starts when the last Jelbie has settled. Its animations run on a reveal clock (OpeningClock) that advances only by what a drawn
//  frame shows, at most a few frames' worth at a time, so a render stall delays a pop and never skips it.
//  Simulator-only capture flags: -OpeningBeat 1...7 starts at that beat (and holds it: no auto-advance) for screenshots; -OpeningReplay 1 plays
//  Settings > Watch the opening straight away (needs a save); -OpeningNew 1 plays a new game's opening, not held.
//

import SwiftUI

enum OpeningScript {
    /// Each caption is split into word groups that fade in one after the other. Joined with spaces they are the exact story text.
    static let captions: [[String]] = [
        ["High above", "the clouds…"],
        ["…floats a little town", "called Wobble Isle.", "You've just moved in!"],
        ["In the middle of town", "is the Jelly Spring.", "Every morning, a few", "of its dewdrops wobble awake…"],
        ["…as Jelbies!"],
        ["Every Jelbie needs", "someone to take care", "of them."],
        ["Look after them,", "and they'll grow:", "learning tricks,", "making friends,", "and competing around town", "in races, shows and volleyball."],
        ["The Spring has a welcome gift", "for its newest neighbour.", "Which one will you take home?"],
    ]
    /// Seconds each beat lasts on its own.
    /// (Beat index 3, the reveal, is nominal: it lasts until the last Jelbie has settled, then `revealTail`.)
    static let durations: [Double] = [5.2, 6.6, 8.2, 11.0, 4.8, 7.4, 6.0]
    /// After the last Jelbie settles, the "…as Jelbies!" beat holds this long (their hello moves play out) before the next caption.
    static let revealTail = 1.6
    /// The Jelbies, in the picker's order (blue, yellow, purple, green): character ids.
    static let characters = [0, 1, 3, 2]
    static let names = ["Blueberry", "Lemon Drop", "Taro", "Matcha"]
    /// Where each stands on the grass (island units, the Spring is at 200, 100): a gentle U (a smile on screen) along the front rim of the oval, the two
    /// middle ones a little nearer the camera, the ends further back and out to the sides. Neighbours touch at most.
    static let restX: [Double] = [122, 171, 229, 278]
    static let restY: [Double] = [132, 146, 146, 132]
    /// Each one's resting angle off the camera (radians, + = towards screen right): all turned in a little towards a point in front of the middle of the
    /// group, the ends about 25 degrees, the middle two about 8.
    static let stance: [Float] = {
        let base: [Float] = [0.436, 0.14, -0.14, -0.436]
        #if targetEnvironment(simulator)
        if UserDefaults.standard.object(forKey: "OpeningStanceScale") != nil { let k = Float(UserDefaults.standard.double(forKey: "OpeningStanceScale")); return base.map { $0 * k } }          // capture aid: exaggerate (or zero) the stance to check its direction
        #endif
        return base
    }()
    static func full(_ beat: Int) -> String { captions[beat].joined(separator: " ") }
}

/// One scripted move for the Jelbie in picker slot `k`, due at reveal-clock time `at` (retried a few times while the Jelbie is busy).
enum OpeningStep { case blink, face(FaceKind, Float), idle(IdleKind), hop, turn(Float), wave, wings }
struct OpeningCue { var at: Double; var k: Int; var step: OpeningStep; var tries = 0 }

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
    var popAt: [Double?] = [nil, nil, nil, nil]          // reveal-clock seconds (OpeningClock)
    var appearAt: [Double?] = [nil, nil, nil, nil]
    var helloDone = [false, false, false, false]
    var reveal = RevealSequencer()
    var revealTask: Task<Void, Never>?
    var cues: [OpeningCue] = []
    var gesturesStarted = false
    var lookAsked = [false, false, false, false]
    var holding = [false, false, false, false]          // the Jelbie is in its held stance (a LOOK idle whose hold never ends: the body only stays turned while a move owns it)
    var seenKind = [String](repeating: "", count: 4)
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

/// The reveal's own clock: it advances by the time between drawn frames, but never by more than `maxStep` at once, so when the renderer
/// stalls (a busy simulator, a hitch) the pop that was in progress is delayed rather than skipped. Not observable: only frames and the
/// sequencer's poll read it.
final class OpeningClock {
    static let maxStep = 0.066
    private(set) var t = 0.0
    private var last: Date?
    nonisolated deinit {}
    /// Simulator capture aid (-OpeningFixedStep 1): every drawn frame advances the clock by exactly 1/30 s, so a slow simulator records the reveal frame by frame.
    private static let fixedStep: Bool = {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.integer(forKey: "OpeningFixedStep") != 0
        #else
        return false
        #endif
    }()
    @discardableResult func advance(_ now: Date) -> Double {
        if Self.fixedStep {
            if let l = last, now > l { t += 1.0 / 30 }
            if last == nil || now > last! { last = now }
            return t
        }
        if let l = last { t += min(max(now.timeIntervalSince(l), 0), Self.maxStep) }
        if last == nil || now > last! { last = now }
        return t
    }
}

/// Who pops when, with no rendering in it: strictly one drop at a time, in order. Drop k swells; once its Jelbie is ready (and the swell has
/// run) it pops; the next drop starts to swell only when that Jelbie has landed and settled. Times are reveal-clock seconds.
struct RevealSequencer {
    struct Timing: Equatable {
        var swell = 1.1          // a drop swells and wobbles this long before it bursts
        var settle = 1.12        // from the burst: 0.62 s leap + 0.5 s landing wobble
        var giveUp = 40.0        // a Jelbie that never stands (it should) does not hold the story for ever
        var hurried: Timing { Timing(swell: 0.45, settle: 0.7, giveUp: giveUp) }
    }
    enum Event: Equatable { case swell(Int), pop(Int), done }
    static let count = 4

    var timing = Timing()
    var hurry = false
    private(set) var next = 0
    private(set) var swellAt = [Double?](repeating: nil, count: count)
    private(set) var popAt = [Double?](repeating: nil, count: count)
    var done: Bool { next >= Self.count }
    private var current: Timing { hurry ? timing.hurried : timing }

    /// 0...1 while drop k swells (it holds at 1 while its Jelbie is still being built); 0 before and after.
    func swell(_ k: Int, now: Double) -> Double {
        guard popAt[k] == nil, let a = swellAt[k] else { return 0 }
        return min(max((now - a) / max(current.swell, 0.01), 0), 1)
    }

    /// Call as often as you like with the current reveal-clock time and which Jelbies are standing. At most one thing happens per call.
    mutating func update(now: Double, ready: [Bool]) -> [Event] {
        guard !done else { return [] }
        let k = next, tm = current
        guard let s = swellAt[k] else { swellAt[k] = now; return [.swell(k)] }
        guard let p = popAt[k] else {
            let waited = now - s
            if waited >= tm.swell, ready[k] || waited >= tm.giveUp { popAt[k] = now; return [.pop(k)] }
            return []
        }
        guard now - p >= tm.settle else { return [] }
        next += 1
        if done { return [.done] }
        swellAt[next] = now
        return [.swell(next)]
    }

    /// Capture aid (-OpeningBeat 5...7): everything has already happened.
    mutating func finishAll(at t: Double) {
        for k in 0..<Self.count { swellAt[k] = t; popAt[k] = t }
        next = Self.count
    }
}

struct OpeningStoryView: View {
    @State private var st = OpeningState()
    @State private var clock = OpeningClock()
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
        let rc = clock.advance(now)
        let pr = OpeningProjector(size: size, cam: cam)
        let local = now.timeIntervalSince(st.beatStart)
        var d = OpeningDraw()
        d.motion = motion
        d.t = motion ? now.timeIntervalSince(st.storyStart) : 0
        d.dropT = st.dropStart.map { motion ? now.timeIntervalSince($0) : 9 }
        d.home = st.beat == 1 ? OArt.smooth(local / 1.6) : (st.beat == 2 ? OArt.smooth(1 - local / 1.0) : 0)
        d.shiver = st.beat == 2 ? OArt.smooth((local - 4.6) / 1.2) : 0          // the four drops shimmer just before they wake; then the one about to pop wobbles on its own
        for k in 0..<4 {
            d.gone[k] = st.popAt[k] != nil
            let s = OArt.smooth(st.reveal.swell(k, now: rc))
            d.swell[k] = s; d.wobble[k] = s
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
            Canvas { ctx, _ in shadows(ctx, pr, now: rc, bob: bob) }
            jelbies(now: rc, pr: pr, bob: bob)
            Canvas { ctx, _ in bursts(ctx, pr, now: now, rc: rc, local: local, bob: bob) }
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
        case 3: return OpeningCam(cy: 800, zoom: land ? 2.15 : 1.75, warm: 1, part: 1, hand: 0)
        case 4, 5: return OpeningCam(cy: 800, zoom: land ? 2.2 : 1.8, warm: 1, part: 1, hand: 0)
        default: return OpeningCam(cy: 800, zoom: land ? 2.2 : 1.8, warm: 1, part: 1, hand: 1)
        }
    }

    // MARK: 3D Jelbies

    private func restPoint(_ k: Int, _ pr: OpeningProjector, bob: Double) -> CGPoint {
        pr.island(OpeningScript.restX[k], OpeningScript.restY[k], bob: bob)
    }
    private func orbPoint(_ k: Int, _ pr: OpeningProjector, bob: Double) -> CGPoint {
        pr.island(OArt.orbX[k], OArt.orbY[k] - 10, bob: bob)
    }

    private func jelbies(now: Double, pr: OpeningProjector, bob: Double) -> some View {
        let f = 58 * pr.zs * 1.5                  // the frame is ~1.5 x the spacing between them (the picker's close-up framing fills it)
        return ZStack {
            ForEach(0..<4, id: \.self) { k in
                if st.mounted[k] {
                    let st = pose(k, now: now, pr: pr, bob: bob, f: f)
                    ShowcaseStage(roster: [OpeningScript.characters[k]], focusFirst: true, fullScreen: false, cutout: true, bare: true, scripted: true, onReady: { m in ready(k, m) })
                        .frame(width: f, height: f)
                        .scaleEffect(x: st.scale * st.sx, y: st.scale * st.sy, anchor: .init(x: 0.5, y: 0.73))
                        .position(x: st.feet.x, y: st.feet.y - 0.23 * f)
                        .opacity(st.opacity)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where the k-th Jelbie is: hidden in its drop, then leaping out of it to its spot on the grass.
    private func pose(_ k: Int, now: Double, pr: OpeningProjector, bob: Double, f: Double) -> (feet: CGPoint, scale: Double, sx: Double, sy: Double, opacity: Double) {
        guard let a = st.appearAt[k] else { return (restPoint(k, pr, bob: bob), 0.01, 1, 1, 0) }
        let rest = restPoint(k, pr, bob: bob)
        let age = now - a
        guard motion else { return (rest, 1, 1, 1, OArt.smooth(age / 0.5)) }
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
        // jelly: stretched tall while it shoots out of the drop, squashed flat on landing, then a couple of damped wobbles
        let fly = p < 1 ? sin(p * .pi) : 0
        let squash = 0.16 * sin(land * .pi * 3) * land
        let sy = 1 + 0.18 * fly - squash, sx = 1 - 0.10 * fly + squash * 0.8
        return (feet, max(0.05, 0.12 + 0.88 * back), sx, sy, min(1, age / 0.1))
    }

    private func ready(_ k: Int, _ m: MelonModel) {
        st.models[k] = m
        LaunchTiming.mark("opening: Jelbie \(k) standing (beat \(st.beat + 1))")
        if st.popAt[k] != nil, st.appearAt[k] == nil { appear(k) }
        if heldWithoutReveal, !st.gesturesStarted, !st.models.contains(where: { $0 == nil }) { st.gesturesStarted = true; gestureCues(st.beat) }
    }

    private func appear(_ k: Int) {
        LaunchTiming.mark("opening: Jelbie \(k) revealed (beat \(st.beat + 1), reveal clock \(String(format: "%.2f", clock.t)) s)")
        st.appearAt[k] = clock.t
        guard motion else { st.helloDone[k] = true; perform(k, .blink, clock.t); return }          // the hello move of the others is cued by pollReveal, on the reveal clock
    }

    /// Each species says hello in its own way, keyed by CHARACTER (not slot): all face the front; at most yellow turns, once, a little.
    private func hello(_ k: Int) {
        switch OpeningScript.characters[k] {
        case 0:          // Blueberry: the side-eye. Eyes narrow, then a head tilt and a slow blink; the body stays square to the camera
            cue(k, 0, .face(.focused, 1.0)); cue(k, 0.9, .face(.curious, 1.8)); cue(k, 2.4, .blink)
        case 1:          // Lemon Drop: a happy tail wag in place, one slight hip turn (~29 degrees) and back to front
            cue(k, 0, .face(.happy, 3.2)); cue(k, 0.3, .turn(-0.45)); cue(k, 1.6, .turn(0))
        case 3:          // Taro: a wing flutter (three flap bursts) with one small hop, facing front (the full flap-hop drifts forward off the stage's floor)
            cue(k, 0, .face(.happy, 3.0)); cue(k, 0, .wings); cue(k, 0.5, .hop); cue(k, 1.0, .wings); cue(k, 2.0, .wings)
        default:         // Matcha: the daisy sun-stretch, reaching up
            cue(k, 0, .face(.happy, 3.2)); cue(k, 0.2, .idle(.stretch))
        }
    }

    /// A capture aid starts after the reveal (-OpeningBeat 5...7): its gestures wait for the Jelbies to be standing (see `ready`).
    private var heldWithoutReveal: Bool { holdBeat.map { $0 >= 4 } ?? false }

    /// The small scripted life of beats 5-7 (slots: blue, yellow, purple, green): each Jelbie its own gesture at its own moment, all facing their stance.
    private func gestureCues(_ b: Int) {
        switch b {
        case 4:
            cue(0, 0.5, .blink); cue(0, 1.1, .hop)                          // Blueberry: a slow blink and a tiny unbothered shrug-hop
            cue(1, 1.5, .idle(.bounce))                                      // Lemon Drop: a bounce
            cue(2, 2.5, .face(.joyArc, 1.2)); cue(2, 2.6, .idle(.giggle))    // Taro: a happy sway
            cue(3, 3.4, .wave)                                               // Matcha: a wave
        case 5:                                                              // calm: blinks at different moments, a smile or two
            for (k, d) in [(0, 0.8), (1, 1.9), (2, 3.1), (3, 4.3)] { cue(k, d, .blink) }
            cue(1, 2.6, .face(.happy, 2.0)); cue(3, 5.2, .face(.happy, 1.8))
        default:
            for (k, d) in [(2, 0.7), (0, 1.6), (3, 2.7), (1, 3.5)] { cue(k, d, .blink) }
        }
    }

    /// Queues a scripted move `after` seconds from now on the reveal clock.
    private func cue(_ k: Int, _ after: Double, _ step: OpeningStep) {
        st.cues.append(OpeningCue(at: clock.t + after, k: k, step: step))
    }

    /// Runs the due cues; a Jelbie that is busy (still landing, mid-move) gets the move a moment later.
    private func runCues(_ rc: Double) {
        guard !st.cues.isEmpty else { return }
        var later: [OpeningCue] = []
        let due = st.cues.filter { $0.at <= rc }
        st.cues.removeAll { $0.at <= rc }
        for var c in due {
            let ok = perform(c.k, c.step, rc)
            if ok || c.tries == 0 || c.tries >= 16 { LaunchTiming.mark("opening: move \(c.k) \(c.step) \(ok ? "played" : (c.tries >= 16 ? "dropped" : "busy")) (reveal clock \(String(format: "%.2f", rc)) s)") }
            if !ok && c.tries < 16 { c.tries += 1; c.at = rc + 0.25; later.append(c) }
        }
        st.cues.append(contentsOf: later)
    }

    /// Asks the Jelbie for one move when it is free to take it (false = busy, try again).
    @discardableResult
    private func perform(_ k: Int, _ step: OpeningStep, _ rc: Double) -> Bool {
        guard let m = st.models[k], !m.paused, let b = m.care.brainFor(0) else { return true }
        let holdingStance = st.holding[k] && b.idleState.kind == .look
        let free = b.commandedIdle == nil && b.idleState.kind == nil && { if case .none = b.script { return true } else { return false } }()
        switch step {
        case .blink: b.blinkRequested = true
        case .face(let f, let hold): b.face(f, hold: hold)
        case .hop:
            guard motion else { return true }
            if holdingStance { releaseStance(k, b); return false }
            guard free, let sim = m.care.lastSim else { return false }
            b.startHopPlay(sim: sim, distance: 0.0001)
        case .idle(let kind):
            guard motion else { return true }
            if holdingStance { releaseStance(k, b); return false }
            guard free else { return false }
            if kind == .flapHop, b.feature != .wings || b.wingsFolded { if let sim = m.care.lastSim { b.startHopPlay(sim: sim, distance: 0.0001) }; return true }
            b.commandedIdle = kind
        case .turn(let off):          // swing the held stance a little (and back): the look idle turns to its goal again
            guard motion else { return true }
            guard holdingStance else { return false }
            b.idleState.goalYaw = b.faceCameraYaw() + OpeningScript.stance[k] + off
            b.idleState.phase = 0; b.idleState.phaseT = 0
        case .wave:
            guard motion else { return true }
            if holdingStance { releaseStance(k, b); return false }
            guard free else { return false }
            b.requestNow(.wave)
        case .wings:
            guard motion else { return true }
            m.care.features.primeBurst(0)          // the next wing flap burst starts on the next tick (2-4 quick flaps)
        }
        return true
    }

    /// Ends a held stance so a move can play (the body turns back to the camera first; `keepFacing` takes the stance up again afterwards).
    private func releaseStance(_ k: Int, _ b: BlobBrain) {
        st.holding[k] = false
        b.idleState.hold = 0
    }

    /// After landing, every Jelbie takes up its stance and keeps it: angled in towards the middle of the group. The body only stays turned while a move
    /// owns it, so the stance is a LOOK idle (turn to the goal, hold) whose hold never runs out; a scripted move releases it and the stance returns after.
    private func keepFacing(_ rc: Double) {
        guard motion, st.beat >= 3 else { return }
        for k in 0..<4 {          // (log what each brain is really doing, so the captures show whether a scripted move took)
            guard let m = st.models[k], let b = m.care.brainFor(0) else { continue }
            let now = "\(b.idleState.kind.map { "\($0)" } ?? "-")/\(b.script)"
            let short = String(now.prefix(18))
            if short != st.seenKind[k] { st.seenKind[k] = short; LaunchTiming.mark("opening: brain \(k) now \(short) autonomy \(b.autonomy) (reveal clock \(String(format: "%.2f", rc)) s)") }
        }
        for k in 0..<4 {
            guard let a = st.appearAt[k], rc - a > 1.2 else { continue }
            guard let m = st.models[k], !m.paused, let b = m.care.brainFor(0) else { continue }
            if st.holding[k] {
                if b.idleState.kind != .look { st.holding[k] = false }          // something ended it
                continue
            }
            if b.idleState.kind == .look, b.commanded, b.commandedIdle == nil, !st.holding[k], st.lookAsked[k] {          // our look has just started: make it a stance hold
                st.lookAsked[k] = false
                b.idleState.goalYaw = b.faceCameraYaw() + OpeningScript.stance[k]
                b.idleState.hold = 1e9
                b.idleState.sign = 0
                st.holding[k] = true
                LaunchTiming.mark("opening: stance \(k) held, goal \(String(format: "%.3f", OpeningScript.stance[k])) rad")
                continue
            }
            guard b.commandedIdle == nil, b.idleState.kind == nil, case .none = b.script, b.pending == nil else { continue }
            if st.cues.contains(where: { $0.k == k && $0.at <= rc + 1.5 }) { continue }          // a scripted move is waiting for this Jelbie to be free: let it go first
            st.lookAsked[k] = true
            b.commandedIdle = .look
        }
    }

    // MARK: shadows, sparkles

    private func shadows(_ ctx: GraphicsContext, _ pr: OpeningProjector, now: Double, bob: Double) {
        for k in 0..<4 {
            guard let a = st.appearAt[k] else { continue }
            let age = now - a
            let u = motion ? OArt.smooth((age - 0.35) / 0.35) : OArt.smooth(age / 0.5)
            let p = restPoint(k, pr, bob: bob)
            let r = 17 * pr.zs
            ctx.fill(OArt.ell(p.x, p.y + 1, r * 1.9, r * 0.62), with: .radialGradient(Gradient(colors: [OArt.C(0xFFFFFF, 0.35 * pr.cam.hand * u), OArt.C(0xFFFFFF, 0)]), center: CGPoint(x: p.x, y: p.y), startRadius: 0, endRadius: r * 1.9))
            ctx.fill(OArt.ell(p.x, p.y + 1, r * 0.95, r * 0.28), with: .color(Color(hex: 0x2E4A2E).opacity(0.22 * u)))
        }
    }

    private func bursts(_ ctx: GraphicsContext, _ pr: OpeningProjector, now: Date, rc: Double, local: Double, bob: Double) {
        let u = pr.zs
        for k in 0..<4 {
            guard let pa = st.popAt[k] else { continue }
            let col = OArt.orbColors[k]
            let age = rc - pa
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
                let la = rc - a - 0.6
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
        if st.beat >= 4, motion {
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
            if st.beat == 5 { careIcons(now: now, local: local, size: size, portrait: portrait) }
            if A11ySettings.shared.captions, let sc = st.soundCaption, now.timeIntervalSince(sc.at) < 2.2 {
                Text(sc.text).font(SK.font(15, .semibold)).foregroundStyle(SK.ink)
                    .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(Color.white.opacity(0.85)))
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, size.height * 0.1)
            }
        }
    }

    private func captionView(now: Date, local: Double, size: CGSize, portrait: Bool) -> some View {
        let groups = OpeningScript.captions[st.beat]
        let longK: CGFloat = OpeningScript.full(st.beat).count > 55 ? 0.86 : 1          // the long captions get a little smaller
        let fontSize: CGFloat = (portrait ? min(34, size.width * 0.087) : min(32, size.height * 0.085)) * longK
        let out = st.beatEnd.timeIntervalSince(now)
        let gap = groups.count > 4 ? 0.6 : 0.95
        let outFade = holdBeat != nil ? 1 : OArt.smooth(out / 0.5)
        let pieces: [Text] = groups.enumerated().map { i, g in
            let a = motion ? OArt.smooth((local - 0.35 - Double(i) * gap) / 0.7) : (local > 0.2 + Double(i) * 0.5 ? 1 : 0)
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
            .padding(.bottom, size.height * (portrait ? (st.beat == 5 ? 0.175 : 0.10) : (st.beat == 5 ? 0.17 : 0.075)))
            .opacity(outFade)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(OpeningScript.full(st.beat))
            .accessibilityAddTraits(.isHeader)
            .id(st.beat)
    }

    /// Beat 6: three tiny badges pop in under the caption: a checkered flag (races), a star with ribbons (shows) and a volleyball.
    private func careIcons(now: Date, local: Double, size: CGSize, portrait: Bool) -> some View {
        let d: CGFloat = portrait ? 54 : 46
        return Canvas { ctx, sz in
            let y = sz.height * (portrait ? 0.935 : 0.915)
            for i in 0..<3 {
                let t0 = 3.4 + Double(i) * 0.55
                let age = local - t0
                guard age > 0 else { continue }
                let u = st.leaving ? 1 : min(age / 0.45, 1)
                let c1 = 1.70158, c3 = c1 + 1
                let k = motion ? max(0.05, 1 + c3 * pow(u - 1, 3) + c1 * pow(u - 1, 2)) : 1
                let cx = sz.width / 2 + (Double(i) - 1) * Double(d) * 1.9
                var c = ctx
                c.translateBy(x: cx, y: y); c.scaleBy(x: k, y: k); c.opacity = min(1, age / 0.15)
                OpeningIcons.badge(c, i, d: Double(d))
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
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
        AudioHub.shared.playOpening("opening_underscore", volume: 0.85, music: true, fadeIn: 1.5, loop: true)          // the story outlasts the 36 s clip: it comes round again
        st.reveal.timing = motion ? RevealSequencer.Timing() : RevealSequencer.Timing(swell: 0.5, settle: 0.8)
        enter(first, tapped: false, initial: true)
        st.revealTask = Task { @MainActor in
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 33_000_000); pollReveal() }
        }
        if first == 0 {
            Task { @MainActor in          // pre-warm: after the first stars have drawn, before the first push-in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if !st.leaving { mountStages(fast: false) }
            }
        }
    }

    private func enter(_ b: Int, tapped: Bool, initial: Bool = false) {
        st.beatTask?.cancel()
        st.token += 1
        let now = Date()
        let size = UIScreen.main.bounds.size
        st.camFrom = initial && b == 0 ? OpeningCam() : camera(at: now)
        st.camTo = target(b, size: size)
        st.camT0 = now
        st.camDur = !motion ? 0.01 : (initial && b > 0 ? 0.01 : (tapped ? 1.3 : [6.2, 6.0, 3.4, 3.2, 3.0, 3.5, 3.6][b]))
        if initial && b > 0 { st.camFrom = st.camTo }
        st.beat = b
        st.beatStart = now
        let vo = UIAccessibility.isVoiceOverRunning ? 1.7 : 1
        let dur = OpeningScript.durations[b] * vo
        st.beatEnd = b == 3 ? .distantFuture : now.addingTimeInterval(dur)          // the reveal beat ends when its last Jelbie has settled (revealFinished)
        if !motion && !initial { st.sceneOpacity = 0; withAnimation(.easeInOut(duration: 0.6)) { st.sceneOpacity = 1 } }
        if b >= 2 && st.dropStart == nil { st.dropStart = now.addingTimeInterval(initial && holdBeat != nil && b >= 3 ? -5 : 0) }
        if b >= 1 { mountStages(fast: b >= 3) }          // beats 1-3 build the four stages hidden, so every Jelbie is standing by when its drop pops
        if b >= 4, !st.reveal.done {
            // only a capture aid (-OpeningBeat 5...7) starts after the reveal: everything has already happened. The story never jumps over the reveal.
            let t = clock.t - 10
            st.reveal.finishAll(at: t)
            for k in 0..<4 { st.popAt[k] = t; st.appearAt[k] = t; st.helloDone[k] = true }
        }
        A11yAnnounce.say(OpeningScript.full(b), priority: .high)
        schedule(b, token: st.token)
        if holdBeat == nil, b != 3 { startTimer(after: dur) }
    }

    private func startTimer(after s: Double) {
        st.beatTask?.cancel()
        let b = st.beat
        st.beatEnd = Date().addingTimeInterval(s)
        st.beatTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
            guard !Task.isCancelled, st.beat == b else { return }
            if b == 2 {
                // the drops stay shimmering until all four Jelbies are standing behind them (slow devices): the pops that follow are never empty
                var waited = 0.0
                while st.models.contains(where: { $0 == nil }), waited < Self.standingCap, !Task.isCancelled, st.beat == b { try? await Task.sleep(nanoseconds: 100_000_000); waited += 0.1 }
                guard !Task.isCancelled, st.beat == b else { return }
            }
            advance(tapped: false)
        }
    }
    /// The longest beat 3 waits for the stages to stand (the simulator's software renderer needs minutes).
    private static var standingCap: Double {
        #if targetEnvironment(simulator)
        return 400
        #else
        return 12
        #endif
    }

    private func advance(tapped: Bool) {
        if st.beat == 3, !st.reveal.done { return }          // the next beat waits until the last Jelbie has settled
        if st.beat >= 6 { finish(); return }
        enter(st.beat + 1, tapped: tapped)
    }

    private func tapped() {
        guard !st.leaving else { return }
        if holdBeat != nil { return }
        if st.beat == 3, !st.reveal.done { st.reveal.hurry = true; return }          // a tap in the reveal only hurries the rest: still one at a time
        advance(tapped: true)
    }

    private func skip() {
        guard !st.leaving else { return }
        finish()
    }

    private func finish() {
        guard !st.leaving else { return }
        st.leaving = true
        st.beatTask?.cancel(); st.stageTask?.cancel(); st.revealTask?.cancel()
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
        st.beatTask?.cancel(); st.stageTask?.cancel(); st.revealTask?.cancel()
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
            cue(4.8, t) { sfx("opening_twinkle", "A tingly shimmer", 0.55) }
        case 3:
            break          // the reveal is event-driven (pollReveal), not cued by time
        case 4:
            if !heldWithoutReveal { gestureCues(4) }
            cue(0.3, t) { sfx("sparkle_1", "A sparkle", 0.6) }
        case 5:
            for i in 0..<3 { cue(3.4 + Double(i) * 0.55, t) { sfx("opening_pop", "A tiny pop", 0.45) } }
            if !heldWithoutReveal { gestureCues(5) }
        default:
            if !heldWithoutReveal { gestureCues(6) }
            cue(0.5, t) { sfx("perk_sparkle_1", "A sparkle", 0.55) }
        }
    }

    /// Steps the reveal: the hello moves (on the reveal clock) and the sequencer, one event at a time.
    private func pollReveal() {
        guard !st.leaving else { return }
        let rc = clock.t
        for k in 0..<4 where !st.helloDone[k] {
            if let a = st.appearAt[k], rc - a >= 0.9 { st.helloDone[k] = true; hello(k) }
        }
        runCues(rc)
        keepFacing(rc)
        guard st.beat >= 3, !st.reveal.done else { return }
        // the drops must be sitting on the water before the first one swells (a tap can bring beat 4 early)
        let landed = !motion || (st.dropStart.map { Date().timeIntervalSince($0) >= OArt.orbLand[3] + 0.4 } ?? false)
        guard landed else { return }
        for e in st.reveal.update(now: rc, ready: st.models.map { $0 != nil }) {
            switch e {
            case .swell(let k): LaunchTiming.mark("opening: drop \(k) swelling (reveal clock \(String(format: "%.2f", rc)) s)")
            case .pop(let k): popNow(k, loud: true)
            case .done: revealFinished()
            }
        }
    }

    private func revealFinished() {
        guard st.beat == 3, holdBeat == nil else { return }
        let vo = UIAccessibility.isVoiceOverRunning ? 1.7 : 1
        startTimer(after: OpeningScript.revealTail * vo)
    }

    private func popNow(_ k: Int, loud: Bool) {
        guard st.popAt[k] == nil else { return }
        st.popAt[k] = clock.t
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
                LaunchTiming.mark("opening: stage \(k) building (beat \(st.beat + 1))")
                for _ in 0..<(fast ? 20 : 60) where st.models[k] == nil && !Task.isCancelled { try? await Task.sleep(nanoseconds: 100_000_000) }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    // MARK: replay keeps the save as it was (the previews write their Jelbies' needs / stats while they stand on the stage)

    private static func keys() -> [String] {
        (0..<4).flatMap { c in [JellyKeys.needs(c), JellyKeys.grime(c), JellyKeys.words(c), JellyKeys.stats(c), JellyKeys.perks(c)] }
    }
    static func saveSnapshot() -> [String: Any] {
        var s: [String: Any] = [:]
        for k in keys() { if let v = UserDefaults.standard.object(forKey: k) { s[k] = v } }
        return s
    }
    static func restoreSnapshot(_ s: [String: Any]) {
        for k in keys() { if let v = s[k] { UserDefaults.standard.set(v, forKey: k) } else { UserDefaults.standard.removeObject(forKey: k) } }
    }
}
