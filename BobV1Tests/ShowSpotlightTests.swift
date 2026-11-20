//
//  ShowSpotlightTests.swift
//  The Trick round's spotlight (Show/ShowSpotlight.swift): at every turn the performer stands at the middle of the stage while the light is on him, no waiting entrant's
//  projected box overlaps his (portrait and landscape), the light's target is the performer and off between turns / rounds, and the fade takes about 0.4 s.
//

import XCTest
import SwiftUI
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

    private func wholeRound(size: CGSize, legacy: Bool = false) {
        ShowStage.legacyLandscapeMark = legacy
        defer { ShowStage.legacyLandscapeMark = false }
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
        var worstBehind: CGFloat = 0, worstFront: CGFloat = 0          // body-box overlap with a waiting body, by depth: the waiter BEHIND the performer (she covers him) / IN FRONT of him (he covers her)
        var envLo = SIMD3<Float>(repeating: 99), envHi = SIMD3<Float>(repeating: -99)          // the performer's widest reach while he holds the light
        var envTrick: [String: (SIMD3<Float>, SIMD3<Float>)] = [:]
        var offBetween = true
        var seenTrick = false
        var danceMiss = 0, danceLit = 0
        var winAge = 0
        var sinceWindow = 0          // frames since the last performer's window closed
        var gapViolations = 0, windowTargetMisses = 0, maxFadeAfter = 0
        var diag: [String] = []
        var prevStage = care.show.trickStage, prevRival = care.show.rivalStep
        var later: [(frame: Int, run: () -> Void)] = []
        func put(_ a: JellyActor, _ p: SIMD2<Float>) { a.sim.teleport(toXZ: p); a.brain?.currentPose(a.sim) }
        var beatLit = 0, lateTargets = 0
        for frame in 0..<(400 * 60) {
            step(room)
            // (the headless room's bodies do not walk by themselves: the walks are done here, at the moment the real walk would end; his step off waits half a second, the score beat)
            let sh0 = care.show
            let enteredRival = sh0.trickStage == .rivals && (sh0.rivalStep != prevRival || prevStage != .rivals)
            if enteredRival && sh0.rivalStep == .playerAway { later.append((frame + 30, { put(room.actors[0], ShowStage.playerAside) })) }
            if sh0.trickStage != .rivals && prevStage == .rivals { put(room.actors[0], ShowStage.playerSpot) }
            if enteredRival, let i = sh0.rivalTurn, let id = book.rivalBody[i], let a = book.extra.first(where: { $0.id == id }) {
                if sh0.rivalStep == .walkIn { later.append((frame + 75, { put(a, ShowStage.playerSpot) })) }          // (she walks up: 1.25 s)
                if sh0.rivalStep == .walkOut { later.append((frame + 30, { put(a, ShowStage.rivalRest(i, sideways: GameCamera.aspect > 1)) })) }          // (her score beat, then back to her mark)
            }
            for l in later where l.frame == frame { l.run() }
            later.removeAll { $0.frame <= frame }
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
            // the score beat: she (he) still stands on the middle while stepping away is not yet under way
            var beatActor: JellyActor?
            if sh.trickStage == .rivals {
                if sh.rivalStep == .walkOut, let i = sh.rivalTurn, let id = book.rivalBody[i] { beatActor = book.extra.first { $0.id == id } }
                if sh.rivalStep == .playerAway { beatActor = room.actors[0] }
            }
            // an entrant who has walked up and stands at the middle is lit while the flow still says walkIn (its next tick moves on to her trick)
            var arrivedInWalkIn = false
            if sh.trickStage == .rivals, sh.rivalStep == .walkIn, let i = sh.rivalTurn, let id = book.rivalBody[i], let ra = book.extra.first(where: { $0.id == id }) {
                let c = ra.sim.centroid(); arrivedInWalkIn = simd_distance(SIMD2(c.x, c.z), ShowStage.playerSpot) < 0.5 && care.showSpotTarget == id
            }
            let beatNear: Bool = beatActor.map { let c = $0.sim.centroid(); return simd_distance(SIMD2(c.x, c.z), ShowStage.playerSpot) < 0.46 } ?? false
            if let p = performer {
                sinceWindow = 0; winAge += 1
                if st.target != p && winAge > 30 { windowTargetMisses += 1 }          // (the first frames: the body is still turning to the camera after the walk)
            } else {
                winAge = 0
                sinceWindow += 1
                if let ba = beatActor, beatNear, st.target != nil { if st.target == ba.id { beatLit += 1 } else { gapViolations += 1 } }          // (lit through the score beat: his own light)
                else if care.showSpotTarget != nil && !arrivedInWalkIn { gapViolations += 1; if diag.count < 6 { diag.append("f\(frame) target \(String(describing: st.target)) in gap: \(sh.trickStage) \(sh.rivalStep)") } }          // (off while anyone walks / the middle is empty)
            }
            if st.target == nil && st.level > 0 { lateTargets += 1 } else { lateTargets = 0 }
            if lateTargets > 27 { gapViolations += 1; lateTargets = 0; if diag.count < 6 { diag.append("f\(frame) fade-out did not finish: level \(st.level) \(sh.trickStage) \(sh.rivalStep)") } }
            guard let p = performer, st.level >= 0.99, let litActor = care.showSpotActor, litActor.id == p else { continue }
            let key = "\(sh.trickTurnNow ?? -1)-\(p)"
            lit12.insert(key); litFrames[key, default: 0] += 1
            let lc = litActor.sim.centroid(); maxDist = max(maxDist, simd_distance(SIMD2(lc.x, lc.z), ShowStage.playerSpot))
            let mine = box(litActor, frame: f, size: size)
            let others = (room.actors + book.extra).filter { $0.id != p && !care.showHides($0.id) }
            peakHop = max(peakHop, litActor.sim.centroid().y)
            let cc = litActor.sim.centroid(); envLo = simd_min(envLo, cc); envHi = simd_max(envHi, cc)
            let tk = "\(sh.trickStage == .rivals ? "rival\(sh.rivalTurn ?? -1)" : "player")-\(sh.trickTurnNow ?? -1)"; if let e = envTrick[tk] { envTrick[tk] = (simd_min(e.0, cc), simd_max(e.1, cc)) } else { envTrick[tk] = (cc, cc) }
            for o in others {
                let bi = mine.intersection(box(o, frame: f, size: size))
                if !bi.isNull {
                    let ob = box(o, frame: f, size: size), frac = bi.width * bi.height / (ob.width * ob.height)
                    worstBodyArea = max(worstBodyArea, bi.width * bi.height); worstBody = max(worstBody, frac)
                    if o.sim.centroid().z < litActor.sim.centroid().z - 0.02 { worstBehind = max(worstBehind, frac) } else { worstFront = max(worstFront, frac) }
                }
            }
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
        XCTAssertGreaterThan(beatLit, 30, "the light stays on through the score beat (entrants and the player)")
        XCTAssertEqual(windowTargetMisses, 0, "the light's target is the performer for his whole window")
        XCTAssertEqual(gapViolations, 0, "the light is off in every gap between turns (fade out within 0.4 s): \(diag)")
        XCTAssertLessThan(maxDist, 0.6, "the lit performer stays within 0.6 of the middle of the stage")
        if !legacy { XCTAssertEqual(worstOverlap, 0, accuracy: 1, "no waiting entrant's face is under the performer or another face (\(size)): \(diag)") }
        print("[ShowSpotlight] \(size) legacy marks \(legacy): body-box overlap by depth: waiter BEHIND the performer worst \(Int(worstBehind * 100)) %, waiter IN FRONT worst \(Int(worstFront * 100)) % (of the waiting body's box)")
        if !legacy { XCTAssertEqual(worstFront, 0, accuracy: 0.0005, "no waiting body stands in front of the performer and is covered by him (\(size))") }
        print("[ShowSpotlight] \(size): worst body-box overlap of a waiting body with the performer: \(Int(worstBody * 100)) % of the waiting body's box (face overlap \(worstOverlap) px2), highest centroid while lit \(peakHop)")
        print("[ShowSpotlight] \(size) reach of the lit performer: x \(envLo.x)...\(envHi.x), y \(envLo.y)...\(envHi.y), z \(envLo.z)...\(envHi.z)")
        for (k, e) in envTrick.sorted(by: { $0.key < $1.key }) { print("[ShowSpotlight] reach \(k): x \(e.0.x)...\(e.1.x) y \(e.0.y)...\(e.1.y) z \(e.0.z)...\(e.1.z)") }
        care.show.abort()
    }

    func testWholeTrickRoundPortrait() { wholeRound(size: CGSize(width: 440, height: 956)) }
    func testWholeTrickRoundLandscape() { wholeRound(size: CGSize(width: 956, height: 440)) }
    /// The layout before the spotlight round (landscape rival 0 on (-1.4, 0.4)), measured by the same harness: the overlap numbers to compare with.
    func testWholeTrickRoundLandscapeLegacyMarks() { wholeRound(size: CGSize(width: 956, height: 440), legacy: true) }

    // MARK: the picture of the light, rendered on a clear background

    /// RGBA (premultiplied) pixels of the painter's output on a transparent canvas.
    private func render(level: Double, scale: Double = 1, size: CGSize = CGSize(width: 200, height: 400)) -> (w: Int, h: Int, px: [UInt8])? {
        let sh = ShowSpotlightShape(centre: CGPoint(x: 100, y: 150), halfW: 30, halfH: 40, floor: CGPoint(x: 100, y: 200))
        let view = Canvas { ctx, sz in ShowSpotlightPainter.paint(&ctx, size: sz, shape: sh, level: level, scale: scale) }.frame(width: size.width, height: size.height)
        let r = ImageRenderer(content: view); r.scale = 1
        guard let cg = r.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let c = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (w, h, px)
    }
    private func alpha(_ i: (w: Int, h: Int, px: [UInt8]), _ x: Int, _ y: Int) -> Int { Int(i.px[(y * i.w + x) * 4 + 3]) }

    /// With the light off the layer draws NOTHING (every pixel transparent), so the picture under it is the old build's picture exactly; fully on, the dim is 40% outside the hole and 0 over the body.
    func testOffDrawsNothingAndOnDimsOutsideTheHole() throws {
        let off = try XCTUnwrap(render(level: 0))
        XCTAssertEqual(off.px.filter { $0 != 0 }.count, 0, "level 0: not one pixel is touched")
        let tiny = try XCTUnwrap(render(level: 0.0005))
        XCTAssertEqual(tiny.px.filter { $0 != 0 }.count, 0, "an invisible level draws nothing either")
        let on = try XCTUnwrap(render(level: 1))
        let corner = alpha(on, 4, 396)          // far from the body: the dim alone (0.40 of 255)
        XCTAssertEqual(Double(corner), 0.40 * 255, accuracy: 4, "dim strength outside the light")
        XCTAssertEqual(alpha(on, 100, 150), 0, "over the middle of his body: clear")
        XCTAssertEqual(alpha(on, 100 + 28, 150), 0, "over the edge of his body: clear")
        XCTAssertEqual(alpha(on, 100, 150 + 38), 0, "over his feet end of the body: clear")
        let dance = try XCTUnwrap(render(level: 1, scale: ShowSpotlightShape.danceScale))
        XCTAssertEqual(Double(alpha(dance, 4, 396)), 0.40 * 0.75 * 255, accuracy: 4, "the dance light is gentler")
        // the half level (mid fade) is half the dim
        let half = try XCTUnwrap(render(level: 0.5))
        XCTAssertEqual(Double(alpha(half, 4, 396)), 0.40 * 0.5 * 255, accuracy: 4)
    }

    /// The light layer is a clear view while the light is fully off (no TimelineView, no frames): `isOn` is the one test the view makes.
    func testLayerOnlyDrawsWhileTheLightShowsOrFades() {
        var s = ShowSpotlightState()
        XCTAssertFalse(s.isOn)
        s.step(target: 1, dt: 1 / 60); XCTAssertTrue(s.isOn)
        for _ in 0..<60 { s.step(target: 1, dt: 1 / 60) }
        XCTAssertTrue(s.isOn)
        for _ in 0..<12 { s.step(target: nil, dt: 1 / 60) }
        XCTAssertTrue(s.isOn, "fading out: still drawn")
        for _ in 0..<30 { s.step(target: nil, dt: 1 / 60) }
        XCTAssertFalse(s.isOn, "fade over: clear again")
    }
}
