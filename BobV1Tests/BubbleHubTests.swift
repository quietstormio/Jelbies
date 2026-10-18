//
//  BubbleHubTests.swift
//  Needs feedback per Jelly: who holds the one bubble slot (neediest, rotating fairly), that a tap selects that Jelly and carries his id,
//  the greeting's hearts and stagger for Pip and Moss, and that a one-Jelly game is untouched.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BubbleHubTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func care(_ n: Int = 3) -> GameCare {
        let c = GameCare(jellyCount: n, persistent: false)
        Self.keep.append(c)
        for j in c.jellies { for k in NeedKind.allCases { j.needs.set(k, 1) }; j.grime.dirt = 0 }
        return c
    }
    /// The game's order each step: Bob's tick (his schedules), then the others' (tickBubbles).
    private func run(_ c: GameCare, seconds: Float, each: (() -> Void)? = nil) {
        let bob = BlobBrain.forGame()
        var t: Float = 0
        while t < seconds { c.tick(brain: bob, renderer: nil, dt: 0.05); c.tickBubbles([], dt: 0.05); each?(); t += 0.05 }
    }

    // MARK: the pure rule

    func testNeediestWinsAndNothingToSayIsNil() {
        let a = BubbleCandidate(id: 0, urgency: 0.72), b = BubbleCandidate(id: 1, urgency: 0.95), c = BubbleCandidate(id: 2, urgency: 0.8)
        XCTAssertEqual(BubbleRotation.pick([a, b, c], shownAt: [0: 5, 1: 5, 2: 5], turn: 5), 1)
        XCTAssertNil(BubbleRotation.pick([], shownAt: [:], turn: 0))
        let n = BlobNeeds(persists: false); Self.keep.append(n)
        for k in NeedKind.allCases { n.set(k, 1) }
        XCTAssertNil(BubbleRotation.urgency(needs: n, coat: .clean))
        XCTAssertEqual(BubbleRotation.urgency(needs: n, coat: .filthy), 0.75)
        n.set(.thirst, 0.1)
        XCTAssertEqual(BubbleRotation.urgency(needs: n, coat: .clean) ?? 0, 0.9, accuracy: 1e-5)
    }

    func testRotationGivesEveryoneATurn() {
        // three equally needy Jellies take the slot in turn; a much needier one still goes first but cannot starve the rest
        var shown: [Int: Int] = [:]
        var order: [Int] = []
        for turn in 1...6 {
            let id = BubbleRotation.pick((0..<3).map { BubbleCandidate(id: $0, urgency: 0.8) }, shownAt: shown, turn: turn - 1)!
            shown[id] = turn; order.append(id)
        }
        XCTAssertEqual(Set(order[0..<3]), [0, 1, 2], "each Jelly in the first three turns: \(order)")
        XCTAssertEqual(Set(order[3..<6]), [0, 1, 2], "and again: \(order)")
        shown = [:]; order = []
        for turn in 1...8 {
            let cs = [BubbleCandidate(id: 0, urgency: 1.0), BubbleCandidate(id: 1, urgency: 0.7)]
            let id = BubbleRotation.pick(cs, shownAt: shown, turn: turn - 1)!
            shown[id] = turn; order.append(id)
        }
        XCTAssertEqual(order.first, 0)
        XCTAssertTrue(order.contains(1), "the lesser need still gets a turn: \(order)")
        XCTAssertGreaterThan(order.filter { $0 == 0 }.count, order.filter { $0 == 1 }.count - 1, "the neediest shows at least as often")
    }

    // MARK: the slot

    func testThirstyPipsBubbleIsPipsAndTapCarriesHisId() {
        let c = care()
        c.jellies[1].needs.set(.thirst, 0.1)
        run(c, seconds: 4)
        XCTAssertEqual(c.bubbleJelly, 1)
        XCTAssertEqual(c.bubbleNeed, .thirst)
        XCTAssertEqual(c.bubbleJellyName, "Pip")
        c.tickBubbles([], dt: 0.05)
        XCTAssertEqual(c.bubbleHead(1), c.bubbleHub.heads[1] ?? c.headWorld)
        XCTAssertEqual(c.tapBubble(), .drink)
        XCTAssertEqual(c.select.selectedID, 1, "the tap highlights Pip")
        XCTAssertEqual(c.targetJelly, 1, "so the care action that follows targets Pip")
        XCTAssertNil(c.bubbleNeed, "the bubble goes after a tap")
    }

    func testOnlyOneBubbleAtATimeAndEveryoneGetsAround() {
        let c = care()
        c.jellies[1].needs.set(.thirst, 0.1)
        c.jellies[2].needs.set(.attention, 0.12)
        c.jellies[0].needs.set(.hunger, 0.15)
        var owners: Set<Int> = []
        run(c, seconds: 130) { if c.bubbleNeed != nil { owners.insert(c.bubbleJelly) } }
        XCTAssertEqual(owners, [0, 1, 2], "all three needy Jellies had a turn")
    }

    func testDirtyJellyGetsTheBathBubble() {
        let c = care()
        c.jellies[2].grime.dirt = 0.95
        run(c, seconds: 6)
        XCTAssertEqual(c.bubbleJelly, 2)
        XCTAssertTrue(c.bubbleClean)
        XCTAssertEqual(c.bubbleIcon, .clean)
    }

    func testBobsOwnBubbleStillWorksWithThree() {
        let c = care()
        c.jellies[0].needs.set(.hunger, 0.1)
        run(c, seconds: 6)
        XCTAssertEqual(c.bubbleJelly, 0)
        XCTAssertEqual(c.bubbleNeed, .hunger)
        XCTAssertEqual(c.tapBubble(), .feed)
        XCTAssertEqual(c.select.selectedID, 0)
    }

    // MARK: the greeting

    func testGreetingHeartsForAllThreeAndStagger() {
        let c = care()
        XCTAssertGreaterThan(BubbleHub.greetStagger(1), 0)
        XCTAssertGreaterThan(BubbleHub.greetStagger(2), BubbleHub.greetStagger(1), "the hops are staggered")
        XCTAssertEqual(BubbleHub.greetStagger(0), 0)
        c.startGreetHearts(1); c.startGreetHearts(2)
        run(c, seconds: 1.4)
        let h = c.bubbleHub.hearts
        XCTAssertEqual(h.filter { $0.id == 1 }.count, BubbleHub.greetHeartCount)
        XCTAssertEqual(h.filter { $0.id == 2 }.count, BubbleHub.greetHeartCount)
        // Bob's greeting hearts are the touch model's: a long absence greets and queues his walk
        let t0 = Date(timeIntervalSince1970: 3_000_000_000)
        c.leftActive(at: t0); c.returnedActive(at: t0.addingTimeInterval(2 * 3600))
        XCTAssertEqual(c.greetings, 1)
    }

    // MARK: one Jelly

    func testOneJellyIsUnchanged() {
        let c = care(1)
        c.jellies[0].needs.set(.thirst, 0.1)
        let bob = BlobBrain.forGame()
        for _ in 0..<5 { c.tick(brain: bob, renderer: nil, dt: 0.05) }
        c.showNeedBubble()
        XCTAssertEqual(c.bubbleJelly, 0)
        XCTAssertEqual(c.bubbleNeed, .thirst)
        XCTAssertEqual(c.tapBubble(), .drink)
        XCTAssertFalse(c.select.isSelecting, "a single Jelly's tap does not light the highlight")
    }
}
