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

@MainActor
@Observable
final class PlayToss {
    enum Phase: Equatable { case off, inHand, flying, loose, catching, toy }
    enum Quality: Equatable { case good, short, weak }

    // MARK: observed state (the UI)
    private(set) var phase: Phase = .off
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

    private func rand() -> Float {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Float(rng >> 40) / Float(1 << 24)
    }
    func seed(_ s: UInt64) { rng = s | 1 }

    // MARK: begin / end

    /// Play mode on with `kind`: the Jelbies take their places, the camera eases to the play view, the ball is in the hand.
    func begin(ball kind: DecorKind, title: String, jellies js: [PlayJelly], snapCamera: Bool = false) {
        guard phase == .off else { return }
        ballKind = kind; toyTitle = title
        if UserDefaults.standard.integer(forKey: "PlayDemo") > 0, let q = UserDefaults.standard.string(forKey: "PlayDemoQuality") { forceQuality = q == "weak" ? .weak : (q == "short" ? .short : .good) }
        ball = TossBall(pos: SIMD3(0, kind.rollRadius, 3), radius: kind.rollRadius)
        jellies = js
        phase = .inHand
        rally = 0; shownRally = 0; nudges = 0; looseT = 0; bumper = nil; passTo = nil; finger = nil; leftHand = false
        camGoal = 1
        if snapCamera { camBlend = 1; GameCamera.playBlend = 1 }
        placeJellies()
    }

    /// Play mode on with a toy that is not the ball (the bubble wand): the camera eases to the play view, HUD hidden, Done shown; the Jelbies stay free.
    func beginToy(title: String, snapCamera: Bool = false) {
        guard phase == .off else { return }
        toyTitle = title; jellies = []
        phase = .toy
        camGoal = 1
        if snapCamera { camBlend = 1; GameCamera.playBlend = 1 }
    }

    /// Done: the Jelbies go back to roaming, the camera eases home.
    func end() {
        guard phase != .off else { return }
        phase = .off
        camGoal = 0
        finger = nil
        release(jellies)
        jellies = []
    }

    private func release(_ js: [PlayJelly]) {
        for j in js {
            let b = j.brain
            if let s = saved[j.id] { b.reserved = s.reserved; b.idleBlocked = s.idleBlocked; b.waitFocus = s.waitFocus } else { b.reserved = false }
            b.trackPoint = nil; b.tossFire = nil
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
        for (k, f) in fx.enumerated() {
            let sy: CGFloat = (k == 1 && n >= 3) ? 0.46 : 0.50          // (the middle one a touch further back: a shallow arc)
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
        return min(max(GameCamera.floorPoint(screen: p, size: viewSize)?.y ?? 3.2, 1.8), 5)
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
        ball.pos = t.start; ball.vel = t.velocity; ball.floorBounces = 0; ball.ignoring = nil
        phase = .flying
        rally = 0; nudges = 0; looseT = 0; flightT = 0; leftHand = false; touched = false; bumper = nil; passTo = nil; headers = 0; rescues = 0; passes = 0
        throwSerial += 1
        returnAim = nil; restT = 0
        onEvent?(.release(speed: simd_length(t.velocity)))
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
        // the ball is a soft obstacle for the walkers (nobody walks through it)
        RoomLayout.ballSpheres.removeAll { $0.uid == Self.sphereUID }
        if (phase == .flying || phase == .loose), ball.pos.y < 0.9 { RoomLayout.ballSpheres.append(BallSphere(c: SIMD2(ball.pos.x, ball.pos.z), r: ball.radius, uid: Self.sphereUID)) }
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
            j.brain.trackPoint = SIMD2(p.x, p.z); j.brain.waitFocus = SIMD2(p.x, p.z)
            // turned well away from it (he walked back to his place with his back to the room): he turns to watch it, on the spot
            guard !j.brain.tossBusy, Self.canHop(j.brain), j.brain.idleState.kind == nil, case .none = j.brain.script, clock - (turnT[j.id] ?? -9) > 0.7 else { continue }
            let want = j.brain.yawTo(SIMD2(p.x, p.z))
            if abs(wrapAngle(want - j.brain.yaw)) > 0.5 { turnT[j.id] = clock; j.brain.startTurn(to: want, sim: j.sim) }
        }
    }

    private func live(dt: Float, world w: TossWorld) {
        flightT += dt
        var world = w
        world.bodies = jellies.map { TossBody(id: $0.id, pos: $0.pos, top: $0.headTop) }
        let before = ball.pos
        let events = ball.step(dt, in: world)
        watch(ball.pos)
        if simd_distance(ball.pos, handWorld()) > 1.5 || ball.pos.z < catchZ() - 0.6 { leftHand = true }
        var headed = false
        for e in events {
            switch e {
            case .floorBounce(let s):
                onEvent?(.floorBounce(speed: s))
                if phase == .flying { phase = .loose; looseT = 0 }
            case .bodyHit(let id, let s):
                if s > 0.9 { onEvent?(.bodyBoop(id: id)) }
                if phase == .flying { phase = .loose; looseT = 0 }
            case .headHit(let id):
                if !headed { headed = true; header(by: id) }
            case .wall: break
            }
        }
        if ball.resting || (ball.onFloor && phase == .flying) { if phase == .flying { phase = .loose; looseT = 0 } }
        // back at the bottom of the screen: caught
        if leftHand, ball.pos.z > catchZ(), ball.pos.y < 2.6, (ball.vel.z > -0.2 || ball.onFloor), ball.ignoring == nil, touched || ball.speedXZ < 1.0 {
            caught(); return
        }
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

    // MARK: header

    private func jelly(_ id: Int) -> PlayJelly? { jellies.first { $0.id == id } }

    /// The ball is on `id`'s crown: it goes back toward the hand, with a quality.
    private func header(by id: Int) {
        guard let j = jelly(id) else { return }
        var q: Quality = forceQuality ?? {
            let r = rand()
            return r < 0.74 ? .good : (r < 0.94 ? .short : .weak)
        }()
        // hitting a pass lands better: the friend meant it
        if passTo == id { q = .good }
        let from = ball.pos
        let hand = handWorld()
        let tz = catchZ() + 0.55
        let tx = min(max(hand.x * 0.5 + (rand() - 0.5) * 0.9, -(DecorPlacement.visibleHalf(z: tz) - 0.9)), DecorPlacement.visibleHalf(z: tz) - 0.9)
        let target = SIMD3<Float>(tx, TossTuning.handHeight, tz)
        returnAim = nil
        let anotherHead = (passTo == nil && jellies.count > 1 && passes == 0 && rally >= 1 && rand() < Self.passChance) ? jellies.filter({ $0.id != id }).min(by: { simd_distance($0.pos, j.pos) < simd_distance($1.pos, j.pos) }) : nil
        var v: SIMD3<Float>
        if let o = anotherHead {
            let tgt = SIMD3<Float>(o.pos.x, o.headTop + ball.radius * 0.4, o.pos.y)
            v = TossAim.ballistic(from: from, to: tgt, flight: (0.75 + 0.05 * simd_distance(o.pos, j.pos)) * TossTuning.slow)
            passTo = o.id; passes += 1
            onEvent?(.pass(from: id, to: o.id))
        } else {
            passTo = nil
            let dist = simd_length(SIMD2(target.x - from.x, target.z - from.z))
            switch q {
            case .good:
                v = TossAim.ballistic(from: from, to: target, flight: min(max(0.7 + 0.07 * dist, 0.8), 1.25) * TossTuning.slow)
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
        v.y = max(v.y, 2.6 / TossTuning.slow)
        ball.vel = v
        ball.pos.y = max(ball.pos.y, j.headTop + ball.radius * 0.8)
        ball.ignoring = id; ball.ignoreT = 0.45
        rally += 1; headers += 1; touched = true
        phase = .flying
        looseT = 0
        j.brain.jellyKick = max(j.brain.jellyKick, 2.2)
        if !j.brain.tossBusy, Self.canHop(j.brain) { j.brain.tossHeaderStart(j.sim, j.skinner) }
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
        guard restT > (leftHand ? Self.restRescueAfter : 0.8) else { return }
        restT = 0
        if !leftHand { caught(); return }
        rescue()
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
        var best: (j: PlayJelly, t: Float, xz: SIMD2<Float>, d: Float)?
        for j in jellies {
            guard let a = arrival(j) else { continue }
            let d = simd_distance(j.pos, a.xz)
            guard d < Self.interceptReach else { continue }
            if best == nil || d < best!.d { best = (j, a.t, a.xz, d) }
        }
        guard let b = best else { return }
        let j = b.j
        let busy = j.brain.tossBusy
        // step under it
        if b.d > 0.30, !busy, b.t > 0.18 {
            let last = interceptAt[j.id]
            if last == nil || (clock - last!.t > 0.45 && simd_distance(last!.p, b.xz) > 0.25) {
                let fx = SIMD2<Float>(min(max(b.xz.x, -DecorPlacement.visibleHalf(z: b.xz.y) + 0.8), DecorPlacement.visibleHalf(z: b.xz.y) - 0.8), min(max(b.xz.y, TossTuning.zBack + 1.2), catchZ() - 1.2))
                j.brain.requestNow(.goTo(fx))
                interceptAt[j.id] = (b.xz, clock)
            }
        }
        // the hop, timed so the top of it meets the ball
        if !busy, b.d < 0.55, b.t <= BlobBrain.tossHeaderLead + 0.03, Self.canHop(j.brain) {
            j.brain.tossHeaderStart(j.sim, j.skinner)
        }
    }

    // MARK: loose ball

    private func loose(dt: Float) {
        let r = ball.radius
        if looseT > Self.rescueAfter { rescue(); return }
        // a Jelbie already on his way / mid-stomp: let him
        if let b = bumper, let j = jelly(b) {
            if !j.brain.tossBusy {
                bumper = nil                        // he finished (fired or gave up): the next decision
            } else { return }
        }
        // wait for it to settle (or for the wait to run out), unless it will land on a head
        if ball.pos.y > 0.7 + r { return }
        let slow = ball.speedXZ < Self.looseWaitSpeed
        guard slow || looseT > 1.6 else { return }
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
        let lim = DecorPlacement.visibleHalf(z: ballXZ.y) - r
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
        guard let p = plan else { return }
        j.brain.tossFire = { [weak self] b in self?.fired(by: b) }
        if j.brain.tossBumpStart(j.sim, j.skinner, stand: p.stand, dir: p.dir, lean: 1) { bumper = j.id }          // (mid-step: the next tick)
    }

    /// The bump's foot landed.
    private func fired(by b: BlobBrain) {
        guard let j = jellies.first(where: { $0.brain === b }) else { return }
        let ballXZ = SIMD2(ball.pos.x, ball.pos.z)
        let rel = ballXZ - j.pos, dist = simd_length(rel)
        let fwd = SIMD2<Float>(sinf(b.yaw), cosf(b.yaw))
        let inReach = dist < Self.kickReach + (ball.radius - SoccerTuning.radius) && dist > 1e-3 && simd_dot(rel / dist, fwd) > 0.4 && ball.pos.y < ball.radius + 0.55
        guard inReach, phase == .loose || phase == .flying else { onEvent?(.whiff(id: j.id)); return }
        let hand = handWorld()
        var target = SIMD2<Float>(hand.x * 0.5, catchZ() + 0.6)
        var factor: Float = [0.8, 0.95, 1.1, 1.25, 1.4, 1.5][min(nudges, 5)] * (0.88 + 0.22 * rand())
        var err: Float = nudges < 3 ? (rand() - 0.5) * 0.35 : 0
        // a pass: to the friend
        if passTo == nil, jellies.count > 1, nudges == 0, rand() < Self.passChance, let o = jellies.filter({ $0.id != j.id }).min(by: { simd_distance($0.pos, ballXZ) < simd_distance($1.pos, ballXZ) }) {
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
        onEvent?(.kick(id: j.id))
        j.brain.jellyKick = max(j.brain.jellyKick, 1.6)
    }

    /// The safety net: a ball that will not come (stuck behind furniture ...) is rolled to the front by a nudge from nobody in particular.
    private func rescue() {
        let ballXZ = SIMD2(ball.pos.x, ball.pos.z)
        let tz = catchZ() + 0.6
        let lim = DecorPlacement.visibleHalf(z: tz) - 0.9
        let target = SIMD3<Float>(min(max(handWorld().x * 0.5, -lim), lim), ball.radius, tz)
        let L = simd_length(SIMD2(target.x, target.z) - ballXZ)
        // a lob (clears the furniture and the Jelbies' shoulders) that comes down in the catch zone
        var v = TossAim.ballistic(from: ball.pos, to: target, flight: min(max(0.8 + 0.06 * L, 0.9), 1.4) * TossTuning.slow)
        v.y = max(v.y, 3.2 / TossTuning.slow)
        ball.vel = v
        ball.pos.y = max(ball.pos.y, ball.radius + 0.02)
        ball.ignoring = nil; touched = true
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
        for j in jellies { j.brain.tossFire = nil }
        RoomLayout.ballSpheres.removeAll { $0.uid == Self.sphereUID }
    }
}

