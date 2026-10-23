//
//  LivelinessMinuteTests.swift
//  "Watching for 60 s shows many different things; no same-moment repeats" (W2, 2026-10-22). The 3-Jelly room as the stage runs it (antics, a watching player, toys),
//  60 s per seed, a per-half-second activity log written to scratchpad/w2/activity_60s_<mood>_<seed>.txt (env W2_OUT overrides the folder).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class LivelinessMinuteTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12 }
    override func tearDown() { BlobBrain.cartwheelTravels = [0.8, 0.6, 0.45]; RoomLayout.dynamicBoxes = []; DecorField.shared.clear(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    static let outDir = ProcessInfo.processInfo.environment["W2_OUT"] ?? "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/w2"
    static let dashes: Set<String> = ["idle:run", "idle:zoomies", "idle:slide", "idle:trot", "idle:cartwheel", "social:chase", "social:zoomies"]

    func minute(mood: BlobMood, seed: UInt64, maxPlain: Float) {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        LivelyLabTests.placeToys()
        let lab = SocialTests.Lab(quiet: false, seed: seed)
        for (i, r) in lab.rigs.enumerated() {
            let b = r.brain
            b.idleMood = mood; b.socialBook.cooldown = 8; b.idleState.cooldown = 9; b.restTimer = 0.5 + Float(i)
            b.anticsEnabled = true; b.watching = true; b.sleepEnabled = true
        }
        BlobBrain.cartwheelStats = (0, 0, 0, 0, 0)
        BlobBrain.cartwheelTravels = ProcessInfo.processInfo.environment["W2_CW_SINGLE"] != nil ? [0.8] : [0.8, 0.6, 0.45]          // (the env var reproduces the single-travel baseline)
        var labels = [[String]](repeating: [], count: 3)
        var distinct = [Set<String>](repeating: [], count: 3)
        var plain = 0, total = 0
        var starts: [(t: Float, j: Int, k: IdleKind)] = []
        var prevKind = [IdleKind?](repeating: nil, count: 3)
        var picks = [[IdleKind]](repeating: [], count: 3)
        var ownRepeats: [String] = []
        var dashStarts = 0, socials = 0
        var prevLabel = [String](repeating: "", count: 3)
        for f in 0..<(60 * 60) {
            lab.tick(watching: false)
            let t = Float(f) / 60
            for (i, r) in lab.rigs.enumerated() {
                let b = r.brain
                let l = LivelyLabTests.label(b) ?? (b.activity == .walking ? "walking" : "standing")
                if f % 30 == 0 { labels[i].append(l) }
                distinct[i].insert(l)
                if LivelyLabTests.isPlain(b) { plain += 1 }
                total += 1
                if l != prevLabel[i] {
                    if Self.dashes.contains(l) { dashStarts += 1 }
                    if l.hasPrefix("social:") && !prevLabel[i].hasPrefix("social:") { socials += 1 }
                    prevLabel[i] = l
                }
                let k = b.idleState.kind
                if k != prevKind[i], let k {
                    if b.social == nil, k != .wander, k != .look {
                        starts.append((t, i, k))
                        if !BlobBrain.flourishKinds.contains(k), k != .sleep, k != .hmph, k != .stumble, !BlobBrain.decorKinds.contains(k) {
                            if picks[i].suffix(3).contains(k) { ownRepeats.append("t \(t) jelly \(i) \(k) in \(picks[i].suffix(3))") }
                            picks[i].append(k)
                        }
                    }
                }
                prevKind[i] = k
            }
        }
        // the log
        var out = "# 60 s \(mood.rawValue) seed \(seed): one row per 0.5 s, columns = Jelly 0 | 1 | 2\n"
        for n in 0..<labels[0].count { out += String(format: "%5.1f  ", Float(n) * 0.5) + (0..<3).map { labels[$0][n].padding(toLength: 22, withPad: " ", startingAt: 0) }.joined(separator: " ") + "\n" }
        let cw = BlobBrain.cartwheelStats
        out += "\nCARTWHEEL tried \(cw.tried) started \(cw.started) refused: floor \(cw.floor) leg \(cw.leg) peer \(cw.peer)\n"
        out += "\nSUMMARY plain share \(Float(plain) / Float(total)) dash starts \(dashStarts) socials \(socials)\n"
        for i in 0..<3 { out += "Jelly \(i): \(distinct[i].count) distinct: \(distinct[i].sorted().joined(separator: ", "))\n" }
        try? FileManager.default.createDirectory(atPath: Self.outDir, withIntermediateDirectories: true)
        try? out.write(toFile: "\(Self.outDir)/activity_60s_\(mood.rawValue)_\(seed).txt", atomically: true, encoding: .utf8)
        MotionLog.write("LIVELY60 \(mood.rawValue) \(seed): plain \(Float(plain) / Float(total)) dashes \(dashStarts) socials \(socials) distinct \(distinct.map(\.count)) union \(distinct.reduce(into: Set<String>()) { $0.formUnion($1) }.count)")

        for i in 0..<3 { XCTAssertGreaterThanOrEqual(distinct[i].count, 6, "Jelly \(i) shows at least 6 different things: \(distinct[i].sorted())") }
        let union = distinct.reduce(into: Set<String>()) { $0.formUnion($1) }
        XCTAssertGreaterThanOrEqual(union.count, 14, "the room shows at least 14 different things: \(union.sorted())")
        XCTAssertTrue(union.contains("idle:cartwheel"), "the cartwheel shows in a minute (tried \(BlobBrain.cartwheelStats)): \(union.sorted())")
        XCTAssertGreaterThanOrEqual(dashStarts, 3, "at least 3 dashes in the room")
        XCTAssertGreaterThanOrEqual(socials, 1, "at least one social")
        XCTAssertLessThan(Float(plain) / Float(total), maxPlain, "plain walking / standing share")
        // (a startle is a REACTION to a friend's jump a moment before, by design: not a copycat pick)
        // no two Jellies start the same move (or its family) within 2 s of each other
        var repeats: [String] = []
        for a in starts { for b in starts where b.j != a.j && b.k != .startle && b.t > a.t && b.t - a.t < 2 && BlobBrain.family(a.k).contains(b.k) { repeats.append("t \(a.t) j\(a.j) \(a.k) / t \(b.t) j\(b.j) \(b.k)") } }
        XCTAssertTrue(repeats.isEmpty, "same-moment repeats: \(repeats)")
        XCTAssertTrue(ownRepeats.isEmpty, "a Jelly repeats one of his own last three picks: \(ownRepeats)")
    }

    func testOkaySeed101() { minute(mood: .okay, seed: 101, maxPlain: 0.40) }
    func testOkaySeed202() { minute(mood: .okay, seed: 202, maxPlain: 0.40) }
    func testHappySeed303() { minute(mood: .happy, seed: 303, maxPlain: 0.50) }          // (happy wanders long legs: 0.47 measured; the okay seeds hold 0.40)
}
