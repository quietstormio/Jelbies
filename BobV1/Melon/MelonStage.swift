//
//  MelonStage.swift
//  Metal stage: MTKView subclass with touch handling, the controller that owns simulation + renderer
//  and drives the frame loop (port of the pointer / frame logic of main.js).
//

import SwiftUI
import MetalKit
import QuartzCore
import simd

// MARK: - SwiftUI wrapper

struct MelonStage: UIViewRepresentable {
    let model: MelonModel

    func makeCoordinator() -> MelonController { MelonController(model: model) }

    func makeUIView(context: Context) -> MelonStageView {
        let controller = context.coordinator
        let view = MelonStageView(frame: .zero, device: controller.device)
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: MelonStageView, context: Context) {}
}

// MARK: - View

let bobScaleCm: Float = 6      // 1 sim unit ~ 6 cm
let bobDensity: Float = 1.1    // gummy, g/cm^3

final class MelonStageView: MTKView, UIGestureRecognizerDelegate {
    weak var controller: MelonController?
    private(set) var activeTouches = 0
    private weak var heldScrollView: UIScrollView?

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        preferredFramesPerSecond = 60      // RateGovernor raises this to 120 on ProMotion when the GPU has headroom
        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = UIColor(red: 0xE2 / 255, green: 0xDF / 255, blue: 0xDA / 255, alpha: 1)
        clearColor = MTLClearColor(red: 0.886, green: 0.875, blue: 0.855, alpha: 1)
        isAccessibilityElement = true
        accessibilityLabel = "Interactive 3D Jelbie character Bob. Drag him to squish, stretch and twist."
        accessibilityHint = "Drag the Jelbie to stretch it, drag empty space to orbit, pinch to zoom, double tap to reset the view."
        accessibilityIdentifier = "melon-stage"

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delaysTouchesBegan = false
        pinch.delaysTouchesEnded = false
        pinch.delegate = self
        addGestureRecognizer(pinch)
        let dbl = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        dbl.numberOfTapsRequired = 2
        dbl.cancelsTouchesInView = false
        dbl.delaysTouchesBegan = false
        dbl.delaysTouchesEnded = false
        dbl.delegate = self
        addGestureRecognizer(dbl)
        let single = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))     // game: a tap on the floor cancels a pending Blob selection
        single.cancelsTouchesInView = false
        single.delaysTouchesBegan = false
        single.delaysTouchesEnded = false
        single.delegate = self
        single.require(toFail: dbl)
        addGestureRecognizer(single)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Start at the screen's native scale; adaptScale (RenderScaler) steps it down under GPU load.
        let s = window?.screen.scale ?? traitCollection.displayScale
        contentScaleFactor = s
        // Deliver touches immediately even inside a ScrollView.
        var v: UIView? = superview
        while let cur = v {
            if let sv = cur as? UIScrollView { sv.delaysContentTouches = false; break }
            v = cur.superview
        }
    }

    // MARK: Scroll ownership

    private func enclosingScrollView() -> UIScrollView? {
        var v: UIView? = superview
        while let cur = v {
            if let sv = cur as? UIScrollView { return sv }
            v = cur.superview
        }
        return nil
    }

    private func claim() {
        guard activeTouches == 0 else { return }
        if let sv = enclosingScrollView(), sv.isScrollEnabled {
            heldScrollView = sv
            sv.isScrollEnabled = false
        }
    }

    private func release() {
        if let sv = heldScrollView { sv.isScrollEnabled = true }
        heldScrollView = nil
    }

    // MARK: Touches (UITouch identity = pointer id)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller?.gfxWake()          // leave the 30 fps idle rest at once (the next draw may be 33 ms away)
        claim()
        activeTouches += touches.count
        for t in touches {
            controller?.pointerDown(id: ObjectIdentifier(t), point: t.location(in: self), size: bounds.size, time: sane(t.timestamp))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            controller?.pointerMove(id: ObjectIdentifier(t), point: t.location(in: self), size: bounds.size)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }

    /// The touch's own timestamp (same uptime clock as CACurrentMediaTime) so delivery lag cannot eat the double-tap window; a stamp that is
    /// not on that clock (synthesized events) falls back to the delivery time.
    private func sane(_ ts: TimeInterval) -> Double? { abs(CACurrentMediaTime() - ts) < 1.0 ? ts : nil }

    private func finish(_ touches: Set<UITouch>) {
        for t in touches { controller?.pointerUp(id: ObjectIdentifier(t), time: sane(t.timestamp)) }
        activeTouches = max(0, activeTouches - touches.count)
        if activeTouches == 0 { release() }
    }

    // MARK: Gestures

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        guard g.state == .changed, g.scale > 0 else { return }
        controller?.pinch(scale: Float(g.scale))
        g.scale = 1
    }

    @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        if controller?.game == true { controller?.gameDoubleTap(g.location(in: self)) }     // game: a double tap on a Blob selects it (no camera reset)
        else { controller?.resetCamera() }
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        if g.state == .ended, controller?.game == true { controller?.gameSingleTap(g.location(in: self)) }
    }

    func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool { true }

    deinit {
        // The enclosing scroll view must never stay locked if the stage disappears mid-touch.
        MainActor.assumeIsolated { release() }
    }
}

// MARK: - Controller

private enum DragMode { case none, grab, orbit, pet, pending, cheeks }

final class MelonController: NSObject, MTKViewDelegate {
    let model: MelonModel
    let device: MTLDevice?
    /// Game screen: living room backdrop, fixed camera, no orbit / zoom.
    let game: Bool

    private let simMesh: SimMesh
    private let renderMesh: RenderMesh
    /// Every Jelly in the room (1 in the studio; 1...3 in the game). `actors[0]` is Bob: the touch play, meals, Clean, voice and the close-up are his.
    private(set) var actors: [JellyActor] = []
    /// The per-Jelly bundle by id (same array as `actors`): brain, sim, skinner, profile / needs / grime / look / words, appearance, selected.
    var jellies: [JellyActor] { actors }
    private var sim: SoftBody { actors[0].sim }
    private var skinner: Skinner { actors[0].skinner }
    /// The Jelly in the tub when it is not Bob (nil otherwise).
    private var washer: JellyActor? {
        let b = model.care.bath
        return game && b.active && b.targetID > 0 ? actors.first { $0.id == b.targetID } : nil
    }
    /// The Jelly being touched in the close-up (Bob in the studio, in roaming and in the bath; the focused one otherwise): his sim, skinner, brain.
    /// `care.focusGroup.touchID` is the one source, so the hearts, the pet credit and the camera clamps agree with the stage.
    private var touchID: Int {
        get {
            guard game else { return 0 }
            if washer != nil { return washer!.id }                                  // the clean-up of another Jelly: the finger scrubs HIM
            return min(model.care.focusGroup.touchID, actors.count - 1)
        }
        set { if game { model.care.focusGroup.touchID = newValue } }
    }
    private var tSim: SoftBody { actors[touchID].sim }
    private var tSkinner: Skinner { actors[touchID].skinner }
    private var tBrain: BlobBrain? { actors[touchID].brain }
    /// A finger has him (grab, throw flight, getting back up): his brain stands aside. Only the touched Jelly.
    private func touchHolds(_ id: Int) -> Bool {
        id == touchID && (mode == .grab || actors[id].sim.grabbing || throwHold > 0 || model.touch.holdsBrain)
    }
    private var renderer: MelonRenderer?
    private var rig = CameraRig()
    private weak var stageView: MelonStageView?

    // frame state
    private var lastTime: CFTimeInterval = 0
    private var acc: Float = 0
    private var simTime: Float = 0
    private var readoutT: Float = 0
    private var firstFrameDone = false
    /// The aspect the roaming polygon was built for (GameCamera.refreshRoam); rebuilt when it changes, and every sim's safety arena follows it.
    private var roamAspect: Float = 0
    private func syncRoam(aspect: Float) {
        guard actors.count > 1, abs(aspect - roamAspect) > 0.005 else { return }
        roamAspect = aspect
        guard GameCamera.refreshRoam(aspect: aspect) != nil else { return }
        for a in actors where a.sim.arenaRadius.isFinite && !(a.brain?.race.active ?? false) && !model.care.bath.fenceLifted {
            a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius
        }
    }
    private var lastNudge: Int
    private var lastReset: Int
    private var lastPaused = false
    private var lastCam = CameraState()
    private var drillFollow: SIMD3<Float>?
    private var haveCam = false
    private var aspectChecked = false                 // the drawable-vs-bounds aspect log, once
    private let massG: Float

    // drag state
    private var mode: DragMode = .none
    private var dragID: ObjectIdentifier?
    // Voice v1: double-tap then hold on empty space = listen while the finger stays (VoiceGesture.swift)
    private var voiceGesture = VoiceGesture()
    private var voiceTouch: ObjectIdentifier?
    private var emptyDown: (id: ObjectIdentifier, t: Double, p: CGPoint)?
    private var planeP = SIMD3<Float>(0, 0, 0)
    private var planeN = SIMD3<Float>(0, 0, -1)
    private var twist: Float = 0
    private var twist0: Float = 0
    private var second: (id: ObjectIdentifier, p: CGPoint)?
    private var last = CGPoint.zero

    // perf counters (all configurations; logged once per second)
    private var dbgFrames = 0
    private var dbgStart: CFTimeInterval = 0
    private var matCost = 0.0, matN = 0
    private var dbgCPU: Double = 0
    private var dbgWait: Double = 0
    private var dbgSim: Double = 0
    private var dbgSteps = 0
    private var dbgSkin: Double = 0
    private var dbgBrain: Double = 0, dbgStepOnly: Double = 0, dbgTouch: Double = 0, dbgHaptic: Double = 0
    // touch play (focus mode): the pet finger
    private var petPoint = CGPoint.zero
    private var restSurface: RestSurface?
    // the gesture decides the action (TouchGesture.swift): pet / tap / pick up / throw / cheeks pinch
    private var gesture = TouchGesture()
    private var pickArm = PickUpArm()          // double-tap-then-hold ON him = pick up
    private var gestureHit: SIMD3<Float>?
    private var cheekFingers: [(id: ObjectIdentifier, p: CGPoint)] = []
    private var tapUntil: CFTimeInterval = 0
    private var grabSamples: [(t: CFTimeInterval, q: SIMD3<Float>)] = []
    private var liftHeight: Float = 0
    private var throwHold: Float = 0
    private var touchSize = CGSize.zero

    #if DEBUG
    private var autoDrag = false
    private var autoT0: CFTimeInterval = 0
    private var autoStart = CGPoint.zero
    private var autoEnd = CGPoint.zero
    private var autoPhase = 0
    private var demo = false
    private var demoT0: CFTimeInterval = 0
    private var demoStep = 0
    private var demoStepT0: Double = 0
    private var demoFresh = false
    private var demoAnchor = CGPoint.zero
    private var demoUp = CGVector(dx: 0, dy: -1)    // screen-space px per world unit (camera up)
    private var demoRight = CGVector(dx: 1, dy: 0)  // screen-space px per world unit (camera right)
    #endif

    // Hopping (fixed-step time, so it honours pause and quarter speed)
    private var hopper = GaitDriver()
    private var wasHopping = false

    // BEGIN brain hook
    /// Capture aid: -BlobIdleMood happy|okay|grumpy pins the mood the idle behaviours read.
    private static let idleMoodOverride: BlobMood? = UserDefaults.standard.string(forKey: "BlobIdleMood").flatMap(BlobMood.init(rawValue:))
    /// Bob's autonomous brain (BlobBrain.swift). nil = the old hop-around. The game screen sets it (or flips `brain.enabled`);
    /// launching with `-BlobDemo wave|walk|idle|play|eat|drink|come|step|look` creates one with that scripted demo.
    var brain: BlobBrain? {
        get { actors[0].brain }
        set { actors[0].brain = newValue; if let b = newValue { wireRoster(b, id: 0); b.currentPose(sim) } }
    }

    /// The room's event bus (BlobBrain+React.swift): the brains post what they do, the others may react.
    lazy var eventBus: ReactionBus = {
        let bus = ReactionBus()
        bus.brains = { [weak self] in self?.actors.compactMap(\.brain) ?? [] }
        DecorField.shared.onTopple = { [weak bus] pos in bus?.post(BusEvent(kind: .towerToppled, source: -1, pos: pos, piece: .blocks)) }
        SoccerEvents.sink = { [weak bus] e in bus?.handleSoccer(e) }          // soccer: goals cheered, fumbles giggled at, a ball rolling past startles (BlobBrain+React.swift)
        return bus
    }()

    /// Centre distance the Jellies keep from each other in the room (a body is ~1.4 wide; they may touch a little, never sit inside each other).
    static let jellyGap: Float = 1.4
    /// Positions of every Jelly at the start of the fixed step (the others steer by last step's positions, so the order they tick in does not matter).
    private var peerSnapshot: [(pos: SIMD2<Float>, walking: Bool)] = []

    /// Wires one brain into the room: it steers around the other Jellies (a standing Jelly is an obstacle to everybody; between two walkers the
    /// lower id gives way) and walks by the room's floor rules.
    private func wireRoster(_ b: BlobBrain, id: Int) {
        b.feature = JellyRoster.feature(slot: id)
        guard actors.count > 1 else { return }
        b.steerID = id
        b.bus = eventBus
        b.peerGap = Self.jellyGap
        model.care.voice.ai.register(b, id: id)            // AI hub: his naps / socials for the diary, and "go to sleep" for him
        // Jellies interacting (BlobSocial.swift): the other brains, and what a social does outside the brain (a heart, a light haptic for the one the player has)
        b.socialOthers = { [weak self, weak b] in self?.actors.compactMap(\.brain).filter { $0 !== b } ?? [] }
        b.onSocial = { [weak self] e in
            guard let self, id < self.actors.count, self.actors[id].selected else { return }
            let now = CACurrentMediaTime()
            switch e {
            case .boop: self.model.touch.spawnHeart(now: now); if self.model.care.focus.isActive { self.model.touch.haptics.transient(now: now, intensity: 0.3, sharpness: 0.25) }
            case .makeUp: self.model.touch.spawnHeart(now: now)
            case .shove: if self.model.care.focus.isActive { self.model.touch.haptics.transient(now: now, intensity: 0.22, sharpness: 0.3) }
            default: break
            }
        }
        b.peers = { [weak self] in
            guard let self else { return [] }
            return self.peerSnapshot.enumerated().filter { $0.offset != id }.map { (id: $0.element.walking ? $0.offset : Int.max / 2, pos: $0.element.pos) }
        }
        let floorRules = b.resolve
        b.resolve = { [weak self] p, r in
            guard let self, !self.peerSnapshot.isEmpty else { return floorRules(p, r) }
            return floorRules(Self.keepApart(floorRules(p, r), id: id, peers: self.peerSnapshot, gap: self.model.care.groupGap), r)
        }
    }

    /// Voice -> the social brains: "stop fighting" ends squabbles on every brain; stop / praise / scold for Jellies other than Bob drive their brains.
    private func wireVoiceSocial() {
        guard actors.count > 1 else { return }
        let voice = model.care.voice
        voice.onStopFighting = { [weak self] _ in
            guard let self else { return }
            for b in self.actors.compactMap(\.brain) { b.stopFighting() }
        }
        voice.onRemote = { [weak self] r, ids in
            guard let self, case .social(let s) = r else { return }
            for id in ids where id > 0 && id < self.actors.count {
                guard let b = self.actors[id].brain else { continue }
                switch s {
                case .stop: b.stop(); b.interruptScript = true
                case .stopFighting: b.stopFighting()
                case .praise, .play:
                    self.model.touch.spawnHeart(now: CACurrentMediaTime())
                    b.commandedNameHop = true
                case .scold: b.commandedIdle = .slump
                case .goodnight: if !self.model.care.raceBusy { b.commandedGoodnight = true }
                }
            }
        }
    }

    /// The hard rule under the steering: a root position is pushed out of the circle (the gap) around every other Jelly, so two bodies never
    /// sit inside each other even when the planner finds no way around (the soft bodies themselves do not collide).
    static func keepApart(_ p: SIMD3<Float>, id: Int, peers: [(pos: SIMD2<Float>, walking: Bool)], gap: Float? = nil) -> SIMD3<Float> {
        var q = p
        let g = gap ?? (GameCamera.focusSpots.count > 1 ? GameCamera.focusRowGap : jellyGap)        // the cosy group close-up stands closer; diners round one drink closer still
        for (j, o) in peers.enumerated() where j != id {
            let d = SIMD2(q.x, q.z) - o.pos, L = simd_length(d)
            if L < g {
                let u = L > 1e-4 ? d / L : SIMD2<Float>(id < j ? -1 : 1, 0)
                q.x = o.pos.x + u.x * g; q.z = o.pos.y + u.y * g
            }
        }
        return q
    }

    /// Seconds before a Jelly may be asked to step aside again.
    static let stepAsideCooldown: Float = 2.5

    /// Two Jellies that stand closer than the gap (one walked up and stopped, or an idle move carried him over): the free one with the higher id
    /// walks to a spot a little over the gap away. Never a Jelly that is walking, commanded, blocked by a meal / close-up / bath, or busy with a move.
    /// Call a few times a second; `cooldown` holds one timer per Jelly.
    static func makeRoom(snapshot: [(pos: SIMD2<Float>, walking: Bool)], brains: [BlobBrain?], cooldown: inout [Float], dt: Float) {
        for i in cooldown.indices { cooldown[i] = max(0, cooldown[i] - dt) }
        // a Jelly held still only by another Jelly's close-up (`focusPaused`) is free to step aside too: frozen in the called one's path he blocked it (2026-10-21)
        let freeBrain: (Int) -> Bool = { i in
            guard let b = brains[i], b.enabled, b.autonomy || b.focusPaused, !b.commanded, !b.held || (b.focusPaused && !b.reserved), b.pending == nil, !b.isSocial, b.idleState.kind == nil, !b.race.active else { return false }
            switch b.script { case .none, .look, .stepInPlace: break; default: return false }
            return b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace
        }
        func free(_ i: Int) -> Bool { cooldown[i] <= 0 && freeBrain(i) }
        clearWay(snapshot: snapshot, brains: brains, cooldown: &cooldown, free: freeBrain)
        for i in 0..<snapshot.count {
            for j in (i + 1)..<snapshot.count where simd_distance(snapshot[i].pos, snapshot[j].pos) < jellyGap && !snapshot[i].walking && !snapshot[j].walking {
                let mover = free(j) ? j : (free(i) ? i : -1)
                guard mover >= 0, let b = brains[mover] else { continue }
                let other = mover == i ? j : i
                let me = snapshot[mover].pos, from = snapshot[other].pos
                let away = simd_normalize(me - from + SIMD2<Float>(1e-4, 0))
                var best: (cost: Float, p: SIMD2<Float>)?
                for k in 0..<12 {
                    let a = Float(k) * (.pi / 6)
                    let dir = SIMD2<Float>(sinf(a), cosf(a))
                    for r: Float in [jellyGap * 1.15, jellyGap * 1.45] {
                        let c = from + dir * r
                        let rc = b.resolve(SIMD3(c.x, 0, c.y), b.footprint)
                        let q = SIMD2(rc.x, rc.z)
                        guard simd_distance(q, c) < 0.05, snapshot.enumerated().allSatisfy({ $0.offset == mover || simd_distance($0.element.pos, q) >= jellyGap * 1.05 }) else { continue }
                        let cost = simd_distance(me, q) - 0.4 * simd_dot(dir, away)
                        if best == nil || cost < best!.cost { best = (cost, q) }
                    }
                }
                if let spot = best?.p { b.requestNow(.goTo(spot)); cooldown[mover] = stepAsideCooldown }
            }
        }
    }
    /// A Jelly on a REQUESTED walk (come here, a meal, a step-aside: `job` set) whose straight way to his next waypoint runs through a standing Jelly: that
    /// Jelly steps out of the lane, sideways, to a spot over the gap from the lane and from everybody else (and off the walker's goal). Standing Jellies
    /// used to be waited for (6 s) and then walked into, and the paused ones of a close-up never moved (2026-10-21: "they are stuck blocking him").
    static func clearWay(snapshot: [(pos: SIMD2<Float>, walking: Bool)], brains: [BlobBrain?], cooldown: inout [Float], free: (Int) -> Bool) {
        for w in 0..<snapshot.count {
            guard let wb = brains[w], wb.enabled, wb.job != nil, case .walk(let scriptGoal, _) = wb.script else { continue }
            // the goal he was ASKED for: the walk's own target is the spot after the floor rules, and keepApart drags it over the gap away from a Jelly who stands
            // on the spot, so the walk ends short of it (the call spot with someone on it: the close-up never started, 2026-10-21). The stander near the real spot
            // is in the way too.
            let goal: SIMD2<Float>
            switch wb.job { case .come(let p), .goTo(let p): goal = p; default: goal = scriptGoal }
            let a = snapshot[w].pos, target = wb.route.first ?? scriptGoal
            let legTo = simd_distance(target, goal) > 0.3 ? target : goal
            let leg = legTo - a, L = simd_length(leg)
            guard L > 0.3 else { continue }
            let dir = leg / L, perp = SIMD2<Float>(-dir.y, dir.x)
            let clear = jellyGap * 1.05
            // out of the walker's corridor: over the gap beside the lane, or over the gap past its end (and never behind the walker, across his body)
            func outOfTheWay(_ q: SIMD2<Float>) -> Bool {
                let tq = simd_dot(q - a, dir), sq = abs(simd_dot(q - a, perp))
                return (sq >= clear || tq >= L + clear) && tq > -clear * 0.5 && simd_distance(q, goal) >= clear && simd_distance(q, scriptGoal) >= clear
            }
            for j in 0..<snapshot.count where j != w && !snapshot[j].walking {
                let p = snapshot[j].pos
                let t = simd_dot(p - a, dir)
                let side = simd_dot(p - a, perp)
                let inLane = t > -0.2 && t < L + jellyGap * 0.5 && abs(side) < jellyGap
                guard inLane || simd_distance(p, goal) < jellyGap, cooldown[j] <= 0, free(j), let b = brains[j] else { continue }           // beside or behind the walker: not in the way
                let foot = inLane ? a + dir * max(0, min(L, t)) : goal
                var best: (cost: Float, p: SIMD2<Float>)?
                for k in 0..<12 {
                    let ang = Float(k) * (.pi / 6)
                    let d = perp * cosf(ang) * (side >= 0 ? 1 : -1) + dir * sinf(ang)          // k = 0: straight out on the side he already leans to
                    for r: Float in [1.15, 1.45, 1.8] {
                        let c = foot + d * (jellyGap * r)
                        let rc = b.resolve(SIMD3(c.x, 0, c.y), b.footprint)
                        let q = SIMD2(rc.x, rc.z)
                        guard simd_distance(q, c) < 0.05, outOfTheWay(q),
                              snapshot.enumerated().allSatisfy({ $0.offset == j || $0.offset == w || simd_distance($0.element.pos, q) >= clear }) else { continue }
                        let crosses = (simd_dot(q - a, perp) >= 0) != (side >= 0)
                        let cost = simd_distance(p, q) + (crosses ? 0.6 : 0)
                        if best == nil || cost < best!.cost { best = (cost, q) }
                    }
                }
                if let spot = best?.p { b.requestNow(.goTo(spot)); cooldown[j] = stepAsideCooldown }
            }
        }
    }
    private var asideCooldown = [Float](repeating: 0, count: JellyRoster.maxCount)
    private var asideClock: Float = 0

    /// Reused each fixed step (no per-step array).
    private var stepSims: [SoftBody] = []
    private var skinJobs: [JellyParallel.SkinJob] = []
    private var lastSlept = 0, lastWakes = 0

    /// Things that keep a Jelly awake besides his own brain and body: a finger on the screen, a hold, and the close-ups (focus, meal, Clean, selection).
    private func sleepForced(_ a: JellyActor) -> Bool {
        if (stageView?.activeTouches ?? 0) > 0 || touchHolds(a.id) || mode != .none { return true }
        if game {
            let c = model.care
            if c.focus.isActive || c.trayOut || c.bath.active || c.tripActive || c.select.isSelecting || c.select.confirmed == a.id { return true }
        }
        return false
    }

    private func publishPeers() {
        guard actors.count > 1 else { return }
        if peerSnapshot.count != actors.count { peerSnapshot = actors.map { (pos: $0.floor, walking: $0.isWalking) }; return }
        for i in 0..<actors.count { peerSnapshot[i] = (pos: actors[i].floor, walking: actors[i].isWalking) }          // in place: no array per step
    }

    /// Called once before each fixed sim step.
    private func hopTick(reduce: Bool) {
        publishPeers()
        let racing = game && model.care.tripActive
        if actors.count > 1, !racing {
            asideClock += sim.stepDt
            if asideClock >= 0.25 { Self.makeRoom(snapshot: peerSnapshot, brains: actors.map(\.brain), cooldown: &asideCooldown, dt: asideClock); asideClock = 0 }
        }
        bobTick(reduce: reduce)
        audioSituation()
        if game { Ears.shared.tick(actors: actors, care: model.care, dt: sim.stepDt) }      // sound reactions (Audio/EarsListener.swift)
        if actors.count > 1 {
            for a in actors.dropFirst() { otherTick(a, reduce: reduce) }
            if game { model.care.tickOthers(actors, dt: sim.stepDt) }
        }
        if game { model.care.tickRace(actors, dt: sim.stepDt) }          // Jelly Circuit: the trip to the track and the race (every Jelly is ticked by now)
        if game { model.care.tickShow(actors, dt: sim.stepDt) }          // Jelly Show: the trip to the stage, the rounds, the Studio's dance drill
        if game { model.care.tickMasks(actors, dt: sim.stepDt); model.care.tickWear(actors, dt: sim.stepDt) }         // sleep eye masks: on when he settles on his back, poof away when he wakes
        if game { model.care.tickDecor(dt: sim.stepDt) }                 // decor: the sat-in beanbag, the booped plant, the rolling ball
    }

    /// Tucked in: everybody is asleep and at least one was put to bed by voice ("goodnight"): the lamp dims and a quilt lies over the pile.
    private var tuckAmount: Float = 0
    private func updateTuck(_ renderer: MelonRenderer, dt: Float) {
        let brains = actors.compactMap(\.brain)
        let down = !brains.isEmpty && brains.allSatisfy { $0.isNapping } && brains.contains { $0.sleep.tucked }
        tuckAmount += max(-dt / 1.5, min(dt / 2.5, (down ? 1 : 0) - tuckAmount))
        if !down, tuckAmount < 0.01 { tuckAmount = 0 }
        renderer.tuckAmount = tuckAmount
        if down, let q = Self.quiltSpot(for: brains.map(\.position)) { renderer.quiltSpot = q }
    }
    /// The quilt over the sleepers' feet: their bounding box, a little bigger.
    static func quiltSpot(for ps: [SIMD2<Float>]) -> (centre: SIMD2<Float>, half: SIMD2<Float>)? {
        guard !ps.isEmpty else { return nil }
        var lo = ps[0], hi = ps[0]
        for p in ps { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        return ((lo + hi) * 0.5 + SIMD2(0, 0.62), SIMD2((hi.x - lo.x) * 0.5 + 1.0, (hi.y - lo.y) * 0.5 + 0.34))
    }

    /// The player is looking at the room: the app is in front and no close-up / menu is open (the room life then keeps something happening).
    private var roomWatched: Bool {
        guard game else { return false }
        let c = model.care
        return !model.paused && !c.focus.isActive && !c.trayOut && !c.bath.active && !c.select.isSelecting
    }

    /// Feeds the audio hub (music mood, snores, mood chirps) from the Jellies, about 10 times a second. A no-op while muted (tests).
    private var audioClock = 0
    private func audioSituation() {
        guard game, !AudioHub.shared.muted else { return }
        audioClock += 1
        guard audioClock % 6 == 0 else { return }
        let brains = actors.map(\.brain)
        var playing = false
        for b in brains {
            guard let b else { continue }
            switch b.idleState.kind { case .zoomies?, .jacks?, .slide?, .scoot?: playing = true; default: break }
            if b.activity == .playing { playing = true }
            if let s = b.social, ![.squabble, .look, .nuzzle, .sitTogether, .sneak, .bagSit, .cuddle].contains(s.kind) { playing = true }          // (chase / tag, dances, bumps ... start the play music)
        }
        if model.touch.thrown { playing = true }          // a toy thrown / bounced in the close-up
        let napping = brains.map { $0?.isNapping ?? false }
        let moods = actors.indices.map { model.care.jelly($0)?.needs.mood ?? .okay }
        AudioHub.shared.raceCrowd(model.care.race.active && model.care.race.trackVisible && model.care.race.kind == .race)
        let raceScene = model.care.race.musicScene
        AudioHub.shared.situation(napping: napping, playing: playing, xs: brains.map { $0?.px ?? 0 }, moods: moods, scene: raceScene != .none ? raceScene : model.care.show.musicScene)
    }

    /// The other Jellies' brain, jelly follow-through and mouth (their needs, mood and greeting are GameCare.tickOthers).
    private func otherTick(_ a: JellyActor, reduce: Bool) {
        guard let brain = a.brain, brain.enabled else { return }
        if !brain.hasRenderMesh { brain.attach(renderMesh: renderMesh) }
        brain.amplitude = reduce ? 0.55 : 1
        brain.idleNight = DayClock.shared.nightFactor; brain.idleMorning = DayClock.shared.morningFactor; brain.idleDeepNight = DayClock.shared.deepNightFactor
        let roomLife = game && !model.care.raceBusy && !brain.race.active          // room life is OFF for every Jelly while a race trip is on (racer or rival body)
        brain.sleepEnabled = roomLife; brain.anticsEnabled = roomLife; brain.watching = roomLife && roomWatched; brain.musicPlaying = AudioHub.shared.musicAudible
        if let o = Self.idleMoodOverride { brain.idleMood = o }
        brain.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: touchHolds(a.id))
        a.skinner.jelly.tick(brain: brain, sim: a.sim, dt: a.sim.stepDt)
        renderer?.setMouth(brain.mouthOpen, body: a.id)
        renderer?.setBlush(brain.blushNow, body: a.id)
    }

    private func bobTick(reduce: Bool) {
        if game && brain == nil { brain = BlobBrain.forGame() }
        if let brain, brain.enabled {
            wasHopping = false
            if !brain.hasRenderMesh { brain.attach(renderMesh: renderMesh) }
            brain.amplitude = reduce ? 0.55 : 1
            brain.idleNight = DayClock.shared.nightFactor; brain.idleMorning = DayClock.shared.morningFactor; brain.idleDeepNight = DayClock.shared.deepNightFactor
            let roomLife = game && !model.care.raceBusy && !brain.race.active          // room life is OFF for every Jelly while a race trip is on (racer or rival body)
            brain.sleepEnabled = roomLife; brain.anticsEnabled = roomLife; brain.watching = roomLife && roomWatched; brain.musicPlaying = AudioHub.shared.musicAudible
            if game {      // room life (BlobBrain+Idle.swift): mood picks the idle behaviours; focus mode and a meal on the tray hold them back
                brain.idleMood = Self.idleMoodOverride ?? model.care.mood
                brain.idleBlocked = (model.care.focus.isActive || model.care.trayOut || model.care.bath.active) && !brain.commanded
                brain.focusPaused = model.care.focusGroup.pauses(0, phase: model.care.focus.phase) && !model.care.trayOut && !model.care.bath.active && !brain.commanded
            }
            if brain.followsStudioCamera { brain.cameraPosXZ = SIMD2(rig.target.x, rig.target.z) + SIMD2(sinf(rig.azimuth), cosf(rig.azimuth)) * 10 }
            let b0 = CACurrentMediaTime()
            throwHold = max(0, throwHold - sim.stepDt)
            brain.tick(sim: sim, skinner: skinner, dt: sim.stepDt, touched: touchHolds(0))
            dbgBrain += CACurrentMediaTime() - b0
            skinner.jelly.tick(brain: brain, sim: sim, dt: sim.stepDt)   // jelly follow-through (JellyJiggle.swift)
            renderer?.mouthOpen = brain.mouthOpen
            renderer?.setBlush(brain.blushNow, body: 0)
            if game { model.care.tick(brain: brain, renderer: renderer, dt: sim.stepDt, sim: sim) }
            return
        }
        renderer?.mouthOpen = 0
        if !model.hopping { wasHopping = false; hopper.cancel(sim); return }
        if !wasHopping { wasHopping = true; hopper.wander = true; hopper.start(sim) }
        hopper.tick(sim, held: mode == .grab || sim.grabbing, reduce: reduce)
    }
    // END brain hook

    #if DEBUG
    /// Launch arguments for viewing individuals: -MelonBreed berry|mint|honey, -MelonMarking 0...6, -MelonFeatureScale 0.8...1.25,
    /// -MelonFeatureCount n, -MelonFeatureSeed n, -MelonSize 0.95...1.05, -MelonShade -0.15...0.15
    static func debugAppearance(_ base: BlobAppearance) -> BlobAppearance {
        let d = UserDefaults.standard
        var a = base
        if let b = d.string(forKey: "MelonBreed") {
            switch b { case "mint": a = .mint; case "honey": a = .honey; case "berry": a = .berry; default: break }
        }
        if d.object(forKey: "MelonMarking") != nil, let m = BlobAppearance.Marking(rawValue: d.integer(forKey: "MelonMarking")) { a.marking = m }
        if d.object(forKey: "MelonFeatureScale") != nil { a.featureScale = Float(d.double(forKey: "MelonFeatureScale")) }
        if d.object(forKey: "MelonFeatureCount") != nil { a.featureCount = d.integer(forKey: "MelonFeatureCount") }
        if d.object(forKey: "MelonFeatureSeed") != nil { a.featureSeed = UInt32(truncatingIfNeeded: d.integer(forKey: "MelonFeatureSeed")) }
        if d.object(forKey: "MelonSize") != nil { a.sizeScale = Float(d.double(forKey: "MelonSize")) }
        if d.object(forKey: "MelonShade") != nil { a.shade = Float(d.double(forKey: "MelonShade")) }
        return a
    }
    #endif

    // Not isolated: Swift 6.2's implicit isolated deinit (swift_task_deinitOnExecutor) aborts on the iOS 26.2 runtime; see MelonModel.
    nonisolated deinit {}

    init(model: MelonModel) {
        self.model = model
        self.game = model.gameMode
        #if DEBUG
        model.appearance = MelonController.debugAppearance(model.appearance)
        #endif
        let ap = model.appearance
        let sm = buildSimMesh(appearance: ap)
        let rm = buildRenderMesh(appearance: ap)
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let count = model.gameMode ? min(max(model.care.jellyCount, 1), JellyRoster.maxCount) : 1
        if model.gameMode, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil { GameCamera.configureRoom(count: count) }          // 2-3 Jellies: the wider roaming camera and floor (one Jelly: the exact old pose; skipped in the test host, whose suites assume the base pose)
        let spots = JellyRoster.spawnSpots(count: count)
        simMesh = sm
        renderMesh = rm
        WearBody.install(rm)
        actors = (0..<count).map {
            JellyActor(id: $0, name: model.care.jelly($0)?.name ?? JellyRoster.name(slot: $0), simMesh: sm, renderMesh: rm, embedding: emb, appearance: ap,
                       firmness: Float(model.firmness), damping: Float(model.damping), spawn: spots[$0])
        }
        for a in actors { a.profile = model.care.jelly(a.id); a.care = model.care; a.appearance = JellyRoster.palette(a.profile?.character ?? JellyRoster.character(a.id)) }
        let body = actors[0].sim
        massG = body.totalRestVolume * powf(bobScaleCm, 3) * bobDensity
        lastNudge = model.nudgeTick
        lastReset = model.resetTick
        device = MTLCreateSystemDefaultDevice()
        super.init()
        actors[0].brain = BlobBrain.fromLaunchArguments()
        if game {
            model.care.voice.wake = { [weak self] in self?.gfxWake() }          // a mic-button press (not a Metal-view touch) leaves the idle rest too
            for a in actors {
                a.sim.arenaCenter = GameCamera.arenaCenter
                a.sim.arenaRadius = GameCamera.arenaRadius
            }
            // the other Jellies: the game brain (floor rules, roaming, attention pitch) with the tray as an obstacle, steering around everybody
            for a in actors.dropFirst() {
                let b = BlobBrain.forGame()
                b.demo = nil; b.runMoveDemo = nil
                b.autonomy = UserDefaults.standard.integer(forKey: "BlobNoWander") == 0
                model.care.wireWorld(b, isBob: false)
                a.brain = b
                wireRoster(b, id: a.id)
                b.currentPose(a.sim)
            }
            wireVoiceSocial()
            model.care.voice.onGoodnight = { [weak self] ids in
                guard let self, !self.model.care.raceBusy else { return }
                // the first in the list goes to bed first (the others gather beside him)
                for id in ids.sorted() where id < self.actors.count { self.actors[id].brain?.commandedGoodnight = true }
            }
        }
        for a in actors { a.reset(drop: model.reduceMotion ? 0 : 0.35, shift: count > 1) }
        for a in actors { a.brain?.feature = a.profile?.feature ?? JellyRoster.feature(slot: a.id) }
        model.particles = body.n
        model.tets = body.nT
        model.seeds = rm.seedCount
        model.mass = Double(massG)
        #if DEBUG
        autoDrag = UserDefaults.standard.integer(forKey: "MelonAutoDrag") != 0
        demo = UserDefaults.standard.integer(forKey: "MelonDemo") != 0
        if UserDefaults.standard.integer(forKey: "MelonHop") != 0 { model.hopping = true }
        #endif
    }

    func attach(to view: MelonStageView) {
        stageView = view
        view.controller = self
        guard let device else { fail("This device has no Metal GPU, so there is nothing to render with."); return }
        guard let r = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: renderMesh,
                                    simEdges: sim.edges, particleCount: sim.n, game: game, bodyCount: actors.count) else {
            fail("The Metal renderer could not be created (shader library or pipeline failure).")
            return
        }
        renderer = r
        if model.gameMode {
            model.care.fittingProvider = { [weak self] look, id in self?.fittingSnapshot(look: look, jelly: id) }
            model.care.portraitProvider = { [weak self] id in self?.fittingSnapshot(look: nil, jelly: id) }
        }
        for a in actors { if let p = a.appearance { r.setPalette(p, body: a.id) } }          // slot 0 too: a non-Bob character there wears his own colours
        view.delegate = self
    }

    private func fail(_ reason: String) {
        let m = model
        Task { @MainActor in m.metalUnavailableReason = reason }
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    // Adaptive render resolution + frame-rate request (RenderScaler.swift). Only the drawable size changes: never the sim.
    // Off in the simulator and under XCTest (render goldens are full scale) unless launched with -AdaptiveScale 1; -AdaptiveScale 0 forces it off.
    private static let adaptiveEnabled: Bool = {
        let d = UserDefaults.standard
        if d.object(forKey: "AdaptiveScale") != nil { return d.bool(forKey: "AdaptiveScale") }
        #if targetEnvironment(simulator)
        return false
        #else
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        #endif
    }()
    private var scaler: RenderScaler?
    private var rateGov: RateGovernor?
    private var lastAppliedFPS = 60
    private var scaleChanges = 0

    // MetalFX (GfxUpscaler.swift): the drawable stays native, the 3D scene renders at `fxScale` x and is upscaled. Off unless -MetalFX 1.
    private static let metalFXFlag = GfxFlags.metalFX && GfxUpscaler.compiledIn
    private var fxScale = 0.0                       // render scale in native multiples (0 = not set yet)
    // Idle rest (IdleRestGovernor): 30 fps once everything has been still for 2 s.
    private static let idleRestFlag = GfxFlags.idleRest
    private var idleRest = IdleRestGovernor()
    private var restFrames = 0, activeFrames = 0, restWakes = 0, lastEnergy: Float = 0
    private static let roomCacheFlag = GfxFlags.roomCache
    private static let gfxOptFlags = GfxFlags.gfxOpt

    private func adaptScale(_ stage: MelonStageView, dt: Double) {
        guard Self.adaptiveEnabled else { return }
        if scaler == nil {
            let native = Double(stage.window?.screen.scale ?? stage.contentScaleFactor)
            // with MetalFX the ladder starts at the MetalFX render scale (never above native); without it, at native
            scaler = RenderScaler(native: Self.metalFXFlag ? min(GfxFlags.metalFXScale, native) : native)
            rateGov = RateGovernor(maxFPS: stage.window?.screen.maximumFramesPerSecond ?? 60)
        }
        let gpu = renderer?.lastGPUMs
        let thermal = ProcessInfo.processInfo.thermalState
        if let s = scaler?.update(dt: dt, gpuMs: gpu, thermal: thermal) {
            if Self.metalFXFlag { fxScale = s } else { stage.contentScaleFactor = CGFloat(s) }
            scaleChanges += 1
            NSLog("%@", String(format: "[melon] scale: -> %.2fx (gpu %.1f ms, budget %.1f ms, thermal %d%@)", s, gpu ?? 0, scaler?.budgetMs ?? 0, thermal.rawValue, Self.metalFXFlag ? ", MetalFX" : ""))
        }
        let atNative = (scaler?.level ?? 0) == 0
        if let f = rateGov?.update(dt: dt, gpuMs: gpu, thermal: thermal, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, atNative: atNative), f != lastAppliedFPS {
            lastAppliedFPS = f
            applyFrameRate(stage)
            NSLog("[melon] frame rate request -> %d Hz", f)
        }
    }

    /// One-second gfx report for the `[melon] env:` line: room cache hit rate / misses / room pixels shaded, MetalFX state, idle rest share.
    private func gfxSummary(_ r: MelonRenderer, frames: Double, rw: Int, rh: Int) -> String {
        let shaded = r.roomPixelsBaseline > 0 ? r.roomPixelsShaded / r.roomPixelsBaseline * 100 : 100
        let tot = Double(max(restFrames + activeFrames, 1))
        let out = String(format: "room cache %@ %@, room px shaded %.0f%% of old path, render %dx%d, MetalFX %@, memoryless %@, order %@, fastMatte %d, idle rest %@ (%.0f%% of frames at 30 fps, %d wakes, KE %.5f)",
                         Self.roomCacheFlag ? "on" : "off", r.roomCacheSummary, shaded, rw, rh, r.metalFXState,
                         r.targetsMemoryless ? "on" : "off", r.gfxOpt.frontToBack ? "near-first" : "slot", r.gfxOpt.fastMatteTier,
                         Self.idleRestFlag ? (idleRest.resting ? "RESTING" : "awake") : "off", Double(restFrames) / tot * 100, restWakes, Double(lastEnergy))
        r.resetRoomCacheCounters(); restFrames = 0; activeFrames = 0
        return out
    }

    /// preferredFramesPerSecond = the governor's 60 / 120, or 30 while resting.
    private func applyFrameRate(_ stage: MelonStageView) {
        let want = idleRest.resting ? 30 : lastAppliedFPS
        if stage.preferredFramesPerSecond != want { stage.preferredFramesPerSecond = want }
    }

    /// Called from touchesBegan (and any other instant wake source): back to full rate without waiting for the next draw.
    func gfxWake() {
        if idleRest.wake() {
            restWakes += 1
            if let stage = stageView { applyFrameRate(stage) }
            NSLog("[melon] idle rest: woken by touch")
        }
    }

    /// Feeds the idle-rest governor: Bob counts as still with no touch, script, walk, request, focus blend, tray or selection, and low kinetic energy.
    private func updateIdleRest(_ stage: MelonStageView, dt: Double) {
        guard Self.idleRestFlag, Self.adaptiveEnabled || UserDefaults.standard.bool(forKey: "IdleRest") else { return }
        var active = stage.activeTouches > 0 || mode != .none || sim.grabbing || throwHold > 0 || model.touch.holdsBrain
        for a in actors {            // every Jelly has to be still
            if let brain = a.brain, brain.enabled {
                active = active || brain.activity != .idle || brain.commanded || brain.pending != nil
                if case .none = brain.script {} else { active = true }
            }
        }
        if game {
            let b = model.care.focus.blend
            active = active || (b > 0.001 && b < 0.999) || model.care.trayOut || model.care.select.isSelecting || model.care.tripActive
        }
        var e: Float? = nil
        if sim.totalMass > 0 { var m: Float = 0; for a in actors { m = max(m, a.sim.kineticEnergy() / a.sim.totalMass) }; e = m }
        lastEnergy = e ?? -1
        let flipped = idleRest.update(dt: dt, active: active, energy: e)
        if idleRest.resting { restFrames += 1 } else { activeFrames += 1 }
        if flipped { applyFrameRate(stage); NSLog("[melon] idle rest: %@ (KE %.5f)", idleRest.resting ? "30 fps" : "back to full rate", Double(e ?? -1)) }
    }

    func draw(in view: MTKView) {
        guard let renderer, let stage = stageView, view.drawableSize.width >= 2, view.drawableSize.height >= 2,
              let drawable = view.currentDrawable else { return }
        let cpu0 = CACurrentMediaTime()
        let now = cpu0
        let dt = lastTime == 0 ? Float(1.0 / 60) : min(Float(now - lastTime), 0.1)
        lastTime = now
        adaptScale(stage, dt: Double(dt))

        // Waits only when the GPU is BodySlot.ring frames behind; logged apart so "cpu" is CPU work (sim + skin + encode), not the GPU wait.
        let w0 = CACurrentMediaTime()
        renderer.beginFrame()
        dbgWait += CACurrentMediaTime() - w0
        let m = model
        let reduce = m.reduceMotion

        // model -> sim
        for a in actors { a.sim.firmness = Float(m.firmness); a.sim.damping = Float(m.damping) }
        let paused = m.paused
        if paused != lastPaused {
            lastPaused = paused
            if paused { cancelGrab() }
        }
        if m.resetTick != lastReset {
            lastReset = m.resetTick
            for a in actors { a.reset(drop: reduce ? 0 : 0.35, shift: actors.count > 1) }
            acc = 0
            mode = (mode == .grab) ? .none : mode
        }
        if m.nudgeTick != lastNudge {
            lastNudge = m.nudgeTick
            if !paused { for a in actors { a.sim.nudge(strength: reduce ? 0.45 : 1) } }
        }

        #if DEBUG
        if autoDrag { runAutoDrag(now: now, stage: stage) }
        if demo { runDemo(now: now, stage: stage) }
        #endif

        let tt0 = CACurrentMediaTime()
        touchDemo(now: now)
        touchTick(dt: dt, now: now)
        dbgTouch += CACurrentMediaTime() - tt0

        // fixed-step simulation
        let s0 = CACurrentMediaTime()
        if !paused {
            acc += dt * (m.slow ? 0.25 : 1)
            // At most 2 steps per frame; leftover time is dropped so one slow frame cannot snowball into more work.
            let maxSteps = 2
            var steps = 0
            while acc >= sim.stepDt && steps < maxSteps {
                hopTick(reduce: reduce)
                let st0 = CACurrentMediaTime()
                stepSims.removeAll(keepingCapacity: true)
                for a in actors where a.updateSleep(forceAwake: sleepForced(a)) { stepSims.append(a.sim) }
                JellyParallel.step(stepSims)                   // every awake body's XPBD step, one per core (settled Jellies sleep)
                dbgStepOnly += CACurrentMediaTime() - st0; acc -= sim.stepDt; steps += 1
            }
            if steps == maxSteps { acc = min(acc, sim.stepDt) }
            if game, steps > 0 { model.care.refreshHeld(actors: actors, renderer: renderer); model.care.refreshMasks(renderer: renderer); model.care.refreshShoes(actors, renderer: renderer, time: Float(CACurrentMediaTime())); model.care.refreshDecor(renderer: renderer, time: Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1000))) }
            simTime += dt * (m.slow ? 0.25 : 1) * (reduce ? 0.25 : 1)   // drives the lava colour drift
            dbgSteps += steps
        }
        dbgSim += CACurrentMediaTime() - s0

        updateIdleRest(stage, dt: Double(dt))
        let sk0 = CACurrentMediaTime()
        for a in actors { a.skinner.tickBlink(dt: dt) }
        skinJobs.removeAll(keepingCapacity: true)
        for a in actors { skinJobs.append(JellyParallel.SkinJob(skinner: a.skinner, sim: a.sim, dst: renderer.dynPointer(body: a.id))) }
        JellyParallel.skin(skinJobs, index: renderMesh.index)
        dbgSkin += CACurrentMediaTime() - sk0
        if game { model.care.refreshWear(actors, renderer: renderer, time: Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1000))) }          // after the skin: surface-bound pieces read this frame's skin
        for a in actors.dropFirst() {
            if let w = a.skinner.takeMatWrites() { renderer.writeMat(w.vertices, values: w.values, body: a.id) }
        }
        if let w = skinner.takeMatWrites() {
            let t0 = CACurrentMediaTime()
            renderer.writeMat(w.vertices, values: w.values)
            matCost += CACurrentMediaTime() - t0; matN += 1
        } else if matN > 0 {
            NSLog("%@", String(format: "[melon] wave arm mat writes: %.1f us per frame (%d frames)", matCost / Double(matN) * 1e6, matN))
            matCost = 0; matN = 0
        }
        let c = sim.centroid()
        if !game { rig.follow(centroid: c, dt: dt, grabbing: mode == .grab) }

        // camera + light
        let pts = stage.bounds.size
        let safe: CGRect
        if stage.traitCollection.horizontalSizeClass == .regular {
            safe = CGRect(x: pts.width * 0.05, y: pts.height * 0.12, width: pts.width * 0.62, height: pts.height * 0.70)
        } else {
            safe = CameraRig.fullSafeRect(pts)
        }
        // the practice drill follows its Jelly closer (smoothed; snaps when the body goes back to the start line under the fade)
        var drillAt: SIMD3<Float>?
        if game, model.care.race.isDrill, model.care.race.cameraBlend > 0 {
            if let f = drillFollow, simd_distance(f, c) < 3 { drillFollow = f + (c - f) * min(1, dt * 8) } else { drillFollow = c }
            drillAt = drillFollow
        } else { drillFollow = nil }
        let raceFollow = game ? model.care.raceFollow(actors, dt: dt) : nil          // a curved course: the follow camera (Race/RaceCamera.swift); nil on the Puddle
        // The projection's aspect is the DRAWABLE's (the pixels actually rendered), never the view's point size: a drawable that lags the bounds
        // (a rotation, a scale change, a new SDK laying the view out differently) would otherwise stretch the Jellies. The two agree whenever
        // the drawable is bounds x scale; the first mismatch is logged once.
        let drawAspect = Float(view.drawableSize.width / max(view.drawableSize.height, 1))
        if !aspectChecked, pts.height > 1 {
            aspectChecked = true
            let ptAspect = Float(pts.width / pts.height)
            NSLog("[melon] camera: drawable %.0fx%.0f (aspect %.4f), bounds %.1fx%.1f pt (aspect %.4f) @ %.2fx, safe %@ | eye (%.2f, %.2f, %.2f) target (%.2f, %.2f, %.2f) wide x%.2f lift %.1f, %d Jellies",
                  view.drawableSize.width, view.drawableSize.height, drawAspect, pts.width, pts.height, ptAspect, Double(stage.contentScaleFactor), NSCoder.string(for: stage.safeAreaInsets),
                  GameCamera.eye.x, GameCamera.eye.y, GameCamera.eye.z, GameCamera.target.x, GameCamera.target.y, GameCamera.target.z, GameCamera.roomWideScale, GameCamera.roomWideLift, actors.count)
            if abs(drawAspect / ptAspect - 1) > 0.01 { NSLog("[melon] camera: WARNING drawable and bounds aspects differ by %.1f%%", Double(abs(drawAspect / ptAspect - 1) * 100)) }
        }
        let cam = game ? GameCamera.camera(aspect: drawAspect, focus: model.care.focus.blend, bath: model.care.bath.cameraBlend, race: model.care.race.cameraBlend, drillAt: drillAt, raceFollow: raceFollow, show: model.care.show.cameraBlend, showFrame: model.care.showFrame) : rig.camera(viewSize: pts, safeRect: safe)
        lastCam = cam
        haveCam = true
        if game { syncRoam(aspect: drawAspect) }          // the roaming floor follows the screen (a rotation changes how much floor is on screen)
        // Outlines (a projection of every skinned vertex + a hull, per Jelly) are only needed while a highlight is up; a double tap / touch-down
        // refreshes them on demand (`refreshOutlines`), so a roster of three no longer pays for them every frame.
        if game, model.care.select.isSelecting {
            // every Jelly's outline comes from his own skinned vertices
            model.care.select.publish(viewProj: cam.viewProj, size: pts, points: { screenPoints(of: $0, pts, cam.viewProj) })
        }
        let camIn = game && model.care.focus.blend > 0.25
        var light = game ? GameCamera.light(centroids: actors.filter { !(camIn && model.care.focusHides($0.id)) }.map { $0.sim.centroid() }) : rig.light(centroid: c)
        if game { light.intensity *= DayLight.at(hour: DayClock.shared.displayHour).jellyMul }          // night: the Jellies' key light is dialled down (never dark)
        if game { updateTuck(renderer, dt: 1.0 / 60) }

        // MetalFX: the drawable stays native; the scene renders smaller and is upscaled. Otherwise render size == drawable size.
        var rw = Int(view.drawableSize.width), rh = Int(view.drawableSize.height)
        renderer.metalFXEnabled = Self.metalFXFlag
        if Self.metalFXFlag {
            let native = Double(stage.window?.screen.scale ?? stage.contentScaleFactor)
            if fxScale == 0 { fxScale = min(GfxFlags.metalFXScale, native) }
            let k = min(1, fxScale / max(native, 1))
            rw = max(2, Int((Double(rw) * k).rounded())); rh = max(2, Int((Double(rh) * k).rounded()))
        }
        renderer.roomCacheEnabled = Self.roomCacheFlag
        renderer.gfxOpt = Self.gfxOptFlags
        if game {
            // every Jelly: his own dirt / shine (Bob's and the washed Jelly's from the clean-up flow); the bath close-up shows the washed Jelly alone
            let bathRoom = model.care.bath.look.visible || model.care.bath.cameraBlend > 0
            let washed = bathRoom ? min(model.care.bath.targetID, actors.count - 1) : 0
            renderer.bathBody = washed
            let camIn = model.care.focus.blend > 0.25          // the close-up is (nearly) on: the Jellies it does not frame are out of the picture
            renderer.raceCourse = model.care.race.course.tier
            renderer.raceVisible = model.care.race.trackVisible
            renderer.showVisible = model.care.show.onStage
            for a in actors {
                renderer.setRacePalette(model.care.racePalette(for: a.id), own: a.appearance, body: a.id)
                renderer.setHidden((bathRoom && a.id != washed) || (camIn && model.care.focusHides(a.id)) || model.care.showHides(a.id), body: a.id)
                renderer.setBathLook(model.care.renderLook(for: a.id), body: a.id)
            }
        }
        renderer.resize(width: rw, height: rh)
        lastRW = rw; lastRH = rh
        var fp = FrameParams()
        fp.time = simTime
        fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
        fp.exposure = 1
        fp.meshAlpha = m.showMesh ? 0.32 : 0
        fp.bg = m.palette.palette.matte ? melonCreamLinear : melonBackgroundLinear
        renderer.setUniforms(camera: cam, light: light, palette: m.palette.palette, params: fp,
                             viewSize: SIMD2<Float>(Float(rw), Float(rh)))
        if m.showMesh { sim.x.withUnsafeBufferPointer { renderer.uploadParticles($0.baseAddress!) } }
        renderer.draw(drawable: drawable, showMesh: m.showMesh)

        if !firstFrameDone {
            firstFrameDone = true
            if m.status == .starting { m.status = paused ? .paused : .live }
        }

        readoutT += dt
        if readoutT > 0.12 {
            readoutT = 0
            publishReadouts()
        }

        dbgCPU += CACurrentMediaTime() - cpu0
        dbgFrames += 1
        if dbgStart == 0 { dbgStart = now }
        if now - dbgStart >= 1 {
            let el = now - dbgStart
            let f = Double(dbgFrames)
            let g = renderer.takeGPUStats()
            NSLog("%@", String(format: "[melon] perf: cpu %.2f ms (+ gpu wait %.2f ms), gpu %.2f ms, sim %.2f ms (%.2f ms/step, %d steps), skin %.2f ms, %d Jellies | %.1f fps, interval %.2f ms",
                         (dbgCPU - dbgWait) / f * 1000, dbgWait / f * 1000, g.avgMs, dbgSim / f * 1000,
                         dbgSteps > 0 ? dbgSim / Double(dbgSteps) * 1000 : 0, dbgSteps, dbgSkin / f * 1000, actors.count, f / el, el / f * 1000))
            NSLog("%@", String(format: "[melon] env: thermal %@, lowPower %@, drawable %dx%d @ %.2fx (native %.0fx), fps pref %d (display max %d, measured %.1f), focus %@, adaptive %@ (%d changes), gpu mem %.1f MB, target rebuilds %d | gfx: %@%@",
                               Self.thermalName(ProcessInfo.processInfo.thermalState), ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "off",
                               Int(view.drawableSize.width), Int(view.drawableSize.height), Double(stage.contentScaleFactor), Double(stage.window?.screen.scale ?? 0),
                               stage.preferredFramesPerSecond, stage.window?.screen.maximumFramesPerSecond ?? 0, f / el,
                               model.care.focus.isActive ? "ON" : "off", Self.adaptiveEnabled ? "on" : "off", scaleChanges,
                               Double(renderer.device.currentAllocatedSize) / 1_048_576, renderer.targetRebuilds, gfxSummary(renderer, frames: f, rw: rw, rh: rh),
                               renderer.perfPasses ? " | passes ms: " + renderer.takePassStats() : ""))
            let slept = actors.reduce(0) { $0 + $1.sleptSteps }, wakes = actors.reduce(0) { $0 + $1.wakeCount }
            NSLog("[melon] sleep: %d of %d Jelly-steps skipped, %d wakes, asleep now: %@", slept - lastSlept, dbgSteps * actors.count, wakes - lastWakes, actors.map { $0.asleep ? "z" : "-" }.joined())
            lastSlept = slept; lastWakes = wakes
            if actors.count > 1 {
                NSLog("[melon] jellies: %@", actors.map { let c = $0.sim.centroid(); return String(format: "%d(%.2f,%.2f)%@", $0.id, c.x, c.z, $0.isWalking ? "w" : "") }.joined(separator: " "))
            }
            if game {
                let hc = model.touch.haptics.takeCost()
                NSLog("%@", String(format: "[touch] perf: sim step %.3f ms, brain %.3f ms/step, touch frame %.3f ms (haptics update %.4f ms) per frame",
                                   dbgSteps > 0 ? dbgStepOnly / Double(dbgSteps) * 1000 : 0, dbgSteps > 0 ? dbgBrain / Double(dbgSteps) * 1000 : 0,
                                   dbgTouch / f * 1000, hc.ms))
            }
            dbgBrain = 0; dbgStepOnly = 0; dbgTouch = 0; dbgSkin = 0
            dbgFrames = 0; dbgStart = now; dbgCPU = 0; dbgWait = 0; dbgSim = 0; dbgSteps = 0
            fflush(stdout)
        }
    }

    // MARK: fitting room (the shop's item sheet)

    private var lastRW = 0, lastRH = 0
    private var fitTex: MTLTexture?

    /// Jelly `id` wearing `look`, drawn by the game renderer itself (the room, the real body shader, the real wardrobe / shoe meshes, the jersey) into an
    /// offscreen target between two frames, from a close 3/4 camera in front of him. nil when there is no game renderer to ask.
    /// `look` nil: a plain portrait of him as he is (what he wears now), for the Studio and the Condition card.
    func fittingSnapshot(look: WearLook?, jelly id: Int) -> UIImage? {
        guard game, let renderer, let room = renderer.room, actors.indices.contains(id) else { return nil }
        // the size of the last frame (nil until the stage has drawn one: the caller asks again)
        let W = lastRW, H = lastRH
        guard W > 8, H > 8, firstFrameDone else { return nil }
        let care = model.care, a = actors[id]
        care.store.fitting = look.map { (id, $0) }
        defer {
            care.store.fitting = nil
            room.setWear(opaque: RoomMesh(), translucent: RoomMesh(), bounds: []); room.setShoes(RoomMesh())
            care.wearDrawn = true; care.shoesDrawn = false; care.shoeSig = []
            renderer.invalidateRoomCache()
        }
        renderer.beginFrame()
        for o in actors { renderer.setHidden(o.id != id, body: o.id) }
        renderer.raceVisible = false
        room.raceVisible = false
        renderer.showVisible = false
        room.showVisible = false
        a.skinner.update(x: a.sim.x, index: renderMesh.index, into: renderer.dynPointer(body: id))
        let w = WornSet(); w.body = WearBody.shared; w.soundOn = false; w.ignoreHide = true
        if let b = a.brain {
            w.tick(id: id, brain: b, sim: a.sim, outfit: care.store.outfit(id), role: .none, hideAll: false, dt: 1.0 / 60)
            if w.shown(id, .hands) != nil { w.setArms(id, care.armFrames(a)) }
        }
        renderer.setJersey(w.jersey(id), body: id)
        let f = w.frame(theme: room.theme, time: 0.4) { renderer.skinPointer(body: $0) }
        room.setWear(opaque: f.opaque, translucent: f.translucent, bounds: [])
        room.setShoes(care.shoeFrame([a], time: 0.4).mesh)
        // a close camera in front of him (his own facing, turned a quarter toward the side)
        let pose = a.sim.bodyPose(iterations: 3)
        let c = pose.centroid
        var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
        fwd = simd_length(fwd) > 1e-3 ? simd_normalize(fwd) : SIMD3(0, 0, 1)
        let yaw: Float = look == nil ? 0.3 : 0.5
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        let head = look.map { $0.slot == .head || $0.slot == .face || $0.slot == .neck } ?? false
        let focusY: Float = head ? c.y + (look?.slot == .head ? 0.5 : 0.3) : c.y + (look == nil ? 0.2 : 0.1)
        let span: Float = look == nil ? 2.3 : (look?.slot == .feet ? 1.5 : (head ? 1.9 : 2.0))
        let aspect = Float(W) / Float(H)
        let th = tanf(GameCamera.fovY / 2)
        let dist = (span / 2) / min(th, th * aspect)
        let target = SIMD3<Float>(c.x, focusY, c.z)
        let eye = target + dir * dist + SIMD3(0, dist * 0.12, 0)
        var cam = CameraState()
        cam.view = M4.lookAt(eye: eye, at: target, up: SIMD3(0, 1, 0))
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.2, far: 60), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye; cam.fwd = simd_normalize(target - eye)
        let light = GameCamera.light(centroid: c)
        var fp = FrameParams()
        fp.time = simTime
        fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
        fp.exposure = 1; fp.meshAlpha = 0
        let pal = JellyRoster.palette(slot: id) ?? model.palette.palette
        fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
        renderer.roomCacheEnabled = false
        renderer.resize(width: W, height: H)
        renderer.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
        if fitTex == nil || fitTex!.width != W || fitTex!.height != H {
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
            fitTex = renderer.device.makeTexture(descriptor: td)
        }
        guard let tex = fitTex, let cmd = renderer.queue.makeCommandBuffer() else { return nil }
        renderer.draw(to: tex, commandBuffer: cmd, showMesh: false)
        cmd.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: W * H * 4)
        px.withUnsafeMutableBytes { tex.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
        let side = min(W, H)
        let cs = CGColorSpaceCreateDeviceRGB()
        // (the CGContext must not outlive the buffer: make the image inside the closure)
        guard let full = px.withUnsafeMutableBytes({ p -> CGImage? in
                  CGContext(data: p.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?.makeImage() }),
              let part = full.cropping(to: CGRect(x: (W - side) / 2, y: (H - side) / 2, width: side, height: side)) else { return nil }
        return UIImage(cgImage: part)
    }

    private static func thermalName(_ t: ProcessInfo.ThermalState) -> String {
        switch t { case .nominal: return "nominal"; case .fair: return "fair"; case .serious: return "SERIOUS"; case .critical: return "CRITICAL"; @unknown default: return "?" }
    }

    private func publishReadouts() {
        model.volumePct = Double(sim.volumeRatio() * 100)
        let ke = sim.kineticEnergy() / sim.totalMass * (massG / 1000) * powf(bobScaleCm / 100, 2)
        model.kineticMicroJ = Double(ke) * 1e6
        model.mass = Double(massG)
    }

    // MARK: Camera

    func pinch(scale: Float) {
        guard !game, mode != .grab, scale > 0 else { return }
        rig.applyZoom(factor: 1 / scale)
    }

    func resetCamera() { if !game { rig.reset() } }

    // MARK: Multi-Blob select (the highlight itself is BlobSelect / SelectionOverlay)

    /// Double tap in the game: select the Blob under the finger (roaming only; with one Blob there is no select step).
    func gameDoubleTap(_ p: CGPoint) {
        guard game, !model.care.focus.isActive, !model.care.tripActive else { return }
        guard !model.care.arranging else { return }
        refreshOutlines()
        if let id = model.care.select.hit(p) { model.care.select.doubleTap(id); return }          // a Jelly under the finger: unchanged
        if let uid = decorUnderFinger(p) { model.care.pickUpDecor(uid) }          // a placed piece (and no Jelly in front of it): pick it up to move it
    }

    /// The placed decor piece under a screen point, unless a Jelly drawn there is nearer the camera (he wins: his tap / pet / select is unchanged).
    func decorUnderFinger(_ p: CGPoint) -> Int? {
        guard game, haveCam, !model.care.arranging, !model.care.focus.isActive, !model.care.bath.active, !model.care.tripActive, !model.care.store.placedDecor.isEmpty, let size = stageView?.bounds.size, size.width > 1,
              let d = model.care.decorHit(screen: p, size: size) else { return nil }
        let jd = pickJelly(p, size).map { simd_distance($0.hit, lastCam.pos) }
        return GameCare.decorWins(pieceT: d.t, jellyDistance: jd) ? d.piece.uid : nil
    }

    /// Fresh silhouettes for a hit test (several Jellies, nothing highlighted: they are not published every frame). One Jelly has no select step.
    private func refreshOutlines() {
        guard game, haveCam, actors.count > 1, let stage = stageView else { return }
        let pts = stage.bounds.size, vp = lastCam.viewProj
        model.care.select.publish(viewProj: vp, size: pts, points: { screenPoints(of: $0, pts, vp) })
    }

    /// A tap on the floor (not on a Blob) cancels a pending selection.
    func gameSingleTap(_ p: CGPoint) {
        let sel = model.care.select
        if game, sel.isSelecting, sel.hit(p) == nil { sel.cancel() }
        if game, !model.care.focus.isActive, !model.care.bath.active, !model.care.tripActive, touchSize.width > 1, pickJelly(p, touchSize) == nil, windowTapped(p, touchSize) {
            DayClock.shared.skipToNextPhase()            // the window: skip to the next part of the day (a short time-lapse)
            AudioHub.shared.uiConfirm()
        }
    }

    /// True when a screen point lands on one of the back-wall windows.
    func windowTapped(_ p: CGPoint, _ size: CGSize) -> Bool {
        let ray = unproject(ndc: ndc(p, size), invViewProj: lastCam.invViewProj)
        let z = RoomLayout.minZ - RoomGeometry.insetDepth * 0.5
        guard abs(ray.d.z) > 1e-5 else { return false }
        let t = (z - ray.o.z) / ray.d.z
        guard t > 0 else { return false }
        let q = ray.o + ray.d * t
        return DayWindow.contains(x: q.x, y: q.y)
    }

    /// A real Jelly's render vertices projected to screen points (for his outline and for hit tests).
    private func screenPoints(of id: Int, _ size: CGSize, _ vp: simd_float4x4) -> [CGPoint] {
        guard let renderer, id < actors.count else { return [] }
        let d = renderer.skinPointer(body: id)
        var out: [CGPoint] = []
        out.reserveCapacity(renderMesh.vertexCount)
        for i in 0..<renderMesh.vertexCount {
            let o = 6 * i
            let q = vp * SIMD4<Float>(d[o], d[o + 1], d[o + 2], 1)
            if q.w > 1e-4 { out.append(CGPoint(x: CGFloat(q.x / q.w * 0.5 + 0.5) * size.width, y: CGFloat(1 - (q.y / q.w * 0.5 + 0.5)) * size.height)) }
        }
        return out
    }

    // MARK: Pointer handling (shared by touches and the DEBUG auto-drag)

    private func ndc(_ p: CGPoint, _ size: CGSize) -> SIMD2<Float> {
        SIMD2<Float>(Float(p.x / size.width) * 2 - 1, 1 - Float(p.y / size.height) * 2)
    }

    private func rotMat(_ a: SIMD3<Float>, _ ang: Float) -> [Float] {
        let c = cosf(ang), s = sinf(ang), t = 1 - c
        let x = a.x, y = a.y, z = a.z
        return [t * x * x + c, t * x * y - s * z, t * x * z + s * y,
                t * x * y + s * z, t * y * y + c, t * y * z - s * x,
                t * x * z - s * y, t * y * z + s * x, t * z * z + c]
    }

    private func dragTarget(_ p: CGPoint, _ size: CGSize, limited: Bool = true) -> SIMD3<Float>? {
        let ray = unproject(ndc: ndc(p, size), invViewProj: lastCam.invViewProj)
        let den = simd_dot(ray.d, planeN)
        if abs(den) < 1e-5 { return nil }
        let t = simd_dot(planeP - ray.o, planeN) / den
        var q = ray.o + ray.d * t
        let dx = q.x - rig.target.x, dz = q.z - rig.target.z, lim: Float = 3.4
        let dl = (dx * dx + dz * dz).squareRoot()
        if dl > lim { q.x = rig.target.x + dx / dl * lim; q.z = rig.target.z + dz / dl * lim }
        if !limited { return q }                        // the raw point under the finger (the throw speed is measured on it)
        q.y = min(max(q.y, 0.02), 3.2)
        if game, model.care.focus.isFocused {
            // he stays near the close-up's spot while lifted
            let spot = model.care.focusSpot(for: touchID), sx = spot.x, sz = spot.y
            q.x = min(max(q.x, sx - 0.18), sx + 0.18); q.z = min(max(q.z, sz - 0.5), sz + 0.5)       // held: his whole body stays in the close-up (it is nearly as wide as the frame)
            q.y = min(q.y, planeP.y + 0.4)            // lifted a hand's width: feet clear of the floor, still whole in the close-up frame
        }
        if game {
            // keep the held patch over the visible floor (and off the sofa / props)
            let k = GameCamera.constrain(SIMD3<Float>(q.x, 0, q.z), radius: 0.35, openSides: model.care.focusGroup.isRow && model.care.focus.isFocused)
            q.x = k.x; q.z = k.z
        }
        return q
    }

    private func applyGrab(_ p: CGPoint, _ size: CGSize) {
        if let q = dragTarget(p, size) {
            grabGoal = q
            tSim.moveGrab(target: q, rot: rotMat(lastCam.fwd, twist + model.touch.heldSway))
            liftHeight = q.y - planeP.y
        }
        if let raw = dragTarget(p, size, limited: false) {
            grabSamples.append((CACurrentMediaTime(), raw)); if grabSamples.count > 8 { grabSamples.removeFirst() }
        }
    }

    /// Where the held patch is headed (kept so the happy sway can turn the patch every frame, not only when the finger moves).
    private var grabGoal: SIMD3<Float>?

    private func cancelGrab() {
        if mode == .grab { tSim.endGrab(); mode = .none; dragID = nil; second = nil }
    }

    /// The Jelly under a screen point and the point on his body (the rendered mesh first, then the nearest particle within a fingertip), nearest first.
    /// In the close-up only the focused Jellies can be touched (the others are hidden).
    private func pickJelly(_ p: CGPoint, _ size: CGSize) -> (id: Int, hit: SIMD3<Float>)? {
        guard let renderer else { return nil }
        let ids = (game && model.care.focus.isActive && !model.care.focusGroup.ids.isEmpty) ? model.care.focusGroup.ids : Array(actors.indices)
        let bodies = ids.filter { $0 < actors.count }.map { TouchPick.Body(id: $0, dyn: renderer.skinPointer(body: $0), x: actors[$0].sim.x) }
        return TouchPick.pick(p, size: size, viewProj: lastCam.viewProj, invViewProj: lastCam.invViewProj, bodies: bodies,
                              index: renderMesh.index, bodyIndexCount: renderMesh.body.first + renderMesh.body.count)
    }

    /// The point on a Jelly's body under a screen point (any visible Jelly).
    private func pickBody(_ p: CGPoint, _ size: CGSize) -> SIMD3<Float>? { pickJelly(p, size)?.hit }

    /// The finger goes to another Jelly: the one it leaves lets go of the touch play first (its state is for one body).
    private func routeTouch(to id: Int) {
        guard id != touchID, id < actors.count else { return }
        if let b = tBrain { model.touch.cancel(sim: tSim, brain: b, skinner: tSkinner) }
        touchID = id
    }

    // Capture aid (not DEBUG-only so the Release sim build can film it): -TouchDemo pet strokes him on a 14 s loop once he is in focus mode.
    private let touchDemoName = UserDefaults.standard.string(forKey: "TouchDemo")
    private var tdT0: CFTimeInterval = 0
    private var tdDown = false
    private var tdHeartT: CFTimeInterval = 0
    private var tdAnchor: SIMD3<Float>?

    private func screenPoint(_ w: SIMD3<Float>, _ size: CGSize) -> CGPoint {
        let c = lastCam.viewProj * SIMD4<Float>(w.x, w.y, w.z, 1)
        return CGPoint(x: CGFloat(c.x / c.w * 0.5 + 0.5) * size.width, y: CGFloat(0.5 - c.y / c.w * 0.5) * size.height)
    }

    private func touchDemo(now: CFTimeInterval) {
        guard game, let name = touchDemoName, haveCam, let stage = stageView else { return }
        let A = ObjectIdentifier(self), B = ObjectIdentifier(stage)
        guard model.care.focus.isFocused else {
            if tdDown { pointerUp(id: A); pointerUp(id: B); tdDown = false }
            return
        }
        if tdT0 == 0 { tdT0 = now }
        guard now - tdT0 > 1.5 else { return }
        let size = stage.bounds.size
        let c = tSim.centroid()
        let right = SIMD3<Float>(lastCam.view.columns.0.x, lastCam.view.columns.1.x, lastCam.view.columns.2.x)
        let up = SIMD3<Float>(lastCam.view.columns.0.y, lastCam.view.columns.1.y, lastCam.view.columns.2.y)
        func at(_ x: Float, _ y: Float) -> CGPoint { screenPoint(c + right * x + up * y, size) }
        func sm(_ v: Double) -> Float { let k = Float(min(1, max(0, v))); return k * k * (3 - 2 * k) }
        let el = now - tdT0 - 1.5
        switch name {
        case "pet":
            let t = el.truncatingRemainder(dividingBy: 14)
            if t < 9, now - tdHeartT > 0.8 { tdHeartT = now; model.touch.spawnHeart(now: now) }       // capture aid: hearts show even before he is happy enough
            if t < 9 {
                let k = Float(min(1, t / 0.6)), ph = Float(t)
                let pt = at(0.4 * sinf(2 * .pi * 0.8 * ph) * k, 0.25 * sinf(2 * .pi * 0.4 * ph) * k)
                if !tdDown { tdDown = true; pointerDown(id: A, point: pt, size: size) } else { pointerMove(id: A, point: pt, size: size) }
            } else if tdDown { pointerUp(id: A); tdDown = false }
        case "pickup":      // double-tap and hold on the crown, lift, hang there wiggling, let go (14 s loop)
            let t = el.truncatingRemainder(dividingBy: 14)
            let lift = 0.45 * sm((t - 0.9) / 1.2)
            let crown = at(0, 0.62)
            if t < 0.12 { if !tdDown { tdDown = true; pointerDown(id: A, point: crown, size: size) } }              // tap 1
            else if t < 0.30 { if tdDown { pointerUp(id: A); tdDown = false } }
            else if t < 6 {                                                                                         // tap 2, held, then lifted
                if !tdDown { tdDown = true; pointerDown(id: A, point: crown, size: size) }
                else { pointerMove(id: A, point: at(0, 0.62 + lift), size: size) }
            } else if tdDown { pointerUp(id: A); tdDown = false }
        case "throw":       // lift, then a fast flick up and to the side on release; he gets back up on his own (28 s loop)
            let t = el.truncatingRemainder(dividingBy: 28)
            if t < 0.12 { if !tdDown { tdDown = true; pointerDown(id: A, point: at(0, 0.62), size: size) } }       // tap 1
            else if t < 0.30 { if tdDown { pointerUp(id: A); tdDown = false } }
            else if t < 2.15 {
                let lift = 0.4 * sm((t - 0.9) / 0.7)
                if !tdDown { tdDown = true; pointerDown(id: A, point: at(0, 0.62), size: size) }
                else if t < 1.9 { pointerMove(id: A, point: at(0, 0.62 + lift), size: size) }
                else { let k = Float(min(1, (t - 1.9) / 0.25)); pointerMove(id: A, point: at(1.1 * k, 0.62 + lift + 1.0 * k), size: size) }   // ~1.5 u in 0.2 s: a flick
            } else if tdDown { pointerUp(id: A); tdDown = false }
        case "drag":        // hold, drag along the floor, lift and swing him around, set him down gently (18 s loop; anchored to where he started)
            let t = el.truncatingRemainder(dividingBy: 18)
            if tdAnchor == nil || t < 0.05 { tdAnchor = c }
            let a0 = tdAnchor ?? c
            func atA(_ x: Float, _ y: Float) -> CGPoint { screenPoint(a0 + right * x + up * y, size) }
            if t < 0.12 { if !tdDown { tdDown = true; pointerDown(id: A, point: atA(0, 0.62), size: size) } }       // tap 1 of the double tap
            else if t < 0.30 { if tdDown { pointerUp(id: A); tdDown = false } }
            else if t < 14 {
                var x: Float = 0, y: Float = 0.62
                if t > 0.5 && t < 1.2 { y = 0.62 + 0.14 * sm((t - 0.5) / 0.5) }                                     // hold, then a little up: that is the pick up
                else if t >= 1.2 && t < 4 { x = 0.55 * sinf(Float(t - 1.2) * 1.9) * sm((t - 1.2) / 0.4); y = 0.62 + 0.14 }   // dragged along the floor (just clear of it)
                else if t >= 4 && t < 10 { let k = sm((t - 4) / 0.8); x = 0.6 * sinf(Float(t - 4) * 2.4) * k; y = 0.76 + 0.30 * k + 0.12 * sinf(Float(t - 4) * 3.1) * k }
                else if t >= 10 { let k = 1 - sm((t - 10) / 1.5); x = 0.4 * k * sinf(Float(t - 10) * 2.4); y = 0.76 + 0.30 * k }
                if !tdDown { tdDown = true; pointerDown(id: A, point: atA(0, 0.62), size: size) }
                else { pointerMove(id: A, point: atA(x, y), size: size) }
            } else if tdDown { pointerUp(id: A); tdDown = false }
        case "cheeks":      // two fingers on the cheeks pinch together, hold, let go (9 s loop)
            let t = el.truncatingRemainder(dividingBy: 9)
            if t < 4 {
                let g = 0.5 - 0.3 * sm((t - 0.5) / 1.0)
                if !tdDown { tdDown = true; pointerDown(id: A, point: at(-0.5, 0.16), size: size); pointerDown(id: B, point: at(0.5, 0.16), size: size) }
                else { pointerMove(id: A, point: at(-g, 0.16), size: size); pointerMove(id: B, point: at(g, 0.16), size: size) }
            } else if tdDown { pointerUp(id: A); pointerUp(id: B); tdDown = false }
        default: break
        }
    }

    /// Once per frame, before the fixed steps: the touch play of focus mode (the pet finger's dent, his reactions, the haptics).
    private func touchTick(dt: Float, now: CFTimeInterval) {
        guard game, let brain = tBrain, brain.enabled else { return }
        let f = model.care.focus
        let play = model.touch
        model.care.focusGroup.touchAnchor = (f.isFocused && touchID != 0) ? tSim.centroid() : nil
        let bathLive = model.care.bath.acceptsTouch
        play.haptics.setWarm(f.phase == .approaching || f.phase == .focused || bathLive)
        let tn = model.care.needs(for: touchID)
        play.mood = tn.mood; play.attentionWanted = tn.wantedNeed == .attention      // a grumpy Blob is touched with an annoyed reaction
        // getting back up: after a throw (or if he is left lying) he rights himself and walks back to the spot
        let held = mode == .grab || tSim.grabbing || mode == .pet || mode == .pending || mode == .cheeks
        play.holdsBrain = play.getUpFrame(dt: dt, now: now, held: held, focusSpot: f.isFocused ? model.care.focusSpot(for: touchID) : (bathLive ? BathFlow.standXZ : nil), sim: tSim, brain: brain)
        if !(f.isFocused || bathLive) || model.paused {
            if mode == .pet || mode == .pending || mode == .cheeks { mode = .none }
            cheekFingers = []; gesture.cancel(); pickArm.reset()
            DeviceMotionFeed.shared.setRunning(false)
            if !play.holdsBrain { play.cancel(sim: tSim, brain: brain, skinner: tSkinner) }
            return
        }
        if restSurface == nil { restSurface = RestSurface(mesh: renderMesh) }
        // phone tilt / shake (the -TouchDemo tilt capture aid feeds a scripted tilt and shakes instead of the sensors)
        var gx: Float, shk: Float
        if touchDemoName == "tilt" {
            if tdT0 == 0 { tdT0 = now }
            let t = Float(now - tdT0)
            gx = max(-1, min(1, 0.9 * sinf(t * 1.3))) * (t > 2 ? 1 : 0)
            shk = (t > 8 && t < 10.5 && Int(t * 4) % 2 == 0) ? 2.6 : 0
        } else {
            let feed = DeviceMotionFeed.shared
            feed.setRunning(true)
            gx = feed.gravityX; shk = feed.shake
        }
        if gx != 0 || shk != 0 || play.isActive {
            play.motionFrame(dt: dt, now: now, gravityX: gx, shake: shk, sim: tSim, brain: brain, skinner: tSkinner)
        }
        gesture.tick(t: now)
        if mode == .pending {
            if gesture.kind == .pickUp { beginPickUp(last, touchSize) }       // double-tap and hold: he lifts without needing to drag
            else if gesture.kind == .hold { mode = .pet }                      // a single press-hold is petting
        }
        // the fingertip dent: a stroke, a press that has not decided yet, or the last moment of a tap
        var ray: (o: SIMD3<Float>, d: SIMD3<Float>)?
        var scr: SIMD2<Float>?
        if (mode == .pet || mode == .pending || now < tapUntil), touchSize.width > 0 {
            let r = unproject(ndc: ndc(petPoint, touchSize), invViewProj: lastCam.invViewProj)
            ray = (r.o, r.d)
            scr = SIMD2(Float(petPoint.x / touchSize.width), Float(petPoint.y / touchSize.height))
        }
        if mode == .cheeks || play.pinch > 0 || play.visPinch != 0 {
            var rays: [(o: SIMD3<Float>, d: SIMD3<Float>)]?
            var gap: Float = 0
            if mode == .cheeks, cheekFingers.count == 2, touchSize.width > 0 {
                rays = cheekFingers.map { let r = unproject(ndc: ndc($0.p, touchSize), invViewProj: lastCam.invViewProj); return (r.o, r.d) }
                gap = Float(hypot(cheekFingers[0].p.x - cheekFingers[1].p.x, cheekFingers[0].p.y - cheekFingers[1].p.y))
            }
            play.cheeksFrame(dt: dt, now: now, rays: rays, gap: gap, sim: tSim, brain: brain, skinner: tSkinner, surface: restSurface)
        } else if mode != .grab, !tSim.grabbing {
            play.petFrame(dt: dt, now: now, ray: ray, screen: scr, sim: tSim, brain: brain, skinner: tSkinner, surface: restSurface)
        }
        if bathLive { model.care.bath.touch(contact: play.contact, hitLocal: play.hitLocal, world: play.hitWorld, speed: play.speed, dt: dt) }
        // pick up / throw: the stretch he is under, the excitement while he is held up, the landing thump
        play.trackImpacts(now: now, sim: tSim)
        if play.thrown, haveCam {
            // soft walls at the visible edges of the close-up (at his depth, with a margin): a throw bounces off them, he stays whole in the picture
            let c = tSim.centroid()
            func onPlane(_ ndc: SIMD2<Float>, z: Float) -> SIMD3<Float> {
                let r = unproject(ndc: ndc, invViewProj: lastCam.invViewProj)
                let t = abs(r.d.z) > 1e-4 ? (z - r.o.z) / r.d.z : 0
                return r.o + r.d * t
            }
            let zf = c.z + 0.5                                   // the front of the body is the widest on screen
            let l = onPlane(SIMD2(-0.90, 0), z: zf), rr = onPlane(SIMD2(0.90, 0), z: zf), tp = onPlane(SIMD2(0, 0.78), z: c.z)
            let spot = model.care.focusSpot(for: touchID)
            play.wallsFrame(now: now, sim: tSim, limits: TouchPlay.FrameLimits(xMin: min(l.x, rr.x), xMax: max(l.x, rr.x), zMin: spot.y - 1.2, zMax: spot.y + 0.3, yMax: tp.y))
        }
        if tSim.grabbing, let g = grabGoal, play.heldSway != 0 {
            tSim.moveGrab(target: g, rot: rotMat(lastCam.fwd, twist + play.heldSway))        // the happy ~1 Hz sway, even with the finger still
        }
        if tSim.grabbing {
            play.squishDepth = min(0.5, tSim.deformation() * TouchPlay.liftDepthGain)
            play.petFrameIdle(dt: dt, now: now)
        } else if play.squishDepth > 0 {
            play.squishDepth = 0; play.petFrameIdle(dt: dt, now: now)
        }
        play.heldFrame(dt: dt, now: now, grabbing: tSim.grabbing, liftHeight: liftHeight, sim: tSim, brain: brain, skinner: tSkinner)
    }

    private func beginPickUp(_ p: CGPoint, _ size: CGSize) {
        guard let hit = gestureHit else { return }
        model.touch.releaseContact(sim: tSim)
        mode = .grab
        twist = 0
        planeP = hit
        planeN = lastCam.fwd
        liftHeight = 0
        grabSamples = []
        tSim.beginGrab(hit: hit, radius: 0.4)
        applyGrab(p, size)
    }

    /// Let go of a held Bob: a fast flick throws him, anything else drops him.
    private func releaseGrab(_ r: TouchGesture.Release) {
        tSim.endGrab()
        mode = .none
        if case .throwIt = r, grabSamples.count >= 2, let a = grabSamples.first(where: { grabSamples.last!.t - $0.t < 0.1 }), let b = grabSamples.last, b.t - a.t > 0.01 {
            var v = (b.q - a.q) / Float(b.t - a.t)
            v.x *= 0.35; v.z *= 0.35
            let hs = simd_length(SIMD2(v.x, v.z)); if hs > 0.9 { v.x *= 0.9 / hs; v.z *= 0.9 / hs }          // a throw bounces around the room, it does not leave it
            v.y = min(max(v.y, 2.5), 4.2)
            let sp = simd_length(v)
            if sp > 6 { v *= 6 / sp }
            tSim.launch(velocity: v, spin: SIMD3<Float>(0, 0, v.x > 0 ? -2.5 : 2.5))
            throwHold = 1.0
            model.touch.thrown = true
            model.touch.haptics.transient(now: CACurrentMediaTime(), intensity: 0.5, sharpness: 0.3)       // the release
        } else { model.touch.jellyLetGo(now: CACurrentMediaTime()) }       // dropped: the jelly snaps back and settles, the haptic follows its wobble
        grabSamples = []; liftHeight = 0
    }

    func pointerDown(id: ObjectIdentifier, point p: CGPoint, size: CGSize, time: Double? = nil) {
        guard haveCam, size.width > 0, size.height > 0 else { return }
        if game, model.care.tripActive { return }          // on the track (or the show's stage) the screen is the buttons: no touch play, no selection, no voice
        if game, model.care.bath.acceptsTouch {
            // the clean-up: every touch is a scrub (no gesture classifier: no pick up, throw or cheeks), starting anywhere
            if mode == .none, !model.paused { mode = .pet; dragID = id; last = p; petPoint = p; touchSize = size }
            return
        }
        if game {
            // Voice: the second down of a double-tap on EMPTY space (no Blob under it) opens listen mode, in roaming and in focus
            if voiceTouch == nil, !model.paused {
                let vnow = time ?? CACurrentMediaTime()       // the touch's own timestamp: delivery lag (the warm-up work on the first tap) must not eat the 0.35 s window
                let onBlob = pickBody(p, size) != nil || { refreshOutlines(); return model.care.select.hit(p) != nil }() || decorUnderFinger(p) != nil          // (a piece counts: a double tap on it is not a call to listen)
                let decision = voiceGesture.touchDown(time: vnow, point: p, hitBlob: onBlob)
                if VoiceTranscriptLog.on { NSLog("[voice] gesture down t=%.3f lag=%.0f ms onBlob=%d -> %@", vnow, (CACurrentMediaTime() - vnow) * 1000, onBlob ? 1 : 0, decision == .beginVoice ? "BEGIN" : "none") }
                if decision == .beginVoice, mode == .none {
                    voiceTouch = id; emptyDown = nil
                    let opened = model.care.voice.begin()
                    if VoiceTranscriptLog.on { NSLog("[voice] begin() -> %d", opened ? 1 : 0) }
                    return
                }
                emptyDown = onBlob ? nil : (id, vnow, p)
                if !onBlob { model.care.voice.warmUp() }        // maybe the first tap of a double-tap: bring the mic up early (self-cancels)
            }
            // touch play only acts inside focus mode (Come here): a roaming Bob is not grabbed, and nothing orbits or zooms.
            // The GESTURE decides the action (pet / tap / pick up / throw / cheeks), never switching mid-gesture.
            let f = model.care.focus
            guard f.isFocused, !model.paused else { return }
            let now = CACurrentMediaTime()
            if mode == .none {
                guard model.touch.getUpPhase == .off, let picked = pickJelly(p, size) else { return }
                let hit = picked.hit
                routeTouch(to: picked.id)
                mode = .pending; dragID = id; last = p; petPoint = p; touchSize = size; gestureHit = hit
                gesture.down(t: now, p: p, armed: pickArm.touchDown(time: now, point: p))
            } else if mode == .pending, id != dragID, pickJelly(p, size)?.id == touchID, !gesture.armed, gesture.secondDown(t: now) {
                mode = .cheeks; touchSize = size
                model.touch.releaseContact(sim: tSim)
                cheekFingers = [(dragID!, petPoint), (id, p)]
            }
            return
        }
        if mode == .grab, id != dragID {
            if second == nil {
                second = (id, p)
                twist0 = twist - Float(atan2(p.y - last.y, p.x - last.x))
            }
            return
        }
        if mode != .none { return }
        let hit: SIMD3<Float>? = model.paused ? nil : pickBody(p, size)
        dragID = id
        last = p
        if let hit {
            mode = .grab
            twist = 0
            planeP = hit
            planeN = lastCam.fwd
            tSim.beginGrab(hit: hit, radius: 0.4)
        } else {
            mode = .orbit
        }
    }

    func pointerMove(id: ObjectIdentifier, point p: CGPoint, size: CGSize) {
        guard haveCam else { return }
        if id == voiceTouch { return }
        if let e = emptyDown, e.id == id, hypot(p.x - e.p.x, p.y - e.p.y) > 20 { emptyDown = nil }       // a drag is not a tap
        if let k = cheekFingers.firstIndex(where: { $0.id == id }) { cheekFingers[k].p = p; touchSize = size; return }
        if game, id == dragID, model.care.bath.acceptsTouch, mode == .pet { petPoint = p; touchSize = size; last = p; return }
        if game, id == dragID {
            let now = CACurrentMediaTime()
            touchSize = size; last = p
            switch mode {
            case .pending:
                petPoint = p
                gesture.move(t: now, p: p)
                if gesture.kind == .pet { mode = .pet }
                else if gesture.kind == .pickUp { beginPickUp(p, size) }
            case .pet: petPoint = p; gesture.move(t: now, p: p)
            case .grab: gesture.move(t: now, p: p); applyGrab(p, size)
            default: break
            }
            return
        }
        if let s = second, s.id == id {
            second = (id, p)
            twist = twist0 + Float(atan2(p.y - last.y, p.x - last.x))
            twist = max(-1.3, min(1.3, twist))
            applyGrab(last, size)
            return
        }
        guard id == dragID, mode != .none else { return }
        let dx = Float(p.x - last.x), dy = Float(p.y - last.y)
        last = p
        if mode == .grab {
            applyGrab(p, size)
        } else if !game {
            rig.orbit(dAzimuth: -dx * 0.006, dElevation: dy * 0.005)
        }
    }

    func pointerUp(id: ObjectIdentifier, time: Double? = nil) {
        if id == voiceTouch { voiceTouch = nil; model.care.voice.release(); return }
        if let e = emptyDown, e.id == id {
            emptyDown = nil
            let vnow = time ?? CACurrentMediaTime()
            if VoiceTranscriptLog.on { NSLog("[voice] gesture up t=%.3f held=%.0f ms", vnow, (vnow - e.t) * 1000) }
            voiceGesture.tapUp(time: vnow, downTime: e.t, point: e.p, hitBlob: false)        // a short tap on empty space arms the gesture
        }
        if let k = cheekFingers.firstIndex(where: { $0.id == id }) {
            cheekFingers.remove(at: k)
            if cheekFingers.count < 2, mode == .cheeks { mode = .none; dragID = nil; gesture.cancel() }
            return
        }
        if game, id == dragID, mode == .pet, model.care.bath.active { mode = .none; dragID = nil; return }
        if game, id == dragID {
            let now = CACurrentMediaTime()
            let r = gesture.up(t: now)
            switch mode {
            case .pending:
                if r == .tap { model.touch.tap(now: now); tapUntil = now + 0.22; pickArm.tapUp(time: now, point: last) }
                mode = .none
            case .grab: releaseGrab(r)
            default: mode = .none
            }
            dragID = nil
            return
        }
        if let s = second, s.id == id { second = nil; return }
        guard id == dragID else { return }
        if mode == .grab { tSim.endGrab() }
        mode = .none
        dragID = nil
        second = nil
    }

    // MARK: DEBUG auto-drag (launch argument -MelonAutoDrag 1)

    #if DEBUG
    private func project(_ w: SIMD3<Float>, _ size: CGSize) -> CGPoint {
        let c = lastCam.viewProj * SIMD4<Float>(w.x, w.y, w.z, 1)
        return CGPoint(x: CGFloat((c.x / c.w * 0.5 + 0.5)) * size.width, y: CGFloat((0.5 - c.y / c.w * 0.5)) * size.height)
    }

    /// t=1.5s grab the apex (highest particle), pull 1.5 units up (screen-up) over 1s, hold, release at t=4.5s.
    private func runAutoDrag(now: CFTimeInterval, stage: MelonStageView) {
        guard haveCam else { return }
        if autoT0 == 0 { autoT0 = now }
        let t = now - autoT0
        let size = stage.bounds.size
        let id = ObjectIdentifier(self)
        switch autoPhase {
        case 0 where t > 1.5:
            let tip = demoPos(demoApexIndex())
            // camera-up in world space
            let up = SIMD3<Float>(lastCam.view.columns.0.y, lastCam.view.columns.1.y, lastCam.view.columns.2.y)
            autoStart = project(tip, size)
            autoEnd = project(tip + up * 1.5, size)
            pointerDown(id: id, point: autoStart, size: size)
            autoPhase = 1
            NSLog("[melon] autodrag: grab at %@ mode=%@", "\(autoStart)", "\(mode)"); fflush(stdout)
        case 1:
            let k = CGFloat(min(1, max(0, (t - 1.5) / 1.0)))
            pointerMove(id: id, point: CGPoint(x: autoStart.x + (autoEnd.x - autoStart.x) * k,
                                               y: autoStart.y + (autoEnd.y - autoStart.y) * k), size: size)
            if t > 4.5 { pointerUp(id: id); autoPhase = 2; NSLog("[melon] autodrag: released"); fflush(stdout) }
        default: break
        }
    }

    // MARK: DEBUG choreographed demo (launch argument -MelonDemo 1)

    private func demoPos(_ i: Int) -> SIMD3<Float> { SIMD3<Float>(sim.x[3 * i], sim.x[3 * i + 1], sim.x[3 * i + 2]) }

    /// Highest particle (Bob's apex).
    private func demoApexIndex() -> Int {
        var best = 0, bh = -Float.greatestFiniteMagnitude
        for i in 0..<sim.n { let y = sim.x[3 * i + 1]; if y > bh { bh = y; best = i } }
        return best
    }

    /// Particle with the largest x among those near belly height (about 35% of the way up the body).
    private func demoSideIndex() -> Int {
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for i in 0..<sim.n { let y = sim.x[3 * i + 1]; lo = min(lo, y); hi = max(hi, y) }
        let belly = lo + (hi - lo) * 0.35
        var best = 0, bx = -Float.greatestFiniteMagnitude
        for i in 0..<sim.n {
            let p = demoPos(i)
            if abs(p.y - belly) > (hi - lo) * 0.15 { continue }
            if p.x > bx { bx = p.x; best = i }
        }
        return best
    }

    /// Screen-space offset (px) for a world-space move of (right, up) units, using the camera axes at step start.
    private func demoOffset(_ r: Double, _ u: Double) -> CGPoint {
        CGPoint(x: demoRight.dx * r + demoUp.dx * u, y: demoRight.dy * r + demoUp.dy * u)
    }

    private func demoSmooth(_ x: Double) -> Double { let k = min(1, max(0, x)); return k * k * (3 - 2 * k) }

    private func demoBegin(_ world: SIMD3<Float>, _ size: CGSize, _ id: ObjectIdentifier) {
        let a = project(world, size)
        let up = SIMD3<Float>(lastCam.view.columns.0.y, lastCam.view.columns.1.y, lastCam.view.columns.2.y)
        let right = SIMD3<Float>(lastCam.view.columns.0.x, lastCam.view.columns.1.x, lastCam.view.columns.2.x)
        let pu = project(world + up, size), pr = project(world + right, size)
        demoUp = CGVector(dx: pu.x - a.x, dy: pu.y - a.y)
        demoRight = CGVector(dx: pr.x - a.x, dy: pr.y - a.y)
        demoAnchor = a
        pointerDown(id: id, point: a, size: size)
    }

    private func runDemo(now: CFTimeInterval, stage: MelonStageView) {
        guard haveCam else { return }
        if demoT0 == 0 { demoT0 = now }
        let t = now - demoT0 - 1.5
        if t < 0 || demoStep >= 8 { return }
        let size = stage.bounds.size
        let A = ObjectIdentifier(self)
        let B = ObjectIdentifier(stage)
        func at(_ r: Double, _ u: Double) -> CGPoint {
            let o = demoOffset(r, u); return CGPoint(x: demoAnchor.x + o.x, y: demoAnchor.y + o.y)
        }
        // step durations (s)
        let durs: [Double] = [4.2, 4.0, 5.2, 3.6, 2.5, 5.5, 7.0, 0.1]
        let s = t - demoStepT0
        switch demoStep {
        case 0: // apex: stretch him tall (up + sideways), release, wobble
            if !demoFresh { demoFresh = true; NSLog("[bob] demo: a) grab apex, stretch up and sideways"); demoBegin(demoPos(demoApexIndex()), size, A) }
            if s < 1.8 { let k = demoSmooth(s / 1.2); pointerMove(id: A, point: at(-0.35 * k, 0.55 * k), size: size) }
            else if s < 1.85 { pointerUp(id: A); NSLog("[bob] demo: a) release, wobble") }
        case 1: // side wiggle
            if !demoFresh { demoFresh = true; NSLog("[bob] demo: b) grab side, wiggle"); demoBegin(demoPos(demoSideIndex()), size, A) }
            if s < 2.0 { let k = sin(4 * Double.pi * s / 2.0) * demoSmooth(s / 0.3); pointerMove(id: A, point: at(0.5 * k, 0), size: size) }
            else if s < 2.05 { pointerUp(id: A); NSLog("[bob] demo: b) release, wobble") }
        case 2: // top: lift + two-finger twist
            if !demoFresh { demoFresh = true; NSLog("[bob] demo: c) grab top, lift, twist"); demoBegin(demoPos(demoApexIndex()), size, A) }
            if s < 0.9 { let k = demoSmooth(s / 0.8); pointerMove(id: A, point: at(0, 0.45 * k), size: size) }
            else if s < 3.1 {
                let center = at(0, 0.45), rad = 90.0
                func f(_ th: Double) -> CGPoint { CGPoint(x: center.x + rad * cos(th), y: center.y + rad * sin(th)) }
                if second == nil { pointerDown(id: B, point: f(0), size: size) }
                let u = (s - 0.9) / 2.0
                // 0 -> +1.0 -> -1.0 -> 0 over 2 s
                let ang: Double
                if u < 0.25 { ang = demoSmooth(u / 0.25) }
                else if u < 0.75 { ang = 1 - 2 * demoSmooth((u - 0.25) / 0.5) }
                else { ang = -1 + demoSmooth((u - 0.75) / 0.25) }
                pointerMove(id: B, point: f(ang), size: size)
            } else if s < 3.15 { pointerUp(id: B); pointerUp(id: A); NSLog("[bob] demo: c) release both, wobble") }
        case 3: // orbit
            if !demoFresh {
                demoFresh = true; NSLog("[bob] demo: d) orbit camera")
                demoAnchor = CGPoint(x: size.width * 0.12, y: size.height * 0.88)
                pointerDown(id: A, point: demoAnchor, size: size)
            }
            if s < 3.0 {
                let u = s / 3.0
                let k = u < 0.5 ? demoSmooth(u / 0.5) : 1 - demoSmooth((u - 0.5) / 0.5)
                // azimuth change = -dx * 0.006; ~40deg = 0.70 rad -> dx = -116 px
                pointerMove(id: A, point: CGPoint(x: demoAnchor.x + 116 * k, y: demoAnchor.y), size: size)
            } else if s < 3.05 { pointerUp(id: A) }
        case 4: // nudge
            if !demoFresh { demoFresh = true; NSLog("[bob] demo: e) nudge"); model.nudge() }
        case 5: // squash: push the apex down toward the floor
            if !demoFresh { demoFresh = true; NSLog("[bob] demo: f) grab apex, push down to squash"); demoBegin(demoPos(demoApexIndex()), size, A) }
            if s < 2.5 { let k = demoSmooth(s / 1.6); pointerMove(id: A, point: at(0, -0.5 * k), size: size) }
            else if s < 2.55 { pointerUp(id: A); NSLog("[bob] demo: f) release, settle") }
        case 6: // hop around for a few seconds
            if !demoFresh { demoFresh = true; NSLog("[bob] demo: g) hop around"); model.hopping = true }
            if s > 6.6 && model.hopping { model.hopping = false; NSLog("[bob] demo: g) stop hopping") }
        default:
            NSLog("[bob] demo: ended"); fflush(stdout)
        }
        if s >= durs[demoStep] { demoStep += 1; demoStepT0 = t; demoFresh = false }
    }
    #endif
}
