//
//  ShowDanceFeetCrossTests.swift
//  The owner, in the Jelly Show's Dance round: "the feet are still crossing during the dance". This runs the REAL dance headless (the stage rig, the real
//  songs and prompts) and measures, in the body's own frame at every 60 Hz frame (planted or in the air):
//    1. the lateral separation (right foot minus left foot, centre to centre) never drops below 60 % of the rest stance width;
//    2. the two footprints (ellipses from the foot particles' extents) never overlap;
//    3. (seen from the front) the legs never swap sides: the same lateral order of the feet, i.e. criterion 1 in the body's frame; the drawn feet of the dance ARE the planned
//       feet (the skinner's world-driven beans), so the planned positions are what is measured. (The body-rigid beans a headless run builds are not what the dance draws; their gap is printed only.)
//  Under (a) every prompt hit on its beat as a Perfect, (b) random L / R presses (same side twice, early, late, during a fill step), (c) no presses,
//  on every rank (calm: Puddle / Pond, lively: Lagoon / Ocean) and every song. (d) shoes: the shoe shell is a function of the bean vertices measured in 3.
//  Every crossing prints which move, beat and input made it and by how much. Also prints each move's lateral travel per step and the plants per beat.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ShowDanceFeetCrossTests: XCTestCase {
    enum Mode: String { case perfect, random, none }

    struct Cross { var move: ShowDanceMove; var beat: Double; var input: String; var kind: String; var worst: Float; var frames = 1 }
    struct Report {
        var crosses: [Cross] = []
        var minSep: Float = .infinity, minBeanGap: Float = .infinity
        var restWidth: Float = 0, restBeanGap: Float = 0
        var travel: [ShowDanceMove: [Float]] = [:], rootTravel: [ShowDanceMove: [Float]] = [:]
        var plants = 0, prompts = 0, promptsAnswered80 = 0
        var beats = 0
    }

    private func ready(_ care: GameCare) { care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }; care.show.cue = { _ in } }
    private func step(_ room: RaceThreeTests.Room) {
        for a in room.actors + room.park { if let b = a.brain { b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false) } }
        room.care.tickRace(room.actors, dt: 1 / 60)
        room.care.tickShow(room.actors, dt: 1 / 60)
    }

    func measure(rank: ShowRank, song: Int, mode: Mode, seed: UInt64 = 1, keepApart: Bool = true) -> Report {
        ShowDancePlan.keepFeetApart = keepApart
        defer { ShowDancePlan.keepFeetApart = true }
        let room = RaceThreeTests.Room(count: 1)
        RaceThreeTests.keep.append(room)
        let care = room.care
        ready(care)
        for b in ShowRank.allCases where b.index < rank.index { care.show.progress.record(rank: b, place: 1, theme: .bunnyPicnic, character: 0, burst: false, perfectDance: false, hatTrick: false) }
        care.show.progress.chosen = rank
        care.show.auto = false
        care.startShow(jelly: 0, rank: rank, seed: ShowDanceStepsTests.seed(forSong: song))
        let b = room.actors[0].brain!, a = room.actors[0]
        for _ in 0..<(60 * 40) { step(room); if care.show.onStage { break } }
        var r = Report()
        let g = care.show.danceSong.grid
        r.beats = care.show.danceSong.lastBeat
        // rest geometry (feet stand square)
        b.ensureFeet(a.sim)
        let geom = b.geom
        r.restWidth = geom.off[1].x - geom.off[0].x
        func ext(_ k: Int) -> (ax: Float, az: Float) {
            let xs = geom.rest[k].map(\.x), zs = geom.rest[k].map(\.z)
            return ((xs.max()! - xs.min()!) / 2, (zs.max()! - zs.min()!) / 2)
        }
        let e0 = ext(0), e1 = ext(1)
        var lowGap: Float = 0
        func beanGap() -> Float? {
            guard let w = GameCare.footBeans(brain: b, sim: a.sim, skinner: a.skinner) else { return nil }
            let yaw = b.yaw
            func xs(_ s: Int, low: Bool) -> [Float] { let y0 = w[s].map(\.y).min() ?? 0; return w[s].filter { !low || $0.y < y0 + 0.1 }.map { rotXZ(SIMD2($0.x, $0.z), -yaw).x } }
            lowGap = xs(1, low: true).min()! - xs(0, low: true).max()!
            return xs(1, low: false).min()! - xs(0, low: false).max()!
        }
        r.restBeanGap = beanGap() ?? 0
        print(String(format: "SHOWFEET geometry: rest width %.3f, foot half extent x %.3f z %.3f, rest bean gap %.3f", r.restWidth, e0.ax, e0.az, r.restBeanGap))
        // prompts (song time, foot as the Left / Right button)
        let song = care.show.danceSong
        let prompts = song.prompts(care.show.dancePattern).map { (t: song.time(ofSlot: $0.slot), foot: $0.foot) }
        var lcg = seed &* 0x9E3779B97F4A7C15 &+ UInt64(song.song * 31 + rank.index)
        func rnd() -> Double { lcg = lcg &* 6364136223846793005 &+ 1442695040888963407; return Double((lcg >> 33) % 100000) / 100000 }
        // random presses: from 2 to 8 per bar, uniformly random times and sides; 40 % repeat the last side
        var randomPresses: [(t: Double, foot: Int)] = []
        do {
            var last = 0
            var t = g.firstBeat + 3 * g.period
            let end = g.firstBeat + Double(song.lastBeat) * g.period
            while t < end { t += 0.12 + rnd() * 0.5; let f = rnd() < 0.4 ? last : 1 - last; randomPresses.append((t, f)); last = f }
        }
        var script = mode == .perfect ? prompts.map { (t: $0.t, foot: $0.foot) } : (mode == .random ? randomPresses : [])
        script.sort { $0.t < $1.t }
        var started = false, swinging = false, startFoot = SIMD2<Float>.zero, startRoot = SIMD2<Float>.zero, startYaw: Float = 0
        var lastInput = "no press yet"
        var cur: Cross?, beanNote = ""
        var sepNow: Float = 0
        var plantTimes: [Double] = []
        var frames = 0
        for _ in 0..<(60 * 60) {
            if care.show.beat == .dancing {
                started = true
                let now = care.show.danceNow()
                while let p = script.first, p.t <= now {
                    script.removeFirst()
                    lastInput = String(format: "%@ press %@ at %.3f s (beat %.2f)", mode.rawValue, p.foot == 0 ? "L" : "R", p.t, (p.t - g.firstBeat) / g.period)
                    care.show.tap(foot: p.foot)          // (the UI's own entry: judges the press, then the stage's onTap / onHit)
                }
            }
            step(room)
            guard started, care.show.beat == .dancing, let run = care.showBook.danceRun else { if started, care.show.beat == .danced { break }; continue }
            frames += 1
            let now = care.show.danceNow()
            let beat = (now - g.firstBeat) / g.period
            let idx = max(0, min(run.nextIndex - 1, run.schedule.count - 1))
            let st = run.schedule.isEmpty ? nil : run.schedule[idx]
            let barNow = min(max(Int((beat - 0.001) / 4), 0), run.phrases.count - 1)
            let move = run.phrases[barNow]
            let yaw = b.yaw
            let p0 = b.feet.state(0).xz, p1 = b.feet.state(1).xz
            let d = rotXZ(p1 - p0, -yaw)
            sepNow = d.x
            r.minSep = min(r.minSep, d.x)
            // footprints: identical axis-aligned ellipses: overlap iff (dx / (ax0 + ax1))^2 + (dz / (az0 + az1))^2 < 1
            let q = (d.x / (e0.ax + e1.ax)) * (d.x / (e0.ax + e1.ax)) + (d.y / (e0.az + e1.az)) * (d.y / (e0.az + e1.az))
            var kind: String?, worst: Float = 0
            beanNote = ""
            if d.x < 0.6 * r.restWidth { kind = "separation"; worst = 0.6 * r.restWidth - d.x }
            if q < 1 { kind = kind.map { $0 + "+overlap" } ?? "overlap"; worst = max(worst, 1 - q) }
            if let gp = beanGap() { r.minBeanGap = min(r.minBeanGap, gp) }          // (informational: headless, the beans are the BODY-rigid ones; in the app the dance's beans are drawn on the planned feet, measured above)
            if let k = kind {
                let step = String(format: "foot in air %d (swinging %@), bar %d (prev bar %@), scheduled %@", b.feet.side, b.feet.swinging ? "yes" : "no", barNow, barNow > 0 ? run.phrases[barNow - 1].rawValue : "-", st.map { String(format: "%@ side %d bar %d (%d of %d) plant %.3f", $0.prompt ? "prompt" : "fill", $0.side, $0.bar, $0.j + 1, $0.n, $0.plant) } ?? "-")
                if var c = cur, c.kind == k, c.move == move { c.worst = max(c.worst, worst); c.frames += 1; cur = c }
                else { if let c = cur { r.crosses.append(c) }; cur = Cross(move: move, beat: beat, input: "\(step); last input: \(lastInput)\(beanNote)", kind: k, worst: worst) }
            } else if let c = cur { r.crosses.append(c); cur = nil }
            // travel and plants
            if !swinging, b.feet.swinging { startFoot = b.feet.pos[b.feet.side]; startRoot = b.position; startYaw = yaw }
            if swinging, !b.feet.swinging {
                // lateral travel in the frame the step started in: the swing foot's own and the root's
                r.travel[move, default: []].append(abs(rotXZ(b.feet.pos[b.feet.side] - startFoot, -startYaw).x))
                r.rootTravel[move, default: []].append(abs(rotXZ(b.position - startRoot, -startYaw).x))
                r.plants += 1; plantTimes.append(now)
            }
            swinging = b.feet.swinging
            _ = sepNow
        }
        if let c = cur { r.crosses.append(c) }
        r.prompts = prompts.count
        r.promptsAnswered80 = prompts.filter { p in plantTimes.contains { abs($0 - p.t) <= 0.08 } }.count
        return r
    }

    func summary(_ name: String, _ r: Report) -> String {
        var s = String(format: "SHOWFEET %@: crossings %d, min centre separation %.3f u (rest %.3f, limit %.3f), min bean gap %.3f (rest %.3f), plants %d (%.2f per beat), prompts on a plant within 80 ms %d of %d",
                       name, r.crosses.count, r.minSep, r.restWidth, 0.6 * r.restWidth, r.minBeanGap, r.restBeanGap, r.plants, Double(r.plants) / Double(max(r.beats, 1)), r.promptsAnswered80, r.prompts)
        for (m, v) in r.travel.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let rt = r.rootTravel[m] ?? [0]
            s += String(format: "\n    lateral travel per step %@: n %d foot mean %.3f max %.3f, body mean %.3f u", m.rawValue, v.count, v.reduce(0, +) / Float(v.count), v.max() ?? 0, rt.reduce(0, +) / Float(max(rt.count, 1)))
        }
        var shown: [String: Int] = [:]
        for m in ShowDanceMove.allCases { let n = r.crosses.filter { $0.move == m }.count; if n > 0 { s += "\n    \(n) crossings in \(m.rawValue)" } }
        for c in r.crosses where shown[c.move.rawValue, default: 0] < 3 {
            shown[c.move.rawValue, default: 0] += 1
            s += String(format: "\n    CROSS %@ move %@ at beat %.2f for %d frames, worst %.3f: %@", c.kind, c.move.rawValue, c.beat, c.frames, c.worst, c.input)
        }
        print(s)
        return s
    }

    /// Every rank, every song, every input mode.
    /// The BEFORE: with the plan's feet guard off (5eab615f's plan) the same measurement finds the crossings the owner saw.
    func testBeforeTheFixTheFeetCross() {
        for (rank, song) in [(ShowRank.puddle, 1), (.ocean, 2)] {
            for mode in [Mode.perfect, .random, .none] {
                let r = measure(rank: rank, song: song, mode: mode, keepApart: false)
                _ = summary("BEFORE (guard off) \(rank) song \(song) \(mode.rawValue)", r)
                XCTAssertGreaterThan(r.crosses.count, 0, "\(rank) song \(song) \(mode.rawValue): the old plan crosses")
            }
        }
    }
    func testQuickPuddleSong1() { sweep([.puddle], songs: 1...1) }
    func testCalmTier() { sweep([.puddle, .pond], songs: 1...4) }
    func testLivelyTier() { sweep([.lagoon, .ocean], songs: 1...4) }
    func testRoomReadsTheSwayAndTheStepsStillPlant() { sweepTravel() }
    private func sweep(_ ranks: [ShowRank], songs: ClosedRange<Int>) {
        var total = 0
        var fails: [String] = []
        for rank in ranks {
            for song in songs {
                for mode in [Mode.perfect, .random, .none] {
                    for seed in UInt64(1)...(mode == .random ? 3 : 1) {
                        let r = measure(rank: rank, song: song, mode: mode, seed: seed)
                        let s = summary("\(rank) song \(song) \(mode.rawValue) seed \(seed)", r)
                        total += r.crosses.count
                        if !r.crosses.isEmpty { fails.append(s.components(separatedBy: "\n").first ?? s) }
                        XCTAssertGreaterThan(r.plants, 0)
                        if mode == .perfect {
                            XCTAssertGreaterThanOrEqual(Double(r.promptsAnswered80), 0.95 * Double(r.prompts), "\(rank) song \(song): prompts planted within 80 ms")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(total, 0, "feet crossed \(total) times:\n" + fails.prefix(8).joined(separator: "\n"))
    }
}

extension ShowDanceFeetCrossTests {
    /// The dance is not shrunk to nothing: the body still sways clearly side to side in the step-touch bars (mean lateral travel of the root per step), and every move still plants.
    func sweepTravel() {
        let r = measure(rank: .puddle, song: 1, mode: .perfect)
        XCTAssertGreaterThan((r.rootTravel[.stepTouch] ?? [0]).reduce(0, +) / Float(max((r.rootTravel[.stepTouch] ?? [0]).count, 1)), 0.05, "the step-touch's body sway")
        XCTAssertGreaterThanOrEqual(Double(r.plants), Double(r.beats) - 2)
    }
}
