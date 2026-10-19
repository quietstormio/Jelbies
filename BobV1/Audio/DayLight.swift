//
//  DayLight.swift
//  The room's light for a time of day, as plain uniforms (no new passes): window sky colours (+ stars at night), key light colour,
//  ambient tint, the table lamp's glow and how much the Jellies' key light is dialled down. Every value is a weighted blend of four
//  phase keyframes by `DayBlend`, so it moves continuously. The DAY keyframe is the identity (sky mix 0, white-ish key, ambient x1, lamp off),
//  which is exactly the room as it looked before day / night existed.
//

import Foundation
import simd

nonisolated struct DayLight: Equatable, Sendable {
    var sky0 = SIMD4<Float>(0, 0, 0, 0)               // rgb window sky at the top, w = star amount
    var sky1 = SIMD4<Float>(0, 0, 0, 0)               // rgb window sky at the horizon, w = sky mix (0 = the palette pane)
    var keyCol = SIMD4<Float>(1, 0.95, 0.88, 0)       // rgb key light colour
    var ambCol = SIMD4<Float>(1, 1, 1, 1)             // rgb ambient tint, w = ambient multiplier
    var lamp = SIMD4<Float>(1.0, 0.68, 0.35, 0)       // rgb lamp light colour, w = glow amount 0...1
    var lampPos = SIMD4<Float>(RoomLayout.table.centre.x, 1.0, RoomLayout.table.centre.y, 2.4)    // xyz lamp, w = pool radius
    /// Multiplier on the Jellies' key light intensity (their shader is untouched; only this scalar changes).
    var jellyMul: Float = 1

    static let day = DayLight()

    private struct Key {
        var top: SIMD3<Float>, bottom: SIMD3<Float>, sky: Float, stars: Float
        var key: SIMD3<Float>, amb: SIMD3<Float>, ambMul: Float, lamp: Float, jelly: Float
    }
    private static let morning = Key(top: SIMD3(0.50, 0.66, 0.98), bottom: SIMD3(1.10, 0.66, 0.40), sky: 0.92, stars: 0,
                                     key: SIMD3(1.0, 0.80, 0.60), amb: SIMD3(1.0, 0.93, 0.88), ambMul: 0.96, lamp: 0.12, jelly: 0.97)
    private static let dayKey = Key(top: .zero, bottom: .zero, sky: 0, stars: 0,
                                    key: SIMD3(1.0, 0.95, 0.88), amb: SIMD3(1, 1, 1), ambMul: 1, lamp: 0, jelly: 1)
    private static let evening = Key(top: SIMD3(0.42, 0.34, 0.66), bottom: SIMD3(1.25, 0.50, 0.16), sky: 0.96, stars: 0.1,
                                     key: SIMD3(1.0, 0.60, 0.32), amb: SIMD3(1.0, 0.80, 0.72), ambMul: 0.9, lamp: 0.75, jelly: 0.9)
    private static let night = Key(top: SIMD3(0.012, 0.022, 0.10), bottom: SIMD3(0.075, 0.10, 0.26), sky: 1, stars: 1,
                                   key: SIMD3(0.52, 0.64, 1.0), amb: SIMD3(0.62, 0.68, 1.0), ambMul: 0.66, lamp: 1, jelly: 0.74)

    /// The light at `hour`, quantised to a minute so the room cache is rebuilt at most once a minute on the real clock.
    static func at(hour: Double, quantise: Bool = true) -> DayLight {
        let h = quantise ? (DayMath.wrap(hour) * 60).rounded() / 60 : DayMath.wrap(hour)
        return make(DayBlend(hour: h))
    }

    static func make(_ b: DayBlend) -> DayLight {
        let m = Float(b.morning), d = Float(b.day), e = Float(b.evening), n = Float(b.night)
        func mix3(_ f: (Key) -> SIMD3<Float>) -> SIMD3<Float> { f(morning) * m + f(dayKey) * d + f(evening) * e + f(night) * n }
        func mix1(_ f: (Key) -> Float) -> Float { f(morning) * m + f(dayKey) * d + f(evening) * e + f(night) * n }
        var l = DayLight()
        // the sky mixes toward its colours; its own brightness weights are ignored where sky = 0 (the day pane), so blend colours by sky weight
        let ws = (m * morning.sky, d * dayKey.sky, e * evening.sky, n * night.sky)
        let wsum = max(ws.0 + ws.1 + ws.2 + ws.3, 1e-4)
        let top = (morning.top * ws.0 + evening.top * ws.2 + night.top * ws.3) / wsum
        let bottom = (morning.bottom * ws.0 + evening.bottom * ws.2 + night.bottom * ws.3) / wsum
        l.sky0 = SIMD4(top, mix1 { $0.stars })
        l.sky1 = SIMD4(bottom, mix1 { $0.sky })
        l.keyCol = SIMD4(mix3 { $0.key }, 0)
        l.ambCol = SIMD4(mix3 { $0.amb }, mix1 { $0.ambMul })
        l.lamp.w = mix1 { $0.lamp }
        l.jellyMul = mix1 { $0.jelly }
        return l
    }
}
