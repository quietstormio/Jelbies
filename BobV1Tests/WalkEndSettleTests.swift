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

    func walkEnd(_ goal: SIMD2<Float>, dump: Bool) -> GlitchEmoteTests.Pops {
        let g = GlitchEmoteTests()
        return g.pops(.wander, seconds: 12, label: "walkEnd \(goal)", start: { r in
            let b = r.brain
            b.route = []; b.scriptT = 0; b.stuckT = 0
            b.restTimer = 1e6; b.idleState.cooldown = 1e6; b.socialBook.cooldown = 1e6
            b.script = .walk(target: goal, then: .none); b.activity = .walking
        }, isOn: { $0.brain.activity == .walking }, dumpEnd: dump)
    }

    func testWalkEndFeetSettleWithoutAPop() {
        let dump = ProcessInfo.processInfo.environment["WALKEND_DUMP"] == "1"
        var lines: [String] = [], feet = 0, body = 0, worst: Float = 0
        for goal in Self.goals {
            let p = walkEnd(goal, dump: dump)
            let f = p.events.filter { $0.part == "foot" }, bo = p.events.filter { $0.part == "body" }
            feet += f.count; body += bo.count; worst = max(worst, (f + bo).map(\.cm).max() ?? 0)
            lines.append("goal \(goal): \(p.byPart) max \(p.max) | \(p.diag)")
            for l in p.lines { lines.append("  " + l) }
        }
        MotionLog.write("WALKEND settle=\(BlobBrain.walkEndSettle) foot pops \(feet), body pops \(body), worst \(worst) cm\n" + lines.joined(separator: "\n"))
        if BlobBrain.walkEndSettle { XCTAssertLessThan(worst, 6, "no foot / body pop of 6 cm or more at the end of a walk") }
    }
}
#endif
