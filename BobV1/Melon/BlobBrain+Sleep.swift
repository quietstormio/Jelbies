//
//  BlobBrain+Sleep.swift
//  Sleep (user 2026-10-19): a Jelly that gets sleepy yawns, rolls onto his BACK where he stands (on the rug / a clear floor spot, not in front of the
//  table or the bowls), shuts his eyes and sleeps belly-up, breathing slowly and snoring now and then. To wake he rolls back over onto his feet the
//  way he went down, stretches (a groggy yawn if somebody tapped him) and carries on.
//
//  PILE: when a Jelly goes to sleep and another one is already asleep (or on his way to sleep) he walks to him and lies down right beside him, so
//  the sleepers form one snuggled row (centre spacing `pileSpacing`, a hair over the body width: touching, never inside each other).
//
//  The roll over is NOT a physics roll: the pose attractor is ramped from upright to `lieAngle` (pitch back, about his x axis inside the heading)
//  with the anchor blended from the feet pivot to the grounded pose, so it is exactly reversible. The feet are the rigid foot beans (like the flip:
//  `driveBeansRigid`, no world foot targets) and the arms stay the rest nubs. Once he has settled the attractor never changes again, so
//  `SoftBody.isSettled` holds and a sleeping Jelly skips his sim step (`JellyActor.brainIsStill`); the breathing is a render-side jelly ripple
//  (`jellyKick`), not the attractor.
//
//  Stages: 0 walk to the spot, 1 turn + yawn, 2 lie down, 3 asleep, 4 roll back, 5 stretch (then `idleFinish`).
//

import Foundation
import simd

struct SleepState {
    var stage = 0
    var t: Float = 0                 // seconds in the stage
    var k: Float = 0                 // 0 standing ... 1 on his back
    var hold: Float = 60             // seconds asleep before he wakes on his own
    var minHold: Float = 14
    var spot = SIMD2<Float>.zero
    var lieYaw: Float = 0
    var wakeAsked = false
    var groggy = false
    var touchT: Float = 0            // seconds a finger has been on him while he sleeps (a tap wakes him gently, a hold lets go of the sleep)
    var breath: Float = 0
    var turned = false
    var joined = false               // lying beside another sleeper
    var stageStart = true
    var kStart: Float = 1
    /// The flop's impact (kick + squish) has fired.
    var impacted = false
    var walkTries = 0
    var clearTries = 0
    /// Put to bed by voice: the room dims and the blanket goes on once everybody is down.
    var tucked = false
    /// Snuggling beside a sleeper (user 2026-10-19): `.hold` = the nearest arm nubs reach a little toward each other and touch while both sleep, `.cuddle` = the joiner
    /// turns slightly toward the other; both breathe in sync. `partner` is the Jelly he lay down beside (the other one gets the reverse link for a hold).
    var mode: SleepMode = .plain
    weak var partner: BlobBrain?
    var holdW: Float = 0
    var holdSide = 1                 // which arm reaches (0 = -x, 1 = +x of the body)
    var leanW: Float = 0
    /// Test hook: the hold shows without a partner (arm-cap / feet suites measure one rig).
    var holdForce = false
    /// A pet bed (decorSleep): the piece's uid (-1 = none), and its hops: 1 turn to the bed, 2 hopping in, 3 hopping out.
    var bed = -1
    var bedHop = 0
    var lieYawHop: Float = 0
    /// A bedtime (the player's word or the night-idle rule): this sleep never fails to lie down.
    var force = false
    var forceRetried = false
    /// Small life while asleep (stage 3 only): shifts, rolls, scoots, twitches, a half-wake. Timers only; see `sleepFidgetTick`.
    var fid = SleepFidget()
    // MARK: staggered bedtime (2026-11-09: three Jelbies yawned, lay down and slept in sync) -- all zero / off for a plain sleep (a daytime nap, `sleepInstant`)
    /// A bedtime from the goodnight: stand with heavy eyes for `linger` s before the walk (stage 0, script .idle), then walk to `lingerTarget` (nil = already there: stage 1).
    var stagger = false
    var lingering = false
    var linger: Float = 0
    var lingerTarget: SIMD2<Float>?
    /// Per-Jelbie yawn timeline (set when the turn is done): a pause, the yawn (x `yawnScale`), maybe a second smaller one, a pause, then the flop.
    var staggerSet = false
    var pre1: Float = 0, pre2: Float = 0, yawnScale: Float = 1
    var yawn2 = false
    // MARK: soft wake (stir in place, slow roll-up, groggy stretch, a half-lid look round): `wakeAsked` is NOT set until the roll starts (mask + snores stay on)
    var softWake = false
    var stirT: Float = -1            // -1 = not stirring; else seconds since the wake was asked (the first `stirLag` of them he just lies there)
    var stirLag: Float = 0, stirDur: Float = 1
    var stirStarted = false
    var stirEye: Float = 0           // the eye crack the stir opened (carried into the roll, fading as the lie blend falls)
    var rollDur: Float = SleepTuning.rollBackTime
    var lookT0: Float = -1
    /// Woken by the meal tray (`callToMeal`): soft wake whatever the call; shown as a non-idle activity so the tray's "stuck idle" retry never re-sends him.
    var mealWake = false
    /// The tray's call that reached him during the stretch (stage 5): kept here (a pending request would abort the stretch) and started by `sleepFinish`.
    var mealCall: BlobRequest?
    var mealWakeT: Float = 0          // seconds since the meal woke him (the group's bounded fallback)
}

struct SleepFidget {
    var nextShift: Float = 0, nextTwitch: Float = 0, nextHalf: Float = 0          // seconds to the next one (0 = not rolled yet)
    var kind = 0                                       // 0 none, 1 wiggle, 2 nuzzle (turn a touch), 3 roll to the other side, 4 drift / scoot
    var u: Float = 0, dur: Float = 1                   // progress 0...1 of the shift in hand
    var yawOff: Float = 0, yawGoal: Float = 0          // slow extra heading (rad)
    var rollOff: Float = 0, rollGoal: Float = 0        // side tilt (rad): which side he lies on
    var ySign: Float = 1, rSign: Float = 1               // the side the NEXT nuzzle / lean goes to (alternates every time: no net turn)
    var wigAmp: Float = 0                              // transient wiggle amplitude (rad)
    var from = SIMD2<Float>.zero, to = SIMD2<Float>.zero, home = SIMD2<Float>.zero
    var twU: Float = -1, twSide = 0, twFoot = false    // twitch progress (-1 = none)
    var halfU: Float = -1                              // half-wake progress (-1 = none)
    var halfAmp: Float = 0
    var rollFrom: Float = 0                            // where the toss in hand started (rollOff is eased from here to rollGoal)
    /// The side tilt now: the side he lies on, plus a slow one-way lean and back while a wiggle is in hand (no oscillation: nothing here moves faster than a breath).
    var rollW: Float { rollOff + (kind == 1 ? wigAmp * powf(sinf(.pi * min(u, 1)), 2) : 0) }          // (sin^2: zero velocity at both ends; a plain sin started with a 5 rad/s^2 kick)
    var active: Bool { kind != 0 || halfU >= 0 || rollOff != 0 }
}

enum SleepMode { case plain, hold, cuddle }

enum SleepTuning {
    /// Pitch (rad) of the body on his back: the face looks up and toward the camera.
    static let lieAngle: Float = 1.05           // (was 1.50 / 86 deg: tipped up about 60 deg so the head end faces the camera and the eye mask reads face-on; feet still toward the camera)
    /// THE FLOP (user 2026-10-20: the slow lean back was "cringy"): an ease-in FALL (k = (t / fallTime)^2) to the impact, a quick overshoot past the lying
    /// pose and a damped spring back; `lieTime` = fall + overshoot + settle, then stage 3 (asleep) with the pose exactly final (isSettled / the sim skip).
    static let fallTime: Float = 0.42, overshootRise: Float = 0.09, overshoot: Float = 0.095, settleTime: Float = 0.35
    static let lieTime: Float = fallTime + overshootRise + settleTime
    /// The wake: a quick ease-out roll-up (a pop) and a short stretch. (The hats' / mask's poof at `holdRoll` of the roll scales with it.)
    static let rollBackTime: Float = 0.5
    static let stretchTime: Float = 1.5
    /// The soft wake (user 2026-11-09 "a slightly slow wake up that's slightly staggered"): stir lying down, a slow smoothstep roll-up, a groggy stretch (x `softStretch`), a short half-lid look round.
    static let stirTime: ClosedRange<Float> = 0.8...1.2, softRollTime: ClosedRange<Float> = 0.8...1.0
    static let softStretch: Float = 1.15, softLookTime: Float = 0.55, stirEyeCrack: Float = 0.24
    /// The yawn before the flop (seconds).
    static let yawnTime: Float = 1.8
    /// Impact: the squash dips to about 0.82 (x lieSquash 0.94 * (1 - impactDip)), the jelly kick.
    static let impactDip: Float = 0.13, impactKick: Float = 2.2, wakeKick: Float = 1.2
    /// ONE night threshold for wanting bed, choosing a night nap length and for the morning wake (they used to be 0.3 / 0.4 / 0.4 and flip-flopped).
    static let nightEdge: Float = 0.4
    /// Only a VERY loud bang wakes a sleeper (clap / whistle / bark only stir him).
    static let earsWakeLevel: Float = 0.92
    /// After any wake he stays up this long (outside deep night), and a failed / abandoned walk to the pile is not retried for this long.
    static let awakeMin: ClosedRange<Float> = 60...150
    static let tryCool: ClosedRange<Float> = 45...90

    /// Lie blend k over the flop (stage 2): k > 1 is the overshoot past the lying pose (the pose adds `overshoot` of the lie angle).
    static func flopK(_ t: Float) -> Float {
        if t < fallTime { let x = max(t, 0) / fallTime; return x * x }
        let u = t - fallTime
        if u < overshootRise { return 1 + overshoot * sinf(.pi / 2 * u / overshootRise) }
        let w = u - overshootRise
        return 1 + overshoot * expf(-w / 0.12) * cosf(2 * .pi * w / 0.42)
    }
    /// The squash dip around the impact, 0...1 (a quick wind-up before, an exponential recovery after).
    static func flopDip(_ t: Float) -> Float {
        if t < fallTime - 0.10 { return 0 }
        if t < fallTime { return smooth01((t - (fallTime - 0.10)) / 0.10) }
        return expf(-(t - fallTime) / 0.10)
    }
    /// Centre spacing of a snuggled row (body width 2R = 1.6, plus the squash widening: touching).
    static let pileSpacing: Float = 1.66
    /// Squash while lying (a little flatter and wider: relaxed).
    static let lieSquash: Float = 0.94
    /// A lying body's footprint, as an ellipse about its spot (half-length along the heading, half-width across it), measured on the DRAWN body in the real
    /// sim (2026-11-05, Release, three sleepers, 120 s with every fidget): the skin reaches +-0.70 along the heading and +-0.76 across it about the soft-body
    /// centroid, and the centroid itself swings up to 0.24 off the spot in the flop and the toss, mostly along the heading (the pitch back). So across the row
    /// the footprint is 0.76 + a little sway, along the heading it is 0.72 + the whole flop swing. No two footprints may intersect (`footMargin` m to spare).
    static let footHalfLen: Float = 0.95, footHalfWid: Float = 0.83, footMargin: Float = 0.03
    /// (2026-11-06, maxRoll 0.30 -> 0.75: re-measured the same way, Release, three sleepers, 120 s x 3 seeds open + blocked: skin across +-0.74...0.76, along -0.69...0.71, i.e. the SAME as
    ///  at 0.30: a body rolling about its own head-to-foot axis is nearly round across it, so the roll does not widen the footprint. The constants stay. A roll toward a close neighbour or in a
    ///  hand-hold is still held to `rollNearMax` (0.30) as a belt-and-braces.)
    /// Hand-holding pairs lie skin to skin on purpose (the stub arms must meet): the measured across-reach 0.76, no margin.
    static let holdHalfWid: Float = 0.77
    static let breathPeriod: Float = 3.6
    /// The breathing ripple (was 0.5: too faint to read).
    static let breathKick: Float = 0.9
    /// Sleep fidgets: a shift every `shiftEvery` s, a twitch every `twitchEvery`, a half-wake every `halfEvery` (Reduce Motion: smaller and x2.5 rarer).
    static let shiftEvery: ClosedRange<Float> = 9...22, twitchEvery: ClosedRange<Float> = 9...30, halfEvery: ClosedRange<Float> = 70...200
    // (2026-11-04: the turn used to wander up to +-0.5 rad at 0.12 rad/s and read as a slow clockwise spin; now small, slow, alternating and always back to centre)
    // (2026-11-06 "rolling over like a kid in bed": maxRoll 0.30 -> `maxRoll` below, shifts about 2.2x as often, and 60 % of them are roll-overs; see `rollRateMax`)
    nonisolated(unsafe) static var maxRoll: Float = 0.75          // (a var only so the no-slide test can compare against the old 0.30)
    static let maxYaw: Float = 0.14, rollRate: Float = 0.05, yawRate: Float = 0.03
    /// A toss / turn eases (smoothstep, so it starts and ends at rest) over this long; nothing a sleeper does is faster. (2026-11-05: they "twitch": the old toss
    /// popped back to flat the frame its constant-rate chase arrived, and there were 0.45 s arm / foot twitches. Both gone.)
    static let tossTime: ClosedRange<Float> = 1.8...3.0
    /// A roll-over is never faster than this many rad/s of smoothstep-AVERAGE speed (peak = 1.5x): a swing of d rad takes at least d / rollRateMax s, so a big roll
    /// from one side to the other (up to 2 * maxRoll = 1.5 rad) takes 6 s and a roll from the back onto a side (0.45...0.75 rad) 1.8...3 s. Peak 0.375 rad/s =
    /// 0.0063 rad per 60 Hz frame, peak angular acceleration 6 * 1.5 / 6^2 = 0.25 rad/s^2: far calmer than the old toss (1.1) and the SleepCalmTests bounds.
    static let rollRateMax: Float = 0.25
    /// With a close neighbour on the side he rolls toward (centre distance under `rollNearDist`), or in a hand-hold / cuddle: the old 0.30 (the row spacing was measured at it).
    static let rollNearMax: Float = 0.30, rollNearDist: Float = 2.3
    static let driftMax: Float = 0.22, driftMaxBed: Float = 0.07
    /// A finger on him for less than this wakes him gently; longer = a real pick up (the sleep is dropped and the touch play takes over).
    static let tapTime: Float = 0.9
    /// Daytime nap hold / evening-night hold, seconds.
    static let napHold: ClosedRange<Float> = 14...26
    static let nightHold: ClosedRange<Float> = 70...110
    /// Joining a sleeper at any time of day: an awake Jelly that sees one fully asleep may come to lie beside him (the roll is made at most every `snuggleCool`).
    static let snuggleChanceTired: Float = 0.30, snuggleChanceRare: Float = 0.06
    static let snuggleCool: ClosedRange<Float> = 80...160
    /// A joiner lies flat with a hand-hold, turned toward the other (cuddle), or just lies there. (Vars so the captures can force one.)
    nonisolated(unsafe) static var holdChance: Float = 0          // (user 2026-11-06: NO hand-hold when sleeping; a joiner just lies down at a normal spot)
    nonisolated(unsafe) static var cuddleChance: Float = 0
    /// Hold: the arm points a touch above sideways; the other arm keeps its hanging stub. Cuddle: turn (rad) toward the other, ramp seconds.
    static let holdEl: Float = 0.12
    static let leanAngle: Float = 0.22
    static let holdRamp: Float = 0.9, holdRampOut: Float = 0.2
    /// The closest two sleepers may lie (bodies never inside each other).
    static let minGap: Float = 1.5
    /// Clearance (from a decor piece's edge to where he lies down).
    static let decorClear: Float = 0.85, decorFlatClear: Float = 0.3          // solid pieces / flat pieces (rug, mat, ball)
    /// The relaxed clearances (a full room with nowhere else): he may lie closer to a piece and nearer the edge of the rug, never inside a piece's footprint.
    static let decorClearRelaxed: Float = 0.5, decorFlatClearRelaxed: Float = 0.1
}

extension BlobBrain {
    // MARK: state read by the stage, the audio hub, the needs and the sim sleep

    /// Settled asleep on his back (the hold stage): music, snores, the slower drain and the sim sleep read this.
    var isNapping: Bool { idleState.kind == .sleep && sleep.stage == 3 && !sleep.wakeAsked }
    /// Any part of the sleep: on the way, lying, waking.
    var isSleeping: Bool { idleState.kind == .sleep }
    /// Lying or rolling (the body is off its feet).
    var isLying: Bool { idleState.kind == .sleep && sleep.stage >= 2 && sleep.stage <= 4 }
    var napDrainScale: Float { isNapping ? (perkFlags.bedtime ? PerkTuning.bedtimeNapDrain : NeedsTuning.napDrain) : 1 }

    // MARK: choosing the spot

    /// Floor he may lie on at `p`: standable, on the rug, clear of the bowls, the call spot, the table and the tray.
    func sleepFloorOK(_ p: SIMD2<Float>, relaxed: Bool = false) -> Bool {
        let q = fixed(p)
        guard simd_distance(q, p) < 0.12 else { return false }
        let L = RoomLayout.self
        guard simd_distance(p, L.rugCentre) < L.rugRadius - (relaxed ? 0.0 : 0.35) else { return false }
        for s in [GameCamera.foodBowlSpot, GameCamera.waterBowlSpot] where simd_distance(p, s) < (relaxed ? 0.7 : 1.0) { return false }
        if simd_distance(p, GameCamera.callSpot) < (relaxed ? 0.9 : 1.3) { return false }
        if simd_distance(p, L.table.centre) < (relaxed ? 1.2 : 1.6) { return false }
        for b in L.dynamicBoxes where L.boxDistanceXZ(p, b) < (relaxed ? 0.8 : 1.1) { return false }
        let solid = relaxed ? SleepTuning.decorClearRelaxed : SleepTuning.decorClear, flat = relaxed ? SleepTuning.decorFlatClearRelaxed : SleepTuning.decorFlatClear
        guard L.decorDistance(p, solidOnly: true) > solid, L.decorDistance(p) > flat else { return false }          // never lain on or under decor
        return true
    }
    /// ... and not under another Jelly (`mates` may be close: they are the pile, but their lying footprints are never overlapped: the elliptical clash below).
    func sleepSpotOK(_ p: SIMD2<Float>, mates: [BlobBrain] = [], relaxed: Bool = false, hold: Bool = false) -> Bool {
        guard sleepFloorOK(p, relaxed: relaxed) else { return false }
        let myYaw = idleState.kind == .sleep ? sleep.lieYaw : faceCameraYaw()
        for o in socialOthers() where o !== self {
            if !mates.contains(where: { $0 === o }) && simd_distance(o.position, p) < peerGap * 0.9 { return false }
            if o.idleState.kind == .sleep, o.sleep.stage <= 4 {          // (a lying body is longer along its heading than it is wide: never a round test)
                if Self.lieClash(p - o.sleep.spot, yawA: myYaw, yawB: o.sleep.lieYaw, hold: hold) || Self.lieClash(p - o.position, yawA: myYaw, yawB: o.sleep.lieYaw, hold: hold) { return false }
            }
        }
        return true
    }

    /// Do two lying footprints (ellipses, `footHalfLen` along the heading, `footHalfWid` across, + `footMargin`) whose centres are `d` apart intersect?
    /// Judged in each body's own heading frame (the pile shares one heading, so the two agree there); either frame saying "inside" is a clash.
    static func lieClash(_ d: SIMD2<Float>, yawA: Float, yawB: Float, hold: Bool = false) -> Bool {
        let hw = hold ? SleepTuning.holdHalfWid : SleepTuning.footHalfWid, k = hold ? 2 : 2 + SleepTuning.footMargin / SleepTuning.footHalfWid
        for y in [yawA, yawB] {
            let l = SIMD2(simd_dot(d, SIMD2(cosf(y), -sinf(y))) / hw, simd_dot(d, SIMD2(sinf(y), cosf(y))) / SleepTuning.footHalfLen)
            if simd_length(l) < k { return true }
        }
        return false
    }
    /// The centre distance at which two footprints just clear each other (+ margin) in direction `dir` (world xz) for a pair with heading `yaw`.
    static func lieReach(_ dir: SIMD2<Float>, yaw: Float) -> Float {
        let u = simd_length(dir) > 1e-4 ? dir / simd_length(dir) : SIMD2<Float>(1, 0)
        let a = simd_dot(u, SIMD2(cosf(yaw), -sinf(yaw))) / SleepTuning.footHalfWid, b = simd_dot(u, SIMD2(sinf(yaw), cosf(yaw))) / SleepTuning.footHalfLen
        return 1.004 * (2 + SleepTuning.footMargin / SleepTuning.footHalfWid) / max((a * a + b * b).squareRoot(), 1e-4)          // (a hair over, so the spot is never exactly on the clash line)
    }

    /// Would lying at `p` (heading `yaw`) overlap another sleeper's reserved spot, lying body or current position? (The last guard before a lie-down: nothing slides after lying.)
    func sleepOverlapsOthers(_ p: SIMD2<Float>, yaw: Float) -> Bool {
        for o in socialOthers() where o !== self && o.idleState.kind == .sleep && o.sleep.stage <= 4 {
            if Self.lieClash(p - o.sleep.spot, yawA: yaw, yawB: o.sleep.lieYaw) || Self.lieClash(p - o.position, yawA: yaw, yawB: o.sleep.lieYaw) { return true }
        }
        return false
    }

    /// The other Jellies that sleep or are on their way to sleep (the pile).
    var sleepMates: [BlobBrain] { socialOthers().filter { $0 !== self && $0.idleState.kind == .sleep && $0.sleep.stage <= 4 } }

    /// Spacing at which the two reaching arm tips just touch (each arm stands out the capped stub length), never closer than the bodies allow.
    func handSpacing() -> Float {
        let g = armGeometry(el: SleepTuning.holdEl, sa: 0, lift: 1, xShift: 0.07, bodyLed: 1)
        let reach = (g.b.x + g.r2) / (1 - (1 - SleepTuning.lieSquash)).squareRoot()
        return min(max(2 * reach - 0.05, SleepTuning.minGap, 2 * SleepTuning.holdHalfWid + 0.01), 2.2)
    }

    /// Where he lies down: beside the pile if there is one, else here when this is a good spot, else the nearest good spot on the rug.
    /// `hold`: a row spot beside ONE sleeper at the hand-holding spacing (nil partner = no such spot, the usual choice).
    func chooseSleepSpot() -> (spot: SIMD2<Float>, yaw: Float, joined: Bool, partner: BlobBrain?) {
        let mates = sleepMates
        let here = position
        if let lead = mates.min(by: { $0.steerID < $1.steerID }) {
            let ly = lead.sleep.lieYaw
            // a snug place against the sleepers: a ring of spots one footprint round each of them; the side-by-side row (a = 0, pi in the lie frame) is tried
            // first and only when every row spot is taken does he lie in front of / behind a sleeper (at the full footprint length), or in a triangle spot
            var best: (SIMD2<Float>, Float)?
            for rowOnly in [true, false] {
                for m in mates {
                    for k in 0..<12 {
                        let isRow = k == 0 || k == 6
                        if isRow != rowOnly { continue }
                        let a = Float(k) * (.pi / 6)
                        let dir = SIMD2(cosf(ly), -sinf(ly)) * cosf(a) + SIMD2(sinf(ly), cosf(ly)) * sinf(a)          // (lie frame: right, then along the heading)
                        let p = m.sleep.spot + dir * Self.lieReach(dir, yaw: ly)
                        var touching = 0, clash = false
                        for o in mates {
                            let d = p - o.sleep.spot
                            if Self.lieClash(d, yawA: ly, yawB: o.sleep.lieYaw) { clash = true }
                            if simd_length(d) < Self.lieReach(d, yaw: ly) * 1.12 { touching += 1 }
                        }
                        guard !clash, sleepSpotOK(p, mates: mates), reachable(here, p) else { continue }
                        let score = simd_distance(here, p) - 1.2 * Float(touching)
                        if best == nil || score < best!.1 { best = (p, score) }
                    }
                }
                if best != nil { break }
            }
            if let b = best { return (b.0, ly, true, nil) }
        }
        let ly = faceCameraYaw() + .pi * (sleepHeadToward ? 1 : 0)
        if sleepSpotOK(here) { return (here, ly, false, nil) }
        var best: (SIMD2<Float>, Float)?
        for ix in -4...4 { for iz in -3...3 {
            let p = SIMD2(Float(ix) * 0.6, 0.25 + Float(iz) * 0.5)
            guard sleepSpotOK(p), reachable(here, p) else { continue }
            let d = simd_distance(here, p)
            if best == nil || d < best!.1 { best = (p, d) }
        } }
        if best == nil {          // a crowded room: a finer look over the whole rug before giving up
            var x: Float = -2.4
            while x <= 2.4001 {
                var z: Float = -2.0
                while z <= 2.2001 {
                    let p = SIMD2<Float>(x, z)
                    if sleepSpotOK(p), reachable(here, p) { let d = simd_distance(here, p); if best == nil || d < best!.1 { best = (p, d) } }
                    z += 0.25
                }
                x += 0.25
            }
        }
        if best == nil {          // a full room: relax the clearances and look again, nearest first (everybody can always sleep somewhere)
            var x: Float = -3.0
            while x <= 3.0001 {
                var z: Float = -2.4
                while z <= 2.6001 {
                    let p = SIMD2<Float>(x, z)
                    if sleepSpotOK(p, relaxed: true), reachable(here, p) { let d = simd_distance(here, p); if best == nil || d < best!.1 { best = (p, d) } }
                    z += 0.2
                }
                x += 0.2
            }
        }
        return (best?.0 ?? here, ly, false, nil)
    }
    /// True = he lies with his head toward the camera (feet away), false = feet toward the camera.
    var sleepHeadToward: Bool { false }

    // MARK: when

    /// Is it time for him to go to sleep now (asked at every autonomous pick): deep night, or another Jelly is asleep / going to sleep (a pile forms:
    /// at night he joins at once, by day only while the first one has just lain down).
    func sleepWanted() -> Bool {
        guard sleepEnabled, social == nil, idleState.kind == nil, !selectedNow else { return false }          // (nobody who is picked goes to bed)
        if bedtimeHours { return false }          // at night he never chooses bed himself: the player's word or the night-idle rule (GameCare+NightRest) decides
        if awakeMin > 0 || sleepTryCool > 0 { return false }          // up for a while after a wake; no bedtime roll right after a failed walk to the pile
        let mates = sleepMates
        if mates.isEmpty { return false }
        let fresh = mates.contains { $0.idleState.t < 20 && $0.sleep.stage <= 3 }
        if fresh && rand() < 0.3 { return true }
        // "come snuggle": any time of day, an awake Jelly may lie down beside one who is fully asleep (the roll starts a cooldown, win or lose)
        if snuggleCool <= 0, !race.active, !sleepLocked, mates.contains(where: { $0.isNapping }) {
            snuggleCool = rand(SleepTuning.snuggleCool.lowerBound, SleepTuning.snuggleCool.upperBound)
            return rand() < (idleNight > 0.2 ? SleepTuning.snuggleChanceTired : SleepTuning.snuggleChanceRare)
        }
        return false
    }

    // MARK: voice: goodnight

    /// "Goodnight": whatever he is doing stops, then the usual sleep (beside the others when somebody is already going to bed), asleep until morning.
    func startGoodnight(_ sim: SoftBody, _ skinner: Skinner) {
        let hold = bedtimeHours ? NightRestTuning.untilMorning : 240
        if idleState.kind == .sleep, !sleep.wakeAsked { sleep.tucked = true; sleep.hold = max(sleep.hold, hold); return }
        var busy = idleState.kind != nil
        if case .none = script {} else { busy = true }
        if busy { abortAll(sim, skinner) }
        pending = nil
        commanded = true
        currentPose(sim)
        if sleepBegin(sim, night: bedtimeHours, force: true, linger: true) {
            sleep.tucked = true
            sleep.hold = max(sleep.hold, hold)
            restTimer = max(restTimer, 1)
        } else { commanded = false }
    }

    /// Night (the one threshold for wanting bed): the brain never goes to bed by itself then.
    var bedtimeHours: Bool { idleNight > SleepTuning.nightEdge || idleDeepNight > 0.5 }

    // MARK: starting

    /// `idleStart(.sleep)`.
    /// `linger`: a bedtime from the goodnight (not a nap, not `sleepInstant`): he first stands a per-Jelbie while with heavy eyes (`SleepOrder`), so three do not set off together.
    func sleepBegin(_ sim: SoftBody, night: Bool, force: Bool = false, linger: Bool = false) -> Bool {
        // a free pet bed is the preferred spot for a Jelly who sleeps alone: he hops over its rim and curls up on the mattress
        var bed: (foot: DecorFoot, stand: SIMD2<Float>)?
        if sleepMates.isEmpty { bed = freeBed() }
        var c = bed.map { b in (spot: b.foot.centre + b.foot.turned(SIMD2(DecorKind.sleepPoint.x, DecorKind.sleepPoint.z)), yaw: faceCameraYaw(), joined: false, partner: nil as BlobBrain?) } ?? chooseSleepSpot()
        if force, bed == nil, !c.joined, !sleepFloorOK(c.spot, relaxed: true) || sleepOverlapsOthers(c.spot, yaw: c.yaw) { c = (forceSpot() ?? position, faceCameraYaw(), false, nil) }
        guard force || bed != nil || c.joined || sleepFloorOK(c.spot, relaxed: true) else { sleepTryCool = rand(SleepTuning.tryCool.lowerBound, SleepTuning.tryCool.upperBound); return false }          // nowhere good to lie down that he can reach: not now
        idleBegin(.sleep)
        sleep = SleepState()
        sleep.force = force
        sleep.spot = c.spot; sleep.lieYaw = c.yaw; sleep.joined = c.joined
        if c.joined {
            if let lead = sleepMates.min(by: { $0.steerID < $1.steerID }) {
                sleep.partner = sleepMates.min(by: { simd_distance($0.position, c.spot) < simd_distance($1.position, c.spot) }) ?? lead
            }
        }
        sleep.hold = night ? rand(SleepTuning.nightHold.lowerBound, SleepTuning.nightHold.upperBound) : rand(SleepTuning.napHold.lowerBound, SleepTuning.napHold.upperBound)
        if perkFlags.bedtime { sleep.hold *= 1.35 }          // the bedtime perk: a deeper, longer sleep
        if bedtimeHours { sleep.hold = NightRestTuning.untilMorning }
        sleep.minHold = night ? 20 : 12
        if linger {
            sleep.stagger = true
            sleep.linger = SleepOrder.delay(.bed, slot: SleepOrder.slot(.bed, self), rand: { self.rand($0, $1) })
        }
        if let b = bed {
            sleep.bed = b.foot.uid; sleep.stage = 0
            idleState.decorUID = b.foot.uid; DecorField.shared.occupant[b.foot.uid] = steerID; decorIgnore = b.foot.uid
            if sleepLingerStart(target: b.stand) { return true }
            script = .walk(target: b.stand, then: .none); activity = .walking
            return true
        }
        if simd_distance(position, c.spot) > 0.25 {
            sleep.stage = 0
            if sleepLingerStart(target: c.spot) { return true }
            script = .walk(target: c.spot, then: .none); activity = .walking
        } else {
            script = .idle; activity = .lookingAround
            sleep.stage = 1
            if sleep.linger > 0.05 { sleep.stage = 0; _ = sleepLingerStart(target: nil) }
        }
        return true
    }

    /// Stage 0 linger (he is `isSleeping` from now: the Cancel pill, `bedtimeWalking` and the NightRest retry loop see him at once): stand still, heavy eyes, then the walk / the turn.
    private func sleepLingerStart(target: SIMD2<Float>?) -> Bool {
        guard sleep.stagger, sleep.linger > 0.05 else { return false }
        sleep.lingering = true; sleep.lingerTarget = target; sleep.t = 0
        script = .idle; activity = .lookingAround
        return true
    }
    /// The linger is over: on to the walk (or, already at the spot, the turn + yawn).
    private func sleepLingerEnd(_ skinner: Skinner) {
        sleep.lingering = false; sleep.t = 0
        skinner.setEyeOpenness(1)
        if let tgt = sleep.lingerTarget {
            sleep.lingerTarget = nil
            scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
            script = .walk(target: tgt, then: .none); activity = .walking
        } else {
            sleep.stage = 1; sleep.stageStart = true
            idleState.phaseT = 0
            script = .idle; activity = .lookingAround
        }
    }

    /// The walk to the spot is over (script .none). Short of it (the leg was given up: somebody stood in the way) he tries again, up to three times,
    /// then lies down where he is. On to the turn + yawn.
    func sleepArrived(_ sim: SoftBody, _ skinner: Skinner) {
        postEvent(.fellAsleep)
        if sleep.bed >= 0 {          // at the foot of the pet bed: turn to it, then the hop over the rim (`sleepBodyTick`)
            sleep.bedHop = 1; sleep.t = 0
            if let f = DecorField.shared.foot(sleep.bed) { let d = f.centre - position; sleep.lieYawHop = atan2f(d.x, d.y) }
            script = .idle; activity = .lookingAround
            idleState.phaseT = 0
            return
        }
        if simd_distance(position, sleep.spot) > 0.6, sleep.walkTries < 3 {
            sleep.walkTries += 1
            // re-plan: the pile may have moved on, so choose again
            let c = chooseSleepSpot()
            sleep.spot = c.spot; sleep.lieYaw = c.yaw; sleep.joined = c.joined
            if simd_distance(position, c.spot) > 0.25 {
                scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
                script = .walk(target: c.spot, then: .none); activity = .walking
                return
            }
        }
        if sleep.force, !sleepFloorOK(position, relaxed: true), !sleep.forceRetried, let f = forceSpot() {
            sleep.forceRetried = true
            sleep.spot = f
            if simd_distance(position, f) > 0.25 {
                scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
                script = .walk(target: f, then: .none); activity = .walking
                return
            }
        }
        if sleep.clearTries < 4, sleepOverlapsOthers(position, yaw: sleep.lieYaw) {          // he stopped short on another sleeper: pick a clear spot and walk there BEFORE lying (never slid after)
            sleep.clearTries += 1
            let c = chooseSleepSpot()
            var s = c.spot
            if sleepOverlapsOthers(s, yaw: c.yaw), let f = forceSpot() { s = f }
            sleep.spot = s; sleep.lieYaw = c.yaw; sleep.joined = c.joined
            if simd_distance(position, s) > 0.25 {
                scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
                script = .walk(target: s, then: .none); activity = .walking
                return
            }
        }
        guard sleep.force || sleepFloorOK(position, relaxed: true) else { sleepTryCool = rand(SleepTuning.tryCool.lowerBound, SleepTuning.tryCool.upperBound); idleFinish(skinner); return }          // no way to a good spot: not here (in front of the table, on the call spot): try again later
        sleep.spot = position
        sleep.stage = 1; sleep.t = 0; sleep.stageStart = true
        idleState.phaseT = 0
        script = .idle; activity = .lookingAround
    }

    // MARK: waking

    /// Wake now: roll back and stretch. `groggy` = a tap (a slower, sleepier stretch); `fast` = something needs him (a meal, a command): no stretch.
    func sleepWake(groggy: Bool, fast: Bool = false) {
        if idleState.kind == .sleep { postEvent(.wokeUp) }
        guard idleState.kind == .sleep else { return }
        if sleep.stage <= 1 { idleState.yielding = true; return }          // not down yet: the usual yield ends it
        if sleep.stage >= 4 { return }
        // a stir in hand: the meal's request just waits for it; a same-moment repeat is ignored; a new ask (a tap, a command) cuts the stir short: today's quick wake
        if sleep.stirT >= 0, !sleep.wakeAsked {
            if sleep.mealWake || SleepOrder.sameMoment(.wake, self) { return }
            sleepRollNow(groggy: groggy); return
        }
        // the soft wake: a meal call always; a group of wake calls in one moment from the 2nd on (the first takes today's quick wake, so a single wake is never slowed);
        // `fast` (race, volley, show: something needs him NOW) never. Only a settled sleeper stirs: mid-flop he just gets up.
        if sleep.stage == 3, sleep.mealWake || !fast {
            let slot = SleepOrder.slot(.wake, self)
            // a second brain joined the moment: this is a group wake, so the first caller (who took the quick path a tick or so ago) is softened too, invisibly
            if slot == 1, !sleep.mealWake, let f = SleepOrder.first(.wake, self), f !== self { f.sleepSoftenQuickWake() }
            if sleep.mealWake || slot > 0 {
                sleepBeginStir(lag: SleepOrder.delay(.wake, slot: slot, rand: { self.rand($0, $1) }), groggy: groggy)
                return
            }
        }
        sleepRollNow(groggy: groggy)
    }

    /// Today's wake: roll back now.
    private func sleepRollNow(groggy: Bool) {
        sleep.wakeAsked = true
        sleep.groggy = groggy
        sleep.stirT = -1
        sleep.softWake = false; sleep.rollDur = SleepTuning.rollBackTime          // (a quick wake never inherits a soft wake's roll time)
        if sleep.stage == 3 || sleep.stage == 2 { sleep.kStart = sleep.k; sleep.stage = 4; sleep.t = 0; sleep.stageStart = true }
    }

    /// Group wake, first caller: his quick roll has barely begun (stage 4 from a settled sleep, at most ~3 ticks): put him back to the lying pose in a zero-lag stir.
    /// `wakeAsked` is cleared again, so `isNapping` (mask, snores) never blinked. Anything further along (or `fast`, which never joins a group) is left alone.
    func sleepSoftenQuickWake() {
        guard idleState.kind == .sleep, sleep.stage == 4, !sleep.softWake, !sleep.mealWake, sleep.kStart > 0.99, sleep.t <= 0.05 else { return }
        sleep.stage = 3; sleep.t = 0; sleep.k = 1; sleep.kStart = 1; sleep.wakeAsked = false
        sleepBeginStir(lag: 0, groggy: true)
    }

    /// The soft wake begins: `lag` s of just lying there, then a stir (an eye crack + a small slow wiggle, still lying, still `isNapping`), then `sleepStirTick` starts the slow roll.
    func sleepBeginStir(lag: Float, groggy: Bool) {
        sleep.softWake = true
        if sleep.mealWake { MealTrace.log("wake BEGIN jelly=\(steerID) lag=\(lag)") }
        sleep.stirT = 0; sleep.stirLag = lag; sleep.stirStarted = false
        sleep.stirDur = rand(SleepTuning.stirTime.lowerBound, SleepTuning.stirTime.upperBound)
        sleep.rollDur = rand(SleepTuning.softRollTime.lowerBound, SleepTuning.softRollTime.upperBound)
    }

    /// Stage 3, while stirring. Positions are never touched (a lying sleeper never slides); the wiggle is the fidget's own eased lean.
    private func sleepStirTick(_ dt: Float) {
        sleep.stirT += dt
        let s = sleep.stirT - sleep.stirLag
        if s < 0 { return }
        if !sleep.stirStarted {
            sleep.stirStarted = true
            if sleep.fid.kind == 0 {
                let sc: Float = amplitude < 0.7 ? 0.4 : 1
                sleep.fid.kind = 1; sleep.fid.u = 0; sleep.fid.dur = sleep.stirDur + 0.05; sleep.fid.wigAmp = (rand() < 0.5 ? -1 : 1) * 0.07 * sc
            }
        }
        sleep.stirEye = SleepTuning.stirEyeCrack * smooth01(s / sleep.stirDur)
        if s >= sleep.stirDur {
            if sleep.mealWake { MealTrace.log("wake ROLL jelly=\(steerID)") }
            sleep.groggy = true; sleep.wakeAsked = true
            sleep.kStart = 1; sleep.stage = 4; sleep.t = 0; sleep.stageStart = true
        }
    }

    // MARK: per-stage work in the normal flow (stages 1 and 5)

    func runSleep(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        sleep.t += dt
        if sleep.bed >= 0, sleep.bedHop == 1 {
            let turning = turnSteps(goal: sleep.lieYawHop, tol: 0.08)
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            if !turning && !feet.active && sleep.t > 0.1, let f = DecorField.shared.foot(sleep.bed) {
                sleep.bedHop = 2; sleep.t = 0
                bagHop(sim, to: f.centre + f.turned(SIMD2(DecorKind.sleepPoint.x, DecorKind.sleepPoint.z)), ground: DecorModels.bedFloor(DecorField.shared.anim[f.uid] ?? DecorAnim(), lift: f.lift), apex: 0.42)
            }
            return
        }
        switch sleep.stage {
        case 0:
            // the linger before the walk (a goodnight only): he stands with heavy eyes and one slow blink, for his own time
            guard sleep.lingering else { break }
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            let lt = sleep.t, mid = sleep.linger * 0.55
            let blink = powf(sinf(.pi * max(0, min(1, (lt - mid) / 0.55))), 2)
            skinner.setEyeOpenness(max(0.1, 1 - 0.4 * smooth01(lt / 0.6) - 0.35 * blink))
            if lt >= sleep.linger { sleepLingerEnd(skinner) }
        case 1:
            // turn to the lying heading, then a big yawn, then down
            if !sleep.turned {
                let turning = turnSteps(goal: sleep.lieYaw, tol: 0.08)
                gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
                if !turning && !feet.active { sleep.turned = true; sleep.t = 0 }
                return
            }
            if sleep.stagger { sleepStaggeredYawn(sim, skinner); return }
            // (the old 3.0 s yawn's shape, played in `yawnTime`)
            let u = sleep.t * 3.0 / SleepTuning.yawnTime
            let k = smooth01(u / 0.8) * (1 - smooth01((u - 2.3) / 0.6))
            let m = smooth01((u - 0.8) / 0.45) * (1 - smooth01((u - 1.9) / 0.45))
            sleepYawnPose(skinner, k: k, mouth: 0.95 * m, shake: u > 0.8 && u < 1.9, sleepy: 0.5 * smooth01((u - 1.5) / 1.4))
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            if sleep.t > SleepTuning.yawnTime && !feet.active { sleepToLie(sim, skinner) }
        case 5:
            // the stretch after the roll back (groggy = slower and sleepier, eyes only half open)
            // (the old 2.7 s stretch's shape, played in `stretchTime`; a groggy one is half again as long)
            if sleep.mealWake { activity = .turning }
            let slow: Float = (sleep.groggy ? (sleep.softWake ? SleepTuning.softStretch : 1.5) : 1) * SleepTuning.stretchTime / 2.7
            let t = sleep.t / slow
            let k = smooth01(t / 0.8) * (1 - smooth01((t - 1.7) / 0.6))
            let m = smooth01((t - 0.7) / 0.4) * (1 - smooth01((t - 1.35) / 0.4))
            sleepYawnPose(skinner, k: k, mouth: sleep.groggy ? 0.95 * m : 0, shake: false, sleepy: max(0.95 * (1 - smooth01(sleep.t / (0.6 * SleepTuning.stretchTime / 2.7))), sleep.groggy ? 0.5 * (1 - smooth01((t - 1.6) / 1.2)) : 0))
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            if sleep.softWake, t > 2.7, !feet.active, sleep.bed < 0 || sleep.bedHop != 0 {
                // the half-lid look round before he carries on (a pet bed's hop out comes straight after the stretch, as today)
                if sleep.lookT0 < 0 { sleep.lookT0 = sleep.t }
                let lu = (sleep.t - sleep.lookT0) / SleepTuning.softLookTime
                sleepYawnPose(skinner, k: 0, mouth: 0, shake: false, sleepy: 0.4 * (1 - smooth01(lu)))
                if lu < 1 { return }
            }
            if t > 2.7 && !feet.active {
                skinner.setEyeOpenness(1); mouthOpen = 0; armDirW = 0; armDirOut = 0; armWalkWant = 0
                if sleep.bed >= 0, sleep.bedHop == 0, let f = DecorField.shared.foot(sleep.bed) {
                    sleep.bedHop = 3; sleep.t = 0          // up and over the rim again
                    bagHop(sim, to: bedExitSpot(f), ground: 0, apex: 0.42)
                    return
                }
                sleepFinish(sim, skinner)
            }
        default: break
        }
    }

    /// The end of the wake (`idleFinish`). A meal-woken sleeper (`callToMeal`) takes the tray's request in THIS tick, so `activity` goes from the shown `.turning` straight to `.walking`
    /// (script `.none` would read `.idle` to the tray's stuck-idle check for a tick). `mealWake` is cleared here: it never outlives the wake. Any other wake: `idleFinish`, as before.
    func sleepFinish(_ sim: SoftBody, _ skinner: Skinner) {
        let meal = sleep.mealWake
        let call = sleep.mealCall
        idleFinish(skinner)
        guard meal else { return }
        MealTrace.log("wake END jelly=\(steerID) (\(sleep.mealWakeT) s since the call)")
        sleep.mealWake = false; sleep.mealCall = nil
        if let r = pending ?? call { pending = nil; start(request: r, sim) }
    }

    /// Stage 1 after the turn, a goodnight bedtime: a pause (heavy eyes), the yawn (x `yawnScale`), for about one in three a gap and a second smaller yawn, a pause, then the flop (unchanged).
    private func sleepStaggeredYawn(_ sim: SoftBody, _ skinner: Skinner) {
        if !sleep.staggerSet {
            sleep.staggerSet = true
            sleep.pre1 = rand(0, 0.4); sleep.pre2 = rand(0, 0.6)
            sleep.yawnScale = rand(0.85, 1.3); sleep.yawn2 = rand() < 1.0 / 3
        }
        let Y1 = SleepTuning.yawnTime * sleep.yawnScale, Y2 = 0.6 * SleepTuning.yawnTime, gap: Float = 0.35
        let t0 = sleep.pre1, t1 = t0 + Y1
        let t1b = sleep.yawn2 ? t1 + gap : t1, t2 = sleep.yawn2 ? t1b + Y2 : t1
        let tEnd = t2 + sleep.pre2
        let t = sleep.t
        func yawn(_ yt: Float, _ dur: Float, _ amp: Float) {
            let u = yt * 3.0 / dur
            let k = smooth01(u / 0.8) * (1 - smooth01((u - 2.3) / 0.6))
            let m = smooth01((u - 0.8) / 0.45) * (1 - smooth01((u - 1.9) / 0.45))
            sleepYawnPose(skinner, k: k * amp, mouth: 0.95 * m * amp, shake: amp > 0.9 && u > 0.8 && u < 1.9, sleepy: 0.5 * smooth01((u - 1.5) / 1.4))
        }
        if t < t0 { sleepYawnPose(skinner, k: 0, mouth: 0, shake: false, sleepy: 0.4 * smooth01(t / 0.5)) }
        else if t < t1 { yawn(t - t0, Y1, 1) }
        else if t < t1b { sleepYawnPose(skinner, k: 0, mouth: 0, shake: false, sleepy: 0.5) }
        else if t < t2 { yawn(t - t1b, Y2, 0.6) }
        else { sleepYawnPose(skinner, k: 0, mouth: 0, shake: false, sleepy: 0.5) }
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        if t > tEnd && !feet.active { sleepToLie(sim, skinner) }
    }

    /// The yawn posture (the same numbers as the idle yawn: arms up as thumbs, the body elongates, a little tip back), eyes squeezed shut.
    private func sleepYawnPose(_ skinner: Skinner, k: Float, mouth: Float, shake: Bool, sleepy: Float) {
        armWalkWant = 1
        let t = sleep.t
        squash *= 1 + 0.15 * smooth01(k) + (shake ? 0.012 * sinf(2 * .pi * 7 * t) : 0)
        pitch += -0.06 * smooth01(k)
        armDirW = smooth01(k)
        armDirEl = [0.95, 0.95]; armDirSa = [0.12, 0.12]; armDirOut = 0.07
        skinner.setEyeOpenness(max(0.05, 1 - 0.85 * smooth01(k) - sleepy))
        mouthOpen = mouth
    }

    func sleepToLie(_ sim: SoftBody, _ skinner: Skinner) {
        sleep.stage = 2; sleep.t = 0; sleep.k = 0; sleep.stageStart = true
        mouthOpen = 0; armDirW = 0; armDirOut = 0; armWalkWant = 0
        // the soles' world targets go: the rigid foot beans follow the body from here (like the flip)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false; walkFinal = false; pivotSide = nil
        gait.wander = false
    }

    // MARK: the body while he is down (stages 2...4), in place of the normal pose / limbs

    /// Ticked from `BlobBrain.tick` right after the idle gate; true = this tick is fully handled.
    func sleepBodyTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        SleepOrder.advance(self, dt)          // (the shared "same moment" reading: every ticking brain's own clock)
        if idleState.kind == .sleep, sleep.mealWake { sleep.mealWakeT += dt }          // (the meal wake's clock runs in EVERY stage of the wake: the stir, the roll, the stretch (stage 5) and a bed hop out, not only 2...4)
        if bedHopTick(sim, skinner, dt) { return true }
        guard idleState.kind == .sleep, case .idle = script, sleep.stage >= 2, sleep.stage <= 4 else { return false }
        activity = sleep.mealWake ? .turning : .lookingAround          // (a meal-woken sleeper is never "idle" to the tray's stuck-idle retry)
        mouthOpen = 0
        sleep.t += dt
        poseOn = true
        switch sleep.stage {
        case 2:
            sleep.k = SleepTuning.flopK(sleep.t)
            if !sleep.impacted, sleep.t >= SleepTuning.fallTime {
                // the impact: a jelly kick and a squish
                sleep.impacted = true
                jellyKick = max(jellyKick, SleepTuning.impactKick)
                AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.8)
            }
            if sleep.t >= SleepTuning.lieTime { sleep.stage = 3; sleep.t = 0; sleep.k = 1; sleep.breath = 0 }
        case 3:
            sleep.k = 1
            sleep.breath += dt
            if sleep.joined, let o = sleep.partner, o.sleep.stage == 3, o.idleState.kind == .sleep { sleep.breath = o.sleep.breath }          // they breathe together
            if sleep.breath >= SleepTuning.breathPeriod { sleep.breath = 0; jellyKick = max(jellyKick, SleepTuning.breathKick) }           // the slow breathing: a soft ripple under the skin (in)
            else if sleep.breath - dt < SleepTuning.breathPeriod * 0.5, sleep.breath >= SleepTuning.breathPeriod * 0.5 { jellyKick = max(jellyKick, SleepTuning.breathKick * 0.45) }          // (and out)
            if !sleep.wakeAsked { sleepFidgetTick(dt) }
            let morning = idleDeepNight < 0.5 && idleNight < SleepTuning.nightEdge
            if sleep.stirT >= 0, !sleep.wakeAsked { sleepStirTick(dt) }
            if sleep.wakeAsked || sleep.t >= sleep.hold {
                sleep.kStart = 1; sleep.stage = 4; sleep.t = 0
            } else if morning && sleep.t >= sleep.minHold && sleep.hold > 600 && sleep.stirT < 0 {
                // the morning: a soft, per-Jelbie-lagged wake (they do not flip on the same frame)
                sleepBeginStir(lag: SleepOrder.delay(.morning, slot: SleepOrder.slot(.morning, self), rand: { self.rand($0, $1) }), groggy: true)
            }
        default:    // 4: roll back over the way he went down
            let x = min(sleep.t / sleep.rollDur, 1)
            sleep.k = sleep.kStart * (sleep.softWake ? 1 - smooth01(x) : (1 - x) * (1 - x))          // ease-out: the roll-up pops up fast, then settles onto his feet (a soft wake: a slow smoothstep)
            if sleep.t >= sleep.rollDur {
                sleep.k = 0
                sleepStand(sim, skinner)
                return false
            }
        }
        applyLie(sim, skinner, dt)
        return true
    }

    // MARK: little movements while asleep

    /// Stage 3 only. Slow and soft; never changes the sleep state. Everything is a timer or a scalar: nothing allocates.
    func sleepFidgetTick(_ dt: Float) {
        let small = amplitude < 0.7
        let sc: Float = small ? 0.4 : 1, gap: Float = small ? 2.5 : 1
        let T = SleepTuning.self
        if sleep.fid.nextShift <= 0 {
            sleep.fid.nextShift = rand(T.shiftEvery.lowerBound, T.shiftEvery.upperBound) * gap
            sleep.fid.nextHalf = rand(T.halfEvery.lowerBound, T.halfEvery.upperBound) * gap
            sleep.fid.home = position
        }
        var f = sleep.fid
        // the shift in hand: every move is eased (smoothstep) so velocity starts and ends at zero
        if f.kind != 0 {
            f.u += dt / f.dur
            let e = smooth01(min(f.u, 1))
            if f.kind == 3 { f.rollOff = f.rollFrom + (f.rollGoal - f.rollFrom) * e }
            if f.kind == 4 {
                px = f.from.x + (f.to.x - f.from.x) * e; pz = f.from.y + (f.to.y - f.from.y) * e
            }
            if f.u >= 1 {
                if f.kind == 3 { f.rollOff = f.rollGoal }
                if f.kind == 4 { px = f.to.x; pz = f.to.y; sleep.spot = f.to }
                f.kind = 0; f.u = 0; f.wigAmp = 0
            }
        } else if sleep.stage == 3, abs(f.rollOff) > T.rollNearMax + 0.02, abs(sleepRollLimited(f.rollOff)) < abs(f.rollOff) - 0.02 {
            // a neighbour came close (or a hand-hold began) while he lies rolled far over: ease back to the measured roll at once (the same slow smoothstep)
            f.kind = 3; f.u = 0; f.rollFrom = f.rollOff; f.rollGoal = sleepRollLimited(f.rollOff)
            f.dur = max(rand(T.tossTime.lowerBound, T.tossTime.upperBound), abs(f.rollGoal - f.rollFrom) / T.rollRateMax)
        } else {
            f.nextShift -= dt
            if f.nextShift <= 0 {
                f.nextShift = rand(T.shiftEvery.lowerBound, T.shiftEvery.upperBound) * gap
                sleep.fid = f
                sleepStartShift(&f, sc)
            }
        }
        // a half-wake: the eyes open a crack, slowly, and close again
        if f.halfU >= 0 {
            f.halfU += dt / 3.2
            if f.halfU >= 1 { f.halfU = -1 }
        } else {
            f.nextHalf -= dt
            if f.nextHalf <= 0 {
                f.nextHalf = rand(T.halfEvery.lowerBound, T.halfEvery.upperBound) * gap
                f.halfU = 0; f.halfAmp = 0.2 * sc + 0.05
            }
        }
        sleep.fid = f
    }

    /// Picks one shift: a toss onto the other side, a slow lean and back, or a slight drift (toward a sleeping friend when there is one). All eased, none with a kick.
    private func sleepStartShift(_ f: inout SleepFidget, _ sc: Float) {
        let T = SleepTuning.self
        let r = rand()
        f.u = 0
        if r < 0.6 {          // roll over: from the back onto a random side; from a side back onto the back or over onto the other side (random, then he stays a while)
            f.kind = 3
            f.rollFrom = f.rollOff
            let amp = rand(0.6, 1) * T.maxRoll * sc
            if abs(f.rollOff) < 0.02 {
                f.rollGoal = (rand() < 0.5 ? -1 : 1) * amp
            } else {
                let side: Float = f.rollOff > 0 ? 1 : -1
                f.rollGoal = rand() < 0.45 ? 0 : -side * amp
            }
            f.rollGoal = sleepRollLimited(f.rollGoal)
            f.dur = max(rand(T.tossTime.lowerBound, T.tossTime.upperBound), abs(f.rollGoal - f.rollFrom) / T.rollRateMax)
        } else if r < 0.78 {  // a slow lean to one side and back
            f.kind = 1; f.dur = rand(2.6, 3.6); f.wigAmp = (rand() < 0.5 ? -1 : 1) * 0.08 * sc
        } else if sleep.bed < 0 && r < 0.86 {  // (user 2026-11-06: a sleeper NEVER changes where he lies; the old drift is gone, this slot is a plain slight lean)
            f.kind = 1; f.dur = 3.0; f.wigAmp = 0.05 * sc
        } else {
            f.kind = 1; f.dur = 3.0; f.wigAmp = 0.05 * sc
        }
    }

    /// The side tilt he may roll to: onto a side with a close neighbour (a snuggle row, a hand-hold pair) only as far as the old `rollNearMax` (the spacing was measured
    /// at that); the free side, and any roll in the open, the full `maxRoll`. A hand-holding pair keeps both hands met: both sides limited.
    func sleepRollLimited(_ goal: Float) -> Float {
        let T = SleepTuning.self
        if goal == 0 { return 0 }
        let near = sleep.mode == .hold || sleep.holdForce || sleep.holdW > 0.1 || sleep.leanW > 0.1
        var cap = near ? T.rollNearMax : T.maxRoll
        let right = SIMD2(cosf(yaw), -sinf(yaw))
        for o in sleepMates where simd_distance(o.position, position) < T.rollNearDist {
            if simd_dot(o.position - position, right) * goal > 0 || abs(simd_dot(o.position - position, right)) < 0.3 { cap = min(cap, T.rollNearMax) }          // (toward him; or in front / behind: either way)
        }
        return goal.sign == .minus ? -min(-goal, cap) : min(goal, cap)
    }

    /// A slight change of where he lies. NEVER toward (or at all beside) another sleeper (user 2026-11-06 "they slide towards each other, like to hold hands"):
    /// a sleeper with a neighbour within `rollNearDist` (a snuggle row, a hand-hold pair, a cuddle) does not move once he lies; a hold only exists where the walk
    /// chose a hold spot before the flop, and a pair that lay down apart simply lies there. (The old partner pull "close up to the footprint gap" is gone.)
    private func sleepPlanDrift(_ f: inout SleepFidget, _ sc: Float) {
        let T = SleepTuning.self
        let mates = sleepMates
        if mates.contains(where: { simd_distance($0.position, position) < T.rollNearDist }) { return }
        let cap = sleep.bed >= 0 ? T.driftMaxBed : T.driftMax
        let a = rand(0, 2 * .pi), m = rand(0.05, cap) * sc
        let to = position + SIMD2(cosf(a), sinf(a)) * m
        if simd_distance(to, f.home) > cap { return }
        for o in mates where simd_distance(o.position, to) < simd_distance(o.position, position) { return }          // never closer to anybody
        if sleep.bed < 0 {
            guard sleepSpotOK(to, mates: mates.filter { $0 === sleep.partner }, relaxed: true, hold: sleep.mode == .hold) else { return }
            guard sleepFloorOK(to, relaxed: true) else { return }
            for o in mates where simd_distance(o.position, to) < T.minGap || Self.lieClash(to - o.position, yawA: sleep.lieYaw, yawB: o.sleep.lieYaw, hold: sleep.mode == .hold) { return }
        }
        f.kind = 4; f.from = position; f.to = to
        f.dur = max(3, simd_distance(position, to) / 0.05)
    }

    /// The attractor at lie blend `sleep.k`.
    private func applyLie(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let k = sleep.k
        let pitchAng = pitchBase * (1 - k) - SleepTuning.lieAngle * k
        // snuggle: ramp the hold arm / the turn toward the other while both sleep, back out when either wakes
        let together = isNapping && !race.active && (sleep.holdForce || (sleep.partner.map { $0.isNapping && simd_distance($0.position, position) < SleepTuning.minGap * 1.5 } ?? false))
        // (in at the snuggle ramp, out fast: the quick roll-up is over in half a second and the arm must be back by then)
        let holdWant: Float = 0, leanWant: Float = 0          // (no hand-hold / cuddle-lean when sleeping, user 2026-11-06)
        let hUp = dt / SleepTuning.holdRamp, hDown = dt / SleepTuning.holdRampOut
        sleep.holdW += max(-hDown, min(hUp, holdWant - sleep.holdW))
        sleep.leanW += max(-hDown, min(hUp, leanWant - sleep.leanW))
        if together, let o = sleep.partner {
            let right = SIMD2(cosf(yaw), -sinf(yaw))
            sleep.holdSide = simd_dot(o.position - position, right) > 0 ? 1 : 0
        } else if sleep.holdForce { sleep.holdSide = 1 }
        let leanSign: Float = sleep.holdSide == 1 ? 1 : -1
        let fid = sleep.fid, fa = fid.active && sleep.stage == 3
        // the side he lies on carries through the wake, fading with the lie blend (never a pop back to flat)
        let rollScale: Float = sleep.stage == 3 ? 1 : (sleep.stage == 4 ? max(0, min(sleep.k, 1)) : 0)
        let q0 = yawQuat(yaw) * simd_quatf(angle: pitchAng, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: SleepTuning.leanAngle * smooth01(sleep.leanW) * leanSign, axis: SIMD3(0, 1, 0))
        // (user 2026-11-04: belly-up he must NEVER spin like a clock hand. The heading offset is gone, and the side roll turns about his own head-to-foot
        //  axis, body y after the pitch back, so he rocks onto a side and back. It used to turn about body z, which points at the sky when lying, so it was a spin.)
        let q = (rollScale > 0 && fid.rollW != 0) ? q0 * simd_quatf(angle: fid.rollW * rollScale, axis: SIMD3(0, 1, 0)) : q0
        var sq = 1 - (1 - SleepTuning.lieSquash) * min(k, 1)
        if sleep.stage == 2 { sq *= 1 - SleepTuning.impactDip * SleepTuning.flopDip(sleep.t) }          // the squash on impact (exactly 1x in stage 3)
        else if sleep.stage == 4 {                                                                          // the wake pop: a taller body for a beat as he comes up
            let x = sleep.t / sleep.rollDur
            if x > 0.5 { sq *= 1 + 0.07 * sinf(.pi * min((x - 0.5) / 0.5, 1)) }
        }
        sim.attractor.rotation = q
        sim.attractor.squash = sq
        var a: SIMD3<Float>
        if geom.valid {
            let m = geom.mid, w = SIMD2(px, pz) + rotXZ(geom.midOff, yaw)
            a = sim.pivotAnchor(rotation: q, squash: sq, pivot: m, world: SIMD3(w.x, sim.floorY + m.y, w.y))
        } else { a = SIMD3(px, sim.groundedAnchorY(rotation: q, squash: sq), pz) }
        // blend to the grounded pose over the body's centre: lying, his middle is over the spot and no part of him is under the floor
        let g = sim.groundedAnchorY(rotation: q, squash: sq)
        let kk = smooth01(min(k, 1))
        a.x += (px - a.x) * kk; a.z += (pz - a.z) * kk
        a.y = max(a.y, g)
        sim.attractor.anchor = a
        sim.attractor.strength = kPose
        poseW = 1
        skinner.setEyeOpenness(min(1, 1 - 0.96 * smooth01(min(1, k * 1.6)) + (fa && fid.halfU >= 0 ? fid.halfAmp * sinf(.pi * fid.halfU) : 0) + sleep.stirEye))
        // feet: the rigid beans ride the body, arms stay the rest nubs
        armWalkWant = 0; armDirW = 0
        if sleep.holdW > 0.001 {
            // the hold: the arm toward the other reaches a little sideways (capped to the stub like every arm), the far one hangs as it walks
            let rest = ArmPath.armWalkElevation(ArmPath.armWalkCentreDeg), restSa = ArmPath.armWalkCentreDeg * .pi / 180
            armWalkWant = 1
            armDirW = smooth01(sleep.holdW)
            armDirEl = sleep.holdSide == 1 ? [rest, SleepTuning.holdEl] : [SleepTuning.holdEl, rest]
            armDirSa = sleep.holdSide == 1 ? [restSa, 0] : [0, restSa]
            armDirOut = 0.07
        }
        driveBeansRigid(sim, skinner, dt, tuck: 0)
        driveArms(sim, skinner, dt)
    }

    /// Back on his feet: hand the body to the normal pose path (feet re-seeded square under the root).
    private func sleepStand(_ sim: SoftBody, _ skinner: Skinner) {
        sleep.stage = 5; sleep.t = 0; sleep.stirEye = 0; sleep.lookT0 = -1
        jellyKick = max(jellyKick, SleepTuning.wakeKick)
        // a good-morning from the nearest awake Jelly (a look at him, then a hop)
        if let g = socialOthers().filter({ $0 !== self && $0.idleState.kind == nil && $0.social == nil && simd_distance($0.position, position) < 6 }).min(by: { simd_distance($0.position, position) < simd_distance($1.position, position) }) {
            g.socialWakeGreetStart(from: self)
        }
        feetInit = false; feet.reset(); stepLive = false; walkFinal = false
        idleState.phase = 0; idleState.phaseT = 0
    }
}

// MARK: - the pet bed

extension BlobBrain {
    /// Spots round the bed (front first, then the sides and the back) a hop from its mattress: 0.4 beyond the rim.
    func bedStandSpots(_ f: DecorFoot) -> [SIMD2<Float>] {
        let r = f.kind.spec.half.y + 0.4          // (piece-local, then turned by its quarter: the "front" of a turned bed is its own front)
        return [Float(0), 0.6, -0.6, 1.2, -1.2, 1.8, -1.8, 2.4, -2.4, .pi].map { f.centre + f.turned(SIMD2(sinf($0), cosf($0)) * r) }
    }
    /// A pet bed nobody uses, with a spot round it he can stand on to hop over the rim.
    func freeBed() -> (foot: DecorFoot, stand: SIMD2<Float>)? {
        let field = DecorField.shared
        for f in field.feet.sorted(by: { simd_distance($0.centre, position) < simd_distance($1.centre, position) }) where f.kind == .petbed && field.available(f) {
            let keep = decorIgnore
            decorIgnore = f.uid          // (he hops over its rim: the bed itself is no wall for the last steps)
            for stand in bedStandSpots(f).sorted(by: { simd_distance($0, position) < simd_distance($1, position) }) {
                let q = fixed(stand)
                if simd_distance(stand, q) < 0.08, peerFree(q), reachable(position, q) { return (f, q) }
            }
            decorIgnore = keep
        }
        return nil
    }
    /// Where he hops down to: the nearest clear spot round the bed to his front.
    func bedExitSpot(_ f: DecorFoot) -> SIMD2<Float> {
        for p in bedStandSpots(f) {
            let q = fixed(p)
            if simd_distance(p, q) < 0.06, peerFree(q) { return p }
        }
        return f.centre + f.turned(SIMD2(0, f.kind.spec.half.y + 0.4))
    }

    /// The two hops over the rim own the body (like the beanbag's): true = this step is handled.
    func bedHopTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        guard idleState.kind == .sleep, sleep.bed >= 0, sleep.bedHop == 2 || sleep.bedHop == 3, case .idle = script, let f = DecorField.shared.foot(sleep.bed) else { return false }
        activity = .playing
        mouthOpen = 0
        sleep.t += dt
        let hopGoal: Float = -hopTipBack * attentionPitch * amplitude
        pitchBase += max(-1.2 * dt, min(1.2 * dt, hopGoal - pitchBase))
        gait.basePitch = pitchBase
        gait.tick(sim, held: false, reduce: amplitude < 0.7)
        if sleep.bedHop == 2 {
            if gait.phase == .land, !bagFloorOn {
                bagFloorOn = true; applyBagFloor(sim, skinner)
                DecorField.shared.kick(f.uid, 1)
                AudioHub.shared.play(.beanbagSit, jelly: steerID, x: px)
            }
        } else if gait.phase == .air || gait.phase == .land, bagFloorOn { bagFloorOn = false; applyBagFloor(sim, skinner) }
        armWalkWant = 1
        let flap = sinf(2 * .pi * 5 * sleep.t)
        armDirW = 1; armDirEl = [0.45 + 0.1 * flap, 0.45 - 0.1 * flap]; armDirSa = [0.1, 0.1]; armDirOut = 0.05
        driveBeansRigid(sim, skinner, dt, tuck: gait.tuck)
        driveArms(sim, skinner, dt)
        if !gait.isBusy {
            gait.basePitch = 0
            gait.hopApex = 0.10; gait.hopDuration = 0.26
            currentPose(sim)
            armDirW = 0; armDirOut = 0
            if sleep.bedHop == 2 {
                sleep.bedHop = 0; sleep.stage = 1; sleep.t = 0; sleep.stageStart = true; sleep.spot = position
                idleState.phaseT = 0
                script = .idle; activity = .lookingAround
            } else {
                sleep.bedHop = 0
                sleepFinish(sim, skinner)
            }
        }
        return true
    }
}

// MARK: - staggering: who goes first

/// Hands out an order index to bedtime / wake calls that reach different Jelbies in the same moment (a loop over the room: the goodnight, "wake up everyone", the tray, the morning),
/// so three Jelbies do not yawn, lie down and wake on the same frame (user 2026-11-09). Each brain only knows itself, so the "same moment" is read off the brains' own clocks:
/// every ticking brain adds its dt to `clocks` (`sleepBodyTick`, once per normal tick); a call joins the open group of its kind while the group's FIRST caller (who must be this brain
/// or one of his room mates) has ticked less than `window`. No wall time except a long expiry, so a test that ticks deterministically gets deterministic groups.
enum SleepOrder {
    enum Kind: Int { case bed = 0, wake = 1, morning = 2 }
    struct Group { weak var first: BlobBrain?; var firstClock: Float = 0; var ids: [ObjectIdentifier] = []; var wall: Double = 0 }
    nonisolated(unsafe) static var clocks: [ObjectIdentifier: Float] = [:]
    nonisolated(unsafe) static var groups = [Group](repeating: Group(), count: 3)
    static let window: Float = 0.3, wallExpiry = 5.0

    static func reset() { clocks = [:]; groups = [Group](repeating: Group(), count: 3) }
    static func advance(_ b: BlobBrain, _ dt: Float) { clocks[ObjectIdentifier(b), default: 0] += dt }

    private static func open(_ kind: Kind, _ b: BlobBrain) -> Group? {
        let g = groups[kind.rawValue]
        guard let f = g.first, ProcessInfo.processInfo.systemUptime - g.wall < wallExpiry else { return nil }
        guard f === b || b.socialOthers().contains(where: { $0 === f }) else { return nil }          // (the same room: a stale group from another room / test is never joined)
        guard (clocks[ObjectIdentifier(f)] ?? 0) - g.firstClock < window else { return nil }
        return g
    }
    /// 0 for the first caller in a moment, 1 for the second, ... (the same brain asked again in the same moment keeps his index).
    static func slot(_ kind: Kind, _ b: BlobBrain) -> Int {
        let id = ObjectIdentifier(b)
        if var g = open(kind, b) {
            if let i = g.ids.firstIndex(of: id) { return i }
            g.ids.append(id); groups[kind.rawValue] = g
            return g.ids.count - 1
        }
        groups[kind.rawValue] = Group(first: b, firstClock: clocks[id] ?? 0, ids: [id], wall: ProcessInfo.processInfo.systemUptime)
        return 0
    }
    /// The first caller of the open group (nil when none is open for this brain).
    static func first(_ kind: Kind, _ b: BlobBrain) -> BlobBrain? { open(kind, b)?.first }
    /// Has this brain already been counted in the open group of this kind?
    static func sameMoment(_ kind: Kind, _ b: BlobBrain) -> Bool { open(kind, b)?.ids.contains(ObjectIdentifier(b)) ?? false }

    /// Seconds from the call to his own start. Bed: ~0-0.5 / 1.0-1.8 / 2.2-3.2 (a linger before the walk). Wake and morning: 0-0.3 / 0.7-1.5 / 1.6-2.8 (lying still before the stir).
    static func delay(_ kind: Kind, slot: Int, rand: (Float, Float) -> Float) -> Float {
        switch kind {
        case .bed: return slot == 0 ? rand(0, 0.4) : slot == 1 ? rand(1.2, 1.8) : rand(2.4, 3.2) + 0.9 * Float(slot - 2)
        case .wake, .morning: return slot == 0 ? rand(0, 0.3) : slot == 1 ? rand(0.7, 1.5) : rand(1.6, 2.8) + 0.8 * Float(slot - 2)
        }
    }
}
