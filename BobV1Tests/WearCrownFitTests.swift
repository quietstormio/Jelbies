//
//  WearCrownFitTests.swift
//  Head wear never lets the head show through: every hat that encloses the head top is fitted to the DRAWN skin each frame (CrownFit), through
//  hop-like stretches, squashes, tips and sudden changes (the skin lags the rigid pose). Independent check: a vertical ray from each skinned head-cap
//  vertex must meet the emitted hat surface above it. Also: Pip's spines, Moss's daisy and Lavender's wings never vanish under worn items.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WearCrownFitTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    func rig() -> JellyActor {
        let w = WearTests(); let (_, actors) = w.room(1)
        return actors[0]
    }
    func skin(_ a: JellyActor) -> [Float] {
        var d = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
        a.skinner.update(x: a.sim.x, index: MotionRig.renderMesh.index, into: &d)
        return d
    }

    /// Cap vertices with no hat surface above them although hat surface lies below them in the same column.
    func pokes(_ m: RoomMesh, skin sk: [Float], body: WearBody) -> (n: Int, gap: Float) {
        var n = 0
        var gap = Float.infinity
        for (k, i) in body.capIndices.enumerated() where k % 5 == 0 {
            let v = SIMD3(sk[6 * i], sk[6 * i + 1], sk[6 * i + 2])
            var above = false, below = false
            var t = 0
            while t + 2 < m.indices.count {
                let a = m.vertices[Int(m.indices[t])].pos, b = m.vertices[Int(m.indices[t + 1])].pos, c = m.vertices[Int(m.indices[t + 2])].pos
                t += 3
                let d = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
                if abs(d) < 1e-9 { continue }
                let u = ((b.z - c.z) * (v.x - c.x) + (c.x - b.x) * (v.z - c.z)) / d
                let w = ((c.z - a.z) * (v.x - c.x) + (a.x - c.x) * (v.z - c.z)) / d
                if u < 0 || w < 0 || u + w > 1 { continue }
                let y = u * a.y + w * b.y + (1 - u - w) * c.y
                if y >= v.y { above = true; if y - v.y < gap, y - v.y < 0.2 { gap = y - v.y } } else { below = true }
            }
            if below && !above { n += 1 }
        }
        return (n, gap)
    }

    /// Hats whose crown hugs the head (a cone / pouf / top hat towers over it by design).
    static let snug: Set<WearLook> = [.bucketHat, .bucketHatPink, .pirateHat, .cowboyHat, .beanieHoney, .beaniePink, .capTeamPink, .capTeamSky, .beret]

    func run(fit: Bool) -> (worst: Int, total: Int, hats: Int, gap: Float) {
        CrownFit.enabled = fit
        defer { CrownFit.enabled = true }
        let a = rig()
        let body = WearBody.shared
        var worst = 0, total = 0, hats = 0, gap: Float = 0
        let hatLooks = WearLook.pieces.filter { $0.slot == .head && WearMeshes.prepare($0, body: body)?.crownEnclosing == true }
        hats = hatLooks.count
        // a stretch / squash / tip sequence with sudden changes (the soft skin lags the rigid pose)
        let seq: [(Float, Float)] = [(1.3, 0), (0.75, 0.2), (1.25, -0.2), (1.35, 0.3), (0.8, 0)]
        for look in hatLooks {
            let w = WornSet(); w.body = body; w.soundOn = false; Self.keep.append(w)
            for (sq, pitch) in seq {
                a.sim.attractor.squash = sq
                a.sim.attractor.rotation = simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
                for _ in 0..<4 { a.sim.step() }
                a.brain?.currentPose(a.sim)
                w.tick(id: 0, brain: a.brain!, sim: a.sim, outfit: [look.slot: look], role: .none, hideAll: false, dt: 1.0 / 60)
                w.syncCarry(0, sim: a.sim)
                let sk = skin(a)
                let m = sk.withUnsafeBufferPointer { p in w.frame(theme: RoomTheme(), hidden: false, time: 0.3) { _ in p.baseAddress }.opaque }
                let r = pokes(m, skin: sk, body: body)
                worst = max(worst, r.n); total += r.n
                if r.gap.isFinite, pitch == 0, Self.snug.contains(look) { gap = max(gap, r.gap) }
            }
        }
        return (worst, total, hats, gap)
    }

    func testEnclosingHatsAreFoundAndStayPutAtRest() {
        let body = WearBody.shared
        let enc = WearLook.pieces.filter { $0.slot == .head && WearMeshes.prepare($0, body: body)?.crownEnclosing == true }
        MotionLog.write("CROWN enclosing hats: \(enc.map(\.art))")
        XCTAssertGreaterThanOrEqual(enc.count, 8)
        for l in [WearLook.bucketHat, .pirateHat, .cowboyHat, .beanieHoney, .witchHat, .tophat, .partyHat, .chefHat, .beret] { XCTAssertTrue(enc.contains(l), "\(l) should enclose the head top") }
    }

    func testNoHatLetsTheHeadShowThrough() {
        let before = run(fit: false), after = run(fit: true)
        MotionLog.write("CROWN pokes before: worst \(before.worst) total \(before.total); after: worst \(after.worst) total \(after.total) over \(after.hats) hats; largest crown-to-skin gap \(after.gap)")
        XCTAssertEqual(after.worst, 0, "the head pokes through a hat even with the crown fit")
        XCTAssertLessThan(after.gap, 0.06, "a hat hovers above the head")
    }

    // MARK: features never vanish under worn items

    func testFeaturesNeverVanishUnderWornItems() {
        let spec = FeatureSpec.shared
        let back = Set(spec.spines.filter { $0.zone == "back" }.map(\.part))
        XCTAssertFalse(back.isEmpty)
        for art in spec.pairs.keys {
            let pip = FeatureCompat.solve(.spines, worn: [art])
            XCTAssertTrue(pip.hiddenParts.isDisjoint(with: back), "\(art) hides a rear spine")
            let moss = FeatureCompat.solve(.daisy, worn: [art])
            XCTAssertFalse(moss.hidden, "\(art) hides the daisy")
            XCTAssertLessThan(FeatureTuning.tuckScale, 1); XCTAssertGreaterThan(FeatureTuning.tuckScale, 0.05)
        }
        for art in ["cowboy_hat", "beret", "propeller_beanie"] { XCTAssertTrue(FeatureCompat.solve(.daisy, worn: [art]).onHat, art) }
    }

    func testPipsHatCoveredSpinesEmergeFromTheBack() {
        let pr = FeatureMeshes.prepare(.spines, body: WearBody.shared)
        XCTAssertNotNil(pr?.part("spike_05")?.emerge); XCTAssertNotNil(pr?.part("spike_04")?.emerge)
        if let e = pr?.part("spike_05")?.emerge { XCTAssertLessThan(e.pivot.y, 0.95); XCTAssertLessThan(e.pivot.z, -0.2) }
    }
}
