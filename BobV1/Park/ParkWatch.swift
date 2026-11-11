//
//  ParkWatch.swift
//  A measuring aid for the acceptance watch of the park (simulator only, never on a device, off unless the app's environment has PARKWATCH_LOG=<absolute host path>).
//  Every 0.1 s of PARK time it appends one line per body (the Jelbies that came + the visitors) to that text file, plus the piece / room shapes and the seesaws' state.
//  SCRATCH/watch/analyze.py turns the file into the counters. Optional PARKWATCH_PLAN=seesaw|hopscotch|both: before the park opens, the saved visit counter is set so the
//  game's own `ParkVisitPlan.begin()` draws that plan. Hook: one line in GameCare+Park.swift `tickPark` (`ParkWatch.tick(self, actors, dt: dt)`).
//  Not reachable from here (private): the stage's StuckWatchdog (so `dog=-1` and no `D` line).
//

#if targetEnvironment(simulator)
import Foundation
import simd

enum ParkWatch {
    nonisolated(unsafe) private static let env = ProcessInfo.processInfo.environment
    nonisolated(unsafe) private static var handle: FileHandle?
    nonisolated(unsafe) private static var failed = false
    nonisolated(unsafe) private static var planChecked = false
    nonisolated(unsafe) private static var t: Float = 0, next: Float = 0
    nonisolated(unsafe) private static var lastHeader = ""
    nonisolated(unsafe) private static var hedgeBox: (x0: Float, x1: Float, z0: Float, z1: Float)?

    static func tick(_ care: GameCare, _ actors: [JellyActor], dt: Float) {
        guard env["PARKWATCH_LOG"] != nil else { return }
        if !planChecked {
            planChecked = true
            if care.park.phase == .off, let p = env["PARKWATCH_PLAN"] { applyPlan(p) }
        }
        guard care.park.phase == .playing else { return }
        t += dt
        guard t + 1e-6 >= next else { return }
        next += 0.1
        let book = care.parkBook
        let bodies = actors.enumerated().filter { book.comers.contains($0.offset) }.map(\.element) + book.actors
        sample(bodies, homeIDs: Set(actors.enumerated().filter { book.comers.contains($0.offset) }.map(\.element.id)))
    }

    // MARK: the plan

    private static func applyPlan(_ name: String) {
        for k in 1...64 {
            let d = ParkVisitPlan.draw(visit: k, seesawOff: 0, hopscotchOff: 0)
            let hit: Bool
            switch name {
            case "seesaw": hit = d.seesaw && !d.hopscotch
            case "hopscotch": hit = !d.seesaw && d.hopscotch
            case "both": hit = d.seesaw && d.hopscotch
            default: return
            }
            if hit { UserDefaults.standard.set(["visit": k - 1, "seesawOff": 0, "hopscotchOff": 0], forKey: ParkVisitPlan.key); return }
        }
    }

    // MARK: the file

    private static func write(_ line: String) {
        if handle == nil, !failed {
            guard let p = env["PARKWATCH_LOG"] else { return }
            try? FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: p) { FileManager.default.createFile(atPath: p, contents: nil) }
            handle = FileHandle(forWritingAtPath: p)
            if handle == nil { failed = true }
            _ = try? handle?.seekToEnd()
        }
        handle?.write((line + "\n").data(using: .utf8)!)
    }

    private static func f(_ v: Float, _ n: Int = 3) -> String { String(format: "%.\(n)f", v) }

    // MARK: one sample

    private static func sample(_ bodies: [JellyActor], homeIDs: Set<Int>) {
        let wall = Date().timeIntervalSince1970
        let key = bodies.map { "\($0.id)" }.joined(separator: ",")
        if key != lastHeader {
            lastHeader = key
            let plan = ParkVisitPlan.current
            let home = bodies.filter { homeIDs.contains($0.id) }.map { "\($0.id)" }.joined(separator: ",")
            let vis = bodies.filter { !homeIDs.contains($0.id) }.map { "\($0.id)" }.joined(separator: ",")
            write("H v=1 wall=\(String(format: "%.2f", wall)) t=\(f(t, 2)) gap=\(f(MelonController.jellyGap)) home=\(home) visitors=\(vis) plan=\(plan.seesaw ? 1 : 0),\(plan.hopscotch ? 1 : 0),\(plan.visit)")
            shapes()
        }
        for a in bodies {
            guard let b = a.brain else { continue }
            let p = a.floor
            // air: the lowest point of the two feet's beans is more than 4 cm over the sim's floor (a hop, the ladder, the platform, the chute, a seat); no bean = the centroid's height over its rest is not known: -1
            var lo = Float.infinity
            for s in 0..<2 { for q in a.skinner.beanPos[s] { lo = min(lo, q.y) } }
            let air = lo.isFinite ? (lo - a.sim.floorY > 0.04 ? 1 : 0) : -1
            var tgt = "tx=- tz=-"
            if case let .walk(target, _) = b.script { tgt = "tx=\(f(target.x, 2)) tz=\(f(target.y, 2))" }
            let idle = b.idleState.kind
            var uid = "-", pk = "-"
            if let k = idle, BlobBrain.decorKinds.contains(k) || k == .hopscotch {
                uid = "\(b.idleState.decorUID)"
                pk = DecorField.shared.foot(b.idleState.decorUID)?.kind.rawValue ?? "?"
            }
            var soc = "-"
            if let s = b.social { soc = "\(s.kind.rawValue)/\(s.phase)" }
            write("B t=\(f(t, 2)) w=\(String(format: "%.2f", wall)) id=\(a.id) home=\(homeIDs.contains(a.id) ? 1 : 0) x=\(f(p.x)) z=\(f(p.y)) air=\(air) try=\(b.tryingToMove ? 1 : 0) act=\(b.activity) \(tgt) idle=\(idle?.rawValue ?? "-") uid=\(uid) pk=\(pk) stage=\(b.idleState.slideStage) step=\(b.idleState.slideStep) phase=\(b.idleState.phase) bag=\(b.idleState.bagStage) perched=\(b.isPerched ? 1 : 0) soc=\(soc) stall=\(f(b.steerStall, 2)) wst=\(f(b.walkStallT, 2)) sw=\(f(b.steerWait, 2)) st=\(f(b.stuckT, 2)) rep=\(b.stuckRepicks) dog=-1")
        }
        for ft in DecorField.shared.feet where ft.kind == .seesaw {
            let seats = (DecorField.shared.seatOccupant[ft.uid] ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
            write("W t=\(f(t, 2)) uid=\(ft.uid) mode=\(SeesawRide.shared.mode(ft.uid)) theta=\(f(SeesawRide.shared.drawnTheta(ft.uid), 4)) seats=\(seats.isEmpty ? "-" : seats)")
        }
    }

    // MARK: the shapes (written with every H)

    private static func shapes() {
        // the decor pieces, with the REAL footprint the steering uses (`DecorFoot.box`: the turned half extents + corner radius); `turn` = the quarter turns the field stores
        for ft in DecorField.shared.feet {
            let c = DecorField.shared.position(ft), bx = ft.box
            var extra = ""
            if ft.kind == .seesaw {          // the stand spot in front of each seat, straight ahead (BlobBrain.seesawStandSpots, first entry): centre + turned(seat.x, standDz)
                for (i, sp) in ft.kind.sitPoints.enumerated() { let q = ft.centre + ft.turned(SIMD2(sp.x, SeesawTuning.standDz)); extra += " stand\(i)=\(f(q.x)),\(f(q.y))" }
            }
            write("S name=\(ft.kind.rawValue)#\(ft.uid) shape=box cx=\(f(c.x)) cz=\(f(c.y)) hx=\(f(bx.half.x)) hz=\(f(bx.half.y)) cr=\(f(bx.radius)) turn=\(ft.quarter) solid=\(ft.spec.solid ? 1 : 0) src=decor\(extra)")
        }
        // the room's colliders (Park/ParkRoom.swift, RoomCatalog.park): couch = the bench, boxes[0] = the flower bed, cylinders[0] = the pond (lampTable is the same cylinder)
        let r = RoomCatalog.park
        let cb = r.couch
        write("S name=bench shape=box cx=\(f(cb.centre.x)) cz=\(f(cb.centre.z)) hx=\(f(cb.halfExtents.x)) hz=\(f(cb.halfExtents.z)) cr=\(f(cb.radius)) turn=0 solid=1 src=room")
        for (i, bx) in r.boxes.enumerated() {
            write("S name=flowerbed\(i) shape=box cx=\(f(bx.centre.x)) cz=\(f(bx.centre.z)) hx=\(f(bx.halfExtents.x)) hz=\(f(bx.halfExtents.z)) cr=\(f(bx.radius)) turn=0 solid=1 src=room")
        }
        for (i, cy) in r.cylinders.enumerated() {
            write("S name=\(i == 0 ? "pond" : "cyl\(i)") shape=circle cx=\(f(cy.centre.x)) cz=\(f(cy.centre.y)) r=\(f(cy.radius)) src=room")
        }
        // art with no collider. The lamp post: ParkRoom.swift line 147 `lampPost(b, x: 1.72, z: -4.85)`, base disc radius 0.14 (ParkNature.lampPost).
        write("S name=lamppost shape=circle cx=1.720 cz=-4.850 r=0.140 src=art")
        // the hedge: two stamps at (-2.4, -6.0) and (0.8, -6.05), scale 1.5, yaw 0 (ParkRoom.swift lines 123); the extent is the asset's own bounds x 1.5 (read from the park_hedge asset)
        if hedgeBox == nil, let art = DecorMeshes.load("hedge", prefix: "park_") {
            var x0 = Float.infinity, x1 = -Float.infinity, z0 = Float.infinity, z1 = -Float.infinity
            for part in art.parts { for q in part.positions { x0 = min(x0, q.x); x1 = max(x1, q.x); z0 = min(z0, q.z); z1 = max(z1, q.z) } }
            if x0.isFinite { hedgeBox = (x0 * 1.5, x1 * 1.5, z0 * 1.5, z1 * 1.5) }
        }
        if let h = hedgeBox {
            for (i, o) in [SIMD2<Float>(-2.4, -6.0), SIMD2<Float>(0.8, -6.05)].enumerated() {
                write("S name=hedge\(i) shape=box cx=\(f(o.x + (h.x0 + h.x1) / 2)) cz=\(f(o.y + (h.z0 + h.z1) / 2)) hx=\((f((h.x1 - h.x0) / 2))) hz=\(f((h.z1 - h.z0) / 2)) cr=0.000 turn=0 solid=1 src=art")
            }
        }
        // the fence: posts every 1.4 from x -14, the span -4.0...2.4 left open (the hedge stands there), z -6.45, post half 0.05, rails half-depth 0.025 (ParkNature.fence, ParkRoom.swift line 124)
        write("S name=fenceL shape=box cx=-9.000 cz=-6.450 hx=5.000 hz=0.050 cr=0.000 turn=0 solid=1 src=art")
        write("S name=fenceR shape=box cx=8.200 cz=-6.450 hx=5.800 hz=0.050 cr=0.000 turn=0 solid=1 src=art")
    }
}
#endif
