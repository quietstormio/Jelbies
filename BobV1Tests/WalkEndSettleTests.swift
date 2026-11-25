//
//  WalkEndSettleTests.swift
//  move-crowd-r2: the glitch hunter's room bucket "walk end" (feet ~6 cm in one step about 50 ms after a walk ends, 205 events per 10 game-min). One game rig walks to a point
//  (several headings, so the stand often has to square up to the camera) and the dev glitch probe's core counts the foot / body pops from the last walking step to 1.5 s after.
//  `WALKEND_DUMP=1` writes the brain state around each pop (GlitchEmoteTests' dump).
//

#if DEBUG || JELBIES_DEV_ARGS || targetEnvironment(simulator)
import XCTest
import simd
@testable import BobV1

@MainActor
final class WalkEndSettleTests: XCTestCase {
    static let goals: [SIMD2<Float>] = [SIMD2(1.8, 0.4), SIMD2(-1.8, 0.4), SIMD2(0.3, -1.6), SIMD2(-0.4, 2.2), SIMD2(1.6, 1.8), SIMD2(-1.5, -1.2)]

    /// The pops from the step the walk ended to 1.5 s after (part, cm).
    func walkEnd(_ goal: SIMD2<Float>, dump: Bool) -> (all: GlitchEmoteTests.Pops, after: [(part: String, cm: Float, t: Float)], endT: Float) {
        let g = GlitchEmoteTests()
        var endT: Float = -1
        let p = g.pops(.wander, seconds: 12, label: "walkEnd \(goal)", start: { r in
            let b = r.brain
            b.route = []; b.scriptT = 0; b.stuckT = 0
            b.restTimer = 1e6; b.idleState.cooldown = 1e6; b.socialBook.cooldown = 1e6
            b.script = .walk(target: goal, then: .none); b.activity = .walking
        }, isOn: { $0.brain.activity == .walking }, each: { r, t in if endT < 0, !r.brain.isWalkScript, t > 0.2 { endT = t } }, dumpEnd: dump)
        var after: [(part: String, cm: Float, t: Float)] = []
        let rx = try! NSRegularExpression(pattern: " t=([0-9.]+) (\\w+) ([0-9.]+) cm")
        for l in p.lines {
            guard let m = rx.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)), let r1 = Range(m.range(at: 1), in: l), let r2 = Range(m.range(at: 2), in: l), let r3 = Range(m.range(at: 3), in: l),
                  let t = Float(l[r1]), let cm = Float(l[r3]) else { continue }
            if endT >= 0, t >= endT - 0.02 { after.append((String(l[r2]), cm, t)) }
        }
        return (p, after, endT)
    }

    func testWalkEndFeetSettleWithoutAPop() {
        let dump = ProcessInfo.processInfo.environment["WALKEND_DUMP"] == "1"
        let saved = BlobBrain.walkEndSettle
        defer { BlobBrain.walkEndSettle = saved }
        var res: [Bool: (n: Int, big: Int, worst: Float)] = [:]
        var lines: [String] = []
        for on in [false, true] {
            BlobBrain.walkEndSettle = on
            var n = 0, big = 0, worst: Float = 0
            for goal in Self.goals {
                let r = walkEnd(goal, dump: dump && !on)
                let ev = r.after.filter { $0.part == "foot" || $0.part == "body" }
                n += ev.count; big += ev.filter { $0.cm >= 5 }.count; worst = max(worst, ev.map(\.cm).max() ?? 0)
                lines.append("settle=\(on) goal \(goal) end t=\(r.endT): " + ev.map { String(format: "%@ %.1f cm at +%.2f s", $0.part, $0.cm, $0.t - r.endT) }.joined(separator: ", "))
            }
            res[on] = (n, big, worst)
        }
        MotionLog.write("WALKEND foot/body pops in the 1.5 s after a walk ends (6 walks): off \(res[false]!), on \(res[true]!)\n" + lines.joined(separator: "\n"))
        XCTAssertLessThanOrEqual(res[true]!.n, res[false]!.n)
        XCTAssertLessThanOrEqual(res[true]!.worst, max(res[false]!.worst, 3.5))
    }
}
#endif
