//
//  PlayNetInertTests.swift
//  The net code is inert when the net is not up (play-net-r1): one seeded soccer game in the controller, as the base commit plays it, and a digest of its touches. Uses only the controller's
//  base API, so the same file runs on the base commit; the two digests must be identical (`[netinert] digest ...`).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class PlayNetInertTests: XCTestCase {
    func testSeededSoccerGameDigest() {
        let size = PlayTossTests.portrait
        PlayTossTests.room(size)
        BlobBrain.pickBudgetSeconds = .infinity
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        TossTuning.zBack = -2.4; TossTuning.zFront = 9
        let start: [SIMD2<Float>] = [SIMD2(-1.6, 0.2), SIMD2(0, 1.4), SIMD2(1.6, 0.2)]
        let rs: [MotionRig] = start.enumerated().map { i, s in
            let r = MotionRig(game: true, settle: 0.5)
            PlayTossTests.keep.append(r)
            r.renderSamples = false
            r.brain.autonomy = true; r.brain.anticsEnabled = true; r.brain.seed = UInt64(1 * 31 + i * 7 + 5)
            r.brain.abortScript(r.sim, r.skinner)
            r.sim.teleport(toXZ: s); r.run(0.3)
            return r
        }
        let p = PlayToss(); p.seed(977 + 13); p.viewSize = size
        var log: [String] = []
        p.onEvent = { e in
            switch e {
            case .header(let id, _): log.append("h\(id)@\(String(format: "%.2f", p.clock))")
            case .kick(let id): log.append("k\(id)@\(String(format: "%.2f", p.clock))")
            case .pass(let a, let b): log.append("p\(a)>\(b)")
            case .whiff(let id): log.append("w\(id)")
            case .rescue: log.append("r")
            case .caught(let n): log.append("c\(n)")
            default: break
            }
        }
        func js() -> [PlayJelly] { rs.enumerated().map { PlayJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, skinner: $0.element.skinner) } }
        p.begin(ball: .soccerball, title: "ball", jellies: js(), snapCamera: true)
        var w = TossWorld(); w.xHalf = PlayToss.ballXHalf
        let dt = rs[0].sim.stepDt
        var t: Float = 0, settle: Float = 4, round = 0, tosses = 0
        while t < 70 {
            for r in rs { r.tick() }
            p.tick(dt: dt, world: w, jellies: js())
            t += dt
            if p.phase == .inHand, t > settle, p.camBlend > 0.9, simd_distance(p.ball.pos, p.handWorld()) < 0.3 {
                let from = CGPoint(x: size.width * 0.5, y: size.height * 0.83)
                let tgt = rs[[1, 0, 2, 1, 2, 0][round % 6]].brain.position
                let head = GameCamera.screenPoint(floor: tgt, y: BobShape.H, size: size) ?? CGPoint(x: size.width / 2, y: size.height / 2)
                let off: CGFloat = [0, 0.03, -0.03][round % 3] * size.width; round += 1
                let dx = head.x + off - from.x, dy = head.y - from.y, L = max(hypot(dx, dy), 1)
                let sp = (L / size.height) / TossAim.reach * size.height
                p.flick(from: from, velocity: CGVector(dx: dx / L * sp, dy: dy / L * sp))
                tosses += 1; settle = t + 1.2
            }
        }
        p.end()
        let digest = "tosses=\(tosses) events=\(log.joined(separator: ",")) ball=\(String(format: "%.3f,%.3f,%.3f", p.ball.pos.x, p.ball.pos.y, p.ball.pos.z))"
        NSLog("[netinert] digest %@", digest)
        XCTAssertGreaterThan(tosses, 5)
    }
}
