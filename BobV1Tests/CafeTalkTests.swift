//
//  CafeTalkTests.swift
//  cafe-talk-r1: the café table after the meal. The lounge runs headless for the lounge runs headless with three, two and one Jelmiko: nobody leaves its stand (0.05 u from where it stood once settled), everybody keeps its facing (0.15 rad, body twist included), they take turns talking, and nobody is walked back by the safety net.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CafeTalkTests: XCTestCase {
    override func tearDown() {
        RoomLayout.apply(RoomCatalog.home)
        DecorField.shared.set([])
        DayClock.shared.forcedHour = 12
        super.tearDown()
    }

    private func step(_ r: DiningJellyTests.Room, _ s: Float, until: (() -> Bool)? = nil, each: (() -> Void)? = nil) {
        for _ in 0..<Int(s * 60) {
            r.tick()
            r.care.tickRace(r.actors, dt: 1.0 / 60)
            r.care.tickCafe(r.actors, dt: 1.0 / 60)
            r.care.tickDecor(dt: 1.0 / 60)
            each?()
            if let until, until() { break }
        }
    }

    /// Runs the café to the start of the lounge, then 30 s of it; returns the worst drift / facing error per body, the conversation numbers and the cheer-end offsets.
    private func lounge(count: Int, seed: UInt64 = 7) -> (drift: Float, yawErr: Float, offsetFromStand: Float, chat: CafeChatState, seats: Int) {
        DayClock.shared.forcedHour = 12
        let r = DiningJellyTests.Room(count: count)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        let c = r.care
        c.bath.wallet.add(100 - c.bath.wallet.count, silent: true)
        for j in c.jellies { c.needs(for: j.id).set(.hunger, 0.3) }
        step(r, 1)
        c.requestCafe()
        step(r, 6) { c.cafe.phase == .menu }
        XCTAssertEqual(c.cafe.phase, .menu)
        let menu: [CafeTreatID] = [.swirl, .cocoa, .pancakes]
        XCTAssertNil(c.orderCafe(CafeOrder(picks: Dictionary(uniqueKeysWithValues: c.cafeDinerIDs.enumerated().map { ($0.element, menu[$0.offset % 3]) }))))
        step(r, 180) { c.cafe.phase == .lounge }
        XCTAssertEqual(c.cafe.phase, .lounge)
        step(r, 6)          // (the settle window: the cheer's hops are walked back to the stands and each body turns to its facing, once)
        c.cafeBook.chat = CafeChatState(seed: seed)
        var start: [Int: SIMD2<Float>] = [:]
        var off: Float = 0
        for a in r.actors { if let b = a.brain, let st = c.cafeBook.stands[a.id] { start[a.id] = GameCare.floorPos(b, a.sim); off = max(off, simd_distance(start[a.id]!, st)) } }
        var drift: Float = 0, yawErr: Float = 0
        step(r, 22, each: {
            for s in c.cafeSeats(r.actors) {
                let b = s.brain
                drift = max(drift, simd_distance(GameCare.floorPos(b, s.sim), start[s.id] ?? s.stand))
                yawErr = max(yawErr, abs(GameCare.wrapAngle(b.yaw + b.twist + b.chat.twist - s.yaw)))
            }
        })
        return (drift, yawErr, off, c.cafeBook.chat, c.cafeSeats(r.actors).count)
    }

    func testThreeAtTheTableStayPutAndTalk() {
        let x = lounge(count: 3)
        print("[cafetalk-test] three: drift \(x.drift) yawErr \(x.yawErr) offset \(x.offsetFromStand) lines \(x.chat.lines) answers \(x.chat.answers) laughs \(x.chat.laughs) corrections \(x.chat.corrections)")
        XCTAssertEqual(x.seats, 3)
        XCTAssertLessThan(x.drift, 0.05, "nobody leaves its stand")
        XCTAssertLessThan(x.yawErr, 0.15, "everybody keeps its facing")
        XCTAssertGreaterThanOrEqual(x.chat.lines, 4, "they take turns talking")
        XCTAssertGreaterThanOrEqual(x.chat.answers, 3, "and answer")
        XCTAssertEqual(x.chat.corrections, 0, "the safety net never had to walk or turn anybody back")
    }

    func testTwoAtTheTableFaceEachOther() {
        let x = lounge(count: 2)
        print("[cafetalk-test] two: drift \(x.drift) yawErr \(x.yawErr) offset \(x.offsetFromStand) lines \(x.chat.lines) answers \(x.chat.answers) corrections \(x.chat.corrections)")
        XCTAssertLessThan(x.drift, 0.05)
        XCTAssertLessThan(x.yawErr, 0.15)
        XCTAssertGreaterThanOrEqual(x.chat.lines, 4)
    }

    func testOneAloneChirpsCalmlyInPlace() {
        let x = lounge(count: 1)
        print("[cafetalk-test] one: drift \(x.drift) yawErr \(x.yawErr) lines \(x.chat.lines)")
        XCTAssertLessThan(x.drift, 0.05)
        XCTAssertLessThan(x.yawErr, 0.15)
        XCTAssertGreaterThanOrEqual(x.chat.lines, 3)
    }

    /// The overlay is small by construction: a lean never exceeds 0.09 rad, a look 0.1 rad.
    func testChatOverlayIsCappedAndLetsGo() {
        let b = BlobBrain.forGame()
        b.chatPose(lean: 5, toward: 0.3, look: 5, bob: 5, arm: 5, mouth: 5, hold: 0.5)
        XCTAssertLessThanOrEqual(abs(b.chat.leanPitch) + abs(b.chat.leanRoll), 0.09 * 1.5)
        XCTAssertLessThanOrEqual(b.chat.look, 0.1)
        XCTAssertLessThanOrEqual(b.chat.bobAmp, 0.07)
        for _ in 0..<120 { b.chat.tick(1.0 / 60) }
        XCTAssertFalse(b.chat.active, "it lets go by itself")
        XCTAssertEqual(b.chat.pitch, 0); XCTAssertEqual(b.chat.roll, 0); XCTAssertEqual(b.chat.twist, 0)
    }
}
