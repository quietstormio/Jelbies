//
//  ShowSpotlightTests.swift
//  The Trick round's spotlight (Show/ShowSpotlight.swift): at every turn the performer stands at the middle of the stage while the light is on him, no waiting entrant's
//  projected box overlaps his (portrait and landscape), the light's target is the performer and off between turns / rounds, and the fade takes about 0.4 s.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ShowSpotlightTests: XCTestCase {
    private func ready(_ care: GameCare) {
        care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }; care.show.cue = { _ in }
    }
    private func step(_ room: RaceThreeTests.Room) {
        for a in room.actors + room.park { if let b = a.brain { b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false) } }
        room.care.tickRace(room.actors, dt: 1 / 60)
        room.care.tickShow(room.actors, dt: 1 / 60)
    }

    func testFadeTakesAboutFourTenths() {
        var s = ShowSpotlightState()
        var t = 0, lit = 0
        while s.level < 1 && t < 200 { s.step(target: 3, dt: 1 / 60); t += 1; if s.shown == 3 && lit == 0 { lit = t } }
        XCTAssertEqual(Double(t) / 60, 0.4, accuracy: 0.06, "fade in")
        t = 0
        while s.level > 0 && t < 200 { s.step(target: nil, dt: 1 / 60); t += 1 }
        XCTAssertEqual(Double(t) / 60, 0.4, accuracy: 0.06, "fade out")
        // a new performer: the old light fades out first, then the new one in; nobody else is ever lit
        s = ShowSpotlightState(); for _ in 0..<60 { s.step(target: 1, dt: 1 / 60) }
        XCTAssertEqual(s.shown, 1); XCTAssertEqual(s.level, 1)
        for _ in 0..<10 { s.step(target: 2, dt: 1 / 60); XCTAssertEqual(s.shown, 1) }
        for _ in 0..<60 { s.step(target: 2, dt: 1 / 60) }
        XCTAssertEqual(s.shown, 2); XCTAssertEqual(s.level, 1)
    }

    /// The projected box of a body (the whole body, its arms), and of its face (the middle of the upper half), in points.
    private func box(_ a: JellyActor, frame: ShowFrame, size: CGSize, face: Bool = false) -> CGRect {
        let c = a.sim.centroid(), H = BobShape.H, R = BobShape.R
        let cy = face ? c.y + H * 0.15 : c.y, hw = face ? R * 0.55 : R * 1.15, hh = face ? H * 0.2 : H * 0.5
        let mid = StageProject.point(SIMD2(c.x, c.z), y: cy, frame: frame, size: size)
        let top = StageProject.point(SIMD2(c.x, c.z), y: cy + hh, frame: frame, size: size)
        let bot = StageProject.point(SIMD2(c.x, c.z), y: cy - hh, frame: frame, size: size)
        let side = StageProject.point(SIMD2(c.x + hw, c.z), y: cy, frame: frame, size: size)
        let w = abs(side.x - mid.x)
        return CGRect(x: mid.x - w, y: top.y, width: 2 * w, height: bot.y - top.y)
    }

    private func wholeRound(size: CGSize) {
        let saved = GameCamera.aspect
        GameCamera.aspect = Float(size.width / size.height)
        defer { GameCamera.aspect = saved }
        let room = RaceThreeTests.Room(count: 3)
        RaceThreeTests.keep.append(room)
        let care = room.care
        ready(care)
        care.startShow(jelly: 0, rank: .puddle, seed: 5)
        for _ in 0..<(6 * 60) { step(room); if care.show.onStage { break } }
        XCTAssertTrue(care.show.onStage)
        care.show.auto = true
        let book = care.showBook
        var lit12 = Set<String>()          // (turn, actor id) pairs lit at full strength
        var litFrames: [String: Int] = [:]
        var maxDist: Float = 0
        var worstOverlap: CGFloat = 0
        var worstBody: CGFloat = 0, worstBodyArea: CGFloat = 0, peakHop: Float = 0
        var offBetween = true
        var seenTrick = false
        var danceMiss = 0, danceLit = 0
        var winAge = 0
        var sinceWindow = 0          // frames since the last performer's window closed
        var gapViolations = 0, windowTargetMisses = 0, maxFadeAfter = 0
        var diag: [String] = []
        var prevStage = care.show.trickStage, prevRival = care.show.rivalStep
        func put(_ a: JellyActor, _ p: SIMD2<Float>) { a.sim.teleport(toXZ: p); a.brain?.currentPose(a.sim) }
        for frame in 0..<(400 * 60) {
            step(room)
            // (the headless room's bodies do not walk by themselves: the player's step aside / back is done here, at the moment the real walk ends)
            let sh0 = care.show
            if sh0.trickStage == .rivals && sh0.rivalStep == .playerAway && !(prevStage == .rivals && prevRival == .playerAway) { put(room.actors[0], ShowStage.playerAside) }
            if sh0.trickStage != .rivals && prevStage == .rivals { put(room.actors[0], ShowStage.playerSpot) }
            if sh0.trickStage == .rivals, sh0.rivalStep != prevRival || prevStage != .rivals, let i = sh0.rivalTurn, let id = book.rivalBody[i], let a = book.extra.first(where: { $0.id == id }) {
                if sh0.rivalStep == .perform { put(a, ShowStage.playerSpot) }          // (she has walked to the middle)
                if sh0.rivalStep == .walkOut { put(a, ShowStage.rivalRest(i, sideways: GameCamera.aspect > 1)) }          // (and back to her mark)
            }
            prevStage = sh0.trickStage; prevRival = sh0.rivalStep
            if care.show.round == .results && care.show.trickStage == .pick && care.show.hasResults { break }
            let st = book.spot
            if care.show.round == .dance {
                let want = care.show.beat == .dancing
                if (care.showSpotTarget != nil) != want { danceMiss += 1 }
                if want && st.level >= 0.99 { danceLit += 1 }
            }
            let inTrick = care.show.round == .trick || (care.show.round == .results && care.show.trickStage != .pick)
            if care.show.round == .look || (care.show.round == .results && care.show.trickStage == .pick) {
                if care.showSpotTarget != nil || st.level > 0 { offBetween = false }
            }
            guard inTrick, let f = care.showFrame else { continue }
            seenTrick = true
            let sh = care.show
            // the performer's own window: his pick + trick (at the middle), or an entrant's trick (she has arrived)
            var performer: Int?
            if !sh.trickEntering {
                switch sh.trickStage {
                case .pick: if let sm = sh.sim, !sm.tricksDone { performer = book.performers.first }
                case .performing: performer = book.performers.first
                case .rivals: if sh.rivalStep == .perform { performer = sh.rivalTurn.flatMap { book.rivalBody[$0] } }
                }
            }
            if let p = performer {
                sinceWindow = 0; winAge += 1
                if st.target != p && winAge > 3 { windowTargetMisses += 1 }          // (the first frames: the body is still stepping into the middle)
            } else {
                winAge = 0
                sinceWindow += 1
                if care.showSpotTarget != nil { gapViolations += 1; if diag.count < 6 { diag.append("f\(frame) target \(String(describing: st.target)) in gap: \(sh.trickStage) \(sh.rivalStep)") } }          // (the target is off in every gap)
                if st.level > 0 { maxFadeAfter = max(maxFadeAfter, sinceWindow) }
                if sinceWindow > 27 && st.level > 0 { gapViolations += 1; if diag.count < 6 { diag.append("f\(frame) level \(st.level) shown \(String(describing: st.shown)) \(sh.trickStage) \(sh.rivalStep) since \(sinceWindow)") } }          // (0.4 s fade out and then fully off)
            }
            guard let p = performer, st.level >= 0.99, let litActor = care.showSpotActor, litActor.id == p else { continue }
            let key = "\(sh.trickTurnNow ?? -1)-\(p)"
            lit12.insert(key); litFrames[key, default: 0] += 1
            let lc = litActor.sim.centroid(); maxDist = max(maxDist, simd_distance(SIMD2(lc.x, lc.z), ShowStage.playerSpot))
            let mine = box(litActor, frame: f, size: size)
            let others = (room.actors + book.extra).filter { $0.id != p && !care.showHides($0.id) }
            peakHop = max(peakHop, litActor.sim.centroid().y)
            for o in others { let bi = mine.intersection(box(o, frame: f, size: size)); if !bi.isNull { let ob = box(o, frame: f, size: size); worstBodyArea = max(worstBodyArea, bi.width * bi.height); worstBody = max(worstBody, bi.width * bi.height / (ob.width * ob.height)) } }
            for o in others {          // (no waiting face is under the performer, and no two waiting faces overlap)
                let inter = mine.intersection(box(o, frame: f, size: size, face: true))
                if !inter.isNull { worstOverlap = max(worstOverlap, inter.width * inter.height); if diag.count < 6 { diag.append("f\(frame) performer \(p) over face of \(o.id) at \(o.floor) \(sh.trickStage) \(sh.rivalStep) \(inter)") } }
            }
            for i in others.indices { for j in others.indices where j > i {
                let inter = box(others[i], frame: f, size: size, face: true).intersection(box(others[j], frame: f, size: size, face: true))
                if !inter.isNull { worstOverlap = max(worstOverlap, inter.width * inter.height) }
            } }
        }
        XCTAssertTrue(seenTrick)
        XCTAssertEqual(danceMiss, 0, "the Dance round's light is on exactly while the dance runs")
        XCTAssertGreaterThan(danceLit, 60, "the dancer was lit")
        XCTAssertTrue(offBetween, "no light in Look or Results")
        XCTAssertEqual(lit12.count, 12, "every one of the 12 turns (3 turns x the player and 3 entrants) was lit at full strength: \(lit12.sorted())")
        for (k, n) in litFrames { XCTAssertGreaterThan(n, 20, "turn \(k) was lit at full strength for a while") }
        XCTAssertEqual(windowTargetMisses, 0, "the light's target is the performer for his whole window")
        XCTAssertEqual(gapViolations, 0, "the light is off in every gap between turns (fade out within 0.4 s): \(diag)")
        XCTAssertLessThan(maxDist, 0.6, "the lit performer stays within 0.6 of the middle of the stage")
        XCTAssertEqual(worstOverlap, 0, accuracy: 1, "no waiting entrant's face is under the performer or another face (\(size)): \(diag)")
        print("[ShowSpotlight] \(size): worst body-box overlap of a waiting body with the performer: \(Int(worstBody * 100)) % of the waiting body's box (face overlap \(worstOverlap) px2), highest centroid while lit \(peakHop)")
        care.show.abort()
    }

    func testWholeTrickRoundPortrait() { wholeRound(size: CGSize(width: 440, height: 956)) }
    func testWholeTrickRoundLandscape() { wholeRound(size: CGSize(width: 956, height: 440)) }
}
