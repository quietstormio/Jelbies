import XCTest
import simd
@testable import BobV1

/// The home room round of 2026-11-15 ("make walking around in the room better ... more interaction ... more Jelmiko sounds ... more emotes ... stop running into
/// each other"): a MEASURING TOOL, not a gate. It soaks the headless room (the SocialTests lab, wired like the stage, every body with `homeRoom` on) under named
/// switch settings ("arms") on the same seeds and appends report lines to a file. It runs only when `ROOMROAM_OUT` is set, so no suite run executes it; run it
/// alone (it moves the shared hub's clock far ahead).
/// Environment (pass each to xcodebuild as TEST_RUNNER_<NAME>):
///   ROOMROAM_OUT       the file the report is appended to (required)
///   ROOMROAM_ARMS      comma list, default "old,new". old = the three switches off, new = all on, traffic / together / voices = only that one on,
///                      notraffic / notogether / novoices = all but that one
///   ROOMROAM_N         comma list of roster sizes (1...3), default "1,3"
///   ROOMROAM_SEEDS     comma list, default "7,31"
///   ROOMROAM_SECONDS   simulated seconds per seed, default 300
///   ROOMROAM_CHARS     comma list of characters for the bodies' features (like SOAK_CHARS in RoomSFXCountTests), default none
///   ROOMROAM_NIGHT     `idleNight` of every body and the hub's `night`, default 0
///   ROOMROAM_WATCHING  0 = nobody watches the room (`brain.watching` false), default 1
///   ROOMROAM_BODY      0 = skip the per-frame feet / arm sampling (faster), default 1
///   ROOMROAM_PICK      SocialTuning.pickChance, default 0.9 (the declared value; the suites lower it to 0.12)
///   ROOMROAM_BUMP / ROOMROAM_NEAR / ROOMROAM_REARM / ROOMROAM_REACH / ROOMROAM_SLOW   see `testMeasureRoom`
@MainActor
final class RoomRoamMeasureTests: XCTestCase {
    override func setUp() { super.setUp(); BlobBrain.pickBudgetSeconds = .infinity; RoomLayout.dynamicBoxes = [] }
    override func tearDown() {
        super.tearDown()
        AudioHub.firedTap = nil; AudioHub.requestSrcTap = nil; AudioHub.requestTap = nil; AudioHub.dropTap = nil; AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() }
        AudioHub.shared.atHome = false
        BlobBrain.pickBudgetSeconds = BlobBrain.defaultPickBudgetSeconds; ContactField.reset()
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    static func env(_ name: String) -> String? { let v = ProcessInfo.processInfo.environment[name] ?? ""; return v.isEmpty ? nil : v }
    static func list(_ name: String, _ fallback: String) -> [String] { (env(name) ?? fallback).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    static func num(_ name: String, _ fallback: Double) -> Double { env(name).flatMap { Double($0) } ?? fallback }
    /// An arm's switches: (traffic, together, voices).
    static func arm(_ name: String) -> (Bool, Bool, Bool)? {
        switch name {
        case "old": return (false, false, false)
        case "new": return (true, true, true)
        case "traffic": return (true, false, false)
        case "together": return (false, true, false)
        case "voices": return (false, false, true)
        case "notraffic": return (false, true, true)
        case "notogether": return (true, false, true)
        case "novoices": return (true, true, false)
        default: return nil
        }
    }

    struct Stats {
        var simSeconds = 0.0          // per body: seeds x seconds
        var legs = 0, dashes = 0, emotes = 0, idleStarts = 0, yields = 0, repicks = 0, bumps = 0, nears = 0, began = 0
        var walkTicks = 0, idleTicks = 0, socialTicks = 0, sleepTicks = 0, restTicks = 0, yieldTicks = 0, slowTicks = 0, touchTicks = 0, reachTicks = 0, pairTicks = 0
        var walkDist: Float = 0, pairDistSum: Float = 0, minApart: Float = .infinity
        var idles: [String: Int] = [:], socials: [String: Int] = [:], ends: [String: Int] = [:]
        var asked: [String: Int] = [:], played: [String: Int] = [:], drops: [String: Int] = [:]
        var closeAfterRoom = 0, minOldAfterRoom = 999.0, minRoomAfterOld = 999.0, minRoomRoom = 999.0
        var feetOverlay: Float = -.infinity, feetPlain: Float = -.infinity, armCap = 0.0, armLed = 0.0, armDepth = 999.0
        var fingerprint: UInt64 = 5381
    }

    func testMeasureRoom() throws {
        guard let out = Self.env("ROOMROAM_OUT") else { throw XCTSkip("a measuring tool: set ROOMROAM_OUT (TEST_RUNNER_ROOMROAM_OUT) to run it") }
        let arms = Self.list("ROOMROAM_ARMS", "old,new")
        let sizes = Self.list("ROOMROAM_N", "1,3").compactMap { Int($0) }.filter { (1...3).contains($0) }
        let seeds = Self.list("ROOMROAM_SEEDS", "7,31").compactMap { UInt64($0) }
        let seconds = Int(Self.num("ROOMROAM_SECONDS", 300))
        let chars = Self.env("ROOMROAM_CHARS").map { $0.split(separator: ",").compactMap { Int($0) } }
        let night = Float(Self.num("ROOMROAM_NIGHT", 0)), watching = Self.num("ROOMROAM_WATCHING", 1) != 0, body = Self.num("ROOMROAM_BODY", 1) != 0
        // Centre distances (the bodies' wall is `MelonController.jellyGap` = 1.4): a pair that is not in a session together, with at least one of them walking, coming
        // from `rearm` or more apart: below `near` = a near miss, below `bump` = they ran into each other. `reach` = close enough to start something together.
        let bump = Float(Self.num("ROOMROAM_BUMP", 1.19)), near = Float(Self.num("ROOMROAM_NEAR", 1.36)), rearm = Float(Self.num("ROOMROAM_REARM", 1.4)), reach = Float(Self.num("ROOMROAM_REACH", 4.8))
        let slow = Float(Self.num("ROOMROAM_SLOW", 0.36))          // u/s: a walking body slower than this is held up (a room walk is about 1.44)
        let oldPick = SocialTuning.pickChance, oldSwitches = (RoomRoam.traffic, RoomRoam.together, RoomRoam.voices)
        SocialTuning.pickChance = Float(Self.num("ROOMROAM_PICK", 0.9))
        defer { SocialTuning.pickChance = oldPick; (RoomRoam.traffic, RoomRoam.together, RoomRoam.voices) = oldSwitches }

        let hub = AudioHub.shared
        hub._openForTest(); AudioHub.dryRun = true
        var simNow = 3_000_000.0; AudioHub.clock = { simNow }
        let cueSink = RecordingHapticSink(), cueDriver = HapticDriver(sinks: [cueSink])          // (HapticDriver.room is weak: the local keeps the driver alive)
        HapticDriver.room = cueDriver; HapticDriver.roomBusy = nil; HapticDriver.jitter = { 1 }
        HapticDriver.clock = { simNow }; HapticDriver.after = { _, f in f() }
        defer { HapticDriver.room = nil; HapticDriver.clock = { CACurrentMediaTime() }; HapticDriver.after = { d, f in DispatchQueue.main.asyncAfter(deadline: .now() + d) { MainActor.assumeIsolated { f() } } }; HapticDriver.jitter = { 1 + Float.random(in: -0.15...0.15) }; withExtendedLifetime(cueDriver) {} }

        var lines: [String] = []
        for armName in arms {
            guard let a = Self.arm(armName) else { XCTFail("unknown arm \(armName)"); continue }
            for n in sizes {
                (RoomRoam.traffic, RoomRoam.together, RoomRoam.voices) = a
                RoomRoam.ran = [0, 0, 0]
                GameCamera.configureRoom(count: n); _ = GameCamera.camera(aspect: 440.0 / 956.0)          // (the game's own call for n at home: MelonStage.swift)
                var s = Stats()
                for seed in seeds {
                    let lab = SocialTests.Lab(n: n, quiet: false, seed: seed)
                    for (i, r) in lab.rigs.enumerated() {
                        r.brain.anticsEnabled = true; r.brain.sleepEnabled = true; r.brain.idleMood = .happy; r.brain.restTimer = 0.5 + Float(i)
                        r.brain.homeRoom = true; r.brain.watching = watching; r.brain.idleNight = night
                        if let c = chars, i < c.count { r.brain.feature = JellyRoster.feature(c[i]) }
                    }
                    var wasWalking = [Bool](repeating: false, count: n), wasYield = [Bool](repeating: false, count: n), lastKind = [IdleKind?](repeating: nil, count: n)
                    var lastPos = lab.rigs.map { GameCare.floorPos($0.brain, $0.sim) }, lastRepick = lab.rigs.map { $0.brain.stuckRepicks }
                    var armed = [Bool](repeating: false, count: n * n), nearSeen = [Bool](repeating: false, count: n * n)
                    // voices: every request with the guard that dropped it (nil = PLAYED). A context voice asked from inside `situation` is the silence filler.
                    var oldAt: [[Double]] = [[], [], []], roomAt: [[Double]] = [[], [], []]
                    var lastStamp = (0..<3).map { simNow - hub.secondsSinceVoice(slot: $0) }
                    var pendingSlot = -1, inSituation = false
                    AudioHub.requestSrcTap = { _, slot in pendingSlot = slot }
                    AudioHub.dropTap = { what, why in
                        guard what.hasPrefix("chirp") || what.hasPrefix("babble") || what.hasPrefix("voice:") || what.hasPrefix("room:") else { return }
                        var key = what
                        if inSituation, what.hasPrefix("voice:"), !what.contains("@") { key += "@ambient" }
                        s.asked[key, default: 0] += 1
                        if let why { s.drops["\(key)|\(why)", default: 0] += 1; return }
                        s.played[key, default: 0] += 1
                        if what.hasPrefix("room:"), (0..<3).contains(pendingSlot) { roomAt[pendingSlot].append(simNow) }
                    }
                    for t in 0..<(seconds * 60) {
                        lab.tick(watching: body)
                        let pos = lab.rigs.map { GameCare.floorPos($0.brain, $0.sim) }          // (the body centres the stage's wall uses)
                        for (i, r) in lab.rigs.enumerated() {
                            let b = r.brain
                            let walking = b.activity == .walking || b.activity == .coming, social = b.isSocial
                            if walking, !wasWalking[i], !social { s.legs += 1 }
                            wasWalking[i] = walking
                            let k = b.idleState.kind
                            if k != lastKind[i] {
                                if let k {
                                    s.idleStarts += 1; s.idles["\(k)", default: 0] += 1
                                    if BlobBrain.emoteKinds.contains(k) { s.emotes += 1 }
                                    if k == .run || k == .zoomies { s.dashes += 1 }
                                }
                                lastKind[i] = k
                            }
                            let y = b.idleState.yielding
                            if y, !wasYield[i] { s.yields += 1 }
                            wasYield[i] = y
                            if y { s.yieldTicks += 1 }
                            let moved = simd_distance(pos[i], lastPos[i])
                            if social { s.socialTicks += 1 } else if k == .sleep { s.sleepTicks += 1 } else if walking { s.walkTicks += 1; s.walkDist += moved; if moved * 60 < slow { s.slowTicks += 1 } } else if k != nil { s.idleTicks += 1 } else { s.restTicks += 1 }
                            let rp = b.stuckRepicks
                            if rp > lastRepick[i] { s.repicks += rp - lastRepick[i] }
                            lastRepick[i] = rp
                        }
                        lastPos = pos
                        for i in 0..<n { for j in (i + 1)..<n {
                            let d = simd_distance(pos[i], pos[j]), p = i * n + j
                            let bi = lab.rigs[i].brain, bj = lab.rigs[j].brain
                            s.pairTicks += 1; s.pairDistSum += d
                            if d < reach { s.reachTicks += 1 }
                            if bi.social != nil, bi.social === bj.social { armed[p] = false; nearSeen[p] = false; continue }          // (together on purpose)
                            let moving = wasWalking[i] || wasWalking[j]
                            if d >= rearm { armed[p] = true; nearSeen[p] = false }
                            if moving { s.minApart = min(s.minApart, d); if d < near { s.touchTicks += 1 } }
                            if armed[p], moving, d < near, !nearSeen[p] { s.nears += 1; nearSeen[p] = true }
                            if armed[p], moving, d < bump { s.bumps += 1; armed[p] = false }
                        } }
                        simNow += 1.0 / 60
                        if t % 6 == 0 {          // (the stage feeds the hub at 10 Hz)
                            inSituation = true
                            hub.situation(napping: lab.rigs.map { $0.brain.isNapping }, playing: false, xs: lab.rigs.map { $0.brain.px }, moods: lab.rigs.map { _ in .happy }, home: true,
                                          ambient: lab.rigs.map { $0.brain.ambientVoiceOK }, walking: lab.rigs.map { $0.brain.activity == .walking || $0.brain.activity == .coming }, night: Double(night))
                            inSituation = false
                        }
                        for i in 0..<3 {          // (an old voice of this slot played: its stamp on the hub's three old clocks moved)
                            let stamp = simNow - hub.secondsSinceVoice(slot: i)
                            if stamp > lastStamp[i] + 1e-9 { if i < n { oldAt[i].append(stamp) }; lastStamp[i] = stamp }
                        }
                    }
                    AudioHub.dropTap = nil; AudioHub.requestSrcTap = nil
                    for i in 0..<3 {
                        for r in roomAt[i] { for o in oldAt[i] {
                            let g = o - r
                            if g >= 0 { s.minOldAfterRoom = min(s.minOldAfterRoom, g); if g < 0.8 { s.closeAfterRoom += 1 } } else { s.minRoomAfterOld = min(s.minRoomAfterOld, -g) }
                        } }
                        for (x, y) in zip(roomAt[i], roomAt[i].dropFirst()) { s.minRoomRoom = min(s.minRoomRoom, y - x) }
                    }
                    for evs in lab.events { for ev in evs {
                        switch ev {
                        case .began(let k, _): s.began += 1; s.socials["\(k)", default: 0] += 1
                        case .ended(_, _, let e): s.ends["\(e)", default: 0] += 1
                        case .boop: s.socials["boopEvent", default: 0] += 1
                        case .shove: s.socials["shoveEvent", default: 0] += 1
                        default: break
                        }
                    } }
                    if body { for w in lab.watch {
                        s.feetOverlay = max(s.feetOverlay, w.feet.overlap); s.feetPlain = max(s.feetPlain, w.plain.overlap)
                        s.armCap = max(s.armCap, Double(w.arm.capMax)); s.armLed = max(s.armLed, Double(w.arm.ledMax)); if w.arm.frames > 0 { s.armDepth = min(s.armDepth, Double(w.arm.minDepth)) }
                    } }
                    for r in lab.rigs { let q = GameCare.floorPos(r.brain, r.sim); for v in [q.x, q.y] { s.fingerprint = (s.fingerprint &* 33) ^ UInt64(bitPattern: Int64((v * 100).rounded())) } }
                    s.simSeconds += Double(seconds)
                    simNow += 120          // (the gaps of the previous run are over)
                }
                // the report: counts are sums over the seeds and the bodies; /min = per body per simulated minute
                let bodyMin = Double(n) * s.simSeconds / 60
                let allTicks = Double(max(1, s.walkTicks + s.idleTicks + s.socialTicks + s.sleepTicks + s.restTicks))
                let per: (Int) -> String = { String(format: "%.2f", Double($0) / max(bodyMin, 0.001)) }
                let share: (Int) -> String = { String(format: "%.3f", Double($0) / allTicks) }
                let fam: (String) -> Int = { p in s.played.filter { $0.key.hasPrefix(p) }.values.reduce(0, +) }
                // (the filler speaks as a chirp `chirp:<v>@ambient` or, for a context voice, `voice:<v>` asked inside `situation`, tagged `@ambient` above: each family is counted once;
                // `context` includes the sleep murmurs `voice:<v>@sleep`)
                let ambientOf: (String) -> Int = { p in s.played.filter { $0.key.hasPrefix(p) && $0.key.hasSuffix("@ambient") }.values.reduce(0, +) }
                let fillerChirp = ambientOf("chirp") + ambientOf("babble"), fillerContext = ambientOf("voice:")
                let filler = fillerChirp + fillerContext
                let chirps = fam("chirp") + fam("babble") - fillerChirp, context = fam("voice:") - fillerContext, room = fam("room:")
                let voices = chirps + context + filler + room
                let tag = "arm=\(armName) n=\(n)"
                var head = "ROOMROAM \(tag) seeds=\(seeds.count) sec=\(seconds) bodyMin=\(String(format: "%.1f", bodyMin))"
                head += " legs=\(s.legs) legs/min=\(per(s.legs)) dashes=\(s.dashes) idles=\(s.idleStarts) idles/min=\(per(s.idleStarts)) emotes=\(s.emotes) emotes/min=\(per(s.emotes))"
                head += " began=\(s.began) began/min=\(per(s.began))"
                head += " bumps=\(s.bumps) nears=\(s.nears) touchSec=\(String(format: "%.1f", Double(s.touchTicks) / 60)) minApart=\(String(format: "%.3f", s.minApart))"
                head += " yields=\(s.yields) yieldSec=\(String(format: "%.1f", Double(s.yieldTicks) / 60)) slowSec=\(String(format: "%.1f", Double(s.slowTicks) / 60)) repicks=\(s.repicks)"
                head += " legSpeed=\(String(format: "%.3f", s.walkTicks > 0 ? Double(s.walkDist) / (Double(s.walkTicks) / 60) : 0))"
                head += " share walk=\(share(s.walkTicks)) idle=\(share(s.idleTicks)) social=\(share(s.socialTicks)) sleep=\(share(s.sleepTicks)) rest=\(share(s.restTicks))"
                head += " pairDist=\(String(format: "%.2f", s.pairTicks > 0 ? Double(s.pairDistSum) / Double(s.pairTicks) : 0)) inReach=\(String(format: "%.3f", s.pairTicks > 0 ? Double(s.reachTicks) / Double(s.pairTicks) : 0))"
                head += " voices=\(voices) voices/min=\(per(voices)) chirps=\(chirps) context=\(context) filler=\(filler) room=\(room)"
                head += " closeAfterRoom=\(s.closeAfterRoom) minOldAfterRoom=\(String(format: "%.2f", s.minOldAfterRoom)) minRoomAfterOld=\(String(format: "%.2f", s.minRoomAfterOld)) minRoomRoom=\(String(format: "%.2f", s.minRoomRoom))"
                head += " ran=\(RoomRoam.ran[0])/\(RoomRoam.ran[1])/\(RoomRoam.ran[2]) fp=\(String(s.fingerprint, radix: 16))"
                lines.append(head)
                lines.append("ROOMROAM-IDLE \(tag) " + s.idles.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                lines.append("ROOMROAM-SOCIAL \(tag) " + s.socials.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ") + " | ends " + s.ends.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                lines.append("ROOMROAM-VOICE \(tag) " + s.asked.sorted { $0.key < $1.key }.map { "\($0.key)=\(s.played[$0.key, default: 0])/\($0.value)" }.joined(separator: " "))
                lines.append("ROOMROAM-DROP \(tag) " + s.drops.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                if body { lines.append("ROOMROAM-BODY \(tag) " + String(format: "feetOverlay=%.4f feetPlain=%.4f (limit %.4f) armCap=%.4f (limit %.4f) armLed=%.4f (rest nub %.4f) armDepth=%.3f", s.feetOverlay, s.feetPlain, FeetAttachTests.minOverlap, s.armCap, Double(ArmCap.maximum), s.armLed, Double(ArmCap.restNub), s.armDepth)) }
            }
        }
        let text = lines.joined(separator: "\n") + "\n"
        print(text)
        if let h = FileHandle(forWritingAtPath: out) { h.seekToEndOfFile(); h.write(Data(text.utf8)); h.closeFile() } else { try text.write(toFile: out, atomically: true, encoding: .utf8) }
    }
}
