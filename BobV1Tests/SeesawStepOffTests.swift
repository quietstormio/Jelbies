//
//  SeesawStepOffTests.swift
//  park-room-r3: nobody stands inside the park seesaw's footprint. (1) the P2 riddle staged and printed (what `seesawFreeSpot` rejects for the right seat's three spots); (2) both riders get off to the
//  ring spot when friends block all normal spots, outside the footprint within 5 s of the ride's end, feet attached, `noStepOff` 0; (3) a 120 s park run with 4 free bodies (3 seeds): no body that is not
//  riding or boarding stands inside the footprint for more than 1 s.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SeesawStepOffTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    let uid = ParkToys.seesawUID
    /// "Inside the footprint" = the body's centre more than this (m) past its edge. A body walking along the piece grazes the edge by a few cm (the floor rules are soft there: -0.01 ... -0.05 seen); the 600 s run's fault was 0.39 deep for 15 s.
    static let graze: Float = 0.10

    override func setUp() { DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0; SeesawRide.shared.reset() }
    override func tearDown() {
        DecorField.shared.clear(); ToyTuning.settle = 5; SeesawRide.shared.reset()
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    private func parkSetup() { RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0) }
    private func configure(_ lab: SocialTests.Lab, chars: [Int], play: Bool) {
        for (k, r) in lab.rigs.enumerated() {
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
            r.brain.anticsEnabled = true; r.brain.skinnerRef = r.skinner; r.skinner.autoBlink = false; r.renderSamples = false
            if play { r.brain.outingPlay = true } else { r.brain.idleMood = .happy; r.brain.idleForced = true }
            r.brain.feature = JellyRoster.feature(chars[k % chars.count])
            r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines
        }
        WearBody.install(MotionRig.renderMesh)
    }

    // MARK: (1) the P2 riddle: the right seat's three spots at the 131-135 s moment

    /// P2.log (slide2): body 2 on the right seat, leaving from 131 s; body 0 walking to the hopscotch queue at (-3.24, -1.61) then (-2.5, -1.16), body 3 standing at (-1.1, -1.125), body 1 on the left seat; on the r2 layout
    /// (seesaw at x -3.2). Prints, per spot, what `seesawFreeSpot` checks.
    func testRiddleP2RightSeat() {
        let old = ParkToys.layout
        defer { ParkToys.layout = old }
        ParkToys.layout = old.map { $0.uid == uid ? PlacedDecor(uid: uid, kind: .seesaw, x: -3.2, z: -3.2, turns: nil) : $0 }
        for (label, seat, rider, others) in [("131 s right seat", 1, SIMD2<Float>(-2.276, -3.2), [SIMD2<Float>(-3.244, -1.611), SIMD2(-1.1, -1.125), SIMD2(-4.124, -3.2)]),
                                             ("134.4 s right seat", 1, SIMD2<Float>(-2.276, -3.2), [SIMD2<Float>(-2.5, -1.161), SIMD2(-1.1, -1.125), SIMD2(-4.124, -3.2)]),
                                             ("131 s left seat", 0, SIMD2<Float>(-4.124, -3.2), [SIMD2<Float>(-3.244, -1.611), SIMD2(-1.1, -1.125), SIMD2(-2.276, -3.2)])] {
            parkSetup()
            let lab = SocialTests.Lab(n: 4, positions: [rider] + others, quiet: true, seed: 5)
            Self.keep.append(lab)
            configure(lab, chars: [0, 1, 2, 3], play: false)
            DecorField.shared.set(ParkToys.placed)
            for _ in 0..<2 { lab.tick(watching: false) }
            guard let f = DecorField.shared.foot(uid) else { return XCTFail("seesaw") }
            let b = lab.rigs[0].brain
            b.decorIgnore = uid
            let here = b.position
            var lines: [String] = []
            for (i, p) in b.seesawStandSpots(f, seat: seat).enumerated() {
                let q = b.fixed(p)
                let peers = b.steerPeers().map { (id: $0.id, d: simd_distance($0.pos, p)) }.sorted { $0.d < $1.d }
                lines.append(String(format: "spot %d (%.2f, %.2f): floor moves it %.3f, footprint %.2f, in hop range %@ (%.2f of %.2f), peerFree %@, nearest peer id %d at %.2f (peerGap %.2f)",
                                    i, p.x, p.y, simd_distance(p, q), f.distance(p), simd_distance(here, p) <= SeesawTuning.maxHop - 0.02 ? "yes" : "NO", simd_distance(here, p), SeesawTuning.maxHop - 0.02,
                                    b.peerFree(q) ? "yes" : "NO", peers.first?.id ?? -1, peers.first?.d ?? -1, b.peerGap))
            }
            let free = b.seesawFreeSpot(f, seat: seat, from: here, origin: here), ring = b.seesawStepOffRing(f, seat: seat)
            print("[riddle] \(label): rider at \(here); seesawFreeSpot \(String(describing: free)); ring \(String(describing: ring))\n[riddle]   " + lines.joined(separator: "\n[riddle]   "))
            if seat == 1 { XCTAssertNotNil(ring, "\(label): the ring has a spot") }          // (the left seat on the old x -3.2 layout has none on the floor: its spots were past the side limit)
        }
    }

    // MARK: (2) both riders step off to the ring when every normal spot is blocked

    /// `forever`: the friends stay pinned on the spots until both riders are down (print only: the last resort at the back is expected); else they are released 3 s after the first rider starts getting up.
    private func blockedRun(seed: UInt64, forever: Bool) {
        parkSetup()
        let lab = SocialTests.Lab(n: 4, positions: [SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4), SIMD2(3.0, 3.0), SIMD2(3.0, 2.0)], quiet: true, seed: seed)
        Self.keep.append(lab)
        configure(lab, chars: [0, 1, 2, 3], play: false)
        var feats: [FeatureSet] = []
        for _ in lab.rigs { let f = FeatureSet(); f.body = WearBody.shared; Self.keep.append(f); feats.append(f) }
        let field = DecorField.shared, R = SeesawRide.shared
        field.set(ParkToys.placed.filter { $0.kind == .seesaw }); field.toys.news.removeAll(); R.reset()
        guard let f = field.foot(uid) else { return XCTFail("seesaw") }
        for r in lab.rigs[0..<2] { XCTAssertTrue(r.brain.decorStart(.decorSit, r.sim, only: .seesaw, uid: uid), "seed \(seed): a rider found a seat") }
        var leash = 0, step = 0, blocked = false, endStep = -1, leaveStep = -1
        var spotsBlocked: [Bool] = [false, false], pins: [SIMD2<Float>] = []
        var landStep = [-1, -1], landPos = [SIMD2<Float>.zero, SIMD2<Float>.zero], minAfter: [Float] = [.infinity, .infinity]
        var wasSit = [false, false], landedD: [Float?] = [nil, nil]          // (the footprint distance of each rider's centre the first step his seesaw use is over)
        while step < 60 * 120 {
            lab.tick(watching: false); field.tick(dt: 1.0 / 60)
            for (j, r) in lab.rigs.enumerated() { feats[j].tick(id: 0, brain: r.brain, sim: r.sim, feature: JellyRoster.feature(j), worn: [], hideAll: false, dt: 1.0 / 60) }
            for r in lab.rigs[0..<2] where r.skinner.beansActive {
                let pull = max(max(r.skinner.joinLeash[0], r.skinner.joinLeash[1]), max(r.skinner.weldPull[0], r.skinner.weldPull[1]))
                if pull > 0.002 { leash += 1 }
            }
            step += 1
            for (j, r) in lab.rigs[0..<2].enumerated() {
                let sitting = r.brain.idleState.kind == .decorSit && r.brain.idleState.decorUID == uid
                if wasSit[j], !sitting, landedD[j] == nil { let c = r.sim.centroid(); landedD[j] = f.distance(SIMD2(c.x, c.z)); landStep[j] = step; landPos[j] = SIMD2(c.x, c.z) }
                if landStep[j] >= 0, !sitting { let c = r.sim.centroid(); minAfter[j] = min(minAfter[j], f.distance(SIMD2(c.x, c.z))) }          // (a rider who boards again is on the piece by right: not counted)
                wasSit[j] = sitting
            }
            if !blocked, R.stage(uid, seat: 0) == .seated, R.stage(uid, seat: 1) == .seated {
                // both are seated: a friend stands on the middle normal spot of each seat, so every normal spot (they are 0.2 apart, the gap is 0.9) is blocked
                blocked = true
                for (k, seat) in [0, 1].enumerated() {
                    let spots = lab.rigs[0].brain.seesawStandSpots(f, seat: seat)
                    pins.append(spots[0])
                    let friend = lab.rigs[2 + k]
                    friend.sim.teleport(toXZ: spots[0])
                    for _ in 0..<120 { friend.sim.step() }
                    friend.brain.currentPose(friend.sim)
                }
            }
            // (the friends stay put until the riders are off: the social rooms nudge a body that stands close to another)
            if leaveStep < 0, R.stage(uid, seat: 0) == .leaving || R.stage(uid, seat: 1) == .leaving { leaveStep = step }
            let hopped = landStep[0] >= 0 && landStep[1] >= 0
            let pinned = forever ? !hopped : (leaveStep < 0 || step < leaveStep + 180)          // (released: a pinned friend squeezing a landed rider against the piece is not what is measured)
            if blocked, endStep < 0, pinned {
                for (k, p) in pins.enumerated() {
                    let fr = lab.rigs[2 + k]
                    fr.sim.teleport(toXZ: p); fr.brain.px = p.x; fr.brain.pz = p.y          // (the brain's own position is what the room's peer snapshot reads)
                }
            }
            if blocked, endStep < 0, (field.seatOccupant[uid]?.count ?? 0) == 0, R.mode(uid) == .idle { endStep = step }
            if endStep >= 0, landStep[0] >= 0, landStep[1] >= 0, step >= max(landStep[0], landStep[1]) + 1200 { break }          // (20 s on after the landings)
            if hopped, step % 20 == 0 {
                print("[stepoff.after] seed \(seed) step \(step) " + lab.rigs.map { r in let c = r.sim.centroid(); return String(format: "(%.2f, %.2f) d%.2f %@/%@/soc %@", c.x, c.z, f.distance(SIMD2(c.x, c.z)), "\(String(describing: r.brain.idleState.kind))", "\(r.brain.activity)", r.brain.social == nil ? "-" : "yes") }.joined(separator: " | "))
            }
            if blocked, endStep < 0, step % 60 == 0 {
                let rb = lab.rigs[0].brain
                print("[stepoff.diag] seed \(seed) step \(step) mode \(R.mode(uid)) stages \(String(describing: R.stage(uid, seat: 0))) \(String(describing: R.stage(uid, seat: 1))) friends at \(lab.rigs[2...].map { $0.sim.centroid() }.map { SIMD2($0.x, $0.z) }) riders at \(lab.rigs[0..<2].map { $0.sim.centroid() }.map { SIMD2($0.x, $0.z) }) bagStage/phase \(lab.rigs[0..<2].map { "\($0.brain.idleState.bagStage)/\($0.brain.idleState.phase)" }) steerPeers of rider 0 \(rb.steerPeers().map { "\($0.id)@\($0.pos)" })")
            }
            if blocked, step % 30 == 0 {
                for (k, rig) in lab.rigs[0..<2].enumerated() where rig.brain.idleState.bagStage == 2 && rig.brain.idleState.phase == 3 {
                    spotsBlocked[k] = spotsBlocked[k] || rig.brain.seesawFreeSpot(f, seat: rig.brain.idleState.seat, from: rig.brain.position, origin: rig.brain.position) == nil
                }
            }
        }
        XCTAssertTrue(blocked, "seed \(seed): both riders sat")
        XCTAssertGreaterThanOrEqual(endStep, 0, "seed \(seed): the ride ended")
        var report = "seed \(seed): ride end at step \(endStep) of \(step) (\(forever ? "friends pinned forever" : "friends released 3 s after the first got up")); ring step-offs \(R.ringStepOffs); BACK step-offs \(R.backStepOffs); noStepOff \(R.noStepOff); refused hops \(R.refusedHops); leash frames \(leash); normal spots seen empty (before the ring): \(spotsBlocked)"
        for (j, r) in lab.rigs[0..<2].enumerated() {
            let c = r.sim.centroid(), d = f.distance(SIMD2(c.x, c.z))
            report += String(format: "; rider %d at (%.2f, %.2f) footprint distance %.2f", j, c.x, c.z, d)
            report += String(format: " (landed at footprint distance %.2f)", landedD[j] ?? -9)
            XCTAssertGreaterThan(landedD[j] ?? -9, 0.2, "seed \(seed): rider \(j)'s step-off landed outside the footprint")
            report += String(format: " (landed at (%.2f, %.2f), lowest footprint distance in the 20 s after %.2f)", landPos[j].x, landPos[j].y, minAfter[j])
            if let rf = GameCamera.roamFloor {
                XCTAssertGreaterThanOrEqual(landPos[j].y, rf.minZ - 0.1, "seed \(seed): rider \(j) landed behind the floor's back edge \(rf.minZ)")
                XCTAssertLessThanOrEqual(abs(landPos[j].x), rf.halfWidth(at: landPos[j].y) + 0.1, "seed \(seed): rider \(j) landed past the floor's side")
            }
            if forever {
                if minAfter[j] <= -Self.graze { print(String(format: "[stepoff.cross] seed %d rider %d landed at (%.2f, %.2f), later walked to footprint distance %.2f (expected: the last resort lands behind the piece)", seed, j, landPos[j].x, landPos[j].y, minAfter[j])) }
            } else {
                XCTAssertGreaterThanOrEqual(landPos[j].y, f.centre.y - f.spec.half.y - 0.05, "seed \(seed): rider \(j) landed at the front or a side, not behind the piece")
                XCTAssertGreaterThan(minAfter[j], -Self.graze, "seed \(seed): rider \(j) never walks more than \(Self.graze) m into the footprint in the 20 s after landing")
            }
        }
        print("[stepoff] " + report)
        if !forever {
            XCTAssertEqual(R.noStepOff, 0, "seed \(seed): every rider found a step-off spot")
            XCTAssertEqual(R.backStepOffs, 0, "seed \(seed): nobody needed the back of the piece once the friends moved on")
        }
        XCTAssertEqual(leash, 0, "seed \(seed): the skin's leash never moved a foot piece through the hops")
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
        field.clear()
    }
    func testBlockedSpotsSeed3() { blockedRun(seed: 3, forever: false) }
    func testBlockedSpotsSeed8() { blockedRun(seed: 8, forever: false) }
    func testBlockedSpotsSeed21PinnedForever() { blockedRun(seed: 21, forever: true) }

    // MARK: (3) the wander check

    private func wanderRun(seed: UInt64) {
        parkSetup()
        let pts: [SIMD2<Float>] = [SIMD2(-1.0, 0.4), SIMD2(1.0, -0.4), SIMD2(0.0, 1.6), SIMD2(-2.2, 1.0)]
        let lab = SocialTests.Lab(n: 4, positions: pts, quiet: false, seed: seed)
        Self.keep.append(lab)
        configure(lab, chars: [0, 1, 2, 3], play: true)
        let field = DecorField.shared, R = SeesawRide.shared
        field.set(ParkToys.placed); field.toys.news.removeAll(); R.reset()
        guard let f = field.foot(uid) else { return XCTFail("seesaw") }
        var run = [Int](repeating: 0, count: 4), worst = [Int](repeating: 0, count: 4), where_ = [String](repeating: "", count: 4)
        for i in 0..<(60 * 120) {
            lab.tick(watching: false); field.tick(dt: 1.0 / 60)
            for (j, r) in lab.rigs.enumerated() {
                let c = r.sim.centroid(), d = f.distance(SIMD2(c.x, c.z))
                let onIt = r.brain.idleState.decorUID == uid && (r.brain.isBagSit || r.brain.idleState.kind == .decorSit)
                if d < -Self.graze, !onIt { run[j] += 1; if run[j] > worst[j] { worst[j] = run[j]; where_[j] = String(format: "t %.1f at (%.2f, %.2f) idle %@ act %@", Float(i) / 60, c.x, c.z, "\(String(describing: r.brain.idleState.kind))", "\(r.brain.activity)") } }
                else { run[j] = 0 }
            }
        }
        print("[wander] seed \(seed): longest run inside the footprint (steps, 60 = 1 s) per body \(worst) \(where_); noStepOff \(R.noStepOff); rides seen \(R.rides.count)")
        for j in 0..<4 { XCTAssertLessThanOrEqual(worst[j], 60, "seed \(seed): body \(j) stood inside the seesaw footprint for \(Float(worst[j]) / 60) s: \(where_[j])") }
        XCTAssertEqual(R.noStepOff, 0)
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
        field.clear()
    }
    func testWanderSeed3() { wanderRun(seed: 3) }
    func testWanderSeed8() { wanderRun(seed: 8) }
    func testWanderSeed21() { wanderRun(seed: 21) }
}
