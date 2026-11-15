//
//  WearGoldenTests.swift
//  Pins what WearMeshes.prepare produces for every look (and the species' art variants and a Circuit bib): everything WearLevel.finalize writes (lvDir, lvExcess, lvY0, the rest surface point of
//  lvBind / clusterLvBind, the cluster and node arrays) plus the surface binds the build makes (p.rest, p.bind, clusterBind, crown). The redone art was approved by eye against exactly this
//  output, so a speed-up of WearBody.radialHit / bind must not move it.
//
//  WEARGOLDEN_DIR (TEST_RUNNER_WEARGOLDEN_DIR) = a folder. A look's golden file there is COMPARED (fail above 0.2 mm in a position or length, 1e-4 in a direction or barycentric,
//  exact for integers and flags); a missing one is WRITTEN. Without the variable the test skips.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WearGoldenTests: XCTestCase {
    private func f(_ x: Float) -> String { String(format: "%.9g", x) }
    private func f3(_ v: SIMD3<Float>) -> String { "\(f(v.x)) \(f(v.y)) \(f(v.z))" }
    private func f2(_ v: SIMD2<Float>) -> String { "\(f(v.x)) \(f(v.y))" }

    /// Lines "KIND name index values..." (D direction 1e-4, P position / length 2e-4, I integer / flag exact).
    static func lines(_ p: WearPrepared, body: WearBody) -> [String] {
        func f(_ x: Float) -> String { String(format: "%.9g", x) }
        func f3(_ v: SIMD3<Float>) -> String { "\(f(v.x)) \(f(v.y)) \(f(v.z))" }
        func f2(_ v: SIMD2<Float>) -> String { "\(f(v.x)) \(f(v.y))" }
        var o: [String] = []
        o.append("I levelPiece 0 \(p.levelPiece ? 1 : 0)")
        o.append("I count 0 \(p.rest.count) \(p.partNames.count) \(p.nodeBind.count)")
        o.append("P tiltFrontY 0 \(f(p.tiltFrontY))")
        for i in p.rest.indices {
            o.append("P rest \(i) \(f3(p.rest[i]))")
            o.append("I bindTri \(i) \(p.bind[i].tri.x) \(p.bind[i].tri.y) \(p.bind[i].tri.z)")
            o.append("D bindBary \(i) \(f3(p.bind[i].bary))")
            o.append("P bindOff \(i) \(f3(p.bind[i].off))")
            o.append("P bindW \(i) \(f(p.w[i]))")
        }
        for (i, c) in p.crown.enumerated() { o.append("P crown \(i) \(f(c))") }
        for k in p.clusterRep.indices { o.append("I clusterRep \(k) \(p.clusterRep[k])"); if p.clusterRep[k] >= 0 { o.append("P clusterCentreFoot \(k) \(f3(body.restFoot(p.clusterBind[k])))") } }
        guard p.levelPiece else { return o }
        for i in p.rest.indices {
            o.append("I level \(i) \(p.level[i] ? 1 : 0)")
            o.append("D lvDir \(i) \(f2(p.lvDir[i]))")
            o.append("P lvExcess \(i) \(f(p.lvExcess[i]))")
            o.append("P lvY0 \(i) \(f(p.lvY0[i]))")
            if p.level[i] { o.append("P lvFoot \(i) \(f3(body.restFoot(p.lvBind[i])))") }
            o.append("I lvNode \(i) \(p.lvNode[i])")
        }
        for k in p.partNames.indices {
            o.append("I clusterLevel \(k) \(p.clusterLevel[k] ? 1 : 0)")
            o.append("D clusterDir \(k) \(f2(p.clusterDir[k]))")
            o.append("P clusterExcess \(k) \(f(p.clusterExcess[k]))")
            o.append("P clusterY0 \(k) \(f(p.clusterY0[k]))")
            if p.clusterLevel[k] { o.append("P clusterLvFoot \(k) \(f3(body.restFoot(p.clusterLvBind[k])))") }
            o.append("I clusterNode \(k) \(p.clusterNode[k])")
        }
        for j in p.nodeBind.indices {
            o.append("I nodeVertex \(j) \(p.nodeVertex[j]) \(p.nodeCluster[j])")
            o.append("P nodeFoot \(j) \(f3(body.restFoot(p.nodeBind[j])))")
            o.append("P nodeY0 \(j) \(f(p.nodeY0[j]))")
            o.append("D nodeDir \(j) \(f2(p.nodeDir[j]))")
            o.append("P nodeRho0 \(j) \(f(p.nodeRho0[j]))")
            o.append("I nodeNbr \(j) \(p.nodeNbr[j].map(String.init).joined(separator: " "))")
        }
        return o
    }

    func testPreparedOutputIsPinned() throws {
        guard let dir = ProcessInfo.processInfo.environment["WEARGOLDEN_DIR"] else { throw XCTSkip("WEARGOLDEN_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        WearBody.install(MotionRig.renderMesh)
        let body = WearBody.shared
        var cases: [(String, () -> WearPrepared?)] = []
        for l in WearLook.allCases where !l.art.isEmpty { cases.append((l.rawValue, { WearMeshes.prepare(l, body: body) })) }
        for l in WearLook.allCases where ["backpack_sky", "cape_hero", "vest_puffer", "cardigan_cable", "tutu_pink"].contains(l.art) {
            cases.append(("\(l.rawValue)__\(l.art)_pip", { WearMeshes.prepare(l, body: body, art: l.art + "_pip") }))
        }
        cases.append(("bib_sky-12", { WearMeshes.bib(team: .sky, number: 12, body: body) }))
        var wrote = 0, compared = 0, failures: [String] = []
        var report = ""
        for (name, make) in cases {
            WearMeshes.clearCache()
            guard let p = make() else { continue }
            let mine = Self.lines(p, body: body)
            let path = dir + "/\(name).golden"
            if let old = try? String(contentsOfFile: path, encoding: .utf8) {
                compared += 1
                let theirs = old.split(separator: "\n", omittingEmptySubsequences: false).dropLast(old.hasSuffix("\n") ? 1 : 0).map(String.init)
                var worst: Float = 0, worstAt = "", bad = 0, firstBad = ""
                if theirs.count != mine.count { bad += 1; firstBad = "line count \(theirs.count) golden vs \(mine.count) now" }
                for (a, b) in zip(theirs, mine) {
                    let ta = a.split(separator: " "), tb = b.split(separator: " ")
                    guard ta.count == tb.count, ta.prefix(3) == tb.prefix(3) else { bad += 1; if firstBad.isEmpty { firstBad = "\(a)  |  \(b)" }; continue }
                    if ta[0] == "I" { if ta != tb { bad += 1; if firstBad.isEmpty { firstBad = "\(a)  |  \(b)" } }; continue }
                    let tol: Float = ta[0] == "D" ? 1e-4 : 2e-4
                    for k in 3..<ta.count {
                        let d = abs((Float(ta[k]) ?? .nan) - (Float(tb[k]) ?? .nan))
                        if d > worst { worst = d; worstAt = "\(ta[1]) \(ta[2])" }
                        if !(d <= tol) { bad += 1; if firstBad.isEmpty { firstBad = "\(a)  |  \(b)" } }
                    }
                }
                report += String(format: "%@: %d lines, %d bad, max diff %.6f at %@\n", name, mine.count, bad, worst, worstAt)
                if bad > 0 { failures.append("\(name): \(bad) differences, first: \(firstBad)") }
            } else {
                try (mine.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
                wrote += 1
            }
        }
        print("WEARGOLDEN wrote \(wrote), compared \(compared)\n" + report)
        try? report.write(toFile: dir + "/compare_report.txt", atomically: true, encoding: .utf8)
        for m in failures { XCTFail(m) }
    }
}
