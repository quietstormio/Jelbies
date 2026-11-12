//
//  SeesawRide.swift
//  The Park seesaw's ride (2026-11-11, branch park-seesaw-r1): the Jelbies SIT on its two cushions facing each other across the plank, get on while it is level and still, ride a calm
//  plank motion that both seats share by construction (ONE angle for the piece), and get off while it is level and still again. Everything specific to the seesaw lives here:
//    SeesawTuning   the constants, the contract geometry (model units, the piece is drawn at DecorKind.scale 1.4), the derived amplitude A, the bumper press
//    SeesawRide     the plank's motion and the ride's state per seesaw uid (a small state machine fed by the riders' reports), the seat frame
//    BlobBrain+     the rider's side: getting on (stage 0 / the hop), the seated pose, getting off (stage 3), each with a hop that never travels over 0.8 m
//  The hooks in BlobBrain+Decor.swift (runBagSit, bagBodyTick) call straight in here; DecorField.tick advances the ride; DecorField.seatWorld reads the seat frame.
//

import Foundation
import simd

nonisolated enum SeesawTuning {
    // MARK: the look of the ride
    /// Each rider is turned this far from facing across the plank toward the camera, so his face reads (a constant: the lead compares 0 and 25 degrees in captures).
    static let faceTurn: Float = 25 * .pi / 180
    /// How much of the plank's angle the body leans with (about the world z axis, split into his own pitch and roll by the way he faces).
    static let leanShare: Float = 0.3
    /// Extra lift of the body's seat above the cushion's top (world units), the knob for the per-species seat height if the skin test asks for one.
    static let seatLift: Float = 0

    // MARK: the plank's motion
    /// One full swing (up and back down) in seconds.
    static let period: Float = 2.3
    /// theta = A * amp * s(phi), phi running with the period: a sine with a slightly flat top (a short dwell at each end). Max of s is 1.
    static func shape(_ phi: Float) -> Float { (sinf(phi) + sinf(3 * phi) / 9) * 9 / 8 }
    static func shapeRate(_ phi: Float) -> Float { (cosf(phi) + cosf(3 * phi) / 3) * 9 / 8 }

    // MARK: the invitation (round 2c)
    /// A lone rider asks for company: ONE news item after he has sat alone this long (a second one `inviteRepeat` later), answered by at most one free Jelbie each (the nearest), with these chances.
    static let inviteAlone: Float = 1.0, inviteRepeat: Float = 5.0, inviteFresh: Float = 8.0
    static let joinChance: Float = 0.75, secondChance: Float = 0.5
    /// The solo rock goes on while the friend is far; the plank eases level when he is within this of his stand spot.
    static let comerNear: Float = 1.6
    /// Off = round 2b's behaviour (no invitation, the plank levels as soon as somebody has taken the other seat): the soak measures both.
    nonisolated(unsafe) static var invitations = true

    // MARK: the timeline (seconds)
    static let settle: Float = 0.4            // seated alone: still this long before the gentle bounce
    static let soloAmp: Float = 0.25          // the gentle bounce alone
    static let soloRamp: Float = 1.0
    static let comerEase: Float = 0.5         // the seated one eases to level when a second rider is coming
    static let pairBeat: Float = 0.3          // after the second landing, before the ride ramps up
    static let rideRamp: Float = 1.5
    static let endRamp: Float = 2.0           // the plank arrives level and still within one period (2.3 s)
    static let endBeat: Float = 0.3
    static let hopGap: Float = 0.3            // the second rider hops off this long after the first
    static let callAwayEase: Float = 0.6      // one rider called away mid-ride: the plank eases to level this fast
    static let swings: ClosedRange<Float> = 5...8
    static let soloHold: ClosedRange<Float> = 7...12
    static let levelTol: Float = 0.01         // "level and still": |theta| below this (and amp exactly 0)
    /// No hop on or off this piece travels farther than this over the floor (metres). A normal seat hop here is 0.84 m (the stand spot in front of the footprint, like every furniture hop): the rule is about multi-metre hops.
    static let maxHop: Float = 1.15
    /// Standing at his spot (1.0 m out) and facing the seat, the body's centre sits 0.16 m behind his root (measured: centroid 1.16 m from the seat point, 1.00 for the root), so the hop from there is 1.14 to 1.17 m.
    /// The spot cannot move closer (the skin is 0.3 cm off the pad's edge at 1.0), so the guard measures the ROOT against the stand spot (a Jelbie on his spot can always hop) and the tests keep the centre's travel under `maxHopCentre`.
    static let maxHopCentre: Float = 1.20          // (what the TESTS assert on the body's centre: the guard itself measures the root)
    /// A called-away rider's hop waits for the plank to be level and still, at most this long after he starts getting up (the controller eases level within 0.6 s).
    static let calledWaitCap: Float = 0.9
    /// How long a rider who has no stand spot in range waits on the seat before he gives up (a sanity bound, never reached in the tests).
    static let noSpotWait: Float = 3.0
    /// Share of the root's distance to the seat closed per step (eased, clamped) after the hop's landing: the landing is within 1 cm, the root settles onto the seat point within 0.2 s.
    static let rootPull: Float = 0.25, rootPullMax: Float = 0.004
    /// How far in front of the centre line (toward the camera) a rider stands to hop on and lands from the hop off, world metres. A body landing or waiting reaches 0.71 m from its root
    /// (measured), the cushion's edge is 0.28 from the centre line: 0.28 + 0.71 + 0.01 = 1.0 keeps a body 1 cm off the cushion.
    static let standDz: Float = 1.0
    /// The brain's hold timer while on the seesaw: huge on purpose. The idle code sets `hold` to 0 to end a sit (come-here, feeding, a request): that is how a call-away is told.
    static let holdMarker: Float = 1e6
    /// How far the feet slide forward on the cushion when he sits down (world units; the beanbag's is 0.27: the handle is in front of him here).
    static let footReach: Float = 0.15
    /// The sit-down's foot steps are slower than the sofa's (a step's rate; the stock 2.6 slid the body 2 to 2.7 cm per step).
    static let footRate: Float = 1.7
    /// The hops up and down take this much longer than the stock bag hop (its rise to a 0.67 m seat peaked at 9.7 cm per step, 5.8 m/s).
    nonisolated(unsafe) static var hopSlow: Float = 1.15          // (a var only so a test can run the stock hop, 1.0, for the comparison)
    /// The seated rider's turn toward a comer (rad, at most) and the pose's squash is the ordinary sit's.
    static let lookMax: Float = 0.2
    static let lookTime: Float = 1.2

    // MARK: the contract (model units; x along the plank, y up, z toward the camera)
    // CONTRACT v2 (round 2): the plank tilts, each seat is its own part on a hinge and only TRANSLATES with its hinge point, level at every angle.
    static let pivotY: Float = 0.27
    static let undersideBelowPivot: Float = 0.015          // beam underside y 0.255
    static let beamHalf = SIMD3<Float>(1.05, 0.045, 0.17)
    static let beamCentreY: Float = 0.30                   // beam top 0.345
    static let cushionX: Float = 0.62, cushionHalf = SIMD3<Float>(0.35, 0.0325, 0.20), cushionCentreY: Float = 0.4425          // x 0.27...0.97, underside 0.410, flat top y 0.475
    static let seatX: Float = 0.66, seatTopY: Float = 0.475
    /// The seat's hinge point (model units, the seat part's pivot is (+-hingeX, hingeY, 0)): the seat moves like this point of the plank and is never turned.
    static let hingeX: Float = 0.62, hingeY: Float = 0.3775
    static let handleX: Float = 0.20, handleHalfX: Float = 0.031, handleTopY: Float = 0.6347, handleBottomY: Float = 0.332, handleBarHalfZ: Float = 0.136, handleBarHalfX: Float = 0.035
    static let bumperX: Float = 0.96, bumperRadius: Float = 0.10, bumperRest: Float = 0.11
    /// The bumper's apex stays this far under the plank's underside while pressed: the dome's flank is not flat, so a tilted plank touches it a little off its centre line.
    static let bumperClearance: Float = 0.0015
    static let pressedFraction: Float = 0.77

    /// The plank's underside height (model units) straight above world x `xb` (model units, about the piece's centre) when the plank is tilted by `theta` (about z; positive raises +x).
    /// The underside line is 0.015 below the pivot line: a point (xl, -0.015) turned by theta about the pivot lands at x = xl cos t + 0.015 sin t, y = xl sin t - 0.015 cos t, so over
    /// world x = xb the underside is y = pivot + xb tan t - 0.015 / cos t. (For the +x end going down, t = -a: y = 0.27 - 0.96 tan a - 0.015 / cos a.)
    static func undersideY(atX xb: Float, theta t: Float) -> Float { pivotY + xb * tanf(t) - undersideBelowPivot / cosf(t) }

    /// The tilt at which the plank's underside first touches the bumper's rest top (0.11) over its centre line: about 0.150 rad.
    static let touchAngle: Float = solveAngle(height: bumperRest)
    /// A: the tilt at which the bumper is pressed down to 77 % of its height (0.0847): about 0.1754 rad. The ride's amplitude, derived from the contract numbers above:
    /// y(a) = 0.27 - 0.96 tan a - 0.015 / cos a falls with a, so a bisection on y(a) = 0.77 * 0.11 finds it.
    static let amplitude: Float = solveAngle(height: pressedFraction * bumperRest)
    private static func solveAngle(height h: Float) -> Float {
        var lo: Float = 0, hi: Float = 0.6
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if undersideY(atX: bumperX, theta: -mid) > h { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }
    /// Bumper apex height (model units) for one end (side -1 = -x, +1 = +x) at plank angle `theta`: rest height, pressed down so the apex stays just under the plank.
    static func bumperTop(side: Float, theta: Float) -> Float {
        let under = undersideY(atX: side * bumperX, theta: theta)
        return max(0.02, min(bumperRest, under - bumperClearance))
    }

    /// How far the seat's hinge moves when the plank is tilted by `theta`, model units: R(theta) * h - h with h = hinge - pivot (the seat is translated by this, never turned).
    static func seatShift(seat: Int, theta t: Float) -> SIMD3<Float> {
        let sx: Float = seat == 0 ? -1 : 1
        let hx = sx * hingeX, hy = hingeY - pivotY
        let c = cosf(t), s = sinf(t)
        return SIMD3(hx * c - hy * s - hx, hx * s + hy * c - hy, 0)
    }
    /// The cushion's top at a seat, piece-local, WORLD units (the drawn piece is scaled by `DecorKind.seesaw.scale`): the sit point translated by the seat's shift (level, no turn).
    static func seatLocal(seat: Int, theta t: Float) -> SIMD3<Float> {
        let k = DecorKind.seesaw.scale
        let sx: Float = seat == 0 ? -1 : 1
        let d = seatShift(seat: seat, theta: t)
        return SIMD3((sx * seatX + d.x) * k, (seatTopY + d.y) * k + seatLift, d.z * k)
    }
    /// A world point (piece-local x, y, z, world units) in the LEVEL seat's own frame, model units: the point with the seat's translation taken out.
    static func toSeat(_ p: SIMD3<Float>, seat: Int, theta t: Float) -> SIMD3<Float> {
        let k = DecorKind.seesaw.scale
        return p / k - seatShift(seat: seat, theta: t)
    }
    /// A world point (piece-local x, y, z, world units) in the plank's own frame, model units: the inverse of the tilt about the pivot.
    static func toPlank(_ p: SIMD3<Float>, theta t: Float) -> SIMD3<Float> {
        let k = DecorKind.seesaw.scale
        let x = p.x / k, y = p.y / k - pivotY, z = p.z / k
        let c = cosf(-t), s = sinf(-t)
        return SIMD3(x * c - y * s, pivotY + x * s + y * c, z)
    }
}

/// A smooth change of a value that starts from the value AND its rate (a cubic Hermite to the target with zero end rate): the plank's angle and its rate stay continuous
/// through every change of mind, and the target is reached exactly.
nonisolated struct SeesawRamp {
    var a0: Float = 0, v0: Float = 0, a1: Float = 0, dur: Float = 0.001, t: Float = 0
    mutating func start(from value: Float, rate: Float, to target: Float, over d: Float) { a0 = value; v0 = rate; a1 = target; dur = max(d, 0.001); t = 0 }
    mutating func advance(_ dt: Float) { t = min(t + dt, dur) }
    var value: Float {
        if t >= dur { return a1 }
        let u = t / dur, u2 = u * u, u3 = u2 * u
        let h00 = 2 * u3 - 3 * u2 + 1, h10 = u3 - 2 * u2 + u, h01 = -2 * u3 + 3 * u2
        return min(max(h00 * a0 + h10 * dur * v0 + h01 * a1, 0), 1)
    }
    var rate: Float {
        if t >= dur { return 0 }
        let u = t / dur, u2 = u * u
        let d00 = 6 * u2 - 6 * u, d10 = 3 * u2 - 4 * u + 1, d01 = -6 * u2 + 6 * u
        return (d00 * a0 + d10 * dur * v0 + d01 * a1) / dur
    }
}

@MainActor
final class SeesawRide {
    static let shared = SeesawRide()
    nonisolated deinit {}          // (a main-actor deinit crashes the Release test host)

    /// What a rider reports each step. coming = walking to his stand spot / turning / waiting for his hop; boarding = the hop up and the sitting down; seated = settled on the cushion;
    /// leaving = getting up (the plank must be still unless he was called away); hopOff = in the hop down.
    enum Stage { case coming, boarding, seated, leaving, hopOff }
    enum Mode { case idle, solo, easing, pairBeat, pairRide, ending, endBeat, leaving, callAway }

    struct Rider {
        var stage: Stage = .coming
        var seatedT: Float = 0
        var hopT: Float = 0
        var forced = false
        var look: Float = 0, bearing: Float = 0          // (the look's share and the last bearing toward a comer: it is held while the look eases out, no snap)
        var prevH: Float = 0, rising = false, topFlag = false
        var reported = false, near = false          // (reported: he has reported himself at least once, i.e. he is at the piece; near: the seated rider saw him within comerNear of his stand spot)
        var waitReason = "", waitT: Float = 0          // (stage 0: what he waits for and for how long: each budget restarts when its own reason begins)
        var apexPrevY: Float = -1, apexRose = false          // (the hop off: the body's centre height of the last step and whether it has risen: the apex is the first step it no longer rises)
    }

    struct Ride {
        var phi: Float = 0
        var ramp = SeesawRamp()
        var amp: Float = 0, ampRate: Float = 0, target: Float = 0
        var theta: Float = 0, thetaRate: Float = 0
        /// The angle the piece is DRAWN with and the riders were placed with: the brains step before the field's tick, so what they read (`theta`) is the angle of the step before this tick; the mesh
        /// is built after the tick and uses that same angle (`drawn`), so the rider and the drawn seat are in the same step.
        var drawn: Float = 0
        var riders: [Int: Rider] = [:]
        var mode: Mode = .idle
        var modeT: Float = 0
        var swingsDone = 0, swingsTarget = 6
        var soloHold: Float = 9
        var order: [Int] = []
        var rng: UInt64 = 0x2545F4914F6CDD1D
        var aloneT: Float = 0, invitesPosted = 0, inviteAt: Float = 0
        var endPending = false          // (the ride was ending when a comer came: if the comer vanishes the rider ends at once, no fresh hold)
        /// The field's layout version this ride last saw (a rebuilt layout with a fresh animation = a new park visit).
        var version = -1
        mutating func rnd(_ r: ClosedRange<Float>) -> Float {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            return r.lowerBound + (r.upperBound - r.lowerBound) * Float(rng >> 40) / Float(1 << 24)
        }
    }
    private(set) var rides: [Int: Ride] = [:]

    // MARK: the invitation
    private(set) var inviteSerials: [Int: Int] = [:]          // serial -> 1 (first item) / 2 (second)
    var rolled = Set<Int>()
    var invitesPostedTotal = 0, noticedTotal = 0
    func isInvite(_ serial: Int) -> Bool { inviteSerials[serial] != nil }
    func isSecondInvite(_ serial: Int) -> Bool { inviteSerials[serial] == 2 }
    /// A lone rider is seated, nobody is coming and a seat is free: somebody may still be invited.
    func inviteOpen(_ uid: Int) -> Bool {
        guard let r = rides[uid] else { return false }
        let seated = r.riders.filter { $0.value.stage == .seated }
        return seated.count == 1 && r.riders.count == 1 && r.mode == .solo
    }
    /// The seated rider's brain reports how near the comer on the other seat is.
    func setNear(_ uid: Int, _ seat: Int, _ near: Bool) { rides[uid]?.riders[seat]?.near = near }
    private func isComer(_ rd: Rider) -> Bool {
        guard rd.stage == .coming || rd.stage == .boarding else { return false }
        return !SeesawTuning.invitations || rd.reported || rd.near
    }
    /// Stage 0 of a comer, for the tests: the last reason word and its numbers by seat, and the waits (max, sum, count, gave up).
    var waitInfo: [Int: String] = [:]
    var waitsMax: Float = 0, waitsSum: Float = 0, waitsN = 0, gaveUp: [String] = []
    /// Seconds he has waited for `reason` (restarts when the reason changes).
    func wait(_ uid: Int, _ seat: Int, _ reason: String, dt: Float, info: String = "") -> Float {
        waitInfo[seat] = reason + "|" + info
        guard var r = rides[uid], var rd = r.riders[seat] else { return 0 }
        if rd.waitReason != reason { rd.waitReason = reason; rd.waitT = 0 }
        rd.waitT += dt
        r.riders[seat] = rd; rides[uid] = r
        return rd.waitT
    }
    /// Somebody is getting off (the other rider, or the ride is ending around a seated one): a comer waits for that, at most 4 s.
    func leaverBlocks(_ uid: Int, _ seat: Int) -> Bool {
        guard let r = rides[uid] else { return false }
        if r.riders.contains(where: { $0.key != seat && ($0.value.stage == .leaving || $0.value.stage == .hopOff) }) { return true }
        switch r.mode { case .ending, .endBeat, .leaving, .callAway: return true; default: return false }
    }
    func noteBoarded(wait: Float) { waitsMax = max(waitsMax, wait); waitsSum += wait; waitsN += 1 }
    /// Hops the hard guard in `seesawHop` refused (a hop farther than `maxHop` from the body's centre); every test expects 0.
    var refusedHops = 0
    /// Riders who found no step-off spot at all (the three normal ones and the ring both empty) and finished on the seat point, inside the footprint (park-room-r3); every test expects 0.
    var noStepOff = 0, ringStepOffs = 0          // (ringStepOffs: riders who got off to the ring spot because the normal ones were blocked)
    /// Stage-0 re-walks to the rider's own spot, by seat, and how far from it he was (the walk-up should already end on the own spot: the tests print these, 0 expected).
    var rewalks: [Int: Int] = [:], rewalkDists: [Float] = []
    func reset() { rides = [:]; inviteSerials = [:]; rolled = []; invitesPostedTotal = 0; noticedTotal = 0; refusedHops = 0; noStepOff = 0; ringStepOffs = 0; rewalks = [:]; rewalkDists = []; waitInfo = [:]; waitsMax = 0; waitsSum = 0; waitsN = 0; gaveUp = [] }
    func theta(_ uid: Int) -> Float { rides[uid]?.theta ?? 0 }
    /// The angle the mesh is drawn with (the one the riders were placed with in the last brain step): the bumpers, the plank, the seats.
    func drawnTheta(_ uid: Int) -> Float { rides[uid]?.drawn ?? 0 }
    func thetaRate(_ uid: Int) -> Float { rides[uid]?.thetaRate ?? 0 }
    func amp(_ uid: Int) -> Float { rides[uid]?.amp ?? 0 }
    func mode(_ uid: Int) -> Mode { rides[uid]?.mode ?? .idle }
    func stage(_ uid: Int, seat: Int) -> Stage? { rides[uid]?.riders[seat]?.stage }
    /// Level and still: nothing moves the seats.
    func still(_ uid: Int) -> Bool { guard let r = rides[uid] else { return true }; return r.amp == 0 && abs(r.theta) < SeesawTuning.levelTol }

    // MARK: the riders' side

    func report(_ uid: Int, _ seat: Int, _ stage: Stage, forced: Bool? = nil) {
        var r = rides[uid] ?? Ride()
        var rd = r.riders[seat] ?? Rider()
        if rd.stage != stage { rd.stage = stage; rd.seatedT = 0; rd.hopT = 0; rd.apexPrevY = -1; rd.apexRose = false; rd.waitReason = ""; rd.waitT = 0 }
        if let f = forced { rd.forced = f }
        rd.reported = true
        r.riders[seat] = rd
        rides[uid] = r
    }
    /// His hop up may start: the plank is level and still, and nobody else is in a hop or getting up on it.
    func mayHopOn(_ uid: Int, _ seat: Int) -> Bool {
        guard let r = rides[uid] else { return true }
        if r.amp != 0 || abs(r.theta) >= SeesawTuning.levelTol { return false }
        switch r.mode { case .ending, .endBeat, .leaving, .callAway: return false; default: break }
        return !r.riders.contains { $0.key != seat && ($0.value.stage == .boarding || $0.value.stage == .leaving || $0.value.stage == .hopOff) }
    }
    /// A seated rider may get up now (normal end of the ride: the plank is still and the order and the 0.3 s gap are kept).
    func mayLeave(_ uid: Int, _ seat: Int) -> Bool {
        guard let r = rides[uid], let rd = r.riders[seat] else { return true }
        if rd.forced { return true }
        guard r.mode == .leaving, r.amp == 0, abs(r.theta) < SeesawTuning.levelTol, let i = r.order.firstIndex(of: seat) else { return false }
        return r.modeT >= (i == 0 ? 0 : SeesawTuning.hopGap)
    }
    /// The top of a swing for this seat happened since the last call (a small happy vocal).
    func takeTop(_ uid: Int, _ seat: Int) -> Bool {
        guard var r = rides[uid], var rd = r.riders[seat], rd.topFlag else { return false }
        rd.topFlag = false; r.riders[seat] = rd; rides[uid] = r
        return true
    }
    /// The hop off has passed its apex: the first call at which the centre height `y` no longer rises after it has risen.
    func apexReached(_ uid: Int, _ seat: Int, y: Float) -> Bool {
        guard var r = rides[uid], var rd = r.riders[seat] else { return true }
        var reached = false
        if rd.apexPrevY >= 0 {
            if y > rd.apexPrevY + 1e-4 { rd.apexRose = true } else if rd.apexRose { reached = true }
        }
        rd.apexPrevY = y
        r.riders[seat] = rd; rides[uid] = r
        return reached
    }
    func bearing(_ uid: Int, _ seat: Int) -> Float { rides[uid]?.riders[seat]?.bearing ?? 0 }
    func setBearing(_ uid: Int, _ seat: Int, _ b: Float) { rides[uid]?.riders[seat]?.bearing = b }
    /// Eases the rider's look toward a comer (0...1) and returns it.
    func lookStep(_ uid: Int, _ seat: Int, want: Float, dt: Float) -> Float {
        guard var r = rides[uid], var rd = r.riders[seat] else { return 0 }
        rd.look += max(-dt / SeesawTuning.lookTime, min(dt / SeesawTuning.lookTime, want - rd.look))
        r.riders[seat] = rd; rides[uid] = r
        return rd.look
    }

    private func postInvite(_ r: inout Ride, _ uid: Int, _ field: DecorField, nth: Int) {
        guard let f = field.foot(uid) else { return }
        field.toys.serial += 1
        field.toys.news.append(ToyNews(serial: field.toys.serial, uid: uid, t: field.toys.clock, pos: f.centre))
        if field.toys.news.count > 4 { field.toys.news.removeFirst() }
        inviteSerials[field.toys.serial] = nth
        invitesPostedTotal += 1
        r.invitesPosted = nth; r.inviteAt = r.aloneT
    }

    // MARK: the plank (called once per step by DecorField.tick)

    /// Advances the ride one step; true while the piece needs its mesh rebuilt (it moves, or somebody is on it).
    @discardableResult
    func tick(_ uid: Int, dt: Float, field: DecorField) -> Bool {
        rides = rides.filter { field.anim[$0.key] != nil }
        var r = rides[uid] ?? Ride()
        let occ = Set((field.seatOccupant[uid] ?? [:]).keys)
        r.riders = r.riders.filter { occ.contains($0.key) }
        // a new park visit: the layout was rebuilt (its version moved) and the piece has a fresh animation (rockT 0: a piece that has been ticking keeps a running clock). A ride left mid-swing
        // starts level and still, and only when nobody is on the piece or coming to it (never a reset under a rider).
        if r.version != field.version {
            if occ.isEmpty, r.version >= 0, field.anim[uid]?.rockT == 0, r.amp != 0 || r.theta != 0 || r.mode != .idle { let rng = r.rng; r = Ride(); r.rng = rng }
            r.version = field.version
        }
        for s in occ where r.riders[s] == nil { r.riders[s] = Rider() }
        for s in Array(r.riders.keys) {
            if r.riders[s]!.stage == .seated { r.riders[s]!.seatedT += dt }
            if r.riders[s]!.stage == .hopOff { r.riders[s]!.hopT += dt }
        }
        r.modeT += dt
        let seated = r.riders.filter { $0.value.stage == .seated }.keys.sorted()
        let comers = r.riders.filter { isComer($0.value) }
        let leavers = r.riders.filter { $0.value.stage == .leaving || $0.value.stage == .hopOff }
        let forced = leavers.contains { $0.value.forced }
        let level = r.amp == 0 && abs(r.theta) < SeesawTuning.levelTol

        func want(_ a: Float, _ d: Float) {
            if abs(r.target - a) > 1e-4 { r.ramp.start(from: r.amp, rate: r.ampRate, to: a, over: d); r.target = a }
        }
        func go(_ m: Mode) { if r.mode != m { r.mode = m; r.modeT = 0 } }

        // a rider who has not started to get up and a comer on the way: the end is called off (back to easing, the pair ride follows); if the comer vanishes the rider ends at once
        if !forced, r.mode == .ending || r.mode == .endBeat || r.mode == .leaving, seated.count == 1, !comers.isEmpty, leavers.isEmpty {
            r.endPending = true; go(.easing); want(0, SeesawTuning.comerEase)
        } else if forced {
            // one rider called away: the leaver goes at once; the plank eases level (0.6 s)
            go(.callAway); want(0, SeesawTuning.callAwayEase)
        } else {
            if seated.count == 2 { r.endPending = false }
            if r.mode == .callAway { go(.idle) }
            switch r.mode {
            case .ending:
                want(0, SeesawTuning.endRamp)
                if level { go(.endBeat) }
            case .endBeat:
                if r.modeT >= SeesawTuning.endBeat {
                    go(.leaving)
                    r.order = seated
                    if r.order.count == 2, r.rnd(0...1) < 0.5 { r.order.reverse() }
                }
            case .leaving:
                // (over when nobody is seated or on his way out: a rider who has taken a seat meanwhile is a comer for the next ride)
                if !r.riders.values.contains(where: { $0.stage == .seated || $0.stage == .leaving || $0.stage == .hopOff }) { go(.idle) }
            default:
                if r.riders.isEmpty { go(.idle); want(0, SeesawTuning.callAwayEase) }
                else if !comers.isEmpty && !seated.isEmpty { go(.easing); want(0, SeesawTuning.comerEase) }
                else if seated.count == 2 {
                    if r.mode != .pairBeat && r.mode != .pairRide { go(.pairBeat) }
                    if r.mode == .pairBeat, r.modeT >= SeesawTuning.pairBeat, level, r.riders.values.allSatisfy({ $0.seatedT >= SeesawTuning.pairBeat }) {
                        go(.pairRide); r.swingsDone = 0; r.swingsTarget = Int(r.rnd(SeesawTuning.swings).rounded())
                        want(1, SeesawTuning.rideRamp)
                    }
                    if r.mode == .pairRide, r.swingsDone >= r.swingsTarget { go(.ending); want(0, SeesawTuning.endRamp) }
                } else if seated.count == 1 && comers.isEmpty && leavers.isEmpty {
                    if r.mode != .solo {
                        if r.endPending { r.endPending = false; go(.ending); want(0, SeesawTuning.endRamp) } else { go(.solo); r.soloHold = r.rnd(SeesawTuning.soloHold); r.swingsDone = 0 }
                    }
                    if r.modeT >= SeesawTuning.settle, r.riders[seated[0]]!.seatedT >= SeesawTuning.settle { want(SeesawTuning.soloAmp, SeesawTuning.soloRamp) }
                    if r.modeT >= r.soloHold { go(.ending); want(0, SeesawTuning.endRamp) }
                } else if seated.isEmpty { want(0, SeesawTuning.comerEase) }
            }
        }

        // the invitation: a rider alone for inviteAlone seconds with a free seat and nobody coming posts ONE news item (the hopscotch's way: not toyPostNews, which would raise the piece's pull),
        // and one more inviteRepeat later; at most two per solo sit
        if SeesawTuning.invitations, r.mode == .solo, seated.count == 1, comers.isEmpty, leavers.isEmpty, r.riders.count == 1 {
            r.aloneT += dt
            if r.invitesPosted == 0, r.aloneT >= SeesawTuning.inviteAlone { postInvite(&r, uid, field, nth: 1) }
            else if r.invitesPosted == 1, r.aloneT >= r.inviteAt + SeesawTuning.inviteRepeat { postInvite(&r, uid, field, nth: 2) }
        } else if seated.isEmpty { r.aloneT = 0; r.invitesPosted = 0 }
        else if r.mode != .solo { r.aloneT = 0 }
        // the motion (the angle the riders used in this step's brain pass is the one drawn)
        r.drawn = r.theta
        r.phi += 2 * .pi / SeesawTuning.period * dt
        if r.phi >= 2 * .pi { r.phi -= 2 * .pi; if r.mode == .pairRide { r.swingsDone += 1 } }
        r.ramp.advance(dt)
        r.amp = r.ramp.value; r.ampRate = r.ramp.rate
        let A = SeesawTuning.amplitude, w = 2 * Float.pi / SeesawTuning.period
        let sv = SeesawTuning.shape(r.phi)
        r.theta = r.amp == 0 ? 0 : A * r.amp * sv
        r.thetaRate = A * (r.ampRate * sv + r.amp * SeesawTuning.shapeRate(r.phi) * w)

        // the top of a swing for each seated rider (his end is up when sign * theta peaks)
        for s in seated {
            var rd = r.riders[s]!
            let h = (s == 0 ? -1 : 1) * r.theta
            let rising = h > rd.prevH
            if rd.rising && !rising && r.amp > 0.5 && h > 0.6 * A * r.amp { rd.topFlag = true }
            rd.rising = rising; rd.prevH = h
            r.riders[s] = rd
        }
        rides[uid] = r
        return r.amp > 0 || r.theta != 0 || !r.riders.isEmpty
    }
}

// MARK: - the rider (BlobBrain)

extension BlobBrain {
    /// His yaw on seat `idleState.seat`: facing across the plank, turned `faceTurn` toward the camera.
    func seesawFacing(_ f: DecorFoot) -> Float {
        let sp = f.kind.sitPoints[min(idleState.seat, f.kind.sitPoints.count - 1)]
        let base = (sp.x < 0 ? 1 : -1) * Float.pi / 2 + f.yaw
        let d = wrapAngle(faceCameraYaw() - base)
        return wrapAngle(base + (d >= 0 ? 1 : -1) * min(SeesawTuning.faceTurn, abs(d)))
    }
    /// The seat's neutral spot (xz) and the seat's height now (the plank is level when he hops on).
    func seesawNeutral(_ f: DecorFoot) -> (xz: SIMD2<Float>, y: Float) {
        let sp = f.kind.sitPoints[min(idleState.seat, f.kind.sitPoints.count - 1)]
        let sw = DecorField.shared.seatWorld(f.uid, seat: idleState.seat) ?? SIMD3(f.centre.x, f.spec.height, f.centre.y)
        return (f.centre + f.turned(SIMD2(sp.x, sp.z)), sw.y)
    }
    /// The spots in front of his seat he hops from and to: straight in front first, then a little to either side. Every one is within `maxHop` of the seat point
    /// (the footprint's half depth is 0.28, the stand gap 0.42: 0.70 straight in front, 0.73 at 0.2 to the side).
    func seesawStandSpots(_ f: DecorFoot, seat: Int) -> [SIMD2<Float>] {
        let sp = f.kind.sitPoints[min(seat, f.kind.sitPoints.count - 1)]
        let dz = SeesawTuning.standDz - sp.z
        return [Float(0), 0.2, -0.2].map { f.centre + f.turned(SIMD2(sp.x + $0, sp.z + dz)) }
    }
    /// The first of those a body can stand on and no friend stands near. Without `origin`: nearest to the seat first, each within `maxHop` of the seat point (the hop up, from his spot).
    /// With `origin` (the body's centre as he is NOW): the nearest to `origin` first, each within `maxHop` of it (the hop down, which must never be longer than `maxHop`).
    func seesawFreeSpot(_ f: DecorFoot, seat: Int, from here: SIMD2<Float>, origin: SIMD2<Float>? = nil) -> SIMD2<Float>? {
        let ignore = decorIgnore
        defer { decorIgnore = ignore }
        let sp = f.kind.sitPoints[min(seat, f.kind.sitPoints.count - 1)]
        let seatXZ = f.centre + f.turned(SIMD2(sp.x, sp.z))
        var spots = seesawStandSpots(f, seat: seat)
        if let origin { spots = spots.sorted { simd_distance($0, origin) < simd_distance($1, origin) } }
        for p in spots where simd_distance(p, origin ?? seatXZ) <= SeesawTuning.maxHop - 0.02 {
            let q = fixed(p)
            if simd_distance(p, q) < 0.05, peerFree(q) { return p }
        }
        return nil
    }
    /// The backstop step-off spot (park-room-r3), used only when `seesawFreeSpot` has none: candidates on rings of 1.0 and 1.1 m round the seat point every 30 degrees (within `maxHop` of the body's
    /// centre, so the hop is the same short one), at least 0.5 m outside the seesaw's footprint, off every other piece, on the floor as it stands (the floor rules move it under 5 cm). The nearest one at least a body
    /// width (peerGap) from the others first; none of those: the one with the largest distance to the nearest other body. nil only when the ring is empty too.
    func seesawStepOffRing(_ f: DecorFoot, seat: Int) -> SIMD2<Float>? {
        let ignore = decorIgnore
        defer { decorIgnore = ignore }
        let sp = f.kind.sitPoints[min(seat, f.kind.sitPoints.count - 1)]
        let seatXZ = f.centre + f.turned(SIMD2(sp.x, sp.z)), here = position
        var cands: [(p: SIMD2<Float>, peer: Float)] = []
        for r: Float in [1.0, 1.1] {
            for k in 0..<12 {
                let a = Float(k) * .pi / 6
                let p = seatXZ + SIMD2(sinf(a), cosf(a)) * r          // (a = 0: straight toward the camera, the normal spot's side)
                guard simd_distance(p, here) <= SeesawTuning.maxHop - 0.02, f.distance(p) >= 0.5, simd_distance(fixed(p), p) < 0.05 else { continue }
                if DecorField.shared.feet.contains(where: { $0.uid != f.uid && $0.distance(p) < 0.1 }) { continue }
                let peer = steerPeers().map { simd_distance($0.pos, p) }.min() ?? .infinity
                cands.append((p, peer))
            }
        }
        let byDistance = cands.sorted { simd_distance($0.p, here) < simd_distance($1.p, here) }
        if let free = byDistance.first(where: { $0.peer >= peerGap }) { return free.p }
        return cands.max { $0.peer < $1.peer }?.p
    }

    /// The body's centre over the floor (what a hop is measured from).
    private func seesawCentreXZ(_ sim: SoftBody) -> SIMD2<Float> { let c = sim.centroid(); return SIMD2(c.x, c.z) }

    /// The one answer to a seesaw invitation (the hook in `toyShouldNotice`): yes for at most ONE Jelbie per item, the nearest free one, with `joinChance` (`secondChance` for the second item).
    func seesawJoinRoll(_ n: ToyNews) -> Bool {
        let R = SeesawRide.shared, f = DecorField.shared
        guard let foot = f.foot(n.uid), f.toys.clock - n.t < SeesawTuning.inviteFresh, R.inviteOpen(n.uid), !R.rolled.contains(n.serial) else { return false }
        var ranked = toyPeers.filter { $0.toyFree }
        ranked.append(self)
        let p = f.position(foot)
        ranked.sort { simd_distance($0.position, p) < simd_distance($1.position, p) }
        guard ranked.first === self else { return false }
        R.rolled.insert(n.serial)
        let yes = rand() < (R.isSecondInvite(n.serial) ? SeesawTuning.secondChance : SeesawTuning.joinChance)
        if yes { R.noticedTotal += 1 }
        return yes
    }

    /// `runBagSit` for the seesaw: stage 0 (turn across the plank, wait for the plank to be still, hop up) and stage 2 (sit down, ride, get up, hop off).
    func seesawRunBagSit(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, _ f: DecorFoot) {
        let R = SeesawRide.shared, uid = f.uid, seat = idleState.seat
        if idleState.bagStage >= 1, poseW <= 0 { let cen = sim.centroid(); px = cen.x; pz = cen.z }
        switch idleState.bagStage {
        case 0:
            R.report(uid, seat, .coming)
            let g = seesawNeutral(f)
            // before the hop he faces the SEAT (the bearing from where he stands), never the seated facing: that turn happens once, in the hop's landing
            idleState.goalYaw = atan2f(g.xz.x - px, g.xz.y - pz)
            // FIRST his own spot (1.0 m out, clear of the cushion: the generic stand spot is 0.81 out, where a landing body reaches into the cushion), THEN the turn: a hop never travels
            // over maxHop, so from farther (a walk that ended short, or the far side spot the generic stand picker may give) he walks to the near spot first, without turning on the way
            let far = simd_distance(position, g.xz) > SeesawTuning.maxHop
            let spot = seesawFreeSpot(f, seat: seat, from: position)
            func giveUp(_ why: String) { R.gaveUp.append(String(format: "%@ seat %d t=%.1f", why, seat, idleState.phaseT)); R.waitInfo[seat] = "gaveup:" + why + "|"; idleFinish(skinner) }
            if far || (spot.map { simd_distance(position, $0) > 0.15 } ?? false) {
                gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
                _ = R.wait(uid, seat, far ? "far" : "rewalk", dt: dt, info: String(format: "root=(%.2f,%.2f) spot=%@", px, pz, spot.map { String(format: "(%.2f,%.2f)", $0.x, $0.y) } ?? "none"))
                guard !feet.active, idleState.phaseT > 0.1 else { return }
                if idleState.decorRetry < Self.standRetries + 3, let spot {
                    idleState.decorRetry += 1
                    R.rewalks[seat, default: 0] += 1; R.rewalkDists.append(simd_distance(position, spot))
                    idleState.target = spot; idleState.decorGo = true
                    scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0
                    script = .walk(target: spot, then: .none); activity = .walking
                    return
                }
                if far { if R.wait(uid, seat, "far", dt: 0) > 2.5 { giveUp("far") }; return }
            }
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.25)
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            if turning || feet.active || idleState.phaseT <= 0.1 {
                _ = R.wait(uid, seat, "turning", dt: dt, info: String(format: "yaw=%.2f goal=%.2f", yaw, idleState.goalYaw))
                return
            }
            // the plank must be level and still (and nobody else in a hop). Behind a rider who is getting off he waits (at most 4 s); anything else holds him 2.5 s, then he turns away at once
            if !R.mayHopOn(uid, seat) {
                let leaver = R.leaverBlocks(uid, seat)
                let t = R.wait(uid, seat, leaver ? "mayHopOn:leaver" : "mayHopOn", dt: dt, info: "mode=\(R.mode(uid)) theta=\(R.theta(uid)) amp=\(R.amp(uid))")
                if t > (leaver ? 4.0 : 2.5) { giveUp(leaver ? "mayHopOn:leaver" : "mayHopOn") }
                return
            }
            // the seat must be clear of anyone walking past (the other seat's rider, seated or on his way, and a sit-together partner do not count)
            let here = position
            let others = socialOthers().filter { o in o !== self && !(o.idleState.kind == .decorSit && o.idleState.decorUID == f.uid) && !(social.map { $0.a === o || $0.b === o } ?? false) }
            let crowded = others.contains { o in
                if simd_distance(o.position, g.xz) < peerGap { return true }
                let d = g.xz - here, l2 = simd_length_squared(d)
                let t = l2 > 1e-6 ? max(0, min(1, simd_dot(o.position - here, d) / l2)) : 0
                return simd_distance(o.position, here + d * t) < peerGap * 0.6
            }
            if crowded {
                if R.wait(uid, seat, "crowded", dt: dt) > 2.5 { giveUp("crowded") }
                return
            }
            // the hop is measured from the root (his spot is in range: he can always hop from it)
            guard seesawHopInRange(sim, to: g.xz) else {
                if R.wait(uid, seat, "range", dt: dt, info: String(format: "root=(%.2f,%.2f) seat=(%.2f,%.2f)", px, pz, g.xz.x, g.xz.y)) > 2.5 { giveUp("range") }
                return
            }
            _ = R.wait(uid, seat, "go", dt: dt, info: String(format: "root=%.3f m from the seat, centre=%.3f m", simd_distance(position, g.xz), simd_distance(seesawCentreXZ(sim), g.xz)))
            let waited = idleState.phaseT
            if seesawHop(sim, to: g.xz, ground: g.y, apex: Self.bagApexUp, facing: seesawFacing(f)) {
                R.noteBoarded(wait: waited)
                idleState.bagStage = 1; idleState.phaseT = 0; idleState.decorBooped = false
                R.report(uid, seat, .boarding)
            }
        case 2:
            seesawSeated(sim, skinner, dt, f)
        default: break
        }
    }

    /// Stage 2: sit down (the ordinary sit, a little shorter reach), ride, get up, hop off.
    private func seesawSeated(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, _ f: DecorFoot) {
        let R = SeesawRide.shared, uid = f.uid, seat = idleState.seat
        var k = idleState.k
        let phT = idleState.phaseT
        let forced = idleState.hold < SeesawTuning.holdMarker * 0.5          // (the idle code zeroed the hold: a request, a feeding, a come-here, a yield)
        switch idleState.phase {
        case 1:
            R.report(uid, seat, .boarding)
            k = smooth01(phT / 1.15)
            if !feet.active && idleState.steps < 2 && phT > Float(idleState.steps) * 0.35 { idleFootStep(reach: SeesawTuning.footReach, rate: SeesawTuning.footRate); idleState.steps += 1 }
            if forced { idleState.phase = 3; idleState.phaseT = 0; idleState.steps = 0 }
            else if phT >= 1.15 && !feet.active { idleState.phase = 2; idleState.phaseT = 0 }
        case 2:
            k = 1
            R.report(uid, seat, .seated, forced: false)
            if forced { R.report(uid, seat, .leaving, forced: true); idleState.phase = 3; idleState.phaseT = 0; idleState.steps = 0 }
            else if R.mayLeave(uid, seat) { R.report(uid, seat, .leaving); idleState.phase = 3; idleState.phaseT = 0; idleState.steps = 0 }
        default:
            R.report(uid, seat, .leaving, forced: forced ? true : nil)
            let dur: Float = forced ? 0.5 : 0.9
            k = min(k, 1 - smooth01(phT / dur))
            if !feet.active && idleState.steps < 2 && phT > Float(idleState.steps) * 0.25 { idleFootStep(reach: 0); idleState.steps += 1 }
            // a called-away one waits (at most calledWaitCap) until the plank is level and still, then goes: the hop starts from the seat
            let plankOK = !forced || R.still(uid) || phT >= SeesawTuning.calledWaitCap
            if phT >= dur && !feet.active && idleState.steps >= 2 && plankOK {
                // the nearest stand spot within maxHop of where the body's centre IS, nobody near it; none: he waits a step and tries again (bounded), never a long hop
                let goal = seesawFreeSpot(f, seat: seat, from: position, origin: position)
                if let goal, seesawHopInRange(sim, to: goal) {
                    idleState.k = 0; sitPose(skinner, 0, slump: false)
                    if seesawHop(sim, to: goal, ground: 0, apex: Self.bagApexDown + max(0, seesawNeutral(f).y - 0.45) * 0.3) {
                        idleState.bagStage = 3; idleState.phaseT = 0
                        R.report(uid, seat, .hopOff)
                        return
                    }
                } else if phT > dur + SeesawTuning.noSpotWait {
                    // no normal spot for 3 s (a friend within a body's width of all three, or a spot off the floor): the ring spot instead (park-room-r3), never a finish on the seat point inside the footprint
                    if let ring = seesawStepOffRing(f, seat: seat),
                       seesawHop(sim, to: ring, ground: 0, apex: Self.bagApexDown + max(0, seesawNeutral(f).y - 0.45) * 0.3) {
                        idleState.bagStage = 3; idleState.phaseT = 0
                        R.ringStepOffs += 1
                        R.report(uid, seat, .hopOff)
                        return
                    }
                    R.noStepOff += 1
                    idleFinish(skinner); return
                }
            }
        }
        idleState.k = k
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        sitPose(skinner, k, slump: false)
        pitch += 0.13 * k          // (the ordinary sit leans back into a backrest: here he sits upright)
        skinner.setEyeOpenness(1 - 0.1 * k)
        seesawRidePose(f, k: k)
    }

    /// The seated rider's motion with the plank: carried by the seat (no lag), leaning with it, a happy face, a happy chirp at the top, a look toward a comer.
    private func seesawRidePose(_ f: DecorFoot, k: Float) {
        let R = SeesawRide.shared, uid = f.uid, seat = idleState.seat
        seesawFollow(f)
        // the plank turns about the world z axis; for a body facing `yaw` that is pitch = -share * theta * sin(yaw), roll = share * theta * cos(yaw)
        let th = R.theta(uid)
        pitch += -SeesawTuning.leanShare * th * sinf(yaw) * k
        roll += SeesawTuning.leanShare * th * cosf(yaw) * k
        // how near is the friend on the other seat: the plank eases level when he is within comerNear of his stand spot (before that the solo rock goes on)
        if SeesawTuning.invitations, let o = socialOthers().first(where: { $0 !== self && $0.idleState.kind == .decorSit && $0.idleState.decorUID == uid && $0.idleState.seat != seat }), !(o.idleState.bagStage == 2 && !o.idleState.decorGo) {
            R.setNear(uid, o.idleState.seat, simd_distance(o.position, o.idleState.target) < SeesawTuning.comerNear || !o.idleState.decorGo)
        }
        // looks toward a comer (the other seat's rider on his way) a little
        var want: Float = 0, bearing = R.bearing(uid, seat)          // (held while the look eases out)
        if let o = socialOthers().first(where: { $0 !== self && $0.idleState.kind == .decorSit && $0.idleState.decorUID == uid && ($0.idleState.bagStage < 2 || ($0.idleState.bagStage == 2 && $0.idleState.phase == 1)) }) {
            want = 1
            bearing = max(-SeesawTuning.lookMax, min(SeesawTuning.lookMax, wrapAngle(atan2f(o.px - px, o.pz - pz) - yaw)))
            R.setBearing(uid, seat, bearing)
        }
        twist = bearing * R.lookStep(uid, seat, want: want, dt: runDt) * k
        // happy while riding
        idleState.slideS -= runDt
        if idleState.slideS <= 0, idleState.phase == 2, R.amp(uid) > 0.05 { face(.happy, hold: 2.0); idleState.slideS = 1.8 }
        if R.takeTop(uid, seat), !voiceMuted, rand() < 0.6 { AudioHub.shared.chirp(jelly: steerID, .happy, x: px, src: "seesaw") }
    }

    /// The root follows the seat's own travel (the seat translates with its hinge, level) in the same step, no lag (`seatFollow`'s rule), and the landing's small offset from the seat point
    /// (under 1 cm) is eased out: a share of the root's distance to the seat point per step, clamped.
    private func seesawFollow(_ f: DecorFoot) {
        guard let sw = DecorField.shared.seatWorld(f.uid, seat: idleState.seat) else { return }
        let sp = f.kind.sitPoints[min(idleState.seat, f.kind.sitPoints.count - 1)]
        let rs = f.turned(SIMD2(sp.x, sp.z))
        let want = SIMD2<Float>(sw.x - (f.centre.x + rs.x), sw.z - (f.centre.y + rs.y))
        var d = want - idleState.seatShift
        let err = SIMD2(sw.x, sw.z) - (position + d), l = simd_length(err)
        if l > 1e-6 { d += err / l * min(l * SeesawTuning.rootPull, SeesawTuning.rootPullMax) }
        idleState.seatShift = want
        guard simd_length(d) > 1e-7 else { return }
        px += d.x; pz += d.y
        feet.pos[0] += d; feet.pos[1] += d
        // a foot step in progress sets the root from its start point every step (`advanceGait`): the seat's travel during the step moves that start point too, or the root falls behind the seat
        // (a called-away rider gets up on a plank that is still easing level: 3.5 cm at one step)
        if stepLive { stepRoot0 += d }
    }

    /// A hop from the root to `goal` is within `maxHop` over the floor (the centre may sit up to 0.16 m behind the root: the tests keep it under `maxHopCentre`).
    func seesawHopInRange(_ sim: SoftBody, to goal: SIMD2<Float>) -> Bool { simd_distance(position, goal) <= SeesawTuning.maxHop }

    /// `bagHop` with a slower hop (`hopSlow`): the same set-up (BlobBrain+Decor.swift), only the duration differs. HARD GUARD: a hop whose floor distance from the body's centre to the goal is over
    /// `maxHop` is refused (false, nothing changed, counted in `SeesawRide.refusedHops`): the callers choose goals in range, this is the safety net.
    @discardableResult
    func seesawHop(_ sim: SoftBody, to goal: SIMD2<Float>, ground: Float, apex: Float, facing: Float? = nil) -> Bool {
        guard seesawHopInRange(sim, to: goal) else { SeesawRide.shared.refusedHops += 1; return false }
        AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.6)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
        gait.wander = false
        let pose = sim.bodyPose(iterations: 6)
        gait.facingYaw = facing ?? faceCameraYaw()
        gait.home = SIMD2(pose.centroid.x, pose.centroid.z)
        poseW = 0; poseOn = false
        gait.hopApex = apex
        gait.hopDuration = SeesawTuning.hopSlow * 0.26 * sqrtf(apex / 0.10) * (1 + 5.0 * max(0, abs(ground - sim.floorY) - 0.41))
        gait.hopToGround = ground
        gait.hop(sim, to: goal, reduceMotion: amplitude < 0.7, chained: false)
        idleState.landT = 0
        return true
    }

    /// `bagBodyTick` for the seesaw: the two hops (up, down) own the body like the bounce. Same as the ordinary tick, with the ride's reports and no seat kick.
    func seesawBodyTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        guard isBagSit, idleState.bagStage == 1 || idleState.bagStage == 3, case .idle = script else { return false }
        let uid = idleState.decorUID, seat = idleState.seat
        activity = .playing
        mouthOpen = 0
        idleState.phaseT += dt
        let hopGoal: Float = -hopTipBack * attentionPitch * amplitude
        pitchBase += max(-1.2 * dt, min(1.2 * dt, hopGoal - pitchBase))
        gait.basePitch = pitchBase
        gait.tick(sim, held: false, reduce: amplitude < 0.7)
        if poseW <= 0 { let cen = sim.centroid(); px = cen.x; pz = cen.z }
        if idleState.bagStage == 1 {
            SeesawRide.shared.report(uid, seat, .boarding)
            if gait.phase == .land, !bagFloorOn {
                // landed ON the level seat: his floor is the seat's top from now on
                bagFloorOn = true
                applyBagFloor(sim, skinner)
                if !idleState.decorBooped { idleState.decorBooped = true; AudioHub.shared.play(.beanbagSit, jelly: steerID, x: px) }
            }
            if bagFloorOn { decorSitPress(uid, 0.5) }
        } else {
            SeesawRide.shared.report(uid, seat, .hopOff)
            decorSitPress(uid, gait.phase == .crouch ? 1 : 0)
            // the cushion stays his floor through the crouch and the rise (he is over it: the skin would sag into it), and goes to the ground at the apex, above both floors
            if bagFloorOn, gait.phase == .land || (gait.phase == .air && SeesawRide.shared.apexReached(uid, seat, y: sim.centroid().y)) { bagFloorOn = false; applyBagFloor(sim, skinner) }
        }
        armWalkWant = 1
        let flap = sinf(2 * .pi * 5 * idleState.phaseT)
        armDirW = 1; armDirEl = [0.45 + 0.1 * flap, 0.45 - 0.1 * flap]; armDirSa = [0.1, 0.1]; armDirOut = 0.05
        driveBeansRigid(sim, skinner, dt, tuck: gait.tuck)
        driveArms(sim, skinner, dt)
        if !gait.isBusy {
            gait.basePitch = 0
            gait.hopApex = 0.10; gait.hopDuration = 0.26
            currentPose(sim)
            armDirW = 0; armDirOut = 0
            if idleState.bagStage == 1 {
                idleState.bagStage = 2; idleState.phaseT = 0; idleState.phase = 1; idleState.steps = 0; idleState.k = 0
                idleState.seatShift = .zero
                script = .idle; activity = .lookingAround
                idleState.hold = SeesawTuning.holdMarker
                idleState.slideS = 0
            } else {
                idleFinish(skinner)
            }
        }
        return true
    }
}
