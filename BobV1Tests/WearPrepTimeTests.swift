//
//  WearPrepTimeTests.swift
//  How long the MAIN THREAD spends preparing each worn piece (WearMeshes.prepare: bind, level, finalize) on a cold cache, and what the worn pieces cost per frame.
//  A 2026-11-14 phone build was killed twice by the iOS watchdog (0x8BADF00D) in WearBody.radialHit while a saved outfit was prepared.
//
//  WEARPREP_OUT (TEST_RUNNER_WEARPREP_OUT) = a folder: the tests write prep.tsv / frame.txt there.
//  WEARPREP_CEILING (TEST_RUNNER_WEARPREP_CEILING) = 1: assert every look prepares in < 150 ms and the worst possible outfit in < 400 ms (Release simulator only).
//  Uses only API present on older commits, so the file can be dropped onto an old checkout.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WearPrepTimeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    struct Row { var name: String, slot: String, verts: Int, levelled: Bool, tilted: Bool, ms: Double, firstMs: Double, artMs: Double }

    private func now() -> Double { CACurrentMediaTime() * 1000 }

    /// Every look (and the art variants the species use, and a Circuit bib), prepared on a cold cache: min of 3 cold repeats, art load and the body's own set-up outside the timer.
    func measureRows() -> [Row] {
        WearBody.install(MotionRig.renderMesh)
        let body = WearBody.shared
        var rows: [Row] = []
        var variantArts: [(WearLook, String)] = []
        for l in WearLook.allCases where !l.art.isEmpty && ["backpack_sky", "cape_hero", "vest_puffer", "cardigan_cable", "tutu_pink"].contains(l.art) { variantArts.append((l, l.art + "_pip")) }
        // the first call on the body (the fast path builds its buckets lazily here)
        let w0 = now(); _ = body.radialHit(dir: SIMD2(0, 1), y: 0.5); let warm = now() - w0
        rows.append(Row(name: "_bodyFirstRadialHit", slot: "-", verts: 0, levelled: false, tilted: false, ms: warm, firstMs: warm, artMs: 0))
        func measure(_ name: String, slot: String, art: () -> Void, prep: () -> WearPrepared?) -> Row {
            let a0 = now(); art(); let artMs = now() - a0
            var best = Double.infinity, first = 0.0
            var p: WearPrepared?
            for k in 0..<3 {
                WearMeshes.clearCache()
                let t0 = now(); p = prep(); let ms = now() - t0
                if k == 0 { first = ms }
                best = min(best, ms)
            }
            return Row(name: name, slot: slot, verts: p?.rest.count ?? 0, levelled: p?.levelPiece ?? false, tilted: p?.tilted ?? false, ms: p == nil ? 0 : best, firstMs: first, artMs: artMs)
        }
        for l in WearLook.allCases {
            if l.art.isEmpty { rows.append(Row(name: l.rawValue, slot: "\(l.slot)", verts: 0, levelled: false, tilted: false, ms: 0, firstMs: 0, artMs: 0)); continue }
            rows.append(measure(l.rawValue, slot: "\(l.slot)", art: { _ = WearMeshes.art(l) }, prep: { WearMeshes.prepare(l, body: body) }))
        }
        for (l, v) in variantArts {
            rows.append(measure("\(l.rawValue)|\(v)", slot: "\(l.slot)", art: { _ = WearMeshes.art(v) }, prep: { WearMeshes.prepare(l, body: body, art: v) }))
        }
        rows.append(measure("bib:sky-12", slot: "body", art: { _ = WearMeshes.art(.bibSky) }, prep: { WearMeshes.bib(team: .sky, number: 12, body: body) }))
        return rows
    }

    func testPrepareTimes() throws {
        let rows = measureRows()
        var tsv = "look\tslot\tvertices\tlevelled\ttilted\tprep_ms_min3\tprep_ms_first\tart_load_ms\n"
        for r in rows { tsv += String(format: "%@\t%@\t%d\t%d\t%d\t%.2f\t%.2f\t%.2f\n", r.name, r.slot, r.verts, r.levelled ? 1 : 0, r.tilted ? 1 : 0, r.ms, r.firstMs, r.artMs) }
        print("WEARPREP TSV\n" + tsv)
        if let d = ProcessInfo.processInfo.environment["WEARPREP_OUT"] {
            try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
            try tsv.write(toFile: d + "/prep.tsv", atomically: true, encoding: .utf8)
        }
        let looks = rows.filter { !$0.name.hasPrefix("_") && !$0.name.contains("|") && !$0.name.hasPrefix("bib:") }
        func ms(_ n: String) -> Double { looks.first { $0.name == n }?.ms ?? 0 }
        let phone = ms("diamondJ") + ms("sneakerLightup")
        var worst = 0.0
        for s in ["feet", "head", "face", "neck", "hands", "body"] { worst += looks.filter { $0.slot == s }.map(\.ms).max() ?? 0 }
        let all = looks.reduce(0.0) { $0 + $1.ms }
        let sums = String(format: "phone outfit (diamondJ + sneakerLightup) %.1f ms | worst possible outfit %.1f ms | all looks %.1f ms\n", phone, worst, all)
        print("WEARPREP SUMS " + sums)
        if let d = ProcessInfo.processInfo.environment["WEARPREP_OUT"] { try sums.write(toFile: d + "/sums.txt", atomically: true, encoding: .utf8) }
        if ProcessInfo.processInfo.environment["WEARPREP_CEILING"] == "1" {
            for r in rows where !r.name.hasPrefix("_") { XCTAssertLessThan(r.ms, 150, "\(r.name) prepares in \(r.ms) ms (ceiling 150)") }
            XCTAssertLessThan(worst, 400, "the worst possible outfit prepares in \(worst) ms (ceiling 400)")
            XCTAssertLessThan(phone, 400)
        }
    }

    // MARK: per frame

    private func makeLab() -> SocialTests.Lab {
        let lab = SocialTests.Lab(n: 3, positions: [SIMD2(-0.8, 0.6), SIMD2(0.2, 0.6), SIMD2(1.2, 0.6)], quiet: true, seed: 3)
        SocialTests.keep.append(lab)
        for (id, r) in lab.rigs.enumerated() {
            r.skinner.autoBlink = false
            r.brain.feature = JellyRoster.feature(id); r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
            r.brain.autonomy = false; r.brain.expr.enabled = false
        }
        WearBody.install(MotionRig.renderMesh); SkinField.prepare(MotionRig.renderMesh)
        return lab
    }

    /// WornSet.frame over 600 frames, three Jellies each in a tutu (or the backpack: both are body pieces, one per Jelly) + scarfPlum + wristbandsSky. Report only.
    func testPerFrameCost() throws {
        let lab = makeLab()
        let outfits: [[WearSlot: WearLook]] = [
            [.body: .capeHero, .neck: .scarfPlum, .hands: .wristbandsSky],
            [.body: .backpackSky, .neck: .scarfPlum, .hands: .wristbandsSky],
            [.body: .capeHero, .neck: .scarfPlum, .hands: .wristbandsSky]]
        let set = WornSet(); set.body = WearBody.shared; set.soundOn = false; Self.keep.append(set)
        var skins = [[Float]](repeating: [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6), count: 3)
        func step() {
            lab.tick(watching: false)
            for (i, r) in lab.rigs.enumerated() {
                r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
                set.tick(id: i, brain: r.brain, sim: r.sim, outfit: outfits[i], role: .none, hideAll: false, dt: 1.0 / 60)
                r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &skins[i])
                set.syncCarry(i, sim: r.sim)
                set.setArms(i, GameCare.armFrames(brain: r.brain, sim: r.sim))
            }
        }
        for _ in 0..<60 { step() }
        // one untimed frame first: WornSet.frame prepares each look's mesh the first time it draws it (that cold cost is the prepare table's, not a per-frame cost)
        _ = skins[0].withUnsafeBufferPointer { a in skins[1].withUnsafeBufferPointer { b in skins[2].withUnsafeBufferPointer { c in
            set.frame(theme: RoomTheme(), time: 0.4) { [a.baseAddress, b.baseAddress, c.baseAddress][$0] } } } }
        var total = 0.0, verts = 0
        let frames = 600
        for _ in 0..<frames {
            step()
            let t0 = now()
            let f = skins[0].withUnsafeBufferPointer { a in skins[1].withUnsafeBufferPointer { b in skins[2].withUnsafeBufferPointer { c in
                set.frame(theme: RoomTheme(), time: 0.4) { [a.baseAddress, b.baseAddress, c.baseAddress][$0] } } } }
            total += now() - t0
            verts = f.opaque.vertices.count
        }
        let msPer = total / Double(frames)
        let line = String(format: "WornSet.frame: %.3f ms per frame over %d frames, 3 Jellies, %d vertices drawn per frame\n", msPer, frames, verts)
        print("WEARPREP FRAME " + line)
        if let d = ProcessInfo.processInfo.environment["WEARPREP_OUT"] { try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true); try line.write(toFile: d + "/frame.txt", atomically: true, encoding: .utf8) }
        XCTAssertGreaterThan(verts, 0)
    }
}
