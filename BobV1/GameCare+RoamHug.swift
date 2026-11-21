//
//  GameCare+RoamHug.swift
//  Capture aid (dev arguments only): `-GameAction roamhug` stands the Jelmiko at the very edges the roam floor allows beside the HUD buttons (the left and right ends of a front row's free span, and the
//  front middle), still, so a screenshot shows how close a body may come to a button (space-fix-r1).
//

import Foundation
import simd

extension GameCare {
    func roamHug() {
        guard DevArgs.enabled, let rf = GameCamera.roamFloor, rf.zs.count > 6 else { return }
        let actors = raceBook.actors
        let row = rf.zs.count - 4          // a row inside the left button's height, where the cut is
        let spans = rf.railFree.isEmpty ? rf.free[row] : rf.railFree[row]
        guard let lo = spans.map(\.lowerBound).min(), let hi = spans.map(\.upperBound).max() else { return }
        let last = rf.zs.count - 1
        let mid = rf.free[last].first { $0.contains(0) }.map { ($0.lowerBound + $0.upperBound) / 2 } ?? 0
        var spots: [SIMD2<Float>] = [SIMD2(lo, rf.zs[row]), SIMD2(hi, rf.zs[row]), SIMD2(mid, rf.zs[last])]
        // the left one one step nearer the camera if there is one body to place there: the bottom-left button column is tallest
        if let k = rf.zs.indices.last(where: { !rf.railFree[$0].isEmpty && (rf.railFree[$0].map(\.lowerBound).min() ?? 0) > -rf.hw[$0] + 0.3 }), k != row { spots[0] = SIMD2(rf.railFree[k].map(\.lowerBound).min() ?? lo, rf.zs[k]) }
        NSLog("[roamhug] spots %@ (row %d of %d, railFree %d)", "\(spots)", row, rf.zs.count, rf.railFree.count)
        for (i, a) in actors.enumerated() where i < spots.count {
            rehome(a, at: spots[i])
            a.brain?.autonomy = false
        }
    }
}
