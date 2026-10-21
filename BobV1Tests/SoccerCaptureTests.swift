//
//  SoccerCaptureTests.swift
//  Not a regression test: renders the soccer round with the REAL renderer when FURN_CAP_DIR is set (TEST_RUNNER_FURN_CAP_DIR), as FurnCaptureTests does
//  for the furniture: kick.png, dribble.png, pass.png, goal.png (the shot, the net's bulge, the celebration, the roll back out), stuck_recovery.png and
//  room_land.png (a landscape room with the ball and the goal, three Jellies).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FurnCaptureTests {
    /// A ball (uid 7), maybe a goal (uid 8), a Jelly at `from` started on the soccer kick in `mode` (0 kick, 1 dribble, 2 shoot, 3 rescue).
    func soccerScene(ball: SIMD2<Float>, goal: SIMD2<Float>? = nil, from: SIMD2<Float>, mode: Int, stuck: Bool = false) -> MotionRig {
        DecorField.shared.clear(); SoccerState.shared.reset(); SoccerEvents.clear()
        var placed = [PlacedDecor(uid: 7, kind: .soccerball, x: ball.x, z: ball.y)]
        if let goal { placed.append(PlacedDecor(uid: 8, kind: .minigoal, x: goal.x, z: goal.y)) }
        DecorField.shared.set(placed)
        if stuck { DecorField.shared.tick(dt: 0); SoccerState.shared.setStuck(7, SoccerTuning.stuckAfter) }
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.renderSamples = false
        r.skinner.autoBlink = false
        r.brain.anticsEnabled = true
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: from)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.seed = 7
        r.brain.soccerModeForce = mode
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.soccerKick, r.sim), "the soccer kick starts (mode \(mode))")
        return r
    }
    /// One frame: the Jelly, his skin, the field with him as a bumper.
    func sstep(_ r: MotionRig) {
        r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
        DecorField.shared.bodies = [(r.brain.steerID, r.brain.position)]
        DecorField.shared.tick(dt: 1.0 / 60)
    }
    func sstepLab(_ lab: SocialTests.Lab) {
        lab.tick(watching: false)
        for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
        DecorField.shared.bodies = lab.rigs.map { ($0.brain.steerID, $0.brain.position) }
        DecorField.shared.tick(dt: 1.0 / 60)
    }
    /// Steps until `done` (at most `limit` frames); false when the limit ran out.
    @discardableResult func until(_ r: MotionRig, limit: Int = 9000, _ done: () -> Bool) -> Bool {
        var n = 0
        while !done() && n < limit { sstep(r); n += 1 }
        return n < limit
    }
    /// A view from the left side (-x) and a little in front: the ball and the goal stay in sight beside him (the close-up's front-right eye hides them).
    func sideView(_ ren: MelonRenderer, _ target: MTLTexture, rigs: [MotionRig], focus: SIMD3<Float>, dist: Float, w: Int, h: Int) -> LockImage {
        decorMesh(into: ren, time: 0.37)
        let cam = camera(eye: focus + SIMD3(-dist * 0.78, dist * 0.38, dist * 0.5), at: focus, aspect: Float(w) / Float(h), fov: 33 * .pi / 180)
        return shot(ren, target, rigs: rigs, cam: cam, w: w, h: h)
    }
    /// From the front-left: the shooter and the goal both in frame (focus half way between them).
    func frontView(_ ren: MelonRenderer, _ target: MTLTexture, rigs: [MotionRig], focus: SIMD3<Float>, dist: Float, w: Int, h: Int) -> LockImage {
        decorMesh(into: ren, time: 0.37)
        let cam = camera(eye: focus + SIMD3(-dist * 0.5, dist * 0.42, dist * 0.8), at: focus, aspect: Float(w) / Float(h), fov: 33 * .pi / 180)
        return shot(ren, target, rigs: rigs, cam: cam, w: w, h: h)
    }
    func ballPos() -> SIMD2<Float> { DecorField.shared.anim[7]!.pos }
    func ballSpeed() -> Float { simd_length(DecorField.shared.anim[7]!.vel) }
    /// The point between him and the ball, at belly height.
    func midFocus(_ r: MotionRig) -> SIMD3<Float> {
        let p = r.sim.centroid(), b = ballPos()
        return SIMD3((p.x + b.x) / 2, 0.45, (p.z + b.y) / 2)
    }

    func testCaptureSoccerKick() throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let w = 560, h = 600
        var cells: [(LockImage, String)] = []
        let r = soccerScene(ball: SIMD2(0.6, 0.6), from: SIMD2(-1.2, 1.4), mode: 0)
        let (ren, t) = try makeRenderer(device, r, w: w, h: h)
        XCTAssertTrue(until(r) { r.brain.idleState.soccer.stage == 0 && !r.brain.idleState.decorGo && !r.brain.feet.active && r.brain.idleState.phaseT > 0.1 }, "lined up")
        cells.append((closeUp(ren, t, rigs: [r], focus: midFocus(r), dist: 4.2, w: w, h: h), "1. lined up behind the ball, on the kick line"))
        XCTAssertTrue(until(r) { r.brain.idleState.soccer.stage == 1 && r.brain.feet.active && r.brain.feet.stepU > 0.35 && r.brain.feet.stepU < 0.6 }, "the stomp")
        cells.append((closeUp(ren, t, rigs: [r], focus: midFocus(r), dist: 4.2, w: w, h: h), "2. the stomp step: the planted foot steps into the ball (no leg swing)"))
        XCTAssertTrue(until(r) { r.brain.idleState.soccer.stage == 2 && r.brain.idleState.phaseT > 0.25 }, "the ball leaves")
        cells.append((closeUp(ren, t, rigs: [r], focus: midFocus(r), dist: 5.0, w: w, h: h), String(format: "3. the ball rolls off at %.1f u/s; he watches it go", ballSpeed())))
        until(r) { r.brain.idleState.kind == nil && !DecorField.shared.anim[7]!.moving }
        cells.append((closeUp(ren, t, rigs: [r], focus: midFocus(r), dist: 6.0, w: w, h: h), String(format: "4. at rest, %.1f u on", simd_distance(ballPos(), SIMD2(0.6, 0.6)))))
        try save(sheet(cells, cols: 2, title: "Soccer: the stomp kick (stubby legs, feet stay attached)"), "kick.png")
    }

    func testCaptureSoccerDribble() throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let w = 560, h = 600
        var cells: [(LockImage, String)] = []
        let r = soccerScene(ball: SIMD2(1.6, 1.4), goal: SIMD2(0, -1.6), from: SIMD2(-0.6, 1.6), mode: 1)
        let (ren, t) = try makeRenderer(device, r, w: w, h: h)
        var kicks = 0
        func kickCount() -> Int { SoccerEvents.count { if case .kick = $0 { return true }; return false } }
        XCTAssertTrue(until(r) { kickCount() >= 1 }, "the first touch")
        for _ in 0..<8 { sstep(r) }
        cells.append((sideView(ren, t, rigs: [r], focus: midFocus(r), dist: 5.0, w: w, h: h), "1. the first touch: the toe nudges the ball on toward the goal's kick spot"))
        kicks = kickCount()
        XCTAssertTrue(until(r) { kickCount() > kicks && r.brain.feet.active }, "a second nudge on a footfall")
        for _ in 0..<10 { sstep(r) }
        cells.append((sideView(ren, t, rigs: [r], focus: midFocus(r), dist: 5.0, w: w, h: h), "2. walking it: a nudge on the footfall, the ball kept ahead"))
        kicks = kickCount()
        if until(r, limit: 1200, { kickCount() > kicks }) { for _ in 0..<14 { sstep(r) } }
        cells.append((sideView(ren, t, rigs: [r], focus: midFocus(r), dist: 5.0, w: w, h: h), "3. another stride, another nudge"))
        XCTAssertTrue(until(r) { r.brain.idleState.soccer.mode == .shoot && r.brain.idleState.soccer.stage >= 1 }, "at the kick spot: the shot")
        let p4 = r.sim.centroid()
        cells.append((frontView(ren, t, rigs: [r], focus: SIMD3((p4.x + 0) / 2, 0.45, (p4.z - 1.3) / 2), dist: 6.0, w: w, h: h), "4. at the kick spot: the shot"))
        try save(sheet(cells, cols: 2, title: "Soccer: the dribble (a nudge on each footfall, ball ahead within 0.6 of his line)"), "dribble.png")
    }

    func testCaptureSoccerPass() throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let w = 760, h = 520
        var cells: [(LockImage, String)] = []
        DecorField.shared.clear(); SoccerState.shared.reset(); SoccerEvents.clear()
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: 0.2, z: 1.0)])
        let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-1.5, 1.4), SIMD2(1.8, 1.6)], quiet: true, seed: 5)
        Self.keep.append(lab)
        for r in lab.rigs { r.skinner.autoBlink = false }
        let a = lab.rigs[0], b = lab.rigs[1]
        XCTAssertTrue(a.brain.socialStart(.pass, with: b.brain, a.sim), "the pass starts")
        let (ren, t) = try makeRenderer(device, a, w: w, h: h)
        func mid() -> SIMD3<Float> { let p = (a.sim.centroid() + b.sim.centroid()) / 2; return SIMD3(p.x, 0.45, p.z) }
        var n = 0
        func kicker() -> MotionRig { (a.brain.social?.roles ?? 0) == 0 ? a : b }
        while !(a.brain.social?.phase == 1 && kicker().brain.feet.active && kicker().brain.feet.stepU > 0.3) && n < 9000 { sstepLab(lab); n += 1 }
        cells.append((closeUp(ren, t, rigs: lab.rigs, focus: mid(), dist: 7.0, w: w, h: h), "1. the kicker stomps the ball toward his friend"))
        while !(a.brain.social?.phase == 2 && ballSpeed() > 0.8) && n < 9000 { sstepLab(lab); n += 1 }
        for _ in 0..<10 { sstepLab(lab) }
        cells.append((closeUp(ren, t, rigs: lab.rigs, focus: mid(), dist: 7.0, w: w, h: h), String(format: "2. the ball rolls across (%.1f u/s); both watch it", ballSpeed())))
        while !(a.brain.social?.roles == 1 && a.brain.social?.phase == 1 && kicker().brain.feet.active) && n < 18000 { sstepLab(lab); n += 1 }
        for _ in 0..<4 { sstepLab(lab) }
        cells.append((closeUp(ren, t, rigs: lab.rigs, focus: mid(), dist: 7.0, w: w, h: h), "3. his friend kicks it back"))
        while !(a.brain.social?.roles == 1 && a.brain.social?.phase == 2 && ballSpeed() > 0.5) && n < 18000 { sstepLab(lab); n += 1 }
        for _ in 0..<12 { sstepLab(lab) }
        cells.append((closeUp(ren, t, rigs: lab.rigs, focus: mid(), dist: 7.0, w: w, h: h), "4. and back it comes"))
        try save(sheet(cells, cols: 2, title: "Soccer: a pass between two Jellies (the pass social with the stomp kick)"), "pass.png")
    }

    func testCaptureSoccerGoal() throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let w = 560, h = 600
        var cells: [(LockImage, String)] = []
        let goal = SIMD2<Float>(0, -1.6)
        let r = soccerScene(ball: SIMD2(0.5, 0.1), goal: goal, from: SIMD2(1.6, 1.6), mode: 2)
        let (ren, t) = try makeRenderer(device, r, w: w, h: h)
        let gf = SIMD3<Float>(goal.x, 0.45, goal.y + 0.9)
        func pair() -> SIMD3<Float> { let p = r.sim.centroid(); return SIMD3((p.x + goal.x) / 2, 0.45, (p.z + goal.y + 0.3) / 2) }
        XCTAssertTrue(until(r) { r.brain.idleState.soccer.stage == 1 && r.brain.feet.active && r.brain.feet.stepU > 0.35 }, "the shot's stomp")
        cells.append((frontView(ren, t, rigs: [r], focus: pair(), dist: 5.8, w: w, h: h), "1. the shot: lined up at the kick spot, the stomp"))
        XCTAssertTrue(until(r) { r.brain.idleState.soccer.stage == 2 && ballSpeed() > 0.5 && (ballPos() - goal).y < 1.0 }, "the ball on its way")
        cells.append((frontView(ren, t, rigs: [r], focus: pair(), dist: 5.8, w: w, h: h), String(format: "2. on its way to the mouth (%.1f u/s)", ballSpeed())))
        XCTAssertTrue(until(r) { SoccerState.shared.goals == 1 && DecorModels.netBulge(DecorField.shared.anim[8]!) > 0.5 }, "GOAL: the net bulges")
        for _ in 0..<2 { sstep(r) }
        cells.append((sideView(ren, t, rigs: [r], focus: SIMD3(goal.x, 0.4, goal.y), dist: 4.0, w: w, h: h), String(format: "3. GOAL: the net puffs out (bulge %.2f)", DecorModels.netBulge(DecorField.shared.anim[8]!))))
        XCTAssertTrue(until(r) { r.brain.idleState.kind == .bounce && r.sim.centroid().y > 0.72 }, "the jump for joy")
        cells.append((frontView(ren, t, rigs: [r], focus: pair() + SIMD3(0, 0.2, 0), dist: 6.2, w: w, h: h), "4. the scorer's jump for joy"))
        until(r) { r.brain.idleState.kind == nil && !DecorField.shared.anim[7]!.moving }
        let l = ballPos() - goal
        cells.append((frontView(ren, t, rigs: [r], focus: pair(), dist: 5.8, w: w, h: h), String(format: "5. the ball rolled gently back out: at rest %.2f in front of the mouth (no teleport)", l.y - GoalGeometry.mouthZ)))
        cells.append((sideView(ren, t, rigs: [r], focus: SIMD3(goal.x, 0.35, goal.y + 0.3), dist: 3.2, w: w, h: h), "6. the goal and the ball, close"))
        try save(sheet(cells, cols: 3, title: "Soccer: a goal (shot, net bulge, celebration, the roll back out)"), "goal.png")
    }

    func testCaptureSoccerStuckRecovery() throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let w = 560, h = 600
        var cells: [(LockImage, String)] = []
        let corner = SIMD2<Float>(-2.0, -2.22)
        let r = soccerScene(ball: corner, from: SIMD2(0.8, 1.2), mode: 3, stuck: true)
        XCTAssertEqual(r.brain.idleState.soccer.mode, .rescue)
        let (ren, t) = try makeRenderer(device, r, w: w, h: h)
        cells.append((closeUp(ren, t, rigs: [r], focus: SIMD3(corner.x, 0.4, corner.y), dist: 4.6, w: w, h: h), "1. the ball has sat in the back corner for 20 s: stuck"))
        var n = 0
        func trace(_ tag: String) { let an = DecorField.shared.anim[7]!; MotionLog.write(String(format: "SOCCER cap rescue %@ n %d jelly (%.2f, %.2f) yaw %.2f ball (%.2f, %.2f) speed %.2f stage %d legs %d script %@ feet %d target (%.2f, %.2f)", tag, n, r.brain.px, r.brain.pz, r.brain.yaw, an.pos.x, an.pos.y, simd_length(an.vel), r.brain.idleState.soccer.stage, r.brain.idleState.soccer.legs, "\(r.brain.script)", r.brain.feet.active ? 1 : 0, r.brain.idleState.target.x, r.brain.idleState.target.y)) }
        trace("start")
        XCTAssertTrue(until(r) { n += 1; if n % 30 == 0 { trace("walk") }; return ballSpeed() > 0.3 || (!r.brain.idleState.decorGo && r.brain.idleState.soccer.stage == 10 && !r.brain.feet.active) }, "he arrives")
        trace("arrived")
        if ballSpeed() < 0.3 { for _ in 0..<12 { sstep(r) } }
        cells.append((frontView(ren, t, rigs: [r], focus: midFocus(r), dist: 5.2, w: w, h: h), "2. he walks over and turns to it"))
        XCTAssertTrue(until(r) { n += 1; if n % 30 == 0 { trace("stand") }; return ballSpeed() > 0.3 }, "the touch out")
        trace("touch")
        for _ in 0..<22 { sstep(r) }
        cells.append((frontView(ren, t, rigs: [r], focus: midFocus(r), dist: 6.0, w: w, h: h), "3. the touch: the ball rolls out of the corner"))
        until(r) { r.brain.idleState.kind == nil && !DecorField.shared.anim[7]!.moving }
        cells.append((frontView(ren, t, rigs: [r], focus: midFocus(r), dist: 5.6, w: w, h: h), String(format: "4. on open floor again (%.1f, %.1f); the fallback nudge would have rolled it out at 28 s", ballPos().x, ballPos().y)))
        try save(sheet(cells, cols: 2, title: "Soccer: a stuck ball is dribbled back out"), "stuck_recovery.png")
    }

    func testCaptureSoccerRoomLandscape() throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let W = 1434, H = 660, a = Float(W) / Float(H)
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: a); GameCamera.refreshRoam(aspect: a)
        DecorField.shared.clear(); SoccerState.shared.reset(); SoccerEvents.clear()
        let book = StoreBook(wallet: DropsWallet(persists: false), persists: false)
        for k in [DecorKind.minigoal, .loveseat, .floorlamp, .soccerball] { book.grant(k.storeID); XCTAssertNotNil(book.place(k.storeID), "\(k) fits") }
        DecorField.shared.set(book.placedDecor)
        let goal = DecorField.shared.goals.first!
        // the ball at the goal's middle kick spot, where a Jelly can shoot from
        let spot = DecorField.shared.kickSpots(goal)[1].ball
        if let b = book.placedDecor.first(where: { $0.kind == .soccerball }) { _ = book.move(b.uid, to: spot) }
        DecorField.shared.set(book.placedDecor)
        let lab = SocialTests.Lab(positions: [SIMD2(-1.6, 1.4), SIMD2(1.4, 1.8), SIMD2(0.2, 2.4)], quiet: true, seed: 5)
        Self.keep.append(lab)
        for r in lab.rigs { r.skinner.autoBlink = false }
        let shooter = lab.rigs[2]
        shooter.brain.soccerModeForce = 2; shooter.brain.idleForced = true
        let started = shooter.brain.idleStart(.soccerKick, shooter.sim)
        var f = 0
        while f < 60 * 40 {
            sstepLab(lab); f += 1
            if started, shooter.brain.idleState.soccer.stage == 2, ballSpeedUID(shooter) > 0.6 { break }
        }
        let (ren, target) = try makeRenderer(device, lab.rigs[0], w: W, h: H)
        decorMesh(into: ren, time: 0.37)
        let img = shot(ren, target, rigs: lab.rigs, cam: GameCamera.camera(aspect: a, focus: 0), w: W, h: H)
        let names = book.placedDecor.map { $0.kind.title }.joined(separator: ", ")
        try save(sheet([(img, "Landscape 2.17:1: \(names); a Jelly's shot on its way to the goal (started: \(started))")], cols: 1, title: "Soccer: the room in landscape"), "room_land.png")
    }
    private func ballSpeedUID(_ r: MotionRig) -> Float { simd_length(DecorField.shared.anim[r.brain.idleState.decorUID]?.vel ?? .zero) }
}
