//
//  ToyAuditTests.swift (toy-audit-r1)
//  The numbers of the toy audit, headless: for each shop toy placed alone (the Shop's own first free spot) with three Jelmiko at home, 3 seeds x N seconds:
//  seconds to the first use, uses per 10 minutes, how long a use lasts, whether every use ENDS, the closest two bodies came while one used it, queue counts.
//  Slow: runs only with TOYAUDIT=1 (TEST_RUNNER_TOYAUDIT=1); TOYAUDIT_SECONDS (default 300), TOYAUDIT_OUT (output file), TOYAUDIT_MIX=1 for the mixed-room take instead.
//
import XCTest
import simd
@testable import BobV1

@MainActor
final class ToyAuditTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    override func tearDown() { DecorField.shared.clear(); ToyTuning.settle = 5; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    static let shopToys: [DecorKind] = StoreCatalog.items.compactMap { $0.decor }.filter { $0.category == .toys && $0.activeInteraction != nil }
    static let mixToys: [DecorKind] = [.drum, .blocks, .spintop, .bouncymat, .hoop, .plushbear]

    struct Result { var first: Float = -1; var uses = 0; var dur: [Float] = []; var stuck = 0; var minGap: Float = .infinity; var crowd = 0; var queued = 0; var tookTurn = 0; var gaveUp = 0; var perKind: [String: Int] = [:]
        var walkF = 0, standF = 0, soloF = 0, pairF = 0, groupF = 0, frames = 0, otherIdle: [String: Int] = [:], starts: [String: Int] = [:], shared = 0, minShareGap: Float = .infinity, minTag = "" }

    func run(kinds: [DecorKind], seconds: Float, seed: UInt64) -> Result {
        let starts: [SIMD2<Float>] = [SIMD2(-1.8, 1.4), SIMD2(-0.2, 1.8), SIMD2(1.4, 1.2)]
        let lab = SocialTests.Lab(n: 3, positions: starts, quiet: false, seed: seed)
        Self.keep.append(contentsOf: lab.rigs)
        let mood = BlobMood(rawValue: ProcessInfo.processInfo.environment["TOYAUDIT_MOOD"] ?? "happy") ?? .happy
        for r in lab.rigs { r.brain.anticsEnabled = true; r.brain.sleepEnabled = true; r.brain.idleMood = mood }
        var placed: [PlacedDecor] = []
        for (i, k) in kinds.enumerated() {
            if let at = DecorPlacement.findSpot(k, among: placed) { placed.append(PlacedDecor(uid: i + 1, kind: k, x: at.x, z: at.y)) }
        }
        DecorField.shared.set(placed); DecorField.shared.toys = ToyBook()
        var res = Result()
        var curUID = [Int](repeating: -1, count: 3), startT = [Float](repeating: 0, count: 3), prevKind = [IdleKind?](repeating: nil, count: 3)
        let frames = Int(seconds * 60)
        for f in 0..<frames {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            let t = Float(f) / 60
            for (i, r) in lab.rigs.enumerated() {
                let b = r.brain
                let uid = (b.idleState.kind.map { BlobBrain.decorKinds.contains($0) } ?? false) ? b.idleState.decorUID : -1
                if uid >= 0, curUID[i] < 0, let ft = DecorField.shared.foot(uid) {
                    res.uses += 1; res.perKind[ft.kind.rawValue, default: 0] += 1; startT[i] = t
                    if res.first < 0 { res.first = t }
                }
                if uid < 0, curUID[i] >= 0 { res.dur.append(t - startT[i]) }
                if uid >= 0, t - startT[i] > 60 { res.stuck += 1; startT[i] = t + 1e6 }
                curUID[i] = uid
                if b.idleState.kind != prevKind[i], let k = b.idleState.kind { res.starts["\(k)", default: 0] += 1 }
                prevKind[i] = b.idleState.kind
                res.frames += 1
                if b.activity == .walking || b.activity == .coming { res.walkF += 1 } else if b.idleState.kind == nil && b.social == nil { res.standF += 1 }
                if b.social != nil { res.pairF += 1 } else if let k = b.idleState.kind, !BlobBrain.decorKinds.contains(k) { res.soloF += 1; res.otherIdle["\(k)", default: 0] += 1 }
            }
            if f % 6 == 0 {
                for i in 0..<3 { for j in (i + 1)..<3 {
                    let paired = lab.rigs[i].brain.social != nil && lab.rigs[i].brain.social === lab.rigs[j].brain.social
                    if paired { continue }
                    let g = lab.centreGap(i, j)
                    if g < res.minGap { res.minGap = g; let bi = lab.rigs[i].brain, bj = lab.rigs[j].brain; res.minTag = "t\(Int(t)) \(i):\(bi.idleState.kind.map { "\($0)" } ?? "-")/aud\(bi.toy.audUID)s\(bi.toy.audStage)/wait\(bi.toy.waitUID)/\(bi.activity) vs \(j):\(bj.idleState.kind.map { "\($0)" } ?? "-")/aud\(bj.toy.audUID)s\(bj.toy.audStage)/wait\(bj.toy.waitUID)/\(bj.activity)" }
                    let usingI = curUID[i] >= 0, usingJ = curUID[j] >= 0
                    if (usingI || usingJ) && g < 1.2 { res.crowd += 1 }
                } }
            }
        }
        for r in lab.rigs { res.shared += r.brain.toy.joined; res.queued += r.brain.toy.queued; res.tookTurn += r.brain.toy.tookTurn; res.gaveUp += r.brain.toy.gaveUp }
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        return res
    }

    func testToyAudit() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["TOYAUDIT"] != nil, "slow: set TEST_RUNNER_TOYAUDIT=1")
        let secs = Float(env["TOYAUDIT_SECONDS"] ?? "") ?? 300
        BlobBrain.audienceOn = env["TOYAUDIENCE"] != "0"; ToyTuning.grumpyPlay = env["TOYGRUMPY"] != "0"
        defer { BlobBrain.audienceOn = true; ToyTuning.grumpyPlay = true }
        let out = env["TOYAUDIT_OUT"] ?? "/tmp/toyaudit_out.txt"
        var lines: [String] = ["toys in the shop: \(Self.shopToys.count): \(Self.shopToys.map { $0.rawValue }.joined(separator: ","))", "seconds per seed: \(secs), seeds 3"]
        if env["TOYAUDIT_MIX"] != nil {
            var tot = Result(); var firsts: [Float] = []
            for seed in (0..<(Int(env["TOYAUDIT_SEEDS"] ?? "") ?? 3)).map({ UInt64([3, 5, 9, 13, 17, 21, 25, 29][$0 % 8]) }) {
                let r = run(kinds: Self.mixToys, seconds: secs, seed: seed)
                tot.uses += r.uses; tot.stuck += r.stuck; tot.crowd += r.crowd; tot.queued += r.queued; tot.tookTurn += r.tookTurn; tot.gaveUp += r.gaveUp
                tot.walkF += r.walkF; tot.standF += r.standF; tot.soloF += r.soloF; tot.pairF += r.pairF; tot.frames += r.frames; if r.minGap < tot.minGap { tot.minGap = r.minGap; tot.minTag = r.minTag }; tot.shared += r.shared; for (k, v) in r.starts { tot.starts[k, default: 0] += v }
                for (k, v) in r.perKind { tot.perKind[k, default: 0] += v }
                for (k, v) in r.otherIdle { tot.otherIdle[k, default: 0] += v }
                firsts.append(r.first)
                lines.append(String(format: "MIX seed %d: uses %d, per kind %@, minGap %.2f (%@)", seed, r.uses, "\(r.perKind.sorted { $0.key < $1.key })", r.minGap, r.minTag))
            }
            let mins = Float(Int(env["TOYAUDIT_SEEDS"] ?? "") ?? 3) * secs / 60
            lines.append(String(format: "MIX total uses per 10 min per body-trio: %.1f; stuck %d crowd %d queued %d tookTurn %d gaveUp %d minGap %.2f; share walk %.1f%% stand %.1f%% solo %.1f%% pair %.1f%%",
                                Float(tot.uses) / mins * 10, tot.stuck, tot.crowd, tot.queued, tot.tookTurn, tot.gaveUp, tot.minGap,
                                100 * Float(tot.walkF) / Float(tot.frames), 100 * Float(tot.standF) / Float(tot.frames), 100 * Float(tot.soloF) / Float(tot.frames), 100 * Float(tot.pairF) / Float(tot.frames)))
            lines.append("MIX shared moments \(tot.shared); per kind uses: \(tot.perKind.sorted { $0.key < $1.key })")
            lines.append("MIX idle starts (all bodies, 3 seeds): \(tot.starts.sorted { $0.key < $1.key })")
            lines.append("MIX other idles (frames): \(tot.otherIdle.sorted { $0.key < $1.key })")
        } else {
            let only = (env["TOYAUDIT_KINDS"] ?? "").split(separator: ",").map(String.init)
            for kind in Self.shopToys where only.isEmpty || only.contains(kind.rawValue) {
                var uses = 0, shr = 0, starts: [String: Int] = [:], firsts: [Float] = [], durs: [Float] = [], stuck = 0, crowd = 0, q = 0, tt = 0, gu = 0, minGap: Float = .infinity
                for seed in [3, 5, 9] as [UInt64] {
                    let r = run(kinds: [kind], seconds: secs, seed: seed)
                    shr += r.shared; for (k, v) in r.starts { starts[k, default: 0] += v }
                    uses += r.uses; if r.first >= 0 { firsts.append(r.first) }; durs += r.dur; stuck += r.stuck; crowd += r.crowd; q += r.queued; tt += r.tookTurn; gu += r.gaveUp; minGap = min(minGap, r.minGap)
                }
                let per10 = Float(uses) / (3 * secs / 600)
                lines.append(String(format: "%@: uses/10min/trio %.1f (n=%d), first use %@, mean use %.1f s (max %.1f), unfinished>60s %d, crowd samples %d, queued %d tookTurn %d gaveUp %d, minGap %.2f, shared moments %d, idle starts %@",
                                    kind.rawValue, per10, uses, firsts.isEmpty ? "never" : String(format: "%.1f s mean of %d/3 seeds", firsts.reduce(0, +) / Float(firsts.count), firsts.count),
                                    durs.isEmpty ? 0 : durs.reduce(0, +) / Float(durs.count), durs.max() ?? 0, stuck, crowd, q, tt, gu, minGap, shr, "\(starts.sorted { $0.key < $1.key })"))
            }
        }
        try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        print("TOYAUDIT\n" + lines.joined(separator: "\n"))
    }
}
