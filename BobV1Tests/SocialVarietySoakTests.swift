import XCTest
import simd
@testable import BobV1

/// 2026-11-06 user: "They're still doing this emote too often. Do different interactive ones ... the back to back ones and hopping ones". A headless soak of the
/// Teddy + Panda pair at home (day and night): what the REAL scheduler starts (`.began` per kind) and how long each kind holds the pair (time share), plus which kinds
/// put a hand on the partner. Regression gate for the variety targets. SOAK_MIN (default 30) and SOAK_SEEDS (default 3) size the run.
@MainActor
final class SocialVarietySoakTests: XCTestCase {
    override func setUp() { super.setUp(); BlobBrain.pickBudgetSeconds = .infinity; RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.9 }
    override func tearDown() { super.tearDown(); BlobBrain.pickBudgetSeconds = BlobBrain.defaultPickBudgetSeconds; ContactField.reset(); RoomLayout.dynamicBoxes = [] }

    static let handKinds: Set<SocialKind> = [.boop, .cheekSquish, .whisperGiggle, .highFive]
    static let livelyKinds: Set<SocialKind> = [.backToBack, .hopAlong, .leapfrog, .bellyBounce, .chestBump, .bump, .dance, .mirrorDance, .danceOff, .twirl, .tag, .littleRace]

    struct Result {
        var starts: [SocialKind: Int] = [:]
        var secs: [SocialKind: Double] = [:]
        var handSecs: [String: Double] = [:]          // caller (social kind, or "nonSocial:<idle>") -> seconds some hand override sat on the partner
        var armSecs: [String: Double] = [:]           // any arm override (armDirW > 0.5) while in a social, by kind
        var picks: [SocialKind: Int] = [:]          // what the roll picked (lastKind changes), including picks the start then refused
        var simSeconds: Double = 0
        var seqRepeatsNext = 0, seqRepeats3 = 0, seqPairs = 0
        mutating func add(_ o: Result) {
            for (k, v) in o.starts { starts[k, default: 0] += v }; for (k, v) in o.picks { picks[k, default: 0] += v }; for (k, v) in o.secs { secs[k, default: 0] += v }
            for (k, v) in o.handSecs { handSecs[k, default: 0] += v }; for (k, v) in o.armSecs { armSecs[k, default: 0] += v }
            simSeconds += o.simSeconds; seqRepeatsNext += o.seqRepeatsNext; seqRepeats3 += o.seqRepeats3; seqPairs += o.seqPairs
        }
        var socialStarts: Int { starts.filter { $0.key != .look }.values.reduce(0, +) }
        var socialSecs: Double { secs.filter { $0.key != .look }.values.reduce(0, +) }
    }

    func run(night: Bool, seed: UInt64, minutes: Double, chars: [Int]) -> Result {
        SocialTests.keep.removeAll()
        let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-1.0, 0.6), SIMD2(1.0, 0.6)], quiet: false, seed: seed)
        for (i, r) in lab.rigs.enumerated() {
            let b = r.brain
            b.anticsEnabled = true; b.sleepEnabled = false; b.idleMood = .happy; b.restTimer = 0.5 + Float(i); b.watching = true
            b.feature = JellyRoster.feature(chars[i])
            b.idleNight = night ? 1 : 0; b.idleDeepNight = 0; b.idleMorning = 0
        }
        var res = Result()
        var kinds: [SocialKind] = []
        let a = lab.rigs[0].brain, bb = lab.rigs[1].brain
        var seen = 0
        var lastA: SocialKind?, lastB: SocialKind?
        let ticks = Int(minutes * 60 * 60)
        for _ in 0..<ticks {
            lab.tick()
            res.simSeconds += 1.0 / 60
            if lab.events[0].count > seen {
                for ev in lab.events[0][seen...] { if case .began(let k, _) = ev, k != .look { res.starts[k, default: 0] += 1; kinds.append(k) } else if case .began(let k, _) = ev { res.starts[k, default: 0] += 1 } }
                seen = lab.events[0].count
            }
            if a.socialBook.lastKind != lastA { lastA = a.socialBook.lastKind; if let k = lastA { res.picks[k, default: 0] += 1 } }
            if bb.socialBook.lastKind != lastB { lastB = bb.socialBook.lastKind; if let k = lastB { res.picks[k, default: 0] += 1 } }
            let k = a.socialKind ?? bb.socialKind
            if let k { res.secs[k, default: 0] += 1.0 / 60 }
            for b in [a, bb] {
                if b.socialBook.handW > 0.3 { res.handSecs[b.socialKind.map { $0.rawValue } ?? "nonSocial:\(b.idleState.kind.map { "\($0)" } ?? "none")", default: 0] += 0.5 / 60 }          // (per pair: two bodies, count half each)
                if b.armDirW > 0.5, let sk = b.socialKind { res.armSecs[sk.rawValue, default: 0] += 0.5 / 60 }
            }
            if lab.events[0].count > 4000 { lab.events[0].removeFirst(2000); seen -= 2000 }
        }
        for (i, k) in kinds.enumerated() where i > 0 {
            res.seqPairs += 1
            if kinds[i - 1] == k { res.seqRepeatsNext += 1 }
            if kinds[max(0, i - 3)..<i].contains(k) { res.seqRepeats3 += 1 }
        }
        return res
    }

    func table(_ title: String, _ r: Result) -> String {
        let ss = Double(max(r.socialStarts, 1)), st = max(r.socialSecs, 1e-6)
        var lines = ["SOAKTABLE \(title): sim-min \(String(format: "%.0f", r.simSeconds / 60)) social starts \(r.socialStarts) (\(String(format: "%.2f", Double(r.socialStarts) / (r.simSeconds / 60))) per pair-min) social time \(String(format: "%.0f", r.socialSecs)) s; repeat-next \(r.seqRepeatsNext)/\(r.seqPairs), repeat-within-3 \(r.seqRepeats3)/\(r.seqPairs)"]
        for k in Set(r.starts.keys).union(r.secs.keys).sorted(by: { (r.starts[$0] ?? 0) > (r.starts[$1] ?? 0) }) where k != .look {
            lines.append(String(format: "  %-13@ picked %4d starts %4d %5.1f%%   time %7.0f s %5.1f%%   %@", k.rawValue as NSString, r.picks[k] ?? 0, r.starts[k] ?? 0, 100 * Double(r.starts[k] ?? 0) / ss, r.secs[k] ?? 0, 100 * (r.secs[k] ?? 0) / st, Self.handKinds.contains(k) ? "[hand]" : (Self.livelyKinds.contains(k) ? "[lively]" : "")))
        }
        let hs = Self.handKinds.reduce(0) { $0 + (r.starts[$1] ?? 0) }, ht = Self.handKinds.reduce(0.0) { $0 + (r.secs[$1] ?? 0) }
        let ls = Self.livelyKinds.reduce(0) { $0 + (r.starts[$1] ?? 0) }, lt = Self.livelyKinds.reduce(0.0) { $0 + (r.secs[$1] ?? 0) }
        lines.append(String(format: "  HAND kinds combined: starts %.1f%% time %.1f%%;  LIVELY kinds combined: starts %.1f%% time %.1f%%", 100 * Double(hs) / ss, 100 * ht / st, 100 * Double(ls) / ss, 100 * lt / st))
        lines.append("  hand-on-partner seconds by caller: " + r.handSecs.sorted { $0.value > $1.value }.map { "\($0.key)=\(String(format: "%.0f", $0.value))" }.joined(separator: " "))
        lines.append("  arm override (armDirW>0.5) in a social, seconds by kind: " + r.armSecs.sorted { $0.value > $1.value }.map { "\($0.key)=\(String(format: "%.0f", $0.value))" }.joined(separator: " "))
        lines.append("  look sessions (idle path): \(r.starts[.look] ?? 0)")
        return lines.joined(separator: "\n")
    }

    func testTeddyPandaVarietyDayAndNight() {
        let env = ProcessInfo.processInfo.environment
        let minutes = Double(env["SOAK_MIN"] ?? "") ?? 30, nSeeds = Int(env["SOAK_SEEDS"] ?? "") ?? 3
        let chars = [JellyRoster.teddyID, JellyRoster.pandaID]
        var out: [String] = []
        for night in [false, true] {
            var tot = Result()
            for s in 0..<nSeeds { tot.add(run(night: night, seed: UInt64(101 + 17 * s), minutes: minutes, chars: chars)) }
            let t = table(night ? "NIGHT" : "DAY", tot)
            print(t); MotionLog.write(t); out.append(t)
            let ss = Double(max(tot.socialStarts, 1)), st = max(tot.socialSecs, 1e-6)
            let hs = Self.handKinds.reduce(0) { $0 + (tot.starts[$1] ?? 0) }, ht = Self.handKinds.reduce(0.0) { $0 + (tot.secs[$1] ?? 0) }
            let ls = Self.livelyKinds.reduce(0) { $0 + (tot.starts[$1] ?? 0) }
            let tag = night ? "night" : "day"
            XCTAssertLessThanOrEqual(Double(hs) / ss, 0.08, "\(tag): hand-on-partner kinds <= 8% of social starts")
            XCTAssertLessThanOrEqual(ht / st, 0.08, "\(tag): hand-on-partner kinds <= 8% of social time")
            for (k, n) in tot.starts where k != .look { XCTAssertLessThanOrEqual(Double(n) / ss, 0.12, "\(tag): \(k) <= 12% of starts") }
            XCTAssertGreaterThanOrEqual(Double(ls) / ss, night ? 0.20 : 0.35, "\(tag): the lively kinds are clearly common")
            XCTAssertGreaterThan(tot.starts[.backToBack] ?? 0, 0, "\(tag): back to back happens"); XCTAssertGreaterThan(tot.starts[.hopAlong] ?? 0, 0, "\(tag): hop along happens")
            XCTAssertEqual(tot.seqRepeatsNext, 0, "\(tag): a pair never repeats the kind it just did")
            XCTAssertLessThanOrEqual(Double(tot.seqRepeats3) / Double(max(tot.seqPairs, 1)), 0.05, "\(tag): rarely within the last 3")
            XCTAssertNil(SocialKind(rawValue: "noseBoop"))
        }
    }
}
