//
//  BlobSocial+Hands.swift
//  THE HAND REACH (2026-11-05, user rule 2: a hand must END on the partner's skin, 0 +- 0.5 cm, never inside).
//
//  The arms are stubs (a 0.225 shoulder-to-tip capsule at the sides of the egg, capped by the wave's thumb), so a hand can only get PAST the skin of a body that stands beside the
//  partner: out to the side the pole of the hand stands 0.24 beyond the flank, straight forward it stays 2 cm BEHIND the belly. So every hand emote stands side by side (both facing the camera) and
//  reaches across the gap. The footprint the contact engine measures (ContactField) is height-blind: its widest part of a body standing at rest is the resting arm nub (0.695 from the centre, at hand
//  height), so what a raised hand meets is the PARTNER'S ARM (nub) - skin like any other - and the stance row simply stands the walk-up `reachBeyondNub` short of the touch, with the arm still down.
//
//  A drive only says WHICH arm, HOW MUCH and the elevation it likes (`socialBook.handWant`, set every tick like the pose overlays); `socialHandsTick` (called from socialTick after the drive) eases the arm
//  override in and out and, in `seek` mode, solves the elevation of the reaching arm so that the POLE of the hand sits exactly ON the partner's skin: the hand's pole (shoulder + axis * (length + tip radius))
//  is carried into the partner's rest frame with his fitted pose and the elevation is bisected until his egg's signed distance there is 0. The hand then rests on the skin whatever the bodies' small
//  mismatch (lean, squash, a few cm of stand-off) - the stance only has to bring the bodies to hand reach.
//

import Foundation
import simd

/// What a drive asks of the arms for this tick.
struct HandReach: Sendable {
    var side: Int                 // 0 = the arm at -x, 1 = the arm at +x
    var w: Float = 1              // 0...1: how far the arm override is wanted (eased over 0.3 s)
    var el: Float = HandReach.elBoop        // the elevation (rad) the arm likes (the hover pose, and the seek's first guess)
    var seek = true               // solve the elevation so the pole lands ON the partner's skin
    var partner = -1              // steerID of the one the hand reaches for
}

extension HandReach {
    static var elBoop: Float { elNub }                   // (the pole at the height of the resting nub's widest point: the hand meets the partner's arm where the footprint says the skins meet)
    static let elFive: Float = 0.08          // (a small raise: the footprint meets the hands at the SPHERES of the tips, the metric at their poles - the steeper the arm the further apart they are: r2 (1 - cos) each)
    /// Where the hand-emote stances stand before the press (skin gap): a hair above the 0.5 cm touch window so the touch is the press, under the 1.5 cm arrival bar.
    static let stand: Float = 0.008
    /// The arm of the shoulder at +x/-x, from the walking-arm data (body frame, +x arm).
    static var shoulder: SIMD3<Float> { SIMD3(Float(ArmPath.armWalkRoot.x), Float(ArmPath.armWalkRoot.y), Float(ArmPath.armWalkRoot.z)) }
    /// Shoulder to the pole of the hand along the axis (the capsule's length + the tip radius).
    static var armLength: Float { Float(ArmPath.armWalkRoot.length + ArmPath.armWalkRoot.r2) }
    /// The pole of the hand in the body frame (+x arm convention) at elevation `el` and sweep `sa` (the walking arm's own parameterisation).
    static func pole(el: Float, sa: Float, out: Float = 0) -> SIMD3<Float> {
        shoulder + SIMD3(out, 0, 0) + SIMD3(cosf(el) * cosf(sa), sinf(el), cosf(el) * sinf(sa)) * armLength
    }
    /// The widest lateral extent of the RESTING body (egg + the arm nub hanging at the side, feet excluded) and where it is (height, z): what the contact engine's footprint sees of a body whose arms are down.
    /// The hand lands THERE (the footprint's extreme and the hand's 3D contact then agree).
    static let restExtreme: (x: Float, y: Float, z: Float) = {
        var best = (x: 0.0, y: 0.0, z: 0.0)
        for iy in 0...60 { for iz in -10...10 {
            let y = 0.15 + 0.9 * Double(iy) / 60, z = Double(iz) * 0.02
            var lo = 0.3, hi = 1.0
            for _ in 0..<30 { let m = 0.5 * (lo + hi); if restSDF(SIMD3(m, y, z)) < 0 { lo = m } else { hi = m } }
            if lo > best.x { best = (lo, y, z) }
        } }
        return (Float(best.x), Float(best.y), Float(best.z))
    }()
    static var restHalfWidth: Float { restExtreme.x }
    /// Elevation (sweep 0) at which the pole is level with the extreme, and the z of the extreme (the sweep aims the pole at it).
    static let elNub: Float = asinf(max(-1, min(1, (restExtreme.y - shoulder.y) / armLength)))
    /// The resting body's skin (rest frame, x folded to +): the egg and the hanging arm nub.
    static func restSDF(_ q: SIMD3<Double>) -> Double {
        guard q.x.isFinite, q.y.isFinite, q.z.isFinite else { return 9 }
        return min(BobForm.bodySDF(q), BobForm.armSDF(SIMD3(abs(q.x), q.y, q.z)).d)
    }
    /// How far the hand at `el` (sweep 0) stands out past the resting body's widest point: the walk-up stops this short of the touch (the arm is still down), the raised arm closes it.
    static func reachBeyondNub(el: Float, sa: Float = 0) -> Float { pole(el: el, sa: sa).x - restHalfWidth }
    /// The sweep that puts the pole level (in z) with the partner's resting arm when both stand side by side facing the camera.
    static var saNub: Float { asinf(max(-0.9, min(0.5, (restExtreme.z - shoulder.z) / (armLength * cosf(elBoop))))) }
    /// Boop: bodies side by side, the hand across the gap onto the partner's arm.
    static var gapBoop: Float { reachBeyondNub(el: elBoop, sa: saNub) }
    /// High five: two hands meet in the middle, so the walk-up stops two reaches short.
    static let gapFive: Float = 2 * reachBeyondNub(el: elFive)
}

extension BlobBrain {
    /// Which arm (0 = -x, 1 = +x) faces the partner.
    func handSide(toward o: BlobBrain) -> Int {
        rotXZ(o.position - position, -faceCameraYaw()).x >= 0 ? 1 : 0          // (as he will stand: side by side facing the camera, not as he happens to walk)
    }

    /// The body frame of a sim as the arm capsules are placed in it: world = org + RS * local (the attractor, exactly as driveArms builds it).
    func armFrame(_ sim: SoftBody) -> (RS: simd_float3x3, org: SIMD3<Float>) {
        let att = sim.attractor, sya = att.squash, sxza = 1 / sya.squareRoot(), c0 = sim.restCentroid
        let RS = simd_float3x3(att.rotation) * simd_float3x3(diagonal: SIMD3(sxza, sya, sxza))
        return (RS, att.anchor - RS * c0)
    }

    /// A world point in the REST frame of `sim`'s body as it is now (the fitted pose; the inverse of `bodyPointWorld`), x folded to the +x half for the symmetric egg.
    func restPoint(of pw: SIMD3<Float>, sim: SoftBody) -> SIMD3<Double> {
        let p = sim.bodyPose(iterations: 3)
        let sy = sim.attractor.squash, sxz = 1 / sy.squareRoot()
        let o = simd_float3x3(p.rotation).transpose * (pw - p.centroid)
        let r = sim.restCentroid + SIMD3(o.x / sxz, o.y / sy, o.z / sxz)
        return SIMD3(Double(abs(r.x)), Double(r.y), Double(r.z))
    }

    /// Every tick after the drive: ease the arm override in / out and (seek) put the pole of the reaching hand on the partner's skin.
    func socialHandsTick(_ sim: SoftBody, _ dt: Float) {
        let want = socialBook.handWant
        if let want { socialBook.handLast = want }
        let goal: Float = want?.w ?? 0
        socialBook.handW += max(-dt / 0.30, min(dt / 0.30, goal - socialBook.handW))
        if socialBook.handW <= 0.0005 && goal == 0 {
            socialBook.handW = 0
            if socialBook.handOn { socialBook.handOn = false; armReachW = 0; armDirW = 0; armDirOut = 0 }
            return
        }
        guard let q = want ?? socialBook.handLast else { return }
        let si = q.side, other = 1 - si
        if !socialBook.handOn {
            socialBook.handOn = true
            socialBook.handEl = [q.el, q.el]; socialBook.handSa = [0, 0]; socialBook.handOut = 0
        }
        armReachW = 1; armDirW = socialBook.handW; armDirOut = socialBook.handOut
        // the free arm hangs relaxed, a little forward
        armDirEl[other] = -0.25; armDirSa[other] = 0.35
        var elT = q.el, saT: Float = 0
        let sg: Float = si == 0 ? -1 : 1
        if goal > 0, let o = socialBrain(q.partner), let osim = o.simRef {
            let sh = HandReach.shoulder, sgP = -sg
            // (until the press everything is judged in the RELAXED frame of both bodies - the pose with the attractor's squash taken out: the walk's landing squash narrows a body ~8 % across for a few steps and he widens again once he
            // stands, which is how a hand that touched at the last step used to end 2 cm inside the partner)
            let settled = (social?.phase ?? 0) >= 2          // (from the press on the squash is the move's own - the giggle, the squish - and the arm follows it: the hand is judged where it IS, not where the body relaxes to)
            var (RS, org) = settled ? armFrame(sim) : relaxedFrame(sim)
            let (RSo, orgo) = settled ? o.armFrame(osim) : o.relaxedFrame(osim)
            // A WALKER'S arm stays in its canonical pose until he stands: the touch distance the stance reads (and freezes / locks on the way in) is the outline of the arm, so an arm that sweeps about while he walks - the sweep
            // that meets the partner from a diagonal is a forward swing - fixes a destination 15 cm short of the hand's reach. Canonical = elevation of the partner's resting arm, sweep that puts the pole level with it (z) when
            // both stand side by side facing the camera (meet: straight out).
            var walking = false; if case .walk = script { walking = true }
            let here = position
            let u = simd_normalize(o.position - here + SIMD2(1e-6, 0)), n = SIMD2<Float>(-u.y, u.x)
            func poleW(_ el: Float, _ sa: Float, _ out: Float) -> SIMD3<Float> { var p = HandReach.pole(el: el, sa: sa, out: out); p.x *= sg; return org + RS * p }
            let out = socialBook.handOut * socialBook.handW          // (the shoulder slid in: what the arm override applies)
            // THE TARGET across the pair's line (n) and in height: seek = the partner's resting arm at its widest (his skin: restSDF), meet = the spot halfway between the two poles at the same elevation
            var tN: Float, tY: Float?
            let hisPole: SIMD3<Float>?
            if q.seek {
                let pp = osim.bodyPose(iterations: 3), e = HandReach.restExtreme
                let w = bodyPointWorld(SIMD3(sgP * e.x, e.y, e.z), sim: osim, pose: (pp.centroid, pp.rotation))
                tN = n.x * w.x + n.y * w.z; tY = nil; hisPole = nil
            } else {
                let mineAt = poleW(q.el, 0, 0)
                var hp = HandReach.pole(el: q.el, sa: 0, out: 0); hp.x *= sgP; let hw = orgo + RSo * hp
                tN = 0.5 * ((n.x * mineAt.x + n.y * mineAt.z) + (n.x * hw.x + n.y * hw.z)); tY = 0.5 * (mineAt.y + hw.y)
                // his actual pole now (his current sweep / elevation / slide), to judge the gap along the line
                var hq = HandReach.pole(el: o.socialBook.handEl[1 - si], sa: o.socialBook.handSa[1 - si], out: o.socialBook.handOut * o.socialBook.handW); hq.x *= sgP
                hisPole = orgo + RSo * hq
            }
            if walking { return }          // (a walker's arms are the walk's own: the hand reaches once he stands - see the drives)
            // sweep (the pole's coordinate along n is monotonic in sa)
            func bisect(_ lo: Float, _ hi: Float, _ f: (Float) -> Float) -> Float {
                var a = lo, b = hi; let fa = f(a), fb = f(b)
                if fa * fb >= 0 { return abs(fa) < abs(fb) ? a : b }
                let rising = fb > fa
                for _ in 0..<12 { let m = 0.5 * (a + b); if (f(m) < 0) == rising { a = m } else { b = m } }
                return 0.5 * (a + b)
            }
            saT = bisect(-0.9, 0.9) { sa in let w = poleW(socialBook.handEl[si], sa, out); return n.x * w.x + n.y * w.z - tN }
            if q.seek {
                let sdf = { (el: Float) -> Double in HandReach.restSDF(self.restPoint(of: poleW(el, saT, out), sim: osim)) }
                let lo: Float = -0.55, hi: Float = 1.4
                if sdf(lo) < 0 && sdf(hi) > 0 {
                    var a = lo, b = hi
                    for _ in 0..<12 { let m = 0.5 * (a + b); if sdf(m) < 0 { a = m } else { b = m } }
                    elT = 0.5 * (a + b)
                }
            } else if let tY {
                elT = bisect(-0.3, 0.9) { el in poleW(el, saT, out).y - tY }
            }
            // THE GIVE: a hand that ends up INSIDE the partner (the walk's last step overshoots a few cm; seek: inside his skin, meet: past his hand) slides back along the shoulder - the arm gives, it does not enter - and creeps out
            // again while the hand hovers; inside the dead band (the hold presses 0.4 cm on purpose) it does not move, so the settle's press and the give never fight. Meeting hands both give: half each.
            // (a walker closes ~1 cm a step and the arm is drawn a tick after it is set: judge the hand where it will be two ticks from now)
            let dNow = simd_distance(position, o.position), closing = socialBook.handPrevD > 0 ? max(0, (socialBook.handPrevD - dNow) / max(dt, 1e-3)) : 0
            socialBook.handPrevD = dNow
            let margin: Float = (social?.phase ?? 0) < 2 ? HandReach.stand : 0          // (until the press the hand stands off by the stance's own gap: the walk's last step and the landing squash then never push it into the partner)
            var gapNow: Float
            if let hisPole { let mp = poleW(elT, saT, out); gapNow = 0.5 * (u.x * (hisPole.x - mp.x) + u.y * (hisPole.z - mp.z)) }
            else { gapNow = Float(HandReach.restSDF(restPoint(of: poleW(elT, saT, out), sim: osim))) }
            let s0 = gapNow - margin - 2 * dt * min(closing, 0.8)
            // (the give only runs once he stands: a walker re-derives his destination from the outline he has, so a hand that gives while he walks shortens the outline, the destination, the walk... until the arm is all the way in)
            if s0 < -0.004 { socialBook.handOut = max(-0.12, socialBook.handOut + s0 + 0.002) }
            else if s0 > (q.seek ? 0.012 : 0.004), socialBook.handOut < 0 { socialBook.handOut = min(0, socialBook.handOut + 0.25 * dt) }
        } else if goal > 0 { socialBook.handOut = 0; socialBook.handPrevD = 0 }
        let rate: Float = 6 * dt
        socialBook.handEl[si] += max(-rate, min(rate, elT - socialBook.handEl[si]))
        socialBook.handSa[si] += max(-rate, min(rate, saT - socialBook.handSa[si]))
        armDirEl[si] = socialBook.handEl[si]; armDirSa[si] = socialBook.handSa[si]
    }

    /// The body frame without the attractor's squash (the pose the body relaxes to once he stands): world = org + RS * local.
    func relaxedFrame(_ sim: SoftBody) -> (RS: simd_float3x3, org: SIMD3<Float>) {
        let att = sim.attractor, RS = simd_float3x3(att.rotation)
        return (RS, att.anchor - RS * sim.restCentroid)
    }
}
