import Foundation
import QuartzCore
import simd

/// The real-app proof lines of the room round (2026-11-15): where the roaming floor stands, where the home bodies and the race rivals are, and where a lone one walks.
/// DEV ONLY and LOG ONLY: it reads the stage and NSLogs `[roamprobe] ...` lines; it changes no game state (its own static bookkeeping aside). Off unless the launch
/// argument `-RaceWallProbe 1` is given in a dev build (`DevArgs.enabled`); `-RaceWallProbeTag <word>` sets the `arm=` word of the PATH lines (default `app`).
/// Five line kinds, `key=value` words separated by one space:
///  STAGE  once per model: which stage it is (room | preview), how many bodies;
///  FLOOR  whenever the global floor state changes (`GameCamera.roamFloor`, the arena, `walkMaxZ`), noticed by the tick of any stage;
///  HOME   per body of the room stage: the wall, the position, the walk goal, the race / show / trip flags; on a change and every 5 s;
///  RIVAL  per visitor body while a race or show runs: the same, on a change and every 2 s;
///  ROOMROAM-PATH  the measuring test's `pathOut` line, once per second per body while he is at home (position and letter exactly as `RoomRoamMeasureTests` does it).
@MainActor
enum RoomRoamProbe {
    static let on = DevArgs.enabled && UserDefaults.standard.integer(forKey: "RaceWallProbe") == 1
    static let tag = UserDefaults.standard.string(forKey: "RaceWallProbeTag") ?? "app"

    private static var t0: Double?
    private static var seenModels = Set<ObjectIdentifier>()
    private static var lastFloorKey = ""
    private static var lastHome: [ObjectIdentifier: (key: String, at: Double)] = [:]
    private static var lastRival: [ObjectIdentifier: (key: String, at: Double)] = [:]
    private static var lastPath: [ObjectIdentifier: Int] = [:]

    private static func out(_ line: String) { NSLog("%@", "[roamprobe] " + line) }
    private static func f2(_ v: Float) -> String { String(format: "%.2f", v) }
    private static func pt(_ p: SIMD2<Float>) -> String { String(format: "%.2f,%.2f", p.x, p.y) }
    private static func r2(_ v: Float) -> Float { (v * 100).rounded() / 100 }
    private static func rad(_ v: Float) -> String { v.isFinite ? f2(v) : "inf" }
    private static func b(_ v: Bool) -> String { v ? "1" : "0" }

    static func tick(actors: [JellyActor], parkActors: [JellyActor], model: MelonModel, aspect: Float) {
        let now = CACurrentMediaTime()
        if t0 == nil { t0 = now }
        let t = now - (t0 ?? now)
        let ts = String(format: "%.1f", t)
        let care = model.care
        let seenBy = model.preview ? "preview" : "room"

        if seenModels.insert(ObjectIdentifier(model)).inserted {
            out("STAGE t=\(ts) stage=\(seenBy) n=\(actors.count) park=\(parkActors.count) drawAspect=\(String(format: "%.3f", aspect))")
        }

        // FLOOR: the global state, checked on every tick of every stage.
        let rf = GameCamera.roamFloor
        let floorKey = [rf == nil ? "no" : "yes", rf.map { String(format: "%.3f", $0.aspect) } ?? "-", rf.map { f2($0.minZ) } ?? "-", rf.map { f2($0.maxZ) } ?? "-",
                        rf?.hw.max().map { f2($0) } ?? "-", pt(GameCamera.arenaCenter), f2(GameCamera.arenaRadius), f2(GameCamera.walkMaxZ)].joined(separator: "|")
        if floorKey != lastFloorKey {
            lastFloorKey = floorKey
            out("FLOOR t=\(ts) floor=\(rf == nil ? "no" : "yes") floorAspect=\(rf.map { String(format: "%.3f", $0.aspect) } ?? "-") minZ=\(rf.map { f2($0.minZ) } ?? "-") maxZ=\(rf.map { f2($0.maxZ) } ?? "-") hwMax=\(rf?.hw.max().map { f2($0) } ?? "-") camWallC=\(pt(GameCamera.arenaCenter)) camWallR=\(f2(GameCamera.arenaRadius)) walkMaxZ=\(f2(GameCamera.walkMaxZ)) seenBy=\(seenBy) n=\(actors.count) park=\(parkActors.count) drawAspect=\(String(format: "%.3f", aspect)) trip=\(b(care.tripActive)) raceBusy=\(b(care.raceBusy))")
        }
        guard !model.preview else { return }

        let racePhase = String(describing: care.race.phase), simPhase = care.race.sim.map { String(describing: $0.phase) } ?? "-"
        let show = care.show.active, trip = care.tripActive, busy = care.raceBusy

        // HOME
        for a in actors {
            let sim = a.sim, brain = a.brain, id = ObjectIdentifier(a)
            let wc = sim.arenaCenter, wr = sim.arenaRadius
            let racing = brain?.race.active ?? false
            let key = [rf == nil ? "no" : "yes", pt(SIMD2(r2(wc.x), r2(wc.y))), wr.isFinite ? f2(wr) : "inf", racePhase, simPhase, b(show), b(trip), b(busy), b(racing)].joined(separator: "|")
            let prev = lastHome[id]
            let changed = prev?.key != key
            if changed || now - (prev?.at ?? 0) >= 5 {
                lastHome[id] = (key, now)
                let c = sim.centroid()          // (the same centroid `bodyPose(iterations:)` returns, but read-only: `bodyPose` rewrites the pose fit's warm start `fitQ`, so it is not called)
                let pos = brain.map { GameCare.floorPos($0, sim) } ?? SIMD2(c.x, c.z)
                let gap = simd_length(sim.attractor.anchor - c)
                var goal = "-", goalOut = "-"
                if let br = brain, case .walk(let g, _) = br.script {
                    goal = pt(g)
                    if wr.isFinite { goalOut = f2(max(0, simd_distance(g, wc) - wr)) }
                }
                out("HOME t=\(ts) id=\(a.id) name=\(a.name.replacingOccurrences(of: " ", with: "_")) floor=\(rf == nil ? "no" : "yes") wallC=\(pt(wc)) wallR=\(rad(wr)) pos=\(pt(pos)) gap=\(f2(gap)) act=\(brain.map { String(describing: $0.activity) } ?? "-") goal=\(goal) goalOut=\(goalOut) racePhase=\(racePhase) simPhase=\(simPhase) show=\(b(show)) trip=\(b(trip)) raceBusy=\(b(busy)) racing=\(b(racing)) homeRoom=\(b(brain?.homeRoom ?? false)) why=\(changed ? "change" : "tick")")
            }
        }

        // RIVAL
        if care.race.active || show {
            for a in parkActors {
                let sim = a.sim, brain = a.brain, id = ObjectIdentifier(a)
                let wc = sim.arenaCenter, wr = sim.arenaRadius
                let racing = brain?.race.active ?? false
                let key = [wr.isFinite ? f2(wr) : "inf", racePhase, simPhase, b(racing)].joined(separator: "|")
                let prev = lastRival[id]
                let changed = prev?.key != key
                if changed || now - (prev?.at ?? 0) >= 2 {
                    lastRival[id] = (key, now)
                    let c = sim.centroid()
                    let pos = brain.map { GameCare.floorPos($0, sim) } ?? SIMD2(c.x, c.z)
                    let gap = simd_length(sim.attractor.anchor - c)
                    out("RIVAL t=\(ts) id=\(a.id) name=\(a.name.replacingOccurrences(of: " ", with: "_")) wallC=\(pt(wc)) wallR=\(rad(wr)) pos=\(pt(pos)) anchor=\(pt(SIMD2(sim.attractor.anchor.x, sim.attractor.anchor.z))) gap=\(f2(gap)) racePhase=\(racePhase) simPhase=\(simPhase) racing=\(b(racing)) why=\(changed ? "change" : "tick")")
                }
            }
        }

        // ROOMROAM-PATH
        if !trip && !busy {
            let sec = Int(t)
            for (i, a) in actors.enumerated() {
                guard let br = a.brain else { continue }
                let id = ObjectIdentifier(a)
                guard lastPath[id] != sec else { continue }
                lastPath[id] = sec
                let p = GameCare.floorPos(br, a.sim)
                let social = br.isSocial, k = br.idleState.kind
                let walking = br.activity == .walking || br.activity == .coming
                let letter = social ? "s" : (k == .sleep ? "z" : (walking ? "w" : (k != nil ? "i" : "r")))
                out("ROOMROAM-PATH arm=\(tag) n=\(actors.count) seed=0 t=\(sec) i=\(i) x=\(f2(p.x)) z=\(f2(p.y)) a=\(letter)")
            }
        }
    }
}
