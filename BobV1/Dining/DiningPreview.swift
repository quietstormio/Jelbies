//
//  DiningPreview.swift
//  DEBUG-only launch arg `-DiningPreview 1`: loops pop-in -> hold -> poof-out of the serving tray for N = 1, then 2, then 3 Blobs,
//  each with berries, pizza (3 slices each), water (a straw per Blob) and soda (a straw per Blob), 4 s per set.
//  Bob stands at place 0 (the tray is positioned from his spot, nudged only if that would leave the screen); the other places show
//  only through their straws, forks and servings. `-DiningClockStart <s>` jumps into the loop, `-DiningTimeScale 0.2` slows it,
//  `-BlobNoWander 1` keeps Bob parked, `-DiningThree 1` draws the other Blobs of N >= 2 (rest mesh stand-ins), `-DiningHold 1` freezes each set at 1.0 s (tray up, no bite) for stills.
//

#if DEBUG || DINING_PREVIEW
import Foundation
import simd

final class DiningPreview {
    let mode: Int
    private var clock: Float = 0
    private var lastIdx = -1
    nonisolated deinit {}

    static let setSeconds: Float = 4
    static let sets: [(Consumable, Int)] = (1...3).flatMap { n in [Consumables.berries, Consumables.pizza, Consumables.water, Consumables.soda].map { ($0, n) } }
    static var loop: Float { setSeconds * Float(sets.count) }

    static func fromLaunchArguments() -> DiningPreview? {
        let m = UserDefaults.standard.integer(forKey: "DiningPreview")
        return m > 0 ? DiningPreview(mode: m) : nil
    }
    init(mode: Int) {
        self.mode = mode; clock = Float(UserDefaults.standard.double(forKey: "DiningClockStart"))
        DiningModels.previewGhosts = UserDefaults.standard.bool(forKey: "DiningThree")      // N >= 2: Bob is Blob #1, the others are rest-mesh stand-ins
    }

    private func pose(_ p: SIMD3<Float>, yaw: Float = 0, pitch: Float = 0) -> simd_float4x4 {
        var m = DiningModels.translation(.zero, yaw: yaw)
        let c = cosf(pitch), s = sinf(pitch)
        let rx = simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, c, s, 0), SIMD4(0, -s, c, 0), SIMD4(0, 0, 0, 1)))
        m = m * rx
        m.columns.3 = SIMD4(p, 1)
        return m
    }
    private func smoothstep01(_ x: Float) -> Float { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }

    /// Tray centre so that place 0 is where Bob stands, moved toward the front spot only as far as needed to stay on screen.
    private func origin(for layout: TrayLayout, bob: SIMD2<Float>) -> SIMD2<Float> {
        let want = bob - layout.places[0].rel
        for k in 0...20 {
            let o = simd_mix(want, DiningSpot.preferred, SIMD2(repeating: Float(k) / 20))
            if DiningSpot.onScreen(origin: o, layout: layout, aspect: GameCamera.aspect) { return o }
        }
        return DiningSpot.preferred
    }

    func tick(dining: DiningSet, bob: SIMD2<Float>, dt: Float) {
        let ts = UserDefaults.standard.double(forKey: "DiningTimeScale")
        let scale: Float = ts > 0 ? Float(ts) : 1
        if ts > 0 { dining.timeScale = Float(ts) }
        clock += dt * scale
        if UserDefaults.standard.bool(forKey: "DiningHold") {                // still frames: stay at 1.0 s into the set (tray up, nobody eating)
            let base = (clock / Self.setSeconds).rounded(.down) * Self.setSeconds
            clock = base + min(clock - base, 1.0)
        }
        let c = clock.truncatingRemainder(dividingBy: Self.loop)
        let idx = Int(c / Self.setSeconds), u = c - Float(idx) * Self.setSeconds
        let (serving, n) = Self.sets[idx]
        let layout = DiningLayout.make(n: n)
        if idx != lastIdx {
            let jump = lastIdx < 0
            lastIdx = idx
            dining.reset()
            if jump && u > 0.7 {                                                // jumped into the middle: the tray is already up
                dining.spawn(serving: serving, n: n, bobAt: bob, forcedOrigin: origin(for: layout, bob: bob)); dining.update(dt: 0.6)
            }
        }
        if dining.phase == .absent && u >= 0.4 && u < 3.0 && dining.puffs.isActive == false && dining.totalBitesLeft >= 0 && !spawnedThisSet(idx) {
            dining.spawn(serving: serving, n: n, bobAt: bob, forcedOrigin: origin(for: layout, bob: bob))
            spawned = idx
        }
        if u >= 3.0 && u < 3.3 && dining.isPresent && dining.phase != .poofing { dining.despawn() }
        // place 0 (Bob) takes a bite: the berry / forkful lifts toward his mouth
        guard dining.phase == .present, serving.kind == .food else { return }
        let mouth = dining.places[0].mouth
        if u > 1.2 && u < 2.7 {
            let k = smoothstep01((u - 1.2) / 1.1)
            if serving.eatStyle == .finger {
                if dining.pieceInHand[0] == nil && dining.bitesLeft[0] == 3 { dining.beginBite(place: 0) }
                if let j = dining.pieceInHand[0] {
                    let a = dining.pieceAnchorWorld(place: 0, index: j)
                    dining.hold(.piece, place: 0, transform: pose(simd_mix(a, mouth - SIMD3(0.05, 0.04, 0.0), SIMD3(repeating: k))))
                }
            } else {
                let rest = dining.forkRestWorld(place: 0)
                let c0 = SIMD3<Float>(dining.origin.x, DiningDims.plateFloorY + 0.1, dining.origin.y)
                let tipToGrip = -DiningModels.forkTip                                  // the grip is behind the tines
                let over = c0 + SIMD3(0, 0.02, -0.12) + tipToGrip
                let up = mouth + SIMD3(0.0, 0.0, 0.0) + tipToGrip
                let p0 = simd_mix(rest.pos, over, SIMD3(repeating: smoothstep01((u - 1.2) / 0.5)))
                let p = u < 1.8 ? p0 : simd_mix(over, up, SIMD3(repeating: smoothstep01((u - 1.8) / 0.9)))
                let yaw = rest.yaw * (1 - smoothstep01((u - 1.2) / 0.5))
                if u > 1.8 && !dining.forkBite[0] && dining.bitesLeft[0] == 3 { dining.beginBite(place: 0) }
                dining.hold(.fork, place: 0, transform: pose(p, yaw: yaw, pitch: -0.3 * (1 - smoothstep01((u - 1.8) / 0.9))))
            }
        } else if u >= 2.7 {
            if dining.pieceInHand[0] != nil || dining.forkBite[0] { dining.finishBite(place: 0) }
            dining.release(.fork, place: 0)
        }
    }

    private var spawned = -1
    private func spawnedThisSet(_ idx: Int) -> Bool { spawned == idx }
}
#endif
