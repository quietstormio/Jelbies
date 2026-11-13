//
//  ParkSlideRoundCornerTests.swift
//  park-slide-r2: the 10-12 s stand at the front-edge corners of the way round the park slide (real app: (2.90,3.59) and (1.30,3.55), stage -3, a friend 1-1.6 m away).
//  A walker on the way round, a friend standing idle on the next leg: he must not stand over 6 s; the attempt ends in a ride or he is dropped (free).
//

import XCTest
import simd
@testable import BobV1

extension ParkSlideRoundTests {
    func testStandingFriendOnTheNextLegDoesNotHoldHimOver6Seconds() {
        struct Case { var name: String; var start: SIMD2<Float>; var friend: SIMD2<Float> }
        let cases = [Case(name: "foot -> west corner", start: SIMD2(2.90, 3.59), friend: SIMD2(1.85, 3.55)),
                     Case(name: "foot -> west corner, friend nearer", start: SIMD2(2.90, 3.59), friend: SIMD2(1.95, 3.40)),
                     Case(name: "west corner -> north leg", start: SIMD2(1.30, 3.55), friend: SIMD2(1.30, 2.45)),
                     Case(name: "west corner -> north leg, friend west", start: SIMD2(1.30, 3.55), friend: SIMD2(0.40, 2.60))]
        var worst: Float = 0, bad: [String] = []
        for c in cases {
            for seed in UInt64(1)...3 {
                let lab = parkLab(n: 2, seed: seed, aspect: Self.portrait, starts: [c.start, c.friend], quiet: true)
                let r = lab.rigs[0], f = lab.rigs[1]
                place(r, c.start); place(f, c.friend)
                f.brain.restTimer = 1e6; f.brain.idleState.cooldown = 1e6
                for _ in 0..<5 { lab.tick(watching: false) }
                var log: [String] = []
                BlobBrain.slideLog = { log.append($0) }
                defer { BlobBrain.slideLog = nil }
                let b = r.brain
                XCTAssertTrue(b.startCommandedDecor(.decorSlide, only: .slide, r.sim, r.skinner), "\(c.name) s\(seed) starts")
                var t: Float = 0, ref = b.position, refT: Float = 0, still: Float = 0, longest: Float = 0, reached = false, ended: Float?
                var trace: [String] = []
                while t < 40 {
                    lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
                    let st = b.idleState
                    let using = st.kind == .decorSlide && st.decorUID == ParkToys.slideUID
                    if using, st.slideStage >= 1 { reached = true; break }
                    if !using { ended = t; break }
                    if t - refT >= 0.5 {
                        if simd_distance(b.position, ref) < 0.05 && st.slideStage < 0 { still += 0.5 } else { still = 0 }
                        longest = max(longest, still)
                        if trace.count < 60 { trace.append(String(format: "t%.1f st%d tgt(%.2f,%.2f) steerWait %.1f stall %.1f walkStall %.1f giveUp %d", t, st.slideStage, st.target.x, st.target.y, b.steerWait, b.steerStall, b.walkStallT, b.steerGiveUp ? 1 : 0)) }
                        ref = b.position; refT = t
                    }
                }
                worst = max(worst, longest)
                print("PSR CORNER \(c.name) s\(seed): longest stand \(longest) s, reached ladder \(reached), attempt ended \(String(describing: ended)), replans: \(log.joined(separator: " | "))")
                if longest > 3 { for l in trace { print("PSR CORNER   trace \(l)") } }
                if longest > 6 { bad.append("\(c.name) s\(seed): \(longest) s") }
                b.abortAll(r.sim, r.skinner)
            }
        }
        print("PSR CORNER worst stand \(worst) s")
        XCTAssertTrue(bad.isEmpty, "stood over 6 s: " + bad.joined(separator: " | "))
    }
}
