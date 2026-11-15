import Foundation
import QuartzCore
import simd

/// The real-app proof lines of the room round (2026-11-15): where the roaming floor stands, where the home bodies and the race rivals are, and where a lone one walks.
/// DEV ONLY and LOG ONLY: it reads the stage and NSLogs `[roamprobe] ...` lines; it changes no game state (its own static bookkeeping aside). Off unless the launch
/// argument `-RaceWallProbe 1` is given in a dev build (`DevArgs.enabled`); `-RaceWallProbeTag <word>` sets the `arm=` word of the PATH lines (default `app`).
/// File sink: when the app's environment has `ROOMPROBE_LOG=<path>` every line is also appended there as `<unix seconds, 3 decimals> <line>` (a UI-test run's NSLog does not
/// reach the test log); the handle is opened once, each line is written at once (pattern: Dining/MealTrace.swift).
/// Eight line kinds, `key=value` words separated by one space:
///  STAGE  once per model: which stage it is (room | preview), how many bodies;
///  FLOOR  whenever the global floor state changes (`GameCamera.roamFloor`, the arena, `walkMaxZ`), noticed by the tick of any stage;
///  HOME   per body of the room stage: the wall, the position, the walk goal, the race / show / trip flags; on a change and every 5 s;
///  RIVAL  per visitor body while a race or show runs: the same, on a change and every 2 s;
///  ROOMROAM-PATH  the measuring test's `pathOut` line, once per second per body while he is at home (position and letter exactly as `RoomRoamMeasureTests` does it);
///  VIEW   room stage: the draw aspect at the first tick and whenever it changes by more than 0.005 (a rotation);
///  CLOCK  room stage, every 5 s: frames, fps, how fast the home bodies' sims ran against real time, per body sim time and asleep;
///  GOAL   room stage, per home body: each new walk goal (more than 0.01 from the last one printed, at most one per 0.5 s per body).
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

    private static var lastView: Float?
    private static var clockLast: Double?
    private static var clockFrames = 0
    private static var clockSim: [ObjectIdentifier: Float] = [:]
    private static var lastGoal: [ObjectIdentifier: (goal: SIMD2<Float>, at: Double)] = [:]
    private static var fileHandle: FileHandle?
    private static var fileTried = false

    private static func out(_ line: String) {
        NSLog("%@", "[roamprobe] " + line)
        if !fileTried {
            fileTried = true
            if let path = ProcessInfo.processInfo.environment["ROOMPROBE_LOG"], !path.isEmpty {
                if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
                fileHandle = FileHandle(forWritingAtPath: path)
                _ = try? fileHandle?.seekToEnd()
            }
        }
        guard let h = fileHandle else { return }
        h.write((String(format: "%.3f ", Date().timeIntervalSince1970) + line + "\n").data(using: .utf8) ?? Data())
    }
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

        // VIEW
        if lastView == nil || abs(aspect - (lastView ?? 0)) > 0.005 {
            out("VIEW t=\(ts) drawAspect=\(String(format: "%.3f", aspect)) was=\(lastView.map { String(format: "%.3f", $0) } ?? "-") n=\(actors.count) floor=\(rf == nil ? "no" : "yes") floorAspect=\(rf.map { String(format: "%.3f", $0.aspect) } ?? "-")")
            lastView = aspect
        }

        // CLOCK
        clockFrames += 1
        if clockLast == nil {
            clockLast = now
            for a in actors { clockSim[ObjectIdentifier(a)] = a.sim.time }
            clockFrames = 1
        } else if let last = clockLast, now - last >= 5 {
            let dt = now - last
            var rate: Float = 0
            var bodies: [String] = []
            for a in actors {
                let id = ObjectIdentifier(a), st = a.sim.time
                rate = max(rate, (st - (clockSim[id] ?? st)) / Float(dt))
                clockSim[id] = st
                bodies.append("\(a.id):\(String(format: "%.1f", st)):\(a.asleep ? 1 : 0)")
            }
            out("CLOCK t=\(ts) dt=\(String(format: "%.2f", dt)) frames=\(clockFrames) fps=\(String(format: "%.1f", Double(clockFrames) / dt)) simRate=\(f2(rate)) bodies=\(bodies.isEmpty ? "-" : bodies.joined(separator: ","))")
            clockLast = now
            clockFrames = 0
        }

        // GOAL
        for a in actors {
            guard let br = a.brain else { continue }
            let id = ObjectIdentifier(a)
            guard case .walk(let g, _) = br.script else { lastGoal[id] = nil; continue }
            let prev = lastGoal[id]
            guard prev == nil || (simd_distance(prev!.goal, g) > 0.01 && now - prev!.at >= 0.5) else { continue }
            lastGoal[id] = (g, now)
            let wc = a.sim.arenaCenter, wr = a.sim.arenaRadius
            out("GOAL t=\(ts) id=\(a.id) name=\(a.name.replacingOccurrences(of: " ", with: "_")) goal=\(pt(g)) from=\(pt(GameCare.floorPos(br, a.sim))) goalOut=\(wr.isFinite ? f2(max(0, simd_distance(g, wc) - wr)) : "-") wallR=\(rad(wr)) floor=\(rf == nil ? "no" : "yes") act=\(String(describing: br.activity)) trip=\(b(trip)) raceBusy=\(b(busy))")
        }

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
