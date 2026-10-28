//
//  ToyRideTests.swift
//  The ride-on toys (2026-10-27): the kick scooter (hop on, a loop, hop off, parked), the rocket and the rocking horse (sit astride, rock, get off), the play tunnel
//  (walk through). Each: starts, rides, finishes, the piece is put back, feet stay attached, arms stay stubby, nobody overlaps anything.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ToyRideTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let log = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/toyride/"
    override func setUp() { DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0) }
    override func tearDown() { DecorField.shared.clear(); ToyTuning.settle = 5; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    static func append(_ s: String, _ name: String) {
        try? FileManager.default.createDirectory(atPath: log, withIntermediateDirectories: true)
        let path = log + name
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write((s + "\n").data(using: .utf8)!); try? h.close() }
    }
    static func write(_ s: String, _ name: String) { try? FileManager.default.createDirectory(atPath: log, withIntermediateDirectories: true); try? s.write(toFile: log + name, atomically: true, encoding: .utf8) }

    /// One Jelbie, one piece: runs his behaviour to the end; returns the per-frame trace (stage, floor y, position, piece pos) every 6th frame.
    struct Trace { var lines: [String] = []; var ended = false; var frames = 0; var minDeckGap: Float = 0; var maxStage = 0 }
    func runSolo(_ kind: DecorKind, at p: SIMD2<Float>, move: IdleKind, from: SIMD2<Float>, seconds: Float = 40, each: ((MotionRig, Int) -> Void)? = nil) -> (MotionRig, Trace) {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: p.x, z: p.y)])
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.renderSamples = false
        r.brain.anticsEnabled = true; r.brain.sleepEnabled = true
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: from)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.idleForced = true
        var tr = Trace()
        XCTAssertTrue(r.brain.decorStart(move, r.sim, only: kind), "\(kind) starts")
        let n = Int(seconds * 60)
        for i in 0..<n {
            r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); DecorField.shared.tick(dt: r.sim.stepDt)
            tr.frames += 1
            tr.maxStage = max(tr.maxStage, r.brain.idleState.slideStage)
            if i % 6 == 0 {
                let a = DecorField.shared.anim[7]
                tr.lines.append(String(format: "%.2fs stage %d s %.2f v %.2f root (%.2f,%.2f) floor %.2f piece (%.2f,%.2f) carried %d", Float(i) / 60, r.brain.idleState.slideStage, r.brain.ride.s, r.brain.ride.v, r.brain.px, r.brain.pz, r.sim.floorY, a?.pos.x ?? 0, a?.pos.y ?? 0, (a?.carried ?? false) ? 1 : 0))
            }
            each?(r, i)
            if r.brain.idleState.kind == nil, i > 30 { tr.ended = true; break }
        }
        return (r, tr)
    }

    func testScooterSoloRide() {
        let (r, tr) = runSolo(.kickscooter, at: SIMD2(1.2, 0.4), move: .decorSlide, from: SIMD2(-1.2, 1.4))
        Self.write(tr.lines.joined(separator: "\n"), "scooter-solo.txt")
        XCTAssertTrue(tr.ended, "the ride ends")
        let a = DecorField.shared.anim[7]!, f = DecorField.shared.foot(7)!
        XCTAssertFalse(a.carried, "parked again")
        XCTAssertLessThan(simd_distance(a.pos, f.centre), 0.01, "parked where it started")
        XCTAssertEqual(r.sim.floorY, 0, accuracy: 1e-4)
        XCTAssertGreaterThanOrEqual(tr.maxStage, 11, "he rode")
    }

    // MARK: invariants

    /// Feet attached + arms stubby, gathered every 4th frame of a run.
    struct Inv {
        var foot = FeetAttachTests.FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity)
        var frames = 0, armMax: Double = 0, armFrames = 0
        @MainActor mutating func take(_ r: MotionRig) {
            frames += 1
            let f = FeetAttachTests.drawnFootFrame(r)
            FeetAttachTests.accumulate(&foot, f)
            guard r.brain.armG > 0.5 else { return }
            for si in 0..<2 {
                let g = r.brain.armLastGeom[si]
                armMax = max(armMax, ArmCap.exposed(a: SIMD3<Double>(g.a), b: SIMD3<Double>(g.b), r2: Double(g.r2))); armFrames += 1
            }
        }
        @MainActor func check(_ name: String) {
            // (the embedded foot's own limits: FeetAttachTests.check with `core`; a bean frame is checked with the bean limits)
            XCTAssertLessThanOrEqual(foot.soleRise, FeetAttachTests.maxSoleRise + 0.02, "\(name): a foot is lifted too high")
            XCTAssertLessThanOrEqual(foot.radius, FeetAttachTests.maxRadius, "\(name): a foot is not under the body")
            XCTAssertLessThanOrEqual(foot.stretch, FeetAttachTests.maxCoreStretch, "\(name): a foot is stretched")
            XCTAssertLessThanOrEqual(armMax, ArmCap.maximum * 1.02, "\(name): an arm reaches")
        }
    }

    func soloWithInvariants(_ name: String, _ kind: DecorKind, at p: SIMD2<Float>, move: IdleKind, from: SIMD2<Float>, seconds: Float) -> (MotionRig, Trace, Inv) {
        var inv = Inv()
        let (r, tr) = runSolo(kind, at: p, move: move, from: from, seconds: seconds) { r, i in if i % 4 == 0, r.brain.idleState.kind != nil { inv.take(r) } }
        Self.write(tr.lines.joined(separator: "\n"), "\(name).txt")
        MotionLog.write(String(format: "TOYRIDE %@: %d frames, feet sole rise %.3f radius %.3f overlap %.3f stretch %.2f, arm max %.4f (limit %.4f, %d arm frames)", name, inv.frames, inv.foot.soleRise, inv.foot.radius, inv.foot.overlap, inv.foot.stretch, inv.armMax, ArmCap.maximum, inv.armFrames))
        return (r, tr, inv)
    }

    func testScooterInvariants() {
        let (_, tr, inv) = soloWithInvariants("scooter", .kickscooter, at: SIMD2(1.2, 0.4), move: .decorSlide, from: SIMD2(-1.2, 1.4), seconds: 40)
        XCTAssertTrue(tr.ended); inv.check("scooter ride")
    }
    func testRocketRideInvariants() {
        let (r, tr, inv) = soloWithInvariants("rocket", .toyrocket, at: SIMD2(1.1, 0.5), move: .decorSit, from: SIMD2(-1.2, 1.4), seconds: 50)
        XCTAssertTrue(tr.ended, "the rocket ride ends"); inv.check("rocket ride")
        XCTAssertEqual(r.sim.floorY, 0, accuracy: 1e-4)
    }
    func testHorseRideInvariants() {
        let (r, tr, inv) = soloWithInvariants("horse", .rockinghorse, at: SIMD2(1.1, 0.5), move: .decorSit, from: SIMD2(-1.2, 1.4), seconds: 50)
        XCTAssertTrue(tr.ended, "the horse ride ends"); inv.check("horse ride")
        XCTAssertEqual(r.sim.floorY, 0, accuracy: 1e-4)
    }
    func testTunnelWalkThrough() {
        var entered = false, exited = false
        var inv = Inv()
        let c = SIMD2<Float>(1.0, 0.2)
        let (r, tr) = runSolo(.playtunnel, at: c, move: .decorPeek, from: SIMD2(-1.6, 1.4), seconds: 40) { r, i in
            if i % 4 == 0, r.brain.idleState.kind != nil { inv.take(r) }
            let f = DecorField.shared.foot(7)!, ax = f.turned(SIMD2(1, 0))
            let u = simd_dot(r.brain.position - c, ax) / f.kind.spec.half.x
            if abs(u) < 0.6 { entered = true }
            if entered, abs(u) > 1.15 { exited = true }
        }
        Self.write(tr.lines.joined(separator: "\n"), "tunnel-solo.txt")
        XCTAssertTrue(tr.ended, "the trip ends"); XCTAssertTrue(entered, "he went in"); XCTAssertTrue(exited, "he came out the other end")
        inv.check("tunnel walk-through")
        XCTAssertNil(DecorField.shared.occupant[7]); _ = r
    }

    // MARK: several Jelbies

    struct Multi { var toyMinGap: Float = .infinity; var minTag = ""; var sessions = [Int](repeating: 0, count: 5), simultaneous = 0, minGap: Float = .infinity, touches = 0, frames = 0, perKind: [String: Int] = [:]
        var rides = 0, gaveUp = 0, noLoop = 0, blocked = 0, riderMin: Float = .infinity, riderTouch = 0, riderFrames = 0, furnitureMin: Float = .infinity, watchFrames = 0, passes = 0, maxUsers = 0 }

    /// A lab of `n` Jelbies with the pieces placed; runs `seconds`, counting toy sessions, double use of a single-user piece, the closest two bodies came, and (rides) the
    /// closest a rider came to solid furniture.
    func runLab(n: Int, pieces: [PlacedDecor], seconds: Float, seed: UInt64 = 11, quiet: Bool = false, start: ((SocialTests.Lab) -> Void)? = nil, each: ((SocialTests.Lab, Int) -> Void)? = nil) -> (SocialTests.Lab, Multi) {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        let starts: [SIMD2<Float>] = n == 2 ? [SIMD2(-2.0, 1.6), SIMD2(-2.4, -0.4)] : [SIMD2(-1.8, 1.4), SIMD2(-0.2, 1.8), SIMD2(1.4, 1.2), SIMD2(2.2, 0.2), SIMD2(-2.4, 0.2)]
        let lab = SocialTests.Lab(n: n, positions: Array(starts.prefix(n)), quiet: quiet, seed: seed)
        for r in lab.rigs { r.brain.anticsEnabled = true; r.brain.sleepEnabled = false; r.brain.idleMood = .happy; r.skinner.autoBlink = false }
        DecorField.shared.set(pieces)
        DecorField.shared.toys = ToyBook()
        start?(lab)
        var m = Multi(), prev = [Int](repeating: -1, count: n)
        for i in 0..<Int(seconds * 60) {
            lab.tick(watching: false)
            DecorField.shared.tick(dt: 1.0 / 60)
            for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            m.frames += 1
            var users: [Int: Int] = [:]
            var riding = false
            for (j, r) in lab.rigs.enumerated() {
                let b = r.brain
                let uid = (b.idleState.kind.map { BlobBrain.decorKinds.contains($0) } ?? false) ? b.idleState.decorUID : -1
                if uid >= 0 { users[uid, default: 0] += 1; if prev[j] < 0, let f = DecorField.shared.foot(uid) { m.sessions[j] += 1; m.perKind[f.kind.rawValue, default: 0] += 1 } }
                if uid < 0, b.toy.waitUID >= 0 { m.watchFrames += 1 }
                prev[j] = uid
                if b.scooterFoot != nil, b.idleState.slideStage >= 11 && b.idleState.slideStage <= 13 { riding = true; r.brain.ride.minGap = .infinity }
            }
            for (j, r) in lab.rigs.enumerated() where r.brain.scooterFoot != nil && r.brain.idleState.slideStage >= 11 && r.brain.idleState.slideStage <= 13 {
                m.riderFrames += 1
                for (k, o) in lab.rigs.enumerated() where k != j {
                    let g = simd_distance(r.brain.position, o.brain.position)
                    m.riderMin = min(m.riderMin, g)
                    if g < MelonController.jellyGap * 0.97 { m.riderTouch += 1 }
                }
            }
            for (uid, c) in users where c > 1 {
                guard let f = DecorField.shared.foot(uid) else { continue }
                m.maxUsers = max(m.maxUsers, c)
                if c > max(f.kind.maxUsers, f.kind.sitPoints.count, f.kind.isBallLike ? 3 : 1) { m.simultaneous += 1 }
            }
            for a in 0..<n { for b in (a + 1)..<n {
                let paired = lab.rigs[a].brain.social != nil && lab.rigs[a].brain.social === lab.rigs[b].brain.social
                if paired { continue }
                let g = simd_distance(lab.rigs[a].brain.position, lab.rigs[b].brain.position)
                let inToy: (BlobBrain) -> Bool = { br in (br.idleState.kind.map { BlobBrain.decorKinds.contains($0) } ?? false) && br.idleState.decorUID >= 0 && !br.idleState.decorGo }
                if inToy(lab.rigs[a].brain) || inToy(lab.rigs[b].brain) { m.toyMinGap = min(m.toyMinGap, g) }
                if g < m.minGap {
                    m.minGap = g
                    let A = lab.rigs[a].brain, B = lab.rigs[b].brain
                    m.minTag = "t \(i / 60)s \(a)-\(b) \(A.position)/\(B.position) idle \(String(describing: A.idleState.kind)) st\(A.idleState.bagStage)/\(A.idleState.slideStage)/dec\(A.idleState.decorUID) | \(String(describing: B.idleState.kind)) st\(B.idleState.bagStage)/\(B.idleState.slideStage)/dec\(B.idleState.decorUID) act \(A.activity)/\(B.activity) script \(A.script)/\(B.script)"
                }
                if g < MelonController.jellyGap * 0.97 { m.touches += 1 }
            } }
            if riding {
                for r in lab.rigs where r.brain.scooterFoot != nil && r.brain.idleState.slideStage >= 11 && r.brain.idleState.slideStage <= 13 {
                    for f in DecorField.shared.feet where f.spec.solid && f.kind != .kickscooter { m.furnitureMin = min(m.furnitureMin, f.distance(r.brain.position)) }
                }
            }
            each?(lab, i)
        }
        for r in lab.rigs { if !r.brain.ride.blockNote.isEmpty { Self.write(r.brain.ride.blockNote, "block-note.txt") }; m.rides += r.brain.ride.rides; m.noLoop += r.brain.ride.noLoop; m.blocked += r.brain.ride.blocked }
        return (lab, m)
    }
    func line(_ name: String, _ m: Multi) -> String {
        "\(name): sessions \(m.sessions) simultaneous-misuse \(m.simultaneous) maxUsers \(m.maxUsers) minGap \(String(format: "%.2f", m.minGap)) toyMinGap \(String(format: "%.2f", m.toyMinGap)) touchFrames \(m.touches)/\(m.frames) rides \(m.rides) noLoop \(m.noLoop) blocked \(m.blocked) riderFrames \(m.riderFrames) riderMinGap \(String(format: "%.2f", m.riderMin)) riderTouchFrames \(m.riderTouch) furnitureMin \(String(format: "%.2f", m.furnitureMin)) watch \(m.watchFrames) MINTAG \(m.minTag) perKind \(m.perKind)"
    }

    /// 3 Jelbies roam with the scooter and furniture in the room: rides happen; nobody comes closer than the contact gap, nobody rides into furniture.
    func testScooterWithThreeJelbiesRoaming() {
        var lines: [String] = []
        for seed in [11] as [UInt64] {
            let pieces = [PlacedDecor(uid: 1, kind: .kickscooter, x: 1.5, z: 0.0), PlacedDecor(uid: 2, kind: .beanbag, x: -2.6, z: -0.6), PlacedDecor(uid: 3, kind: .bookshelf, x: 3.0, z: -1.8),
                          PlacedDecor(uid: 4, kind: .plant, x: -3.4, z: 1.6), PlacedDecor(uid: 5, kind: .drum, x: 0.2, z: -2.0)]
            let (_, m) = runLab(n: 3, pieces: pieces, seconds: 150, seed: seed)
            lines.append(line("scooter x3 seed \(seed)", m))
            XCTAssertGreaterThan(m.rides, 0, "seed \(seed): the scooter was ridden")
            XCTAssertEqual(m.simultaneous, 0, "seed \(seed): a single-user toy was used by two at once")
            XCTAssertGreaterThanOrEqual(m.riderMin, MelonController.jellyGap * 0.97, "seed \(seed): a rider came within touching distance of another Jelbie")
            XCTAssertGreaterThanOrEqual(m.furnitureMin, 0.3, "seed \(seed): a rider came too close to furniture")
        }
        Self.write(lines.joined(separator: "\n"), "scooter-x3.txt")
    }

    /// Two Jelbies and one piece: the first starts now, the second goes to it at once (a busy single-user piece: he waits and cheers, then takes his turn; a two-user piece:
    /// he joins). Checks the turns, the occupancy and that two bodies in a toy session never come within touching distance.
    func pairSession(_ kind: DecorKind, seconds: Float, n: Int = 2) -> Multi {
        let at = kind.spec.half.x > 1 ? SIMD2<Float>(0.9, -0.4) : SIMD2<Float>(1.2, 0.2)
        var m = Multi()
        let (lab, mm) = runLab(n: n, pieces: [PlacedDecor(uid: 1, kind: kind, x: at.x, z: at.y)], seconds: seconds, start: { lab in
            let mv = kind.activeInteraction!
            for j in 0..<n { lab.rigs[j].brain.toyGo(1, lab.rigs[j].sim); Self.append("\(kind) rig\(j): wait \(lab.rigs[j].brain.toy.waitUID) bored \(lab.rigs[j].brain.toy.bored) spot \(String(describing: DecorField.shared.foot(1).flatMap { lab.rigs[j].brain.toyWatchSpot($0) })) occupant \(String(describing: DecorField.shared.occupant[1])) idle \(String(describing: lab.rigs[j].brain.idleState.kind)) decorIgnore \(String(describing: lab.rigs[j].brain.decorIgnore))", "pair-diag.txt") }
        }, each: { lab, i in
            if i == 600, n == 2 {
                let b = lab.rigs[1].brain, f = DecorField.shared.foot(1)!
                b.decorIgnore = nil
                let st = b.decorStand(kind.activeInteraction!, f, from: b.position)
                Self.append("DIAG10 \(kind) avail \(DecorField.shared.available(f)) stand \(String(describing: st)) reach \(st.map { b.reachable(b.position, $0) } ?? false) dist \(st.map { simd_distance(b.position, $0) } ?? -1) sleepLocked \(b.sleepLocked) occupant \(String(describing: DecorField.shared.occupant[1])) coUsers \(String(describing: DecorField.shared.coUsers[1])) first \(b.toy.waitUID) idleKind \(String(describing: b.idleState.kind)) scriptNone \(b.scriptIsNone) pending \(String(describing: b.pending)) freeQ \(b.attached) \(b.held) \(b.commanded) \(String(describing: b.social)) \(String(describing: b.job)) \(b.race.active) \(String(describing: b.commandedIdle))", "pair-diag.txt")
            }
            if i % 60 == 0, n == 2 { let b = lab.rigs[1].brain; Self.append("\(kind.rawValue) t\(i / 60) rig1 wait \(b.toy.waitUID) retry \(b.toy.retryUID) pos \(b.position) idle \(String(describing: b.idleState.kind)) act \(b.activity) job \(String(describing: b.job)) cmd \(b.commanded) social \(b.social != nil) reserved \(b.reserved) | rig0 stage \(lab.rigs[0].brain.idleState.slideStage) idle \(String(describing: lab.rigs[0].brain.idleState.kind)) occ \(String(describing: DecorField.shared.occupant[1]))", "pair-trace-\(kind.rawValue).txt") }
        })
        m = mm
        Self.write(lab.rigs.map { "queued \($0.brain.toy.queued) tookTurn \($0.brain.toy.tookTurn) gaveUp \($0.brain.toy.gaveUp) noticed \($0.brain.toy.noticed) wait \($0.brain.toy.waitUID) idle \(String(describing: $0.brain.idleState.kind)) stage \($0.brain.idleState.slideStage) cooldown \($0.brain.idleState.cooldown)" }.joined(separator: "\n"), "pair-end-\(kind.rawValue).txt")
        return m
    }
    func testNewToysWithTwoJelbies() { pairs([.kickscooter, .toyrocket, .rockinghorse, .playtunnel, .ringstacker, .plushdino], "toys-x2-new.txt") }
    func testOtherToysWithTwoJelbies() { pairs([.plushbear, .beachball, .ball, .blocks, .drum, .duck], "toys-x2-other.txt") }
    func testEveryToyWithTwoJelbies() { pairs((ProcessInfo.processInfo.environment["TOYRIDE_KINDS"] ?? "").split(separator: ",").compactMap { DecorKind(rawValue: String($0)) }, "every-toy-x2.txt") }
    func pairs(_ kinds: [DecorKind], _ file: String) {
        var lines: [String] = []
        for k in kinds {
            let m = pairSession(k, seconds: 50, n: k == .beachball || k == .ball ? 3 : 2)
            lines.append(line(k.rawValue, m))
            XCTAssertGreaterThan(m.sessions.reduce(0, +), 0, "\(k): somebody played with it")
            XCTAssertEqual(m.simultaneous, 0, "\(k): used by too many at once")
            XCTAssertGreaterThanOrEqual(m.toyMinGap, 0.85, "\(k): two bodies in toy play came too close")
            if !(k.isBallLike || k.maxUsers > 1 || k.sitPoints.count > 1) { XCTAssertGreaterThanOrEqual(m.sessions.filter { $0 > 0 }.count, 2, "\(k): both Jelbies got a turn (one waited, then went)") }
            if k.maxUsers > 1 { XCTAssertEqual(m.maxUsers, 2, "\(k): two used it together") }
        }
        Self.write(lines.joined(separator: "\n"), file)
    }

    // MARK: performance

    struct Perf { var frames = 0, brainMean = 0.0, brainP50 = 0.0, brainP95 = 0.0, brainP99 = 0.0, brainMax = 0.0, decorMean = 0.0, decorMax = 0.0, rides = 0, sessions = 0, rideFrames = 0, rideMean = 0.0, otherMean = 0.0 }
    static func nowMs() -> Double { Double(mach_absolute_time()) * Self.tb / 1e6 }
    static let tb: Double = { var i = mach_timebase_info_data_t(); mach_timebase_info(&i); return Double(i.numer) / Double(i.denom) }()

    /// Per-frame CPU cost (ms) of the brains' tick (behaviour, steering, toys; the soft-body step is not in it) and of the decor mesh rebuild, over `seconds` (after a warm-up),
    /// with `n` Jelbies. `riding`: the cost of a frame in which a Jelbie is on the scooter, against the other frames.
    func perfRun(n: Int, park: Bool, pieces: [PlacedDecor], seconds: Float, seed: UInt64 = 11, useToys: Bool) -> Perf {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        _ = DecorMeshes.loaded.count          // (the art loads once, at the first piece; not a per-frame cost)
        if park { RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0) }
        defer { if park { GameCamera.endPark(count: 3) } }
        let starts: [SIMD2<Float>] = [SIMD2(-1.8, 1.4), SIMD2(-0.2, 1.8), SIMD2(1.4, 1.2), SIMD2(2.2, 0.2), SIMD2(-2.4, 0.2)]
        let lab = SocialTests.Lab(n: n, positions: Array(starts.prefix(n)), quiet: false, seed: seed)
        for r in lab.rigs { r.brain.anticsEnabled = true; r.brain.sleepEnabled = false; r.brain.idleMood = .happy; r.skinner.autoBlink = false; if park { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius } }
        DecorField.shared.set(pieces)
        DecorField.shared.toys = ToyBook()
        if useToys { for (j, r) in lab.rigs.enumerated() { let f = DecorField.shared.feet[j % DecorField.shared.feet.count]; r.brain.toyGo(f.uid, r.sim) } }
        PerfProbe.reset(); PerfProbe.on = true; defer { PerfProbe.on = false; Self.append("--- \(park ? "park" : "home") x\(n) toys \(useToys) ---\n" + PerfProbe.report, "perf-probes.txt") }
        var brain: [Double] = [], decor: [Double] = [], ride: [Double] = [], other: [Double] = []
        var p = Perf()
        var prev = [Int](repeating: -1, count: n)
        let dt: Float = 1.0 / 60
        let warm = 180
        for fi in 0..<(Int(seconds * 60) + warm) {
            lab.snapshot = lab.rigs.map { (pos: GameCare.floorPos($0.brain, $0.sim), walking: $0.brain.activity == .walking || $0.brain.activity == .coming) }
            lab.asideClock += dt
            if lab.asideClock >= 0.25 { MelonController.makeRoom(snapshot: lab.snapshot, brains: lab.rigs.map { $0.brain }, cooldown: &lab.aside, dt: lab.asideClock); lab.asideClock = 0 }
            var bt = 0.0, anyRide = false
            var perRig: [Double] = []
            for r in lab.rigs {
                let a = Self.nowMs()
                r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false)
                bt += Self.nowMs() - a
                perRig.append(Self.nowMs() - a)
                if r.brain.scooterFoot != nil, r.brain.idleState.slideStage >= 11, r.brain.idleState.slideStage <= 13 { anyRide = true }
                r.sim.step(); r.t += r.sim.stepDt
            }
            let a = Self.nowMs()
            DecorField.shared.tick(dt: dt)
            let fieldMs = Self.nowMs() - a
            for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            bt += Self.nowMs() - a
            let jellyMs = Self.nowMs() - a - fieldMs
            let d0 = Self.nowMs()
            let f = DecorField.shared
            var active = Set<Int>()
            for (k, v) in f.anim where v.active { active.insert(k) }
            if !active.isEmpty { _ = DecorModels.build(feet: f.feet.filter { active.contains($0.uid) }, field: f, time: 0.5) }
            let dm = Self.nowMs() - d0
            for (j, r) in lab.rigs.enumerated() {
                let b = r.brain
                let uid = (b.idleState.kind.map { BlobBrain.decorKinds.contains($0) } ?? false) ? b.idleState.decorUID : -1
                if uid >= 0, prev[j] < 0, fi >= warm { p.sessions += 1 }
                prev[j] = uid
            }
            if fi < warm { continue }
            brain.append(bt); decor.append(dm)
            if bt > 20 { Self.append("SPIKE frame \(fi) \(String(format: "%.1f", bt)) ms (perRig \(perRig.map { String(format: "%.1f", $0) }) field \(String(format: "%.1f", fieldMs)) jelly \(String(format: "%.1f", jellyMs))): " + lab.rigs.map { "\(String(describing: $0.brain.idleState.kind))/st\($0.brain.idleState.slideStage)/\($0.brain.activity)/wait\($0.brain.toy.waitUID)" }.joined(separator: " "), "perf-spikes.txt") }
            if anyRide { ride.append(bt + dm) } else { other.append(bt + dm) }
        }
        for r in lab.rigs { p.rides += r.brain.ride.rides }
        brain.sort(); decor.sort()
        p.frames = brain.count
        p.brainMean = brain.reduce(0, +) / Double(brain.count); p.brainP50 = brain[brain.count / 2]; p.brainP95 = brain[Int(Double(brain.count) * 0.95)]; p.brainP99 = brain[Int(Double(brain.count) * 0.99)]; p.brainMax = brain.last ?? 0
        p.decorMean = decor.reduce(0, +) / Double(decor.count); p.decorMax = decor.last ?? 0
        p.rideFrames = ride.count; p.rideMean = ride.isEmpty ? 0 : ride.reduce(0, +) / Double(ride.count); p.otherMean = other.isEmpty ? 0 : other.reduce(0, +) / Double(other.count)
        return p
    }
    func perfLine(_ name: String, _ p: Perf) -> String {
        String(format: "%@: %d frames, brain tick mean %.3f ms p50 %.3f p95 %.3f p99 %.3f max %.2f | decor rebuild mean %.4f max %.3f | sessions %d rides %d | scooter-ride frames %d: %.3f ms vs other frames %.3f ms", name, p.frames, p.brainMean, p.brainP50, p.brainP95, p.brainP99, p.brainMax, p.decorMean, p.decorMax, p.sessions, p.rides, p.rideFrames, p.rideMean, p.otherMean)
    }

    static let oldToys: [PlacedDecor] = [PlacedDecor(uid: 1, kind: .ball, x: -2.4, z: -0.2), PlacedDecor(uid: 2, kind: .drum, x: -2.6, z: 2.2), PlacedDecor(uid: 3, kind: .blocks, x: 2.6, z: 0.6), PlacedDecor(uid: 4, kind: .plushbear, x: 0.2, z: -1.6), PlacedDecor(uid: 5, kind: .rockinghorse, x: 2.6, z: -1.8)]
    static let newToys: [PlacedDecor] = [PlacedDecor(uid: 1, kind: .kickscooter, x: 0.0, z: -0.2), PlacedDecor(uid: 2, kind: .beachball, x: -2.6, z: 2.2), PlacedDecor(uid: 3, kind: .ringstacker, x: 2.6, z: 0.6),
                                         PlacedDecor(uid: 4, kind: .plushdino, x: 0.2, z: -2.0), PlacedDecor(uid: 5, kind: .toyrocket, x: -2.6, z: -1.6), PlacedDecor(uid: 6, kind: .playtunnel, x: 1.8, z: 2.4)]

    func testPerfHomeThreeJelbies() {
        var lines: [String] = []
        let base = perfRun(n: 3, park: false, pieces: [], seconds: 25, useToys: false)
        let old = perfRun(n: 3, park: false, pieces: Self.oldToys, seconds: 25, useToys: true)
        let new = perfRun(n: 3, park: false, pieces: Self.newToys, seconds: 25, useToys: true)
        lines += [perfLine("HOME x3 no toys (baseline)", base), perfLine("HOME x3 old toys in use", old), perfLine("HOME x3 new toys in use (scooter, rocket, tunnel, dino, rings, ball)", new)]
        Self.write(lines.joined(separator: "\n"), "perf-home.txt")
        MotionLog.write("PERF " + lines.joined(separator: " || "))
        XCTAssertLessThan(new.brainMean, max(base.brainMean, old.brainMean) * 1.25 + 0.25, "the new toys' behaviours cost about what the old ones do")
        XCTAssertLessThan(new.brainP95, 3, "no frame hitch: the brains' tick stays far under a frame (16.7 ms)")
    }
    func testPerfParkFiveJelbies() {
        var lines: [String] = []
        let base = perfRun(n: 5, park: true, pieces: ParkToys.placed, seconds: 25, useToys: false)
        let withNew = perfRun(n: 5, park: true, pieces: ParkToys.placed + Self.newToys.prefix(3).enumerated().map { PlacedDecor(uid: 100 + $0.offset, kind: $0.element.kind, x: [-1.0, 1.6, 0.4][$0.offset], z: [1.0, 0.6, 2.2][$0.offset]) }, seconds: 25, useToys: true)
        lines += [perfLine("PARK x5 park toys (baseline)", base), perfLine("PARK x5 park toys + scooter, beach ball, ring stacker in use", withNew)]
        Self.write(lines.joined(separator: "\n"), "perf-park.txt")
        MotionLog.write("PERF " + lines.joined(separator: " || "))
        XCTAssertLessThan(withNew.brainMean, base.brainMean * 1.35 + 0.3)
        XCTAssertLessThan(withNew.brainP95, 4)
    }
}

extension Array { var nonEmpty: [Element]? { isEmpty ? nil : self } }
