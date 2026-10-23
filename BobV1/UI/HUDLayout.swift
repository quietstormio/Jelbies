//
//  HUDLayout.swift
//  Where the side rails sit. In portrait the bottom of the rails is lifted above the band the front row of Jelbies occupies, so a Jelbie at
//  the very front is never under a button.
//

import SwiftUI
import simd

enum HUDTuning {
    /// Portrait: the bottom of the side rails sits this fraction of the screen height above the bottom edge, which is the band the front row of Jelbies
    /// (feet to head + flower/spines) occupies. Set to the smallest value HUDLayoutTests passes with, plus 0.01.
    static let frontBandPortrait: CGFloat = 0.24
    /// Landscape: 0 when the front-corner Jelbies do not reach under the rails; otherwise the band (the test decides).
    static let frontBandLandscape: CGFloat = 0
    static let railGap: CGFloat = 10            // space between buttons in a rail
    static let goOutSize: CGFloat = 56, goOutSizeTight: CGFloat = 46
}

enum HUDLayout {
    /// Bottom padding for the bottom HUD cluster, measured from the bottom safe edge.
    static func lift(size: CGSize, safeBottom: CGFloat, compact: Bool) -> CGFloat {
        compact ? HUDTuning.frontBandLandscape * size.height : max(0, HUDTuning.frontBandPortrait * size.height - safeBottom)
    }

    /// For tests: the screen y (points, top-left origin) of the highest point of a front-row Jelbie whose body reaches into [xLo, xHi] screen points.
    @MainActor static func frontBandTop(aspect: Float, size: CGSize, xRange: ClosedRange<CGFloat>?) -> CGFloat {
        GameCamera.configureRoom(count: 3)
        guard let rf = GameCamera.refreshRoam(aspect: aspect) else { return size.height }
        let cam = GameCamera.camera(aspect: aspect)
        var top = size.height
        let z = rf.maxZ
        let hw = rf.halfWidth(at: z)
        var x = -hw
        while x <= hw + 0.001 {
            let e = GameCamera.roamLateralExtent, h = BobShape.H * 1.25, d: Float = 0.8
            var corners = [SIMD3<Float>]()
            for cx in [x - e, x + e] { for cy in [0, h] { for cz in [z - d, z + d] { corners.append(SIMD3(cx, cy, cz)) } } }
            let pts = Silhouette.project(corners, viewProj: cam.viewProj, size: size)
            if let lo = pts.map(\.x).min(), let hi = pts.map(\.x).max(), let y = pts.map(\.y).min() {
                if xRange == nil || (hi >= xRange!.lowerBound && lo <= xRange!.upperBound) { top = min(top, y) }
            }
            x += 0.1
        }
        return top
    }
}
