//
//  PlayToss.swift
//  Play mode's ball game (user 2026-11-02: "like Paper Toss on iOS ... I slide my finger and it goes to a Jelbie and they bounce it back ... not like fetch").
//
//    inHand    the ball is held at the bottom of the screen; a finger drags it, the flick lets it go (TossAim: the swipe's direction + speed set where it lands, with a
//              gentle aim assist toward the Jelbie nearest the swipe).
//    flying    gravity, bounces, walls (TossBall). The Jelbie it is heading for steps a little to be under it, hops, and the ball meets his crown: a HEADER sends it back
//              toward the camera on an arc (a good one lands at the bottom of the screen: caught). A header can be a miss on purpose (short, or weak): then
//    loose     the ball is on the floor. A Jelbie trots round behind it and bump-kicks it toward the camera (BlobBrain+PlayToss, the soccer stomp); it takes a few nudges,
//              each one nearer the front (never fetch: nobody carries it). With two or three Jelbies the one who bumped may pass it to a friend, who then bumps it back.
//    catching  the ball reached the bottom of the screen: it settles into the hand (hearts, a chirp, a soft thump).
//  Everything the player feels (haptics, sounds, hearts) goes out as `PlayEvent`s (GameCare+Play.swift).
//

import Foundation
import Observation
import simd
import CoreGraphics

/// One Jelbie as the controller sees him.
@MainActor
struct PlayJelly {
    let id: Int
    let brain: BlobBrain
    let sim: SoftBody
    let skinner: Skinner
    /// A park visitor: heads and kicks the ball back when it comes to him, but is not placed on the play line.
    var free = false
    var pos: SIMD2<Float> { brain.position }
    /// The crown's height now (the body's centre + half the height: the squash, the hop and the wobble are in the centroid).
    var headTop: Float { sim.centroid().y + BobShape.H * 0.5 }
}

enum PlayEvent: Equatable {
    case release(speed: Float)
    case floorBounce(speed: Float)
    case header(id: Int, quality: PlayToss.Quality)
    case bodyBoop(id: Int)
    case kick(id: Int)
    case pass(from: Int, to: Int)
    case whiff(id: Int)
    case rescue
    case caught(rally: Int)
}

/// What the Jelmiko do with the ball before it goes back to the player (play-ball-s3): ONE place. `none` = the ball goes straight back; `passing` = a chain: the ball is on its way to `to` (a friend) and `left` more passes follow it. Later games of their own (keepy-uppy, shots at a net) are more cases here; `PlayToss.keeping` is derived from it.
enum OwnGame: Equatable {
    case none
    case passing(left: Int, from: Int, to: Int)
}

@MainActor
@Observable
final class PlayToss {
    enum Phase: Equatable { case off, inHand, flying, loose, catching, toy }
    enum Quality: Equatable { case good, short, weak }

    // MARK: observed state (the UI)
    private(set) var phase: Phase = .off
    /// The Jelmiko have the ball and are passing it among themselves (the "Pass it back" button shows). Never true with one Jelmiko.
    private(set) var ownGame: OwnGame = .none
    var keeping: Bool { if case .passing = ownGame { return true }; return false }
    var active: Bool { phase != .off }
    /// The ball game is on (the Jelbies are held to their play line); a non-ball toy (the bubble wand, `.toy`) leaves them free.
    var ballGame: Bool { active && phase != .toy }
    private(set) var ballKind: DecorKind = .ball
    private(set) var toyTitle = ""
    /// Rally of the last throw (hand-offs between a Jelbie and the ball), shown as a small "x3" for a moment after a catch.
    private(set) var rally = 0
    private(set) var shownRally = 0
    private(set) var catchSerial = 0
    private(set) var throwSerial = 0

    // MARK: not observed (per-frame)
    @ObservationIgnored var ball = TossBall(pos: SIMD3(0, 0.27, 3), radius: 0.27)
    @ObservationIgnored private(set) var camBlend: Float = 0
    @ObservationIgnored private(set) var camGoal: Float = 0
    @ObservationIgnored var viewSize = CGSize(width: 393, height: 852)
    @ObservationIgnored var jellies: [PlayJelly] = []
    @ObservationIgnored var onEvent: ((PlayEvent) -> Void)?
    /// The finger is on the ball (view points); nil = the ball rests in the hand's spot.
    @ObservationIgnored var finger: CGPoint?
    @ObservationIgnored private(set) var nudges = 0
    @ObservationIgnored private(set) var looseT: Float = 0
    @ObservationIgnored private(set) var flightT: Float = 0
    @ObservationIgnored private(set) var headers = 0
    @ObservationIgnored private(set) var rescues = 0
    @ObservationIgnored private(set) var passes = 0
    @ObservationIgnored private(set) var leftHand = false
    /// A Jelbie has touched the ball since the throw (a header or a bump): only then does a fast ball at the front count as caught.
    @ObservationIgnored private(set) var touched = false
    @ObservationIgnored private var catchFrom = SIMD3<Float>.zero
    @ObservationIgnored private var catchT: Float = 0
    @ObservationIgnored private var bumper: Int?
    @ObservationIgnored private var passTo: Int?
    /// play-ball-s2: this flight is played by foot (rolled once per flight from `PlayTuning.style`), who has the foot plan (the kick spot, the direction), and when the ball first got down to kick height.
    @ObservationIgnored private(set) var footFlight = false
    @ObservationIgnored private var footChoice: Int?
    @ObservationIgnored private var footPlan: [Int: (spot: SIMD2<Float>, dir: SIMD2<Float>, planned: Float, until: Float)] = [:]
    @ObservationIgnored private var kickHeightT: Float?
    /// The passes this throw is meant to make before the ball goes back (rolled at the throw from the style: 0 = none) and when the player asked for it back.
    @ObservationIgnored private(set) var pendingPasses = 0
    @ObservationIgnored private var recallAt: Float?
    @ObservationIgnored private var passPlan: (to: Int, spot: SIMD2<Float>, dir: SIMD2<Float>, until: Float)?
    @ObservationIgnored private var footAimed = false          // (the throw was aimed at his feet: a header fallback cannot meet it, so the plan is held to the last moment)
    /// Where a good return is meant to come down (the catch zone), and the steering assist that eases it there; the seconds the loose ball has lain still.
    @ObservationIgnored private var returnAim: SIMD2<Float>?
    @ObservationIgnored private var restT: Float = 0
    @ObservationIgnored private var bumpNeeded = false
    @ObservationIgnored private var interceptAt: [Int: (p: SIMD2<Float>, t: Float)] = [:]
    @ObservationIgnored private var saved: [Int: (reserved: Bool, idleBlocked: Bool, waitFocus: SIMD2<Float>?)] = [:]
    @ObservationIgnored private var rng: UInt64 = 0x9E3779B97F4A7C15
    @ObservationIgnored private(set) var clock: Float = 0
    /// For tests: pins the header quality (nil = rolled).
    @ObservationIgnored var forceQuality: Quality?
    @ObservationIgnored var spots: [Int: SIMD2<Float>] = [:]
    /// Each Jelbie's place on the play line (by id) and when he was last sent back to it.
    @ObservationIgnored private var home: [Int: SIMD2<Float>] = [:]
    @ObservationIgnored private var homeT: [Int: Float] = [:]
    @ObservationIgnored private var turnT: [Int: Float] = [:]

    nonisolated deinit {}

    // MARK: tuning
    static let kickReach: Float = 1.15
    static let handScreen = CGPoint(x: 0.5, y: 0.87)
    static let interceptReach: Float = 1.9
    static let looseWaitSpeed: Float = 1.3
    static let rescueAfter: Float = 6
    /// A loose ball resting where nobody is sending it back for this long is lobbed to the hand (user 2026-11-07: > 2 s unreachable).
    static let restRescueAfter: Float = 2
    static let passChance: Float = 0.16
    /// play-ball-s2: seconds from the go to the planned kick's foot landing (wind-up 0.18 + the stomp to its landing), the ball's kick height above the floor (centre), and how far in front of his centre the ball is met (just outside his body's circle).
    static let footLead: Float = 0.42
    static let kickHeightAbove: Float = 0.30
    static func contactDist(_ r: Float) -> Float { TossTuning.bodyRadius + r + 0.08 }

    private func rand() -> Float {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Float(rng >> 40) / Float(1 << 24)
    }
    func seed(_ s: UInt64) { rng = s | 1 }

    /// The ball's side walls: half the width at depth `z`. Play mode: the play view's (the ball stays in frame); `-PlayOld 1`: the visible floor's, as it was.
    static func ballXHalf(_ z: Float) -> Float { GameCamera.playBallHalf(z: z) ?? (DecorPlacement.visibleHalf(z: z) + 0.3) }
    /// The same without the old extra 0.3 (the landing ring, the targets).
    static func ballReach(_ z: Float) -> Float { GameCamera.playBallHalf(z: z) ?? DecorPlacement.visibleHalf(z: z) }
    /// The most |x| a Jelmiko's centre may have at depth `z` while he plays: the play floor's row; the old rule outside the frame.
    static func bodyReach(_ z: Float) -> Float {
        if GameCamera.playFrame, !PlayTuning.old, let f = GameCamera.roamFloor { return f.halfWidth(at: z) }
        return DecorPlacement.visibleHalf(z: z) - 0.8
    }
    /// The z range a Jelmiko's centre may have while he plays.
    static func bodyZ() -> ClosedRange<Float> {
        if GameCamera.playFrame, !PlayTuning.old, let f = GameCamera.roamFloor { return f.minZ ... f.maxZ }
        return TossTuning.zBack + 1.2 ... 9
    }

    // the frame (GameCamera.playFrame): the floor the Jelmiko play on is what the play camera shows
    @ObservationIgnored private var frameSaved: (floor: GameCamera.RoamFloor?, walls: [RoomLayout.Plane], arena: (c: SIMD2<Float>, r: Float), hudRevision: Int, stageAspect: Float, viewAspect: Float)?
    @ObservationIgnored private var frameAspect: Float = 0
    private var viewAspect: Float { Float(viewSize.width / max(viewSize.height, 1)) }
    private func frameOn() {
        guard !PlayTuning.old, GameCamera.parkRoamMaxZ == nil else { return }
        if frameSaved == nil { frameSaved = (GameCamera.roamFloor, RoomLayout.walls, (GameCamera.arenaCenter, GameCamera.arenaRadius), HUDLayout.measuredRevision, GameCamera.aspect, viewAspect); logFrame("before") }
        GameCamera.playFrame = true
        frameAspect = viewAspect
        GameCamera.refreshRoam(aspect: frameAspect)
        frontWall()
        logFrame("during")
    }
    /// Capture aid (simulator, `-PlayDemo`): the room's safety wall, front wall and floor before / during / after play.
    private func logFrame(_ tag: String) {
        #if targetEnvironment(simulator)
        guard DevArgs.enabled, UserDefaults.standard.integer(forKey: "PlayDemo") > 0 else { return }
        let f = GameCamera.roamFloor
        NSLog("[playtoss] walls %@: arena (%.2f, %.2f) r %.2f | front wall z %.2f | floor z %.2f...%.2f rows %d", tag, GameCamera.arenaCenter.x, GameCamera.arenaCenter.y, GameCamera.arenaRadius, -(RoomLayout.walls.count > 1 ? RoomLayout.walls[1].d : 0), f?.minZ ?? 0, f?.maxZ ?? 0, f?.zs.count ?? 0)
        #endif
    }
    /// The ball's front wall: the floor at the bottom of the play view (the ball is never left off the bottom edge); the room's 9 as before when the dial is 1.
    private func frontWall() {
        let was = GameCamera.playBlend
        GameCamera.playBlend = 1; defer { GameCamera.playBlend = was }
        guard let f = GameCamera.floorPoint(screen: CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.94), size: viewSize) else { return }
        TossTuning.zFront = min(9, max(f.y, catchZ() + 0.6))
    }
    private func frameOff() {
        GameCamera.playFrame = false; GameCamera.playFrameView = nil
        guard let s = frameSaved else { return }
        frameSaved = nil
        // the saved room floor is put back only when nothing it was built from changed during play: the same view shape AND the same measured HUD (the stage rebuilds the floor when the
        // HUD's rails move or the phone turns, and during play that rebuild is the PLAY floor, so the stage would never rebuild the room's: it is rebuilt here instead, for the STAGE's
        // aspect (the play overlay can be narrower than the stage: the safe area; a turn swaps the stage's width and height as it does the overlay's)
        let turned = abs(frameAspect - s.viewAspect) > 0.005
        let stageNow = turned ? s.stageAspect * frameAspect / max(s.viewAspect, 0.01) : s.stageAspect
        if s.floor == nil || (!turned && s.hudRevision == HUDLayout.measuredRevision) {
            GameCamera.roamFloor = s.floor; RoomLayout.walls = s.walls; GameCamera.arenaCenter = s.arena.c; GameCamera.arenaRadius = s.arena.r
        } else { GameCamera.refreshRoam(aspect: stageNow) }
        GameCamera.aspect = stageNow
        logFrame("after")
    }

    // MARK: begin / end

    /// Play mode on with `kind`: the Jelbies take their places, the camera eases to the play view, the ball is in the hand.
    func begin(ball kind: DecorKind, title: String, jellies js: [PlayJelly], snapCamera: Bool = false) {
        guard phase == .off else { return }
        ballKind = kind; toyTitle = title
        if UserDefaults.standard.integer(forKey: "PlayDemo") > 0, let q = UserDefaults.standard.string(forKey: "PlayDemoQuality") { forceQuality = q == "weak" ? .weak : (q == "short" ? .short : .good) }
        if UserDefaults.standard.integer(forKey: "PlayDemo") > 0, UserDefaults.standard.object(forKey: "PlayDemoSeed") != nil { seed(UInt64(max(UserDefaults.standard.integer(forKey: "PlayDemoSeed"), 1))) }          // (capture aid: the same rolls every take)
        ball = TossBall(pos: SIMD3(0, kind.rollRadius, 3), radius: kind.rollRadius)
        jellies = js
        phase = .inHand
        rally = 0; shownRally = 0; nudges = 0; looseT = 0; bumper = nil; passTo = nil; finger = nil; leftHand = false
        ownGame = .none; pendingPasses = 0; passPlan = nil; recallAt = nil
        camGoal = 1
        if snapCamera { camBlend = 1; GameCamera.playBlend = 1 }
        frameOn()
        placeJellies()
    }

    /// Play mode on with a toy that is not the ball (the bubble wand): the camera eases to the play view, HUD hidden, Done shown; the Jelbies stay free.
    func beginToy(title: String, snapCamera: Bool = false) {
        guard phase == .off else { return }
        toyTitle = title; jellies = []
        phase = .toy
        camGoal = 1
        if snapCamera { camBlend = 1; GameCamera.playBlend = 1 }
        frameOn()
    }

    /// Done: the Jelbies go back to roaming, the camera eases home.
    func end() {
        guard phase != .off else { return }
        phase = .off
        ownGame = .none; pendingPasses = 0; passPlan = nil
        camGoal = 0
        finger = nil
        release(jellies)
        jellies = []
        frameOff()
    }

    private func release(_ js: [PlayJelly]) {
        for j in js {
            let b = j.brain
            if let s = saved[j.id] { b.reserved = s.reserved; b.idleBlocked = s.idleBlocked; b.waitFocus = s.waitFocus } else { b.reserved = false }
            b.trackPoint = nil; b.tossFire = nil; b.playChase = 0
        }
        saved = [:]
        interceptAt = [:]
        RoomLayout.ballSpheres.removeAll { $0.uid == Self.sphereUID }
    }
    static let sphereUID = -7001

    /// Where the Jelbies stand to play: abreast on a line across the floor, the nearest one to the middle in front.
    func placeJellies() {
        let line = jellies.filter { !$0.free }
        spots = Self.playSpots(count: line.count, size: viewSize)
        let order = line.sorted { $0.pos.x < $1.pos.x }
        for (k, j) in order.enumerated() {
            saved[j.id] = (j.brain.reserved, j.brain.idleBlocked, j.brain.waitFocus)
            j.brain.reserved = true; j.brain.idleBlocked = true
            let sp = spots[k] ?? .zero
            home[j.id] = sp; homeT[j.id] = clock
            j.brain.requestNow(.goTo(sp))
        }
    }

    /// The play line: where each Jelbie stands, from the play view itself (screen fractions across the floor at a fixed screen height), so the row is framed whatever the aspect.
    static func playSpots(count n: Int, size: CGSize) -> [Int: SIMD2<Float>] {
        let fx: [Float]
        let land = size.width > size.height
        switch n { case 0: fx = []; case 1: fx = [0.5]; case 2: fx = land ? [0.4, 0.6] : [0.3, 0.7]; default: fx = land ? [0.33, 0.5, 0.67] : [0.27, 0.5, 0.73] }
        let was = GameCamera.playBlend
        GameCamera.playBlend = 1; defer { GameCamera.playBlend = was }
        var out: [Int: SIMD2<Float>] = [:]
        // (the row stands where it always stood on the FLOOR: the old play camera put the middle of the screen there. With the dial lower the screen's middle is the far back
        // wall, so the row's depth is taken from the old view and only its width from the camera in use, at the same screen fractions across)
        let rowZ: [Int: Float]? = {
            guard !PlayTuning.old, PlayTuning.camZoom < 1 else { return nil }
            let zoom = PlayTuning.zoomOverride; defer { PlayTuning.zoomOverride = zoom }
            PlayTuning.zoomOverride = 1
            var z: [Int: Float] = [:]
            for (k, f) in fx.enumerated() {
                let sy: CGFloat = (k == 1 && n >= 3) ? 0.46 : 0.50
                if let p = GameCamera.floorPoint(screen: CGPoint(x: size.width * CGFloat(f), y: size.height * sy), size: size) { z[k] = p.y }
            }
            return z
        }()
        for (k, f) in fx.enumerated() {
            var sy: CGFloat = (k == 1 && n >= 3) ? 0.46 : 0.50          // (the middle one a touch further back: a shallow arc)
            if let z0 = rowZ?[k] {
                // (the wide view puts the hand further from the row than the old view did: the row stands `rowForward` nearer so the ball's trips keep their length)
                let z = min(z0 + PlayTuning.rowForward, (GameCamera.roamFloor?.maxZ ?? 9) - 0.3)
                if let s = GameCamera.screenPoint(floor: SIMD2(0, z), size: size) { sy = s.y / size.height }
            }
            if let p = GameCamera.floorPoint(screen: CGPoint(x: size.width * CGFloat(f), y: size.height * sy), size: size) { out[k] = p }
        }
        return out
    }

    // MARK: the hand

    /// The screen point the ball sits at / follows.
    func handPoint() -> CGPoint {
        if let f = finger { return CGPoint(x: min(max(f.x, 0), viewSize.width), y: min(max(f.y, viewSize.height * 0.40), viewSize.height * 0.97)) }
        return CGPoint(x: viewSize.width * Self.handScreen.x, y: viewSize.height * Self.handScreen.y)
    }
    func handWorld() -> SIMD3<Float> {
        TossAim.hand(at: handPoint(), size: viewSize) ?? SIMD3(0, TossTuning.handHeight, 3)
    }
    /// The z the ball must reach to count as back in the hand: the floor under the bottom band of the screen.
    func catchZ() -> Float {
        let p = CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.80)
        return min(max(GameCamera.floorPoint(screen: p, size: viewSize)?.y ?? 3.2, 1.8), PlayTuning.old ? 5 : 9)          // (a wider view puts the bottom band further out: the old cap of 5 made the catch a long zip to the hand)
    }

    // MARK: the flick

    /// The finger let go. A flick throws; a slow release drops the ball where it was held.
    func flick(_ f: TossFlick) {
        guard phase == .inHand, camBlend > 0.85 else { return }
        finger = nil
        let bodies = jellies.map { TossBody(id: $0.id, pos: $0.pos, top: $0.headTop) }
        guard var t = TossAim.throwFor(f, bodies: bodies, radius: ball.radius) else { return }
        // the ball starts in the hand (never behind the camera or inside the catch band's far edge)
        t.start.y = max(t.start.y, ball.radius + 0.2)
        let foot = rollFoot()
        footAimed = false
        var v = t.velocity
        // play-ball-s2: a ball that is played by foot is thrown to come down at his feet, just in front of him on the player's side, not at his crown (the gentle nudge cannot move a ball two units, and the one it is heading for should not have to walk backwards with his back to the room)
        if foot, t.flight > 0, let id = t.assistedBody, let b = jelly(id), let tv = footThrow(from: t.start, flight: t.flight, to: b) { v = tv; footAimed = true }
        letGo(from: t.start, velocity: v, foot: foot)
    }

    /// The seeded roll for one incoming flight: by foot (1 - headShare) or by head. No roll for a ball that is always headed (the bouncy ball keeps its random stream).
    func rollFoot() -> Bool {
        guard !PlayTuning.ballReturnOld, !jellies.isEmpty else { return false }
        let h = PlayTuning.style(ballKind).headShare
        guard h < 1 else { return false }
        return rand() >= h
    }

    /// How many passes this throw makes before the ball goes back (play-ball-s3): `style.chainChance` of the balls, 1...`chainMax` passes; none with one Jelmiko and none for a ball that is always headed straight back (their random stream is untouched).
    private func rollChain() -> Int {
        guard !PlayTuning.ballReturnOld, jellies.filter({ !$0.free }).count >= 2 else { return 0 }
        let st = PlayTuning.style(ballKind)
        guard st.headShare < 1, st.chainMax > 0 else { return 0 }
        guard rand() < st.chainChance else { return 0 }
        return min(st.chainMax, 1 + Int(rand() * Float(st.chainMax)))
    }

    private func footThrow(from start: SIMD3<Float>, flight T: Float, to b: PlayJelly) -> SIMD3<Float>? {
        let r = ball.radius
        let pp = playerPoint()
        let d = pp - b.pos
        guard simd_length(d) > 1e-3 else { return nil }
        var spot = b.pos + simd_normalize(d) * Self.contactDist(r)
        let lim = Self.ballReach(spot.y) - r - 0.1
        spot.x = min(max(spot.x, -lim), lim)
        spot.y = min(spot.y, catchZ() - 0.8)
        return TossAim.ballistic(from: start, to: SIMD3(spot.x, r + Self.kickHeightAbove, spot.y), flight: T)
    }

    /// Test / capture entry: the ball is let go at `start` with `velocity` exactly as a flick would (a roll or a low pass a finger cannot throw is made this way).
    func launch(from start: SIMD3<Float>, velocity v: SIMD3<Float>) {
        guard phase == .inHand else { return }
        finger = nil
        footAimed = false
        letGo(from: start, velocity: v, foot: rollFoot())
    }

    private func letGo(from start: SIMD3<Float>, velocity v: SIMD3<Float>, foot: Bool = false) {
        footFlight = foot; footChoice = nil; footPlan = [:]; kickHeightT = nil
        ownGame = .none; passPlan = nil; recallAt = nil; pendingPasses = rollChain()
        if UserDefaults.standard.integer(forKey: "PlayDemo") > 0 { NSLog("[playchain] throw=%d planned=%d foot=%d", throwSerial + 1, pendingPasses, foot ? 1 : 0) }
        ball.pos = start; ball.vel = v; ball.floorBounces = 0; ball.ignoring = nil
        phase = .flying
        rally = 0; nudges = 0; looseT = 0; flightT = 0; leftHand = false; touched = false; bumper = nil; passTo = nil; headers = 0; rescues = 0; passes = 0
        throwSerial += 1
        returnAim = nil; restT = 0
        onEvent?(.release(speed: simd_length(v)))
    }

    /// Lets go at `p` with `v` (points / second). Test and capture entry point for `flick`.
    func flick(from p: CGPoint, velocity v: CGVector) { flick(TossFlick(release: p, velocity: v, size: viewSize)) }

    // MARK: tick

    func tick(dt: Float, world: TossWorld, jellies js: [PlayJelly]) {
        clock += dt
        // the camera ease
        if camGoal != camBlend {
            if A11ySettings.shared.reduceMotion { camBlend = camGoal } else { camBlend += (camGoal - camBlend) * min(1, dt * 4.2); if abs(camGoal - camBlend) < 0.004 { camBlend = camGoal } }
            GameCamera.playBlend = camBlend
        }
        guard active else { return }
        jellies = js
        if GameCamera.playFrame, abs(viewAspect - frameAspect) > 0.005 { reframe() }          // (the phone was turned: the frame is the new view's)
        switch phase {
        case .inHand:
            ball.pos = handWorld(); ball.vel = .zero
            ball.pos.y = max(ball.pos.y, ball.radius + 0.2)
            watch(ball.pos)
            rehome()
        case .catching:
            catchT += dt
            let k = min(1, catchT / 0.28), e = k * k * (3 - 2 * k)
            let h = handWorld()
            ball.pos = catchFrom + (h - catchFrom) * e + SIMD3(0, 0.25 * sinf(.pi * k), 0)
            ball.rot = simd_normalize(simd_quatf(angle: dt * 6, axis: SIMD3(1, 0, 0)) * ball.rot)
            if k >= 1 { phase = .inHand; finger = nil }
        case .flying, .loose:
            live(dt: dt, world: world)
        case .off, .toy: break
        }
        // a live ball: they go for it a little faster (PlayTuning.chaseGain; -PlayOld 1 = the old walk)
        let chase: Float = (!PlayTuning.old && (phase == .flying || phase == .loose)) ? PlayTuning.chaseGain : 0
        for j in jellies where j.brain.playChase != chase { j.brain.playChase = chase }
        // the ball is a soft obstacle for the walkers (nobody walks through it)
        RoomLayout.ballSpheres.removeAll { $0.uid == Self.sphereUID }
        if (phase == .flying || phase == .loose), ball.pos.y < 0.9 { RoomLayout.ballSpheres.append(BallSphere(c: SIMD2(ball.pos.x, ball.pos.z), r: ball.radius, uid: Self.sphereUID)) }
    }

    /// The view changed shape: the play floor is rebuilt and the Jelmiko on the line walk to their new places.
    private func reframe() {
        frameAspect = viewAspect
        GameCamera.refreshRoam(aspect: frameAspect)
        frontWall()
        let line = jellies.filter { !$0.free }
        spots = Self.playSpots(count: line.count, size: viewSize)
        for (k, j) in line.sorted(by: { $0.pos.x < $1.pos.x }).enumerated() {
            let sp = spots[k] ?? .zero
            home[j.id] = sp; homeT[j.id] = clock
            if !j.brain.tossBusy { j.brain.requestNow(.goTo(sp)) }
        }
    }

    /// Back in the hand: a Jelbie who stepped away to meet the ball strolls back to his place on the line.
    private func rehome() {
        for j in jellies where !j.brain.tossBusy {
            guard let h = home[j.id], simd_distance(j.pos, h) > 0.7, clock - (homeT[j.id] ?? -9) > 1.5, Self.canHop(j.brain) else { continue }
            homeT[j.id] = clock
            j.brain.requestNow(.goTo(h))
        }
    }

    /// Every Jelbie keeps turning to the ball (the waiting pose); the one under it keeps his own legs.
    private func watch(_ p: SIMD3<Float>) {
        for j in jellies {
            // play-ball-r2: the head follows the ball everywhere, but the BODY keeps facing the player (a ball that flew past him to the back wall, or sideways along the row, turned the outer ones right round and the next ball found them 60-80 degrees off)
            let body: SIMD2<Float> = PlayTuning.ballReturnOld ? SIMD2(p.x, p.z) : playerPoint()          // (the ball sweeps past the outer ones sideways: a body that turned to it was 75-80 degrees off the player when it arrived)
            var look = SIMD2(p.x, p.z)
            if !PlayTuning.ballReturnOld {          // (the head follows the ball while it is within about 45 degrees of the player's line from him; past that his look turns his whole body toward it, and the ball sweeping past the outer ones in landscape found them 75-80 degrees round)
                let a = look - j.pos, b = playerPoint() - j.pos
                if simd_length(a) > 1e-3, simd_length(b) > 1e-3, simd_dot(a, b) < 0.7 * simd_length(a) * simd_length(b) { look = playerPoint() }
            }
            j.brain.trackPoint = look; j.brain.waitFocus = body
            // turned well away from it (he walked back to his place with his back to the room): he turns to watch it, on the spot
            guard !j.brain.tossBusy, Self.canHop(j.brain), j.brain.idleState.kind == nil, case .none = j.brain.script, clock - (turnT[j.id] ?? -9) > 0.7 else { continue }
            let want = j.brain.yawTo(body)
            if abs(wrapAngle(want - j.brain.yaw)) > 0.5 { turnT[j.id] = clock; j.brain.startTurn(to: want, sim: j.sim) }
        }
    }

    private func live(dt: Float, world w: TossWorld) {
        flightT += dt
        var world = w
        world.bodies = jellies.map { TossBody(id: $0.id, pos: $0.pos, top: $0.headTop) }
        let before = ball.pos
        let events = ball.step(dt, in: world)
        for j in jellies where !j.brain.tossBusy && !j.brain.feet.active && j.brain.idleState.kind == nil { standTop[j.id] = j.headTop }
        if !PlayTuning.ballReturnOld { for o in jellies { let P = playerPoint() - o.pos; o.brain.tossFaceYaw = (o.brain.tossBusy && simd_length(P) > 1e-3) ? atan2f(P.x, P.y) : nil } }          // (the header's hop turns him toward the player in the air)
        watch(ball.pos)
        if simd_distance(ball.pos, handWorld()) > 1.5 || ball.pos.z < catchZ() - 0.6 { leftHand = true }
        var headed = false
        for e in events {
            switch e {
            case .floorBounce(let s):
                if kickHeightT == nil { kickHeightT = clock }
                onEvent?(.floorBounce(speed: s))
                if phase == .flying { phase = .loose; looseT = 0 }
            case .bodyHit(let id, let s):
                // play-ball-s2: any contact with the Jelmiko who is set to kick it is a strike, not a soft bounce
                if footFlight || footChoice != nil, let kj = jelly(id), ball.pos.y < ball.radius + 0.9, !PlayTuning.ballReturnOld, kj.brain.tossFootApproach || !kj.brain.tossBusy {
                    strikeByContact(kj)
                    break
                }
                if s > 0.9 { onEvent?(.bodyBoop(id: id)) }
                if UserDefaults.standard.integer(forKey: "PlayDemo") > 0, let j = jelly(id) { NSLog("[playsoft] clock=%.3f throw=%d id=%d speed=%.2f ballY=%.2f headTop=%.2f idle=%@ stage=%d phase=%@", clock, throwSerial, id, s, ball.pos.y, j.headTop, String(describing: j.brain.idleState.kind), j.brain.idleState.toss.stage, String(describing: phase)) }
                if phase == .flying { phase = .loose; looseT = 0 }
            case .headHit(let id):
                if !headed { headed = true; header(by: id) }
            case .wall: break
            }
        }
        if ball.resting || (ball.onFloor && phase == .flying) { if phase == .flying { phase = .loose; looseT = 0 } }
        if kickHeightT == nil, ball.pos.y <= ball.radius + Self.kickHeightAbove + 0.02, ball.vel.y <= 0.3, ball.ignoring == nil { kickHeightT = clock }
        if passPlan != nil { preparePassReceiver() }
        if !PlayTuning.ballReturnOld, footFlight || footChoice != nil { footTick() }
        // back at the bottom of the screen: caught
        if leftHand, ball.pos.z > catchZ(), ball.pos.y < 2.6, (ball.vel.z > -0.2 || ball.onFloor), ball.ignoring == nil, touched || ball.speedXZ < 1.0 {
            caught(); return
        }
        if phase == .loose { for o in jellies where o.brain.tossHeaderApproach && o.brain.idleState.toss.stage < 4 { o.brain.tossHeaderRelease(o.sim, o.skinner) } }          // (a ball on the floor: nobody holds a header stand for it)
        if phase != .flying { headChoice = nil }
        if phase == .flying { steerReturn(dt: dt); intercepts(dt: dt, before: before) }
        restWatch(dt: dt)
        if phase == .loose { looseT += dt; loose(dt: dt) }
    }

    /// A hop may start now: not mid-step and not on a walk (he arrives first).
    static func canHop(_ b: BlobBrain) -> Bool {
        if b.feet.active { return false }
        if case .walk = b.script { return false }
        return true
    }

    /// Capture aid (`-PlayDemo`): one line per strike with the striker's visible facing error toward the player (the hand), its lift and the screen points for cutting pictures.
    private func touchLog(_ kind: String, _ j: PlayJelly) {
        guard UserDefaults.standard.integer(forKey: "PlayDemo") > 0 else { return }
        let hand = handWorld()
        let toHand = SIMD2(hand.x - j.pos.x, hand.z - j.pos.y)
        let to = playerPoint() - j.pos
        let ys = j.sim.yaw()
        let fwd = SIMD2<Float>(sinf(ys), cosf(ys))
        let err = acosf(max(-1, min(1, simd_dot(fwd, to) / max(simd_length(to), 1e-4)))) * 180 / .pi
        // what the eye sees: in a jump the body's heading is the hop's attractor (the root heading `brain.yaw` is not updated in the air and `sim.yaw()` reads the soft body's tilt as turn)
        let af = j.sim.attractor.rotation.act(SIMD3<Float>(0, 0, 1))
        let vy = j.brain.idleState.kind == .tossHeader ? atan2f(af.x, af.z) : j.brain.yaw
        let visErr = abs(wrapAngle(atan2f(to.x, to.y) - vy)) * 180 / .pi
        let sz = viewSize
        let js = GameCamera.screenPoint(floor: j.pos, y: j.sim.centroid().y, size: sz) ?? .zero
        let bs = GameCamera.screenPoint(floor: SIMD2(ball.pos.x, ball.pos.z), y: ball.pos.y, size: sz) ?? .zero
        NSLog("[playtouch] clock=%.3f throw=%d ball=%@ kind=%@ id=%d face=%.1f brainYawErr=%.1f visErr=%.1f handErr=%.1f yaw=%.0f pl=%.1f,%.1f pos=%.1f,%.1f centroidY=%.3f headTop=%.3f idle=%@ stage=%d rise=%.3f jellyScr=%.0f,%.0f ballScr=%.0f,%.0f view=%.0fx%.0f planned=%d since=%.2f",
              clock, throwSerial, ballKind == .soccerball ? "soccer" : (ballKind == .beachball ? "beach" : "bouncy"), kind, j.id, err,
              abs(wrapAngle(atan2f(to.x, to.y) - j.brain.yaw)) * 180 / .pi, visErr, abs(wrapAngle(atan2f(toHand.x, toHand.y) - vy)) * 180 / .pi, vy * 180 / .pi, playerPoint().x, playerPoint().y, j.pos.x, j.pos.y, j.sim.centroid().y, j.headTop, String(describing: j.brain.idleState.kind), j.brain.idleState.toss.stage, j.headTop - (standTop[j.id] ?? j.headTop), js.x, js.y, bs.x, bs.y, sz.width, sz.height, footPlan[j.id] != nil ? 1 : 0, kickHeightT.map { clock - $0 } ?? -1)
    }

    /// Where the player stands: the hand's spot (the flick's origin, the camera side).
    /// (play-ball-r2 step 1c) The player is the one looking: the camera's place on the floor, not the hand under it. In landscape the outer Jelmiko stand 3 u out and only 1 to 3 u in front of the hand, so a body facing the camera is 55-65 degrees off the line to the hand; to the eye it is the 15-20 degrees it looks. Everything that turns a body toward the player (the stand, the mid-air turn, the bodies that keep facing the player) uses this.
    func playerPoint() -> SIMD2<Float> {
        if PlayTuning.ballReturnOld { let h = handWorld(); return SIMD2(h.x, h.z) }
        let cam = GameCamera.camera(aspect: Float(viewSize.width / max(viewSize.height, 1)))
        let r = unproject(ndc: SIMD2<Float>(0, -1), invViewProj: cam.invViewProj)
        return SIMD2(r.o.x, r.o.z)
    }
    func handPlayerPoint() -> SIMD2<Float> { let h = handWorld(); return SIMD2(h.x, h.z) }
    /// The Jelmiko on the play line wait where they are while the ball game is on: GameCare+Dining's `reserved` (its wait pose, never a roam leg) is held for them.
    func holds(_ id: Int) -> Bool { ballGame && jellies.contains { $0.id == id && !$0.free } }

    // MARK: header

    private func jelly(_ id: Int) -> PlayJelly? { jellies.first { $0.id == id } }

    /// The ball is on `id`'s crown: it goes back toward the hand, with a quality.
    private func header(by id: Int) {
        guard let j = jelly(id) else { return }
        footFlight = false; footChoice = nil
        if j.brain.tossFootApproach { j.brain.tossFootRelease(j.sim, j.skinner) }
        var q: Quality = forceQuality ?? {
            let r = rand()
            return r < 0.74 ? .good : (r < 0.94 ? .short : .weak)
        }()
        // hitting a pass lands better: the friend meant it
        if passTo == id { q = .good }
        let from = ball.pos
        let hand = handWorld()
        let tz = catchZ() + 0.55
        let tx = min(max(hand.x * 0.5 + (rand() - 0.5) * 0.9, -(Self.ballReach(tz) - 0.9)), Self.ballReach(tz) - 0.9)
        let target = SIMD3<Float>(tx, TossTuning.handHeight, tz)
        returnAim = nil
        let styled = !PlayTuning.ballReturnOld && PlayTuning.style(ballKind).headShare < 1
        let anotherHead: PlayJelly? = styled ? nextHop(by: j) : ((passTo == nil && jellies.count > 1 && passes == 0 && rally >= 1 && rand() < Self.passChance) ? jellies.filter({ $0.id != id }).min(by: { simd_distance($0.pos, j.pos) < simd_distance($1.pos, j.pos) }) : nil)
        noteRecallStrike()
        var v: SIMD3<Float>
        if let o = anotherHead {
            let tgt = SIMD3<Float>(o.pos.x, o.headTop + ball.radius * 0.4, o.pos.y)
            v = TossAim.ballistic(from: from, to: tgt, flight: (0.75 + 0.05 * simd_distance(o.pos, j.pos)) * TossTuning.slow)
            passTo = o.id; passes += 1
            if styled { NSLog("[playpass] clock=%.3f throw=%d kind=head from=%d to=%d dist=%.2f", clock, throwSerial, id, o.id, simd_distance(o.pos, j.pos)) }
            onEvent?(.pass(from: id, to: o.id))
        } else {
            passTo = nil
            let dist = simd_length(SIMD2(target.x - from.x, target.z - from.z))
            switch q {
            case .good:
                let slope = PlayTuning.old ? 0.07 : PlayTuning.returnFlightSlope, cap = PlayTuning.old ? 1.25 : PlayTuning.returnFlightCap
                v = TossAim.ballistic(from: from, to: target, flight: (PlayTuning.ballReturnOld ? min(max(0.7 + slope * dist, 0.8), cap) : min(max(0.40 + 0.04 * dist, 0.55), 0.70)) * TossTuning.slow)          // (play-ball-r2: a flatter, quicker return that visibly leaves the head toward the player)
                returnAim = SIMD2(target.x, target.z)
            case .short:
                let k = 0.45 + 0.2 * rand()
                let tgt = SIMD3<Float>(from.x + (target.x - from.x) * k, ball.radius, from.z + (target.z - from.z) * k)
                let T = min(max(0.6 + 0.06 * dist * k, 0.7), 1.1) * TossTuning.slow
                v = TossAim.ballistic(from: from, to: tgt, flight: T)
                // it lands, bounces and rolls: aim the whole run (flight + bounce + roll) at the spot, not just the first landing
                v.x *= T / (T + 0.9 * TossTuning.slow); v.z *= T / (T + 0.9 * TossTuning.slow)
            case .weak:
                let a = (rand() - 0.5) * 2.4
                let d = SIMD2<Float>(sinf(a) * 0.6, 1)
                let tgt = SIMD3<Float>(from.x + d.x * 1.4, ball.radius, from.z + 1.5 + 0.5 * rand())
                v = TossAim.ballistic(from: from, to: tgt, flight: 0.55 * TossTuning.slow)
                v.x *= 0.55 / 1.45; v.z *= 0.55 / 1.45
            }
        }
        v.y = max(v.y, (PlayTuning.ballReturnOld ? 2.6 : 1.75) / TossTuning.slow)          // (play-ball-r2: a lower, quicker departure; seen from the room's camera a high slow one cancels its own move toward the player and the ball seems to hang on the crown)
        ball.vel = v
        ball.pos.y = max(ball.pos.y, j.headTop + ball.radius * 0.8)
        ball.ignoring = id; ball.ignoreT = 0.45
        rally += 1; headers += 1; touched = true; headChoice = nil
        phase = .flying
        looseT = 0
        touchLog("header", j)
        j.brain.jellyKick = max(j.brain.jellyKick, 2.2)
        if !j.brain.tossBusy, Self.canHop(j.brain) { let P = playerPoint() - j.pos; if simd_length(P) > 1e-3 { j.brain.tossFaceYaw = atan2f(P.x, P.y) }; j.brain.tossHeaderStart(j.sim, j.skinner, jump: !PlayTuning.ballReturnOld) }
        onEvent?(.header(id: id, quality: q))
    }

    /// A good return that is drifting off its mark is eased (a gentle pull on its sideways speed, never a snap) so it comes down in the catch zone.
    private func steerReturn(dt: Float) {
        guard let aim = returnAim, ball.ignoring == nil, ball.vel.y < 1.5 || ball.pos.y > 1.0 else { return }
        let g = TossTuning.gravity
        let y0 = ball.pos.y - TossTuning.handHeight
        let t = (ball.vel.y + (ball.vel.y * ball.vel.y + 2 * g * y0).squareRoot()) / g
        guard y0 > 0, t > 0.12 else { return }
        let want = (aim - SIMD2(ball.pos.x, ball.pos.z)) / t
        let cur = SIMD2(ball.vel.x, ball.vel.z)
        let n = cur + (want - cur) * min(1, dt * 5)
        ball.vel.x = n.x; ball.vel.z = n.y
    }

    /// Safety nets for a ball that lies where nobody sends it back: after 2 s it is lobbed to the hand; a dropped ball that never left the hand is simply caught.
    private func restWatch(dt: Float) {
        guard phase == .loose || phase == .flying else { restT = 0; return }
        if ball.onFloor, ball.speedXZ < 0.35, bumper == nil || !(jelly(bumper!)?.brain.tossBusy ?? false) { restT += dt } else { restT = 0 }
        guard restT > (leftHand ? (PlayTuning.old ? Self.restRescueAfter : PlayTuning.restRescue) : 0.8) else { return }
        restT = 0
        if !leftHand { caught(); return }
        rescue()
    }

    // MARK: ready steps (play-frame-r1: "when I throw it they run")

    @ObservationIgnored private var supportT: [Int: Float] = [:]
    /// The Jelmiko who are not the one going for the ball take a few steps toward where it will be (a step or two, at most `PlayTuning.supportReach` of the way, every
    /// 1.4 s at most), so a live ball moves all three, not one: they are in position for a pass and the next bump. `rehome` sends them back to the line once it is caught.
    private func support(toward xz: SIMD2<Float>, except: Set<Int>) {
        guard !PlayTuning.old else { return }
        for j in jellies where !j.free && !except.contains(j.id) {
            guard !j.brain.tossBusy, Self.canHop(j.brain), j.brain.idleState.kind == nil, clock - (supportT[j.id] ?? -9) > PlayTuning.supportEvery else { continue }
            let d = simd_distance(j.pos, xz)
            guard d > PlayTuning.supportMinDist, d < PlayTuning.supportMaxDist else { continue }
            let step = min((d - PlayTuning.supportMinDist) * PlayTuning.supportReach, PlayTuning.supportMaxStep)
            guard step >= PlayTuning.supportMinStep else { continue }          // (no shuffles: a step is worth walking)
            supportT[j.id] = clock
            j.brain.requestNow(.goTo(j.pos + (xz - j.pos) / d * step))
        }
    }

    // MARK: intercepts (the Jelbie it is heading for steps under it and hops)

    private func arrival(_ j: PlayJelly) -> (t: Float, xz: SIMD2<Float>)? {
        let g = TossTuning.gravity
        let yHead = j.headTop + ball.radius * 0.55
        let y0 = ball.pos.y - yHead, vy = ball.vel.y
        guard y0 > -0.05 else { return nil }
        let disc = vy * vy + 2 * g * max(y0, 0)
        let t = (vy + disc.squareRoot()) / g
        guard t > 0, t < 1.8 * TossTuning.slow else { return nil }
        return (t, SIMD2(ball.pos.x + ball.vel.x * t, ball.pos.z + ball.vel.z * t))
    }

    private func intercepts(dt: Float, before: SIMD3<Float>) {
        guard ball.ignoring == nil || ball.ignoreT < 0.2 else { return }
        if footFlight, !PlayTuning.ballReturnOld, footIntercepts() { return }
        var best: (j: PlayJelly, t: Float, xz: SIMD2<Float>, d: Float)?
        for j in jellies {
            guard let a = arrival(j) else { continue }
            let d = simd_distance(j.pos, a.xz)
            guard d < Self.interceptReach else { continue }
            if best == nil || d < best!.d { best = (j, a.t, a.xz, d) }
        }
        // the one already going for it keeps it (two Jelmiko about as near as each other must not hand it back and forth every step: each hand-over releases the other's stand and nobody gets there)
        if !PlayTuning.ballReturnOld, let c = headChoice, c != best?.j.id, let jc = jelly(c), let a = arrival(jc), simd_distance(jc.pos, a.xz) < Self.interceptReach { best = (jc, a.t, a.xz, simd_distance(jc.pos, a.xz)) }
        headChoice = best?.j.id
        if PlayTuning.ballReturnOld || best == nil {
            support(toward: ball.landing(xHalf: Self.ballReach)?.xz ?? SIMD2(ball.pos.x, ball.pos.z), except: [])
        }          // (play-ball-r2: while a ball is on its way to one Jelmiko the others stand: in landscape they are 3 u apart and walked across its path)
        guard let b = best else { for o in jellies where o.brain.tossHeaderApproach && o.brain.idleState.toss.stage < 4 { o.brain.tossHeaderRelease(o.sim, o.skinner) }; return }
        let j = b.j
        let busy = j.brain.tossBusy
        // where the ball is when it is at the crown's height at the jump's top (a fast, flat ball is a long way from where it crosses the standing crown's height: the stand and the nudge aim at THIS point)
        let mt = meetTime(j)
        let meetT = mt?.t ?? b.t
        let meetXZ: SIMD2<Float> = mt != nil ? SIMD2(ball.pos.x + ball.vel.x * meetT, ball.pos.z + ball.vel.z * meetT) : b.xz
        // play-ball-r2: the one it is heading for goes to where it will come down, turns onto the player, crouches and jumps so the crown meets it. NOTHING here decides whether the ball is
        // struck: that is `headHit` -> `header(by:)` as before; this only prepares the body (a late or unready Jelmiko still strikes it).
        if !busy, b.t > BlobBrain.tossCrouch + 0.1, !PlayTuning.ballReturnOld {
            let zr = Self.bodyZ(), zy = min(max(meetXZ.y, zr.lowerBound), max(min(catchZ() - 1.2, zr.upperBound), zr.lowerBound)), bx = Self.bodyReach(PlayTuning.old ? meetXZ.y : zy)
            let meet = SIMD2<Float>(min(max(meetXZ.x, -bx), bx), zy)
            // he comes within `Self.steerReach` of the meeting point and no nearer (the last bit is the ball's: see `steerOntoCrown`), so the walk is short and he has time to turn onto the player
            var stand = j.pos
            let off = meet - j.pos
            if simd_length(off) > Self.steerReach { stand = meet - off / simd_length(off) * (Self.steerReach * 0.6) }
            let dirP = playerPoint() - stand
            let dir = simd_length(dirP) > 1e-3 ? simd_normalize(dirP) : SIMD2<Float>(0, 1)
            j.brain.tossFire = nil
            if j.brain.tossBumpStart(j.sim, j.skinner, stand: stand, dir: dir, header: true) { interceptAt[j.id] = (meetXZ, clock) }
            else if b.d > 0.30, interceptAt[j.id] == nil || clock - interceptAt[j.id]!.t > 0.45 {          // (he is in the middle of something the stand cannot interrupt: as before he is sent walking at once, the stand follows next step)
                j.brain.requestNow(.goTo(stand)); interceptAt[j.id] = (meetXZ, clock)
            }
            if UserDefaults.standard.integer(forKey: "PlayDemo") > 0, Int(clock * 20) % 4 == 0 { NSLog("[playhead] clock=%.2f best=%d t=%.2f d=%.2f meetT=%.2f meet=(%.2f,%.2f) stand=(%.2f,%.2f) busy=%d kind=%@ script=%@", clock, j.id, b.t, b.d, meetT, meetXZ.x, meetXZ.y, stand.x, stand.y, j.brain.tossBusy ? 1 : 0, String(describing: j.brain.idleState.kind), String(String(describing: j.brain.script).prefix(20))) }
        } else if b.d > (PlayTuning.ballReturnOld ? 0.30 : Self.lateWalk), !busy, b.t > 0.18 {          // (the old step under it: with `-BallReturnOld 1` always; otherwise for the late ball there is no time for a stand, crouch and jump: he steps under it as before and the old hop below meets it)
            let last = interceptAt[j.id]
            if last == nil || (clock - last!.t > 0.45 && simd_distance(last!.p, b.xz) > 0.25) {
                let zr = Self.bodyZ(), zy = min(max(b.xz.y, zr.lowerBound), max(min(catchZ() - 1.2, zr.upperBound), zr.lowerBound)), bx = Self.bodyReach(PlayTuning.old ? b.xz.y : zy)
                j.brain.requestNow(.goTo(SIMD2<Float>(min(max(b.xz.x, -bx), bx), zy)))
                interceptAt[j.id] = (b.xz, clock)
            }
        } else if busy, j.brain.tossHeaderApproach, j.brain.idleState.toss.stage < 3, let last = interceptAt[j.id], simd_distance(j.brain.idleState.toss.stand, meetXZ) > Self.steerReach + 0.4, clock - last.t > 0.3 {
            j.brain.tossHeaderRelease(j.sim, j.skinner)          // (the ball moved on: he is released and sent to the new place next step)
            interceptAt[j.id] = nil
        }
        // the ones whose approach the ball has left behind (it is not coming to them any more) are released at once: the old loose-ball job is then done by whoever is nearest
        for o in jellies where o.id != j.id && o.brain.tossHeaderApproach && o.brain.idleState.toss.stage < 4 { o.brain.tossHeaderRelease(o.sim, o.skinner) }
        steerOntoCrown(j, arriveIn: meetT)
        // the go: crouch now so the crown is rising as the ball arrives (met as near the top of the jump as the ball's own height allows)
        if busy, j.brain.tossHeaderApproach, j.brain.idleState.toss.stage == 3, let m = meetTime(j), m.t <= BlobBrain.tossCrouch + Self.riseTime(m.rise) + Self.goEarly {
            j.brain.idleState.toss.go = true
        }
        // fallback: no approach could be set (mid-step ...): the old hop, timed so the top of it meets the ball
        if !busy, b.d < (PlayTuning.ballReturnOld ? 0.55 : Self.lateWalk), b.t <= BlobBrain.tossHeaderLead + (PlayTuning.ballReturnOld ? 0.03 : 0.10), Self.canHop(j.brain) {
            let P = playerPoint() - j.pos; if simd_length(P) > 1e-3 { j.brain.tossFaceYaw = atan2f(P.x, P.y) }
            j.brain.tossHeaderStart(j.sim, j.skinner, jump: !PlayTuning.ballReturnOld)
        }
    }

    /// How far from his crown's line the ball may be and still be eased onto it (play-ball-r2, mechanism b: the ball's last moment is nudged onto the crown of the Jelmiko who is set to head it, so he need not walk under it with his back turned).
    /// The jump starts this much earlier than the ball's own path says, so the crown meets it at the top (measured: without it the contact came at about 55% of the rise).
    static let goEarly: Float = 0.10
    /// A late ball (no time for a stand) that will pass within this of him is not walked to: he jumps where he stands, turning toward the player in the air, and the nudge brings the ball onto his crown. Further out he steps under it as before (walking, so facing his walk).
    static let lateWalk: Float = 0.9
    static let steerReach: Float = 0.8
    /// The cap on the sideways speed the nudge may add (m/s): a gentle curve, never a snap.
    static let steerMaxDV: Float = 1.7
    private func steerOntoCrown(_ j: PlayJelly, arriveIn t: Float, to spot: SIMD2<Float>? = nil) {
        guard !PlayTuning.ballReturnOld, j.brain.tossBusy, t > 0.04, t < 1.4 else { return }
        let target: SIMD2<Float> = spot ?? ((j.brain.idleState.kind == .tossBump && j.brain.idleState.toss.walking) ? j.brain.idleState.toss.stand : j.pos)
        let here = SIMD2(ball.pos.x, ball.pos.z) + SIMD2(ball.vel.x, ball.vel.z) * t
        let miss = target - here
        guard simd_length(miss) < Self.steerReach + 0.2 else { return }
        let want = SIMD2(ball.vel.x, ball.vel.z) + miss / t
        let cur = SIMD2(ball.vel.x, ball.vel.z)
        var d = (want - cur) * min(1, 0.05 / max(t, 0.05) + 0.1)
        let L = simd_length(d), cap = Self.steerMaxDV * 0.02          // (per tick; about 60 ticks a second)
        if L > cap { d *= cap / L }
        ball.vel.x += d.x; ball.vel.z += d.y
    }

    /// The seconds a jump takes to raise the crown by `h` (the hop's parabola: apex `tossCrownRise` at `tossJumpLead`).
    private static func riseTime(_ h: Float) -> Float {
        let k = min(max(h / BlobBrain.tossCrownRise, 0), 1)
        return BlobBrain.tossJumpLead * (1 - (1 - k).squareRoot())
    }
    @ObservationIgnored private var standTop: [Int: Float] = [:]
    @ObservationIgnored private var headChoice: Int?
    /// Where the falling ball is met: the highest rise of his crown (from a list, the top of the jump first) at which the ball's own path still comes down through the crown's height, and the seconds until then.
    private func meetTime(_ j: PlayJelly) -> (t: Float, rise: Float)? {
        let top = standTop[j.id] ?? (j.sim.restCentroid.y + BobShape.H * 0.5)
        let g = TossTuning.gravity, vy = ball.vel.y
        for h in [Float(0.38), 0.28, 0.18, 0.08] {
            let y0 = ball.pos.y - (top + h + ball.radius * 0.9)
            let disc = vy * vy + 2 * g * y0
            guard disc >= 0 else { continue }
            let t = (vy + disc.squareRoot()) / g
            if t > -0.2 { return (t, h) }
        }
        return nil
    }

    // MARK: passing (play-ball-s3)

    /// The strike by `j` is about to send the ball on: who gets it? A friend (a chain goes on) or nil (the ball goes back to the player, and the chain is over).
    private func nextHop(by j: PlayJelly) -> PlayJelly? {
        var left = 0; var prev: Int?
        switch ownGame {
        case .none: left = pendingPasses; pendingPasses = 0
        case .passing(let l, let from, _): left = l; prev = from
        }
        let styled = PlayTuning.style(ballKind).headShare < 1 && !PlayTuning.ballReturnOld
        if UserDefaults.standard.integer(forKey: "PlayDemo") > 0 { NSLog("[playchain] hop by=%d left=%d", j.id, left) }
        guard styled, left > 0 else { ownGame = .none; return nil }
        let line = jellies.filter { !$0.free && $0.id != j.id && simd_distance($0.pos, j.pos) >= PlayTuning.passMinDist && simd_distance($0.pos, j.pos) <= PlayTuning.passMaxDist }
        // never back to the one who just passed, unless there are only two of them
        let others = line.filter { $0.id != prev }
        let pool = (others.isEmpty && jellies.filter({ !$0.free }).count <= 2) ? line : others
        guard !pool.isEmpty else { ownGame = .none; return nil }
        let still = pool.filter { Self.canHop($0.brain) && !$0.brain.tossBusy }          // (one who is standing is better than one still walking home: he can turn to the pass at once)
        let pick = still.isEmpty ? pool : still
        let o = pick[min(Int(rand() * Float(pick.count)), pick.count - 1)]
        ownGame = .passing(left: left - 1, from: j.id, to: o.id)
        return o
    }

    /// A pass along the floor: the ball leaves `j`'s foot toward the spot just in front of `o`, slow enough to follow (0.8 to 1.1 s), and `o` is prepared at once (turns to it, sets the foot plan of a planned kick) so he strikes it first time.
    private func groundPass(by j: PlayJelly, to o: PlayJelly) {
        let r = ball.radius, cd = Self.contactDist(r)
        let ballXZ = SIMD2(ball.pos.x, ball.pos.z)
        let toPlayer = playerPoint() - o.pos, toPasser = j.pos - o.pos
        // he turns a little toward the ball (0.25 of the way to the passer), more would put the spot nearer the passer than 1.3 u: then none
        var dirO = SIMD2<Float>(0, 1), spot = o.pos, D: Float = 0
        for tilt in [Float(0.25), 0] {
            var d = (simd_length(toPlayer) > 1e-3 ? simd_normalize(toPlayer) : SIMD2<Float>(0, 1)) + (simd_length(toPasser) > 1e-3 ? simd_normalize(toPasser) * tilt : .zero)
            d = simd_length(d) > 1e-3 ? simd_normalize(d) : SIMD2(0, 1)
            var sp = o.pos + d * cd
            let lim = Self.ballReach(sp.y) - r - 0.1
            sp.x = min(max(sp.x, -lim), lim)
            dirO = d; spot = sp; D = simd_length(sp - ballXZ)
            if D >= 1.3 { break }
        }
        guard D >= 1.3 else { ownGame = .none; liveKick(by: j); return }          // (never a pass that close: the ball goes back)
        let k = TossTuning.rollDecayPerS
        let T = min(max(0.7 + 0.1 * D, 0.8), 1.1)
        let speed = D * k / (1 - expf(-k * T)) * 1.08
        let d = (spot - ballXZ) / D
        ball.vel = SIMD3(d.x * speed, 0.4, d.y * speed)
        ball.pos.y = max(ball.pos.y, r + 0.02)
        ball.ignoring = j.id; ball.ignoreT = 0.35
        returnAim = nil
        passTo = o.id; passes += 1; nudges += 1; touched = true; rally += 1
        phase = .loose; looseT = 0
        touchLog("kick", j)
        NSLog("[playpass] clock=%.3f throw=%d kind=foot from=%d to=%d dist=%.2f T=%.2f speed=%.2f", clock, throwSerial, j.id, o.id, D, T, speed)
        noteRecallStrike()
        footPlan[j.id] = nil; footChoice = nil; bumper = nil
        footFlight = true; kickHeightT = nil
        passPlan = (o.id, spot, dirO, clock + T + 1.2)
        preparePassReceiver()
        onEvent?(.kick(id: j.id))
        onEvent?(.pass(from: j.id, to: o.id))
        j.brain.jellyKick = max(j.brain.jellyKick, 1.6)
    }

    /// The friend turns to the pass and holds the foot plan until the ball is in reach (tried every tick until he can start: he may be mid-step as the pass is struck).
    private func preparePassReceiver() {
        guard let pp = passPlan, let o = jelly(pp.to) else { passPlan = nil; return }
        if o.brain.tossFootApproach { passPlan = nil; return }
        guard !o.brain.tossBusy || o.brain.tossFootApproach else { return }
        o.brain.tossFire = { [weak self] bb in self?.fired(by: bb) }
        o.brain.tossFireReady = { [weak self] bb in self?.fireReady(bb) ?? true }
        let stand = o.pos
        if o.brain.tossBumpStart(o.sim, o.skinner, stand: stand, dir: pp.dir, lean: 1, foot: true, lunge: true) {
            footChoice = o.id; footPlan[o.id] = (pp.spot, pp.dir, clock, pp.until); bumper = o.id
            passPlan = nil
            NSLog("[playpass] prepared clock=%.3f id=%d", clock, o.id)
        } else if clock - (interceptAt[o.id]?.t ?? -9) > 0.3 {          // (he is on a walk home: stopped where he is, then the stand starts)
            o.brain.requestNow(.goTo(o.pos)); interceptAt[o.id] = (o.pos, clock)
            NSLog("[playpass] not ready clock=%.3f id=%d kind=%@ script=%@ feet=%d", clock, o.id, String(describing: o.brain.idleState.kind), String(String(describing: o.brain.script).prefix(24)), o.brain.feet.active ? 1 : 0)
        }
    }

    /// The player asks for the ball back (the "Pass it back" button): nothing waits and nobody is interrupted; the chain is over and the NEXT strike of the ball goes to the player.
    func recall() {
        guard keeping, !PlayTuning.ballReturnOld else { return }
        var to = -1
        if case .passing(_, _, let t) = ownGame { to = t }
        recallAt = clock
        ownGame = .none; pendingPasses = 0
        NSLog("[playrecall] clock=%.3f phase=%@ ballTo=%d pos=%.2f,%.2f,%.2f", clock, String(describing: phase), to, ball.pos.x, ball.pos.y, ball.pos.z)
        // the friend who is set to receive turns to where the ball will go (the player) instead of the next friend
        if let c = footChoice, let j = jelly(c), j.brain.tossFootApproach, j.brain.idleState.toss.stage <= 6, j.brain.idleState.toss.stage != 1, j.brain.idleState.toss.stage != 5 {
            let P = playerPoint() - j.pos
            if simd_length(P) > 1e-3 { j.brain.idleState.goalYaw = atan2f(P.x, P.y); j.brain.idleState.toss.dir = simd_normalize(P) }
        }
    }

    private func noteRecallStrike() {
        guard let t = recallAt else { return }
        NSLog("[playrecall] strike dt=%.2f", clock - t)
    }

    /// The ball is on the Jelmiko who was to kick it (or on any free one: nobody lets a ball lie): the contact IS the strike: the kick starts from where he stands, the stomp follows as its follow-through.
    private func strikeByContact(_ kj: PlayJelly) {
        kj.brain.tossFire = { [weak self] b in self?.fired(by: b) }
        if !kj.brain.tossFootApproach {
            let P = playerPoint() - kj.pos
            _ = kj.brain.tossBumpStart(kj.sim, kj.skinner, stand: kj.pos, dir: simd_length(P) > 1e-3 ? simd_normalize(P) : SIMD2(0, 1), foot: true, lunge: true)
        }
        kj.brain.tossStrikeNow()
        NSLog("[playfoot] bodystrike clock=%.3f id=%d ballY=%.2f", clock, kj.id, ball.pos.y)
        fired(by: kj.brain, force: true)
    }

    // MARK: planned kicks (play-ball-s2)

    /// When the falling ball's centre is at kick height, and where.
    private func kickArrival() -> (t: Float, xz: SIMD2<Float>)? {
        let g = TossTuning.gravity
        let y0 = ball.pos.y - (ball.radius + Self.kickHeightAbove)
        guard y0 > 0 else { return nil }
        let t = (ball.vel.y + (ball.vel.y * ball.vel.y + 2 * g * y0).squareRoot()) / g
        guard t > 0, t < 1.8 * TossTuning.slow else { return nil }
        return (t, SIMD2(ball.pos.x + ball.vel.x * t, ball.pos.z + ball.vel.z * t))
    }

    private func inKickReach(_ j: PlayJelly) -> Bool {
        let rel = SIMD2(ball.pos.x, ball.pos.z) - j.pos, dist = simd_length(rel)
        let fwd = SIMD2<Float>(sinf(j.brain.yaw), cosf(j.brain.yaw))
        return dist < Self.kickReach + (ball.radius - SoccerTuning.radius) && dist > 1e-3 && simd_dot(rel / dist, fwd) > 0.4 && ball.pos.y < ball.radius + 0.55
    }

    /// A foot flight: the Jelmiko the ball is coming to goes to a stand behind where it comes down to kick height, turns to where the kick will go and holds it; `footTick` gives the go. NOTHING here decides whether the ball is struck (it is: a body contact, a header, or the loose path): a late or surprise ball falls back to the header path. True = handled this tick.
    private func footIntercepts() -> Bool {
        if let c = footChoice, let jc = jelly(c), jc.brain.tossFootApproach { return true }
        guard let k = kickArrival() else { return false }
        let r = ball.radius, cd = Self.contactDist(r)
        let pp = playerPoint()
        let dv = pp - k.xz
        let dir = simd_length(dv) > 1e-3 ? simd_normalize(dv) : SIMD2<Float>(0, 1)
        var spot = k.xz
        let zr = Self.bodyZ()
        let lim = Self.ballReach(spot.y) - r - 0.1
        spot.x = min(max(spot.x, -lim), lim)
        var stand = spot - dir * cd
        stand.y = min(max(stand.y, zr.lowerBound), zr.upperBound)
        stand.x = min(max(stand.x, -Self.bodyReach(stand.y)), Self.bodyReach(stand.y))
        var best: (j: PlayJelly, walk: Float)?
        for j in jellies {
            let f = j.brain.fixed(stand)
            guard simd_distance(f, stand) < 0.25, j.brain.peerFree(f) else { continue }
            let w = simd_distance(j.pos, stand)
            if w < Self.interceptReach, best == nil || w < best!.walk { best = (j, w) }
        }
        guard let b = best else { if footAimed { return true }; footFlight = false; return false }
        let j = b.j
        let need = b.walk / 1.5 + 0.2 + Self.footLead + (j.brain.tossBusy || !Self.canHop(j.brain) ? 0.15 : 0)
        if k.t < (footAimed ? 0.45 : need) {
            NSLog("[playfoot] late clock=%.3f throw=%d id=%d tk=%.2f need=%.2f walk=%.2f aimed=%d", clock, throwSerial, j.id, k.t, need, b.walk, footAimed ? 1 : 0)
            if footAimed { return true }          // (the ball was thrown at his feet: a header cannot meet it; the body contact is the strike, see `live`)
            footFlight = false; return false
        }          // (no time for a stand: the header path, where he stands, as in step 1)
        let wasBusy = j.brain.tossBusy
        j.brain.tossFire = { [weak self] bb in self?.fired(by: bb) }
        j.brain.tossFireReady = { [weak self] bb in self?.fireReady(bb) ?? true }
        let spotNow = stand + dir * cd
        if j.brain.tossBumpStart(j.sim, j.skinner, stand: stand, dir: dir, lean: 1, foot: true, lunge: true) {
            footChoice = j.id; footPlan[j.id] = (spotNow, dir, clock, 0); bumper = j.id
            NSLog("[playfoot] plan clock=%.3f throw=%d id=%d tk=%.2f need=%.2f walk=%.2f stand=(%.2f,%.2f) spot=(%.2f,%.2f) busy=%d", clock, throwSerial, j.id, k.t, need, b.walk, stand.x, stand.y, spotNow.x, spotNow.y, wasBusy ? 1 : 0)
            return true
        }
        if b.walk > 0.3, interceptAt[j.id] == nil || clock - interceptAt[j.id]!.t > 0.45 { j.brain.requestNow(.goTo(stand)); interceptAt[j.id] = (stand, clock) }
        return true          // (not yet: he is mid-step; next tick)
    }

    private func fireReady(_ b: BlobBrain) -> Bool {
        guard let j = jellies.first(where: { $0.brain === b }) else { return true }
        return inKickReach(j)
    }

    /// Every tick while a kick is planned: ease the ball onto the kick spot, give the go so the foot lands as the ball arrives, let a plan go when the ball went elsewhere.
    private func footTick() {
        // a pass that reaches its receiver who is not set (still walking, mid-step): the ball is struck at once, it never rolls past him
        if let pid = passTo, ownGame != .none || passPlan != nil, phase == .loose, let rj = jelly(pid), !rj.brain.tossFootApproach, !rj.brain.tossBusy,
           ball.pos.y < ball.radius + 0.5, simd_distance(SIMD2(ball.pos.x, ball.pos.z), rj.pos) < Self.contactDist(ball.radius) + 0.1 { passPlan = nil; strikeByContact(rj); return }
        guard let c = footChoice, let j = jelly(c) else { return }
        guard j.brain.tossFootApproach else { if !j.brain.tossBusy { footChoice = nil }; return }
        guard let plan = footPlan[c] else { return }
        let ballXZ = SIMD2(ball.pos.x, ball.pos.z)
        let low = ball.pos.y <= ball.radius + Self.kickHeightAbove + 0.02
        if !low, let k = kickArrival() {
            if phase == .flying { steerOntoCrown(j, arriveIn: k.t, to: plan.spot) }
            if j.brain.tossFootReady, k.t <= Self.footLead { j.brain.tossFootGo(); NSLog("[playfoot] go clock=%.3f id=%d tk=%.2f dist=%.2f", clock, c, k.t, simd_distance(ballXZ, plan.spot)) }
            return
        }
        // on the floor (a bounce, a roll): in reach now or by the time the foot lands: go at once; gone off: let him go
        let vxz = SIMD2(ball.vel.x, ball.vel.z)
        let k = TossTuning.rollDecayPerS
        if plan.until > clock, j.brain.tossFootReady {          // (a pass rolling to him: the go is timed by when the ball reaches the spot in front of him, so the foot lands as it arrives, not by where it will be later)
            let d = simd_distance(ballXZ, plan.spot), sp = simd_length(vxz)
            if sp < 0.6, d > 1.3, ball.onFloor, !inKickReach(j) {          // (the pass stopped short or went elsewhere: nobody waits for it, the nearest takes it now and the chain is over)
                j.brain.tossFootRelease(j.sim, j.skinner); footChoice = nil; bumper = nil; passPlan = nil; ownGame = .none; pendingPasses = 0
                NSLog("[playfoot] pass-stopped clock=%.3f id=%d d=%.2f", clock, c, d); return
            }
            if inKickReach(j) || d < 0.5 { NSLog("[playfoot] strike-pass clock=%.3f id=%d d=%.2f (ball already here)", clock, c, d); passPlan = nil; strikeByContact(j) }          // (he was set late: no time for the wind-up, the ball is struck at once)
            else if sp > 0.3, simd_dot(vxz, plan.spot - ballXZ) > 0 {
                let rem = 1 - d * k / sp
                let tts: Float = rem > 0.02 ? -logf(rem) / k : 99
                if tts <= Self.footLead { j.brain.tossFootGo(); NSLog("[playfoot] go-pass clock=%.3f id=%d d=%.2f tts=%.2f", clock, c, d, tts) }
            }
            return
        }
        let ahead = ballXZ + vxz * ((1 - expf(-k * Self.footLead)) / k)
        if j.brain.tossFootReady {
            if simd_distance(j.pos, ahead) < Self.kickReach + (ball.radius - SoccerTuning.radius) - 0.05 || inKickReach(j) { j.brain.tossFootGo(); NSLog("[playfoot] go-floor clock=%.3f id=%d dist=%.2f", clock, c, simd_distance(j.pos, ballXZ)) }
            else if plan.until <= clock, simd_distance(j.pos, ahead) > 2.0 || looseT > 0.5 { j.brain.tossFootRelease(j.sim, j.skinner); footChoice = nil; bumper = nil; NSLog("[playfoot] release clock=%.3f id=%d dist=%.2f", clock, c, simd_distance(j.pos, ballXZ)) }
        }
    }

    // MARK: loose ball

    private func loose(dt: Float) {
        let r = ball.radius
        if looseT > Self.rescueAfter { rescue(); return }
        if looseT > 0.4, !keeping {          // (the ones who are not the next to bump: a few steps toward the ball)
            let ballAt = SIMD2(ball.pos.x, ball.pos.z)
            var skip = Set<Int>(); if let b = bumper { skip.insert(b) }
            if let n = jellies.min(by: { simd_distance($0.pos, ballAt) < simd_distance($1.pos, ballAt) }) { skip.insert(n.id) }
            support(toward: ballAt, except: skip)
        }
        // a Jelbie already on his way / mid-stomp: let him
        if let b = bumper, let j = jelly(b) {
            if !j.brain.tossBusy {
                bumper = nil                        // he finished (fired or gave up): the next decision
            } else { return }
        }
        // wait for it to settle (or for the wait to run out), unless it will land on a head
        if ball.pos.y > 0.7 + r { return }
        let slow = ball.speedXZ < Self.looseWaitSpeed
        let byFoot = footFlight && !PlayTuning.ballReturnOld          // (play-ball-s2: a ball that was to be kicked is kicked on the bounce the moment he can be there: no waiting for it to slow down)
        guard slow || looseT > 1.6 || byFoot else { return }
        // who goes: the nearest Jelbie that is free (the friend the last bump was passed to goes first)
        let free = jellies.filter { !$0.brain.tossBusy }
        let choice = (passTo.flatMap { id in free.first { $0.id == id } }) ?? free.min { simd_distance($0.pos, SIMD2(ball.pos.x, ball.pos.z)) < simd_distance($1.pos, SIMD2(ball.pos.x, ball.pos.z)) }
        guard let j = choice else { return }
        // where it will lie: its roll runs out in v / decay
        // (a ball still in the air / bouncing travels on through its bounces before the roll starts: counted, or he stands short and the stomp whiffs)
        let gq = TossTuning.gravity, e = TossTuning.restitution
        let vLand = (ball.vel.y * ball.vel.y + 2 * gq * max(ball.pos.y - r, 0)).squareRoot()
        let airT = ball.pos.y > r + 0.03 || abs(ball.vel.y) > 0.5 ? min((ball.vel.y + vLand) / gq + 2 * vLand * e / (1 - e) / gq, 1.6) : 0
        var ballXZ = SIMD2(ball.pos.x, ball.pos.z) + SIMD2(ball.vel.x, ball.vel.z) * (airT * 0.75 + 0.8 / TossTuning.rollDecayPerS)
        let lim = Self.ballReach(ballXZ.y) - r
        ballXZ = SIMD2(min(max(ballXZ.x, -lim), lim), min(max(ballXZ.y, TossTuning.zBack + r), catchZ()))
        let target = SIMD2<Float>(handWorld().x * 0.5, catchZ() + 0.6)
        var dir = target - ballXZ
        let L = simd_length(dir)
        dir = L > 1e-3 ? dir / L : SIMD2(0, 1)
        let back = SoccerTuning.standBack + (r - SoccerTuning.radius)
        var plan: (stand: SIMD2<Float>, dir: SIMD2<Float>)?
        for a in [Float(0), 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.2, -2.2] {
            let c = cosf(a), s = sinf(a)
            let u = SIMD2<Float>(dir.x * c - dir.y * s, dir.x * s + dir.y * c)
            let q = ballXZ - u * back
            let f = j.brain.fixed(q)
            if simd_distance(f, q) < 0.1, j.brain.peerFree(f) { plan = (f, u); break }
        }
        if plan == nil, !PlayTuning.ballReturnOld {          // (a ball against a side wall: the nearest allowed spot to it, kicking along the wall toward the player, before the safety net)
            for back2 in [back, back * 0.8, back * 0.6] {
                for a in [Float(0), 0.5, -0.5, 1.0, -1.0] {
                    let c = cosf(a), s = sinf(a)
                    let u = SIMD2<Float>(dir.x * c - dir.y * s, dir.x * s + dir.y * c)
                    let f = j.brain.fixed(ballXZ - u * back2)
                    let g = ballXZ - f
                    if simd_length(g) > 0.45, simd_length(g) < 1.8, j.brain.peerFree(f) { plan = (f, simd_normalize(g)); break }
                }
                if plan != nil { break }
            }
        }
        guard let p = plan else { return }
        j.brain.tossFire = { [weak self] b in self?.fired(by: b) }
        let lively = !PlayTuning.ballReturnOld && PlayTuning.style(ballKind).headShare < 1          // (soccer and beach kicks: the readable wind-up and lunge; the foot lands only when the ball is in reach)
        j.brain.tossFireReady = lively ? { [weak self] b in self?.fireReady(b) ?? true } : nil
        if j.brain.tossBumpStart(j.sim, j.skinner, stand: p.stand, dir: p.dir, lean: 1, lunge: lively) { bumper = j.id }          // (mid-step: the next tick)
    }

    /// The bump's foot landed.
    private func fired(by b: BlobBrain, force: Bool = false) {
        guard let j = jellies.first(where: { $0.brain === b }) else { return }
        let ballXZ = SIMD2(ball.pos.x, ball.pos.z)
        let rel = ballXZ - j.pos, dist = simd_length(rel)
        let fwd = SIMD2<Float>(sinf(b.yaw), cosf(b.yaw))
        let inReach = dist < Self.kickReach + (ball.radius - SoccerTuning.radius) && dist > 1e-3 && simd_dot(rel / dist, fwd) > 0.4 && ball.pos.y < ball.radius + 0.55
        guard inReach || force, phase == .loose || phase == .flying else { onEvent?(.whiff(id: j.id)); NSLog("[playfoot] whiff clock=%.3f id=%d dist=%.2f y=%.2f", clock, j.id, dist, ball.pos.y); return }
        let hand = handWorld()
        if !PlayTuning.ballReturnOld, PlayTuning.style(ballKind).headShare < 1 {          // (play-ball-s2: soccer / beach kicks; s3: a pass along the floor to a friend, or the lively arc back to the hand)
            if let o = nextHop(by: j) { groundPass(by: j, to: o) } else { liveKick(by: j) }
            return
        }
        var factor: Float = [0.8, 0.95, 1.1, 1.25, 1.4, 1.5][min(nudges, 5)] * (0.88 + 0.22 * rand())
        var err: Float = nudges < 3 ? (rand() - 0.5) * 0.35 : 0
        let passFriend: PlayJelly? = (passTo == nil && jellies.count > 1 && nudges == 0 && rand() < Self.passChance) ? jellies.filter({ $0.id != j.id }).min(by: { simd_distance($0.pos, ballXZ) < simd_distance($1.pos, ballXZ) }) : nil
        var target = SIMD2<Float>(hand.x * 0.5, catchZ() + 0.6)
        // a pass: to the friend
        if let o = passFriend {
            target = o.pos + SIMD2(0, 0.6); factor = 0.95; err = 0; passTo = o.id; passes += 1
            onEvent?(.pass(from: j.id, to: o.id))
        } else { passTo = nil }
        var d = target - ballXZ
        let L = simd_length(d)
        d = L > 1e-3 ? d / L : SIMD2(0, 1)
        let c = cosf(err), s = sinf(err)
        d = SIMD2(d.x * c - d.y * s, d.x * s + d.y * c)
        let need = L * TossTuning.rollDecayPerS
        let speed = min(max(need * factor, 1.5), 6)
        ball.vel = SIMD3(d.x * speed, 1.1, d.y * speed)
        ball.pos.y = max(ball.pos.y, ball.radius + 0.02)
        nudges += 1; touched = true
        phase = .loose; looseT = 0
        touchLog("kick", j)
        onEvent?(.kick(id: j.id))
        j.brain.jellyKick = max(j.brain.jellyKick, 1.6)
    }

    /// play-ball-s2: a kick that goes to the player: it leaves faster than it came, on a low lively arc that comes down in the catch zone (the same steering as a header's return eases it there).
    private func liveKick(by j: PlayJelly) {
        let from = ball.pos
        let hand = handWorld()
        let tz = catchZ() + 0.55
        let tx = min(max(hand.x * 0.5 + (rand() - 0.5) * 0.9, -(Self.ballReach(tz) - 0.9)), Self.ballReach(tz) - 0.9)
        let target = SIMD3<Float>(tx, TossTuning.handHeight, tz)
        let dist = simd_length(SIMD2(target.x - from.x, target.z - from.z))
        var v = TossAim.ballistic(from: from, to: target, flight: min(max(0.40 + 0.07 * dist, 0.5), 0.95) * TossTuning.slow)
        v.y = max(v.y, 1.6 / TossTuning.slow)
        // a Jelmiko in the way (a kick from the back of the room goes through the row): the arc is lifted just enough to pass over his crown (without it the ball hit his side, a soft bounce, and went back to the wall)
        let g = TossTuning.gravity, vh = SIMD2(v.x, v.z), sp = simd_length(vh)
        if sp > 1e-3 {
            for o in jellies where o.id != j.id {
                let rel = o.pos - SIMD2(from.x, from.z)
                let t = simd_dot(rel, vh) / (sp * sp)
                guard t > 0.02, t < 3 else { continue }
                let lateral = simd_length(rel - vh * t)
                guard lateral < TossTuning.bodyRadius + ball.radius + 0.1 else { continue }
                let need = o.headTop + ball.radius + 0.12
                v.y = max(v.y, (need - from.y + 0.5 * g * t * t) / t)
            }
        }
        ball.vel = v
        ball.pos.y = max(ball.pos.y, ball.radius + 0.06)
        ball.ignoring = j.id; ball.ignoreT = 0.35
        returnAim = SIMD2(target.x, target.z)
        passTo = nil
        nudges += 1; touched = true; rally += 1
        phase = .flying; looseT = 0
        touchLog("kick", j)
        noteRecallStrike()
        footFlight = false; footChoice = nil; kickHeightT = nil; bumper = nil; footPlan[j.id] = nil; passPlan = nil
        onEvent?(.kick(id: j.id))
        j.brain.jellyKick = max(j.brain.jellyKick, 1.6)
    }

    /// The safety net: a ball that will not come (stuck behind furniture ...) is rolled to the front by a nudge from nobody in particular.
    private func rescue() {
        let ballXZ = SIMD2(ball.pos.x, ball.pos.z)
        let tz = catchZ() + 0.6
        let lim = Self.ballReach(tz) - 0.9
        let target = SIMD3<Float>(min(max(handWorld().x * 0.5, -lim), lim), ball.radius, tz)
        let L = simd_length(SIMD2(target.x, target.z) - ballXZ)
        // a lob (clears the furniture and the Jelbies' shoulders) that comes down in the catch zone
        var v = TossAim.ballistic(from: ball.pos, to: target, flight: min(max(0.8 + 0.06 * L, 0.9), 1.4) * TossTuning.slow)
        v.y = max(v.y, 3.2 / TossTuning.slow)
        ball.vel = v
        ball.pos.y = max(ball.pos.y, ball.radius + 0.02)
        ball.ignoring = nil; touched = true
        footFlight = false; footChoice = nil; kickHeightT = nil; ownGame = .none; pendingPasses = 0; passPlan = nil
        if let t = recallAt { NSLog("[playrecall] rescue dt=%.2f", clock - t) }
        phase = .flying; returnAim = SIMD2(target.x, target.z)
        rescues += 1; looseT = 0
        onEvent?(.rescue)
    }

    private func caught() {
        catchFrom = ball.pos; catchT = 0
        phase = .catching
        shownRally = rally
        catchSerial += 1
        onEvent?(.caught(rally: rally))
        bumper = nil; passTo = nil; returnAim = nil; restT = 0
        footFlight = false; footChoice = nil; footPlan = [:]; kickHeightT = nil; ownGame = .none; pendingPasses = 0; passPlan = nil
        if let t = recallAt { NSLog("[playrecall] hand dt=%.2f", clock - t); recallAt = nil }
        for j in jellies { j.brain.tossFire = nil; j.brain.tossFireReady = nil }
        RoomLayout.ballSpheres.removeAll { $0.uid == Self.sphereUID }
    }
}

