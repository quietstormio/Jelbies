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
}

struct SleepFidget {
    var nextShift: Float = 0, nextTwitch: Float = 0, nextHalf: Float = 0          // seconds to the next one (0 = not rolled yet)
    var kind = 0                                       // 0 none, 1 wiggle, 2 nuzzle (turn a touch), 3 roll to the other side, 4 drift / scoot
    var u: Float = 0, dur: Float = 1                   // progress 0...1 of the shift in hand
    var yawOff: Float = 0, yawGoal: Float = 0          // slow extra heading (rad)
    var rollOff: Float = 0, rollGoal: Float = 0        // side tilt (rad): which side he lies on
    var wigAmp: Float = 0                              // transient wiggle amplitude (rad)
    var from = SIMD2<Float>.zero, to = SIMD2<Float>.zero, home = SIMD2<Float>.zero
    var twU: Float = -1, twSide = 0, twFoot = false    // twitch progress (-1 = none)
    var halfU: Float = -1                              // half-wake progress (-1 = none)
    var halfAmp: Float = 0
    var rollW: Float { rollOff + (kind == 1 ? wigAmp * sinf(.pi * u) * sinf(2 * .pi * 2 * u) : 0) }
    var active: Bool { kind != 0 || twU >= 0 || halfU >= 0 || yawOff != yawGoal || rollOff != rollGoal }
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
    static let breathPeriod: Float = 3.6
    /// The breathing ripple (was 0.5: too faint to read).
    static let breathKick: Float = 0.9
    /// Sleep fidgets: a shift every `shiftEvery` s, a twitch every `twitchEvery`, a half-wake every `halfEvery` (Reduce Motion: smaller and x2.5 rarer).
    static let shiftEvery: ClosedRange<Float> = 20...60, twitchEvery: ClosedRange<Float> = 9...30, halfEvery: ClosedRange<Float> = 70...200
    static let maxRoll: Float = 0.38, maxYaw: Float = 0.5, rollRate: Float = 0.16, yawRate: Float = 0.12
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
    nonisolated(unsafe) static var holdChance: Float = 0.4
    nonisolated(unsafe) static var cuddleChance: Float = 0.3
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
    /// ... and not under another Jelly (`mates` may be close: they are the pile).
    func sleepSpotOK(_ p: SIMD2<Float>, mates: [BlobBrain] = [], relaxed: Bool = false) -> Bool {
        guard sleepFloorOK(p, relaxed: relaxed) else { return false }
        for o in socialOthers() where o !== self && !mates.contains(where: { $0 === o }) && simd_distance(o.position, p) < peerGap * 0.9 { return false }
        return true
    }

    /// The other Jellies that sleep or are on their way to sleep (the pile).
    var sleepMates: [BlobBrain] { socialOthers().filter { $0 !== self && $0.idleState.kind == .sleep && $0.sleep.stage <= 4 } }

    /// Spacing at which the two reaching arm tips just touch (each arm stands out the capped stub length), never closer than the bodies allow.
    func handSpacing() -> Float {
        let g = armGeometry(el: SleepTuning.holdEl, sa: 0, lift: 1, xShift: 0.07, bodyLed: 1)
        let reach = (g.b.x + g.r2) / (1 - (1 - SleepTuning.lieSquash)).squareRoot()
        return min(max(2 * reach - 0.05, SleepTuning.minGap), 2.2)
    }

    /// Where he lies down: beside the pile if there is one, else here when this is a good spot, else the nearest good spot on the rug.
    /// `hold`: a row spot beside ONE sleeper at the hand-holding spacing (nil partner = no such spot, the usual choice).
    func chooseSleepSpot(hold: Bool = false) -> (spot: SIMD2<Float>, yaw: Float, joined: Bool, partner: BlobBrain?) {
        let mates = sleepMates
        let here = position
        if let lead = mates.min(by: { $0.steerID < $1.steerID }) {
            let ly = lead.sleep.lieYaw
            if hold {
                var bestH: (SIMD2<Float>, BlobBrain, Float)?
                let sp = handSpacing()
                for m in mates where m.sleep.partner == nil && m.sleep.mode == .plain && m.sleep.stage <= 3 {
                    for sgn in [Float(-1), 1] {
                        let p = m.sleep.spot + SIMD2(sgn * sp, 0)
                        var clash = false
                        for o in mates where simd_distance(o.sleep.spot, p) < SleepTuning.minGap { clash = true }
                        guard !clash, sleepSpotOK(p, mates: mates), reachable(here, p) else { continue }
                        let d = simd_distance(here, p)
                        if bestH == nil || d < bestH!.2 { bestH = (p, m, d) }
                    }
                }
                if let b = bestH { return (b.0, b.1.sleep.lieYaw, true, b.1) }
            }
            // a snug place against the sleepers: a ring of spots one body width round each of them (a row, then a triangle); the one touching most and nearest wins
            var best: (SIMD2<Float>, Float)?
            for m in mates {
                for k in 0..<12 {
                    let a = Float(k) * (.pi / 6)
                    let p = m.sleep.spot + SIMD2(cosf(a), sinf(a)) * SleepTuning.pileSpacing
                    var touching = 0, clash = false
                    for o in mates {
                        let d = simd_distance(o.sleep.spot, p)
                        if d < SleepTuning.pileSpacing * 0.93 { clash = true }
                        if d < SleepTuning.pileSpacing * 1.12 { touching += 1 }
                    }
                    guard !clash, sleepSpotOK(p, mates: mates), reachable(here, p) else { continue }
                    let score = simd_distance(here, p) - 1.2 * Float(touching) + 0.4 * abs(sinf(a))          // (a row along x is the neatest)
                    if best == nil || score < best!.1 { best = (p, score) }
                }
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
        if sleepBegin(sim, night: bedtimeHours, force: true) {
            sleep.tucked = true
            sleep.hold = max(sleep.hold, hold)
            restTimer = max(restTimer, 1)
        } else { commanded = false }
    }

    /// Night (the one threshold for wanting bed): the brain never goes to bed by itself then.
    var bedtimeHours: Bool { idleNight > SleepTuning.nightEdge || idleDeepNight > 0.5 }

    // MARK: starting

    /// `idleStart(.sleep)`.
    func sleepBegin(_ sim: SoftBody, night: Bool, force: Bool = false) -> Bool {
        let wantHold = rand() < SleepTuning.holdChance
        // a free pet bed is the preferred spot for a Jelly who sleeps alone: he hops over its rim and curls up on the mattress
        var bed: (foot: DecorFoot, stand: SIMD2<Float>)?
        if sleepMates.isEmpty { bed = freeBed() }
        var c = bed.map { b in (spot: b.foot.centre + b.foot.turned(SIMD2(DecorKind.sleepPoint.x, DecorKind.sleepPoint.z)), yaw: faceCameraYaw(), joined: false, partner: nil as BlobBrain?) } ?? chooseSleepSpot(hold: wantHold)
        if force, bed == nil, !c.joined, !sleepFloorOK(c.spot, relaxed: true) { c = (forceSpot() ?? position, faceCameraYaw(), false, nil) }
        guard force || bed != nil || c.joined || sleepFloorOK(c.spot, relaxed: true) else { sleepTryCool = rand(SleepTuning.tryCool.lowerBound, SleepTuning.tryCool.upperBound); return false }          // nowhere good to lie down that he can reach: not now
        idleBegin(.sleep)
        sleep = SleepState()
        sleep.force = force
        sleep.spot = c.spot; sleep.lieYaw = c.yaw; sleep.joined = c.joined
        if c.joined {
            if let p = c.partner { sleep.mode = .hold; sleep.partner = p; p.sleep.mode = .hold; p.sleep.partner = self }
            else if let lead = sleepMates.min(by: { $0.steerID < $1.steerID }) {
                if rand() < SleepTuning.cuddleChance / max(1 - SleepTuning.holdChance, 0.1) { sleep.mode = .cuddle }
                sleep.partner = sleepMates.min(by: { simd_distance($0.position, c.spot) < simd_distance($1.position, c.spot) }) ?? lead
            }
        }
        sleep.hold = night ? rand(SleepTuning.nightHold.lowerBound, SleepTuning.nightHold.upperBound) : rand(SleepTuning.napHold.lowerBound, SleepTuning.napHold.upperBound)
        if perkFlags.bedtime { sleep.hold *= 1.35 }          // the bedtime perk: a deeper, longer sleep
        if bedtimeHours { sleep.hold = NightRestTuning.untilMorning }
        sleep.minHold = night ? 20 : 12
        if let b = bed {
            sleep.bed = b.foot.uid; sleep.stage = 0
            idleState.decorUID = b.foot.uid; DecorField.shared.occupant[b.foot.uid] = steerID; decorIgnore = b.foot.uid
            script = .walk(target: b.stand, then: .none); activity = .walking
            return true
        }
        if simd_distance(position, c.spot) > 0.25 {
            script = .walk(target: c.spot, then: .none); activity = .walking
            sleep.stage = 0
        } else {
            script = .idle; activity = .lookingAround
            sleep.stage = 1
        }
        return true
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
            let c = chooseSleepSpot(hold: sleep.mode == .hold)
            sleep.spot = c.spot; sleep.lieYaw = c.yaw; sleep.joined = c.joined
            if let p = c.partner, sleep.mode == .hold, p !== sleep.partner { sleep.partner?.sleep.mode = .plain; sleep.partner?.sleep.partner = nil; sleep.partner = p; p.sleep.mode = .hold; p.sleep.partner = self }
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
        sleep.wakeAsked = true
        sleep.groggy = groggy
        if sleep.stage == 3 || sleep.stage == 2 { sleep.kStart = sleep.k; sleep.stage = 4; sleep.t = 0; sleep.stageStart = true }
        _ = fast
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
        case 1:
            // turn to the lying heading, then a big yawn, then down
            if !sleep.turned {
                let turning = turnSteps(goal: sleep.lieYaw, tol: 0.08)
                gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
                if !turning && !feet.active { sleep.turned = true; sleep.t = 0 }
                return
            }
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
            let slow: Float = (sleep.groggy ? 1.5 : 1) * SleepTuning.stretchTime / 2.7
            let t = sleep.t / slow
            let k = smooth01(t / 0.8) * (1 - smooth01((t - 1.7) / 0.6))
            let m = smooth01((t - 0.7) / 0.4) * (1 - smooth01((t - 1.35) / 0.4))
            sleepYawnPose(skinner, k: k, mouth: sleep.groggy ? 0.95 * m : 0, shake: false, sleepy: max(0.95 * (1 - smooth01(sleep.t / (0.6 * SleepTuning.stretchTime / 2.7))), sleep.groggy ? 0.5 * (1 - smooth01((t - 1.6) / 1.2)) : 0))
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            if t > 2.7 && !feet.active {
                skinner.setEyeOpenness(1); mouthOpen = 0; armDirW = 0; armDirOut = 0; armWalkWant = 0
                if sleep.bed >= 0, sleep.bedHop == 0, let f = DecorField.shared.foot(sleep.bed) {
                    sleep.bedHop = 3; sleep.t = 0          // up and over the rim again
                    bagHop(sim, to: bedExitSpot(f), ground: 0, apex: 0.42)
                    return
                }
                idleFinish(skinner)
            }
        default: break
        }
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
        if bedHopTick(sim, skinner, dt) { return true }
        guard idleState.kind == .sleep, case .idle = script, sleep.stage >= 2, sleep.stage <= 4 else { return false }
        activity = .lookingAround
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
            if sleep.wakeAsked || sleep.t >= sleep.hold || (morning && sleep.t >= sleep.minHold && sleep.hold > 600) {
                sleep.kStart = 1; sleep.stage = 4; sleep.t = 0
            }
        default:    // 4: roll back over the way he went down
            let x = min(sleep.t / SleepTuning.rollBackTime, 1)
            sleep.k = sleep.kStart * (1 - x) * (1 - x)          // ease-out: the roll-up pops up fast, then settles onto his feet
            if sleep.t >= SleepTuning.rollBackTime {
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
            sleep.fid.nextTwitch = rand(T.twitchEvery.lowerBound, T.twitchEvery.upperBound) * gap
            sleep.fid.nextHalf = rand(T.halfEvery.lowerBound, T.halfEvery.upperBound) * gap
            sleep.fid.home = position
        }
        // the slow offsets chase their goals at a gentle fixed rate, and snap exactly (so the body can settle and skip its step again)
        var f = sleep.fid
        func chase(_ v: inout Float, _ g: Float, _ rate: Float) {
            let d = g - v
            if abs(d) <= rate * dt { v = g } else { v += d > 0 ? rate * dt : -rate * dt }
        }
        chase(&f.yawOff, f.yawGoal, T.yawRate * (small ? 0.5 : 1))
        chase(&f.rollOff, f.rollGoal, T.rollRate * (small ? 0.5 : 1))
        // the shift in hand
        if f.kind != 0 {
            f.u += dt / f.dur
            if f.kind == 4 {
                let e = smooth01(min(f.u, 1))
                px = f.from.x + (f.to.x - f.from.x) * e; pz = f.from.y + (f.to.y - f.from.y) * e
            }
            if f.u >= 1 {
                if f.kind == 4 { px = f.to.x; pz = f.to.y; sleep.spot = f.to }
                f.kind = 0; f.u = 0; f.wigAmp = 0
            }
        } else {
            f.nextShift -= dt
            if f.nextShift <= 0 {
                f.nextShift = rand(T.shiftEvery.lowerBound, T.shiftEvery.upperBound) * gap
                sleep.fid = f
                sleepStartShift(&f, sc)
            }
        }
        // a twitch (a foot is a tiny jelly flutter, an arm lifts a touch)
        if f.twU >= 0 {
            f.twU += dt / 0.45
            if f.twU >= 1 { f.twU = -1 }
        } else {
            f.nextTwitch -= dt
            if f.nextTwitch <= 0 {
                f.nextTwitch = rand(T.twitchEvery.lowerBound, T.twitchEvery.upperBound) * gap
                f.twU = 0; f.twSide = rand() < 0.5 ? 0 : 1; f.twFoot = rand() < 0.5
                if f.twFoot { jellyKick = max(jellyKick, 0.3 * sc) }
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

    /// Picks one shift: wiggle, nuzzle, roll to the other side, or a slight drift (toward a sleeping friend when there is one).
    private func sleepStartShift(_ f: inout SleepFidget, _ sc: Float) {
        let T = SleepTuning.self
        let r = rand()
        f.u = 0
        if r < 0.3 {          // wiggle and settle
            f.kind = 1; f.dur = rand(2.2, 3.4); f.wigAmp = 0.07 * sc
            jellyKick = max(jellyKick, 0.35 * sc)
        } else if r < 0.55 {  // nuzzle in: a small turn
            f.yawGoal = max(-T.maxYaw, min(T.maxYaw, f.yawOff + rand(-0.3, 0.3) * sc))
            f.kind = 0         // (the offset itself is the move)
        } else if r < 0.75 {  // roll over onto the other side
            f.rollGoal = abs(f.rollOff) < 0.05 || f.rollGoal == 0 ? (rand() < 0.5 ? -1 : 1) * T.maxRoll * sc : -f.rollGoal
            if f.rollGoal == 0 { f.rollGoal = T.maxRoll * sc }
            jellyKick = max(jellyKick, 0.2 * sc)
        } else if sleep.bed < 0 || r < 0.9 {  // a slight change of where he lies
            sleepPlanDrift(&f, sc)
        } else {
            f.kind = 1; f.dur = 2.6; f.wigAmp = 0.05 * sc
        }
    }

    private func sleepPlanDrift(_ f: inout SleepFidget, _ sc: Float) {
        let T = SleepTuning.self
        let mates = sleepMates
        var to = position
        if sleep.bed < 0, sleep.mode != .hold, let o = sleep.partner, o.isNapping {
            let d = o.position - position, len = simd_length(d)
            let want = T.pileSpacing + 0.04
            if len > want + 0.05 { to = position + d / len * min(0.3 * sc, len - want) }
        }
        if to == position {
            let cap = sleep.bed >= 0 ? T.driftMaxBed : T.driftMax
            let a = rand(0, 2 * .pi), m = rand(0.05, cap) * sc
            to = position + SIMD2(cosf(a), sinf(a)) * m
            if simd_distance(to, f.home) > cap { return }
        }
        if sleep.bed < 0 {
            guard sleepSpotOK(to, mates: mates.filter { $0 === sleep.partner }, relaxed: true) else { return }
            guard sleepFloorOK(to, relaxed: true) else { return }
            for o in mates where simd_distance(o.position, to) < T.minGap { return }
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
        let holdWant: Float = (together && (sleep.mode == .hold || sleep.holdForce)) ? 1 : 0, leanWant: Float = (together && sleep.mode == .cuddle) ? 1 : 0
        let hUp = dt / SleepTuning.holdRamp, hDown = dt / SleepTuning.holdRampOut
        sleep.holdW += max(-hDown, min(hUp, holdWant - sleep.holdW))
        sleep.leanW += max(-hDown, min(hUp, leanWant - sleep.leanW))
        if together, let o = sleep.partner {
            let right = SIMD2(cosf(yaw), -sinf(yaw))
            sleep.holdSide = simd_dot(o.position - position, right) > 0 ? 1 : 0
        } else if sleep.holdForce { sleep.holdSide = 1 }
        let leanSign: Float = sleep.holdSide == 1 ? 1 : -1
        let fid = sleep.fid, fa = fid.active && sleep.stage == 3
        let q0 = yawQuat(yaw + (fa ? fid.yawOff : 0)) * simd_quatf(angle: pitchAng, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: SleepTuning.leanAngle * smooth01(sleep.leanW) * leanSign, axis: SIMD3(0, 1, 0))
        let q = fa && (fid.rollW != 0) ? q0 * simd_quatf(angle: fid.rollW, axis: SIMD3(0, 0, 1)) : q0
        var sq = 1 - (1 - SleepTuning.lieSquash) * min(k, 1)
        if sleep.stage == 2 { sq *= 1 - SleepTuning.impactDip * SleepTuning.flopDip(sleep.t) }          // the squash on impact (exactly 1x in stage 3)
        else if sleep.stage == 4 {                                                                          // the wake pop: a taller body for a beat as he comes up
            let x = sleep.t / SleepTuning.rollBackTime
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
        skinner.setEyeOpenness(1 - 0.96 * smooth01(min(1, k * 1.6)) + (fa && fid.halfU >= 0 ? fid.halfAmp * sinf(.pi * fid.halfU) : 0))
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
        } else if fa, fid.twU >= 0, !fid.twFoot {
            // a dream twitch: one arm lifts a touch and drops (the same stub, capped like every arm)
            let rest = ArmPath.armWalkElevation(ArmPath.armWalkCentreDeg), restSa = ArmPath.armWalkCentreDeg * .pi / 180
            armWalkWant = 1
            armDirW = sinf(.pi * fid.twU)
            armDirEl = fid.twSide == 1 ? [rest, SleepTuning.holdEl] : [SleepTuning.holdEl, rest]
            armDirSa = fid.twSide == 1 ? [restSa, 0] : [0, restSa]
            armDirOut = 0.07
        }
        driveBeansRigid(sim, skinner, dt, tuck: 0)
        driveArms(sim, skinner, dt)
    }

    /// Back on his feet: hand the body to the normal pose path (feet re-seeded square under the root).
    private func sleepStand(_ sim: SoftBody, _ skinner: Skinner) {
        sleep.stage = 5; sleep.t = 0
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
                idleFinish(skinner)
            }
        }
        return true
    }
}
