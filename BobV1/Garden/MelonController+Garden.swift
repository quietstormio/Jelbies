//
//  MelonController+Garden.swift
//  A touch in the Garden: the plot under the finger (by its screen circle) or nothing. The stage calls it before the normal touch routing, and only when no
//  Jelbie is under the finger (a Jelbie standing in front of a plot is still pet / picked as usual).
//

import Foundation
import simd

extension MelonController {
    /// True when the touch landed on a plot (and was handled).
    func gardenTap(_ p: CGPoint, _ size: CGSize) -> Bool {
        guard haveCam, size.width > 1, size.height > 1, model.care.gardenAcceptsTaps else { return false }
        let v = lastCam.view
        let right = SIMD3<Float>(v.columns.0.x, v.columns.1.x, v.columns.2.x)
        func screen(_ w: SIMD3<Float>) -> CGPoint? {
            let q = lastCam.viewProj * SIMD4<Float>(w, 1)
            guard q.w > 1e-4 else { return nil }
            return CGPoint(x: CGFloat(q.x / q.w * 0.5 + 0.5) * size.width, y: CGFloat(1 - (q.y / q.w * 0.5 + 0.5)) * size.height)
        }
        var best: (plot: Int, d: CGFloat)?
        for i in 0..<GardenTuning.plotCount {
            let c = GardenLayout.plotCentre(i) + SIMD3<Float>(0, 0.22, 0)
            guard let s = screen(c), let e = screen(c + right * 0.5) else { continue }
            let r = max(abs(e.x - s.x), 34)
            let d = hypot(p.x - s.x, p.y - s.y)
            if d <= r * 1.15, best == nil || d < best!.d { best = (i, d) }
        }
        guard let hit = best else { return false }
        model.care.gardenTapped(plot: hit.plot)
        return true
    }
}
