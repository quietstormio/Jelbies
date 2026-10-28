//
//  DecorModels+Batch3.swift
//  How the third batch's Blender parts are posed (2026-10-24). Same machinery as the rest of the decor: `DecorAnim` is driven by the Jellies' existing boop /
//  peek / sit hooks (`kick`, `peek`, `sink`, the pinwheel's `spin`), and nothing is rebuilt unless a piece is animating. Animation that belongs to a boop is
//  read from `kickT` (seconds since the boop) while `kick` is alive, so every piece rests in its exported pose when nobody touches it.
//
//    plant stand  fronds sway (boop)             clock         pendulum swings (boop)       pinwheel    spins down (boop, `spin` / `spinAngle`)
//    bubble mach. fan whirrs, 7 bubbles rise     rocking horse rocks on its runners (rolling arc) + tail swish
//    jack-in-box  crank turns, lid flips, clown springs out and falls back     plush bear  squash-and-stretch, head wobble
//    toy piano    keys ripple up the scale       aquarium      fish dart, tails wag, bubbles stream (peek)   easel  canvas sways (peek)
//    cushion pile squashes a little under a sitter
//

import simd
import Foundation

extension DecorModels {
    private typealias Pose = (SIMD3<Float>, SIMD3<Float>, Float) -> (SIMD3<Float>, SIMD3<Float>)

    private static func sm3(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t) }
    private static func turn(_ v: SIMD3<Float>, _ n: SIMD3<Float>, about p: SIMD3<Float>, _ q: simd_quatf) -> (SIMD3<Float>, SIMD3<Float>) { (p + q.act(v - p), q.act(n)) }

    /// The bubble machine's nozzle (bubblemachine.json `nozzle`, `nozzle_dir`).
    static let bubbleNozzle = SIMD3<Float>(0, 0.66, 0.29)
    static let bubbleDir = simd_normalize(SIMD3<Float>(0, 0.435, 0.9))
    /// The horse's runners are an arc of this radius, centred this high (rockinghorse.json `rock_radius`, the runner's 0.05 lift).
    static let horseArcR: Float = 1.3
    static let horseArcY: Float = 1.35
    static let clockPivot = SIMD3<Float>(0, 0.97, 0.205)
    static let canvasPivot = SIMD3<Float>(0, 1.42, 0.03)
    static let pianoWhite: [Float] = (0..<8).map { Float($0) }
    static let pianoBlackAfter = [0, 1, 3, 4, 5]
    /// Seconds since the boop while one is alive (else far past every animation).
    private static func since(_ a: DecorAnim) -> Float { a.kick > 0.002 ? a.kickT : 99 }

    static func addBatch3(_ kind: DecorKind, _ art: DecorMeshes.Art, o: SIMD3<Float>, anim a: DecorAnim, time: Float, uid: Int, into b: RoomMeshBuilder) -> Bool {
        func emit(_ part: DecorMeshes.Part, _ pose: Pose? = nil) { DecorMeshes.emit(part, into: b, offset: o, pose: pose) }
        func all(except: Set<String> = [], _ pose: Pose? = nil) { for part in art.parts where !except.contains(part.name) { emit(part, pose) } }
        let k = min(a.kick, 1.2), t = since(a), ph = Float(uid) * 0.7
        switch kind {
        case .cushionpile:
            let amt = 0.06 * a.sink
            all { v, n, w in (SIMD3(v.x * (1 + 0.3 * amt * w), v.y * (1 - amt * w), v.z * (1 + 0.3 * amt * w)), n) }
        case .plantstand:
            all(except: ["leaves"])
            if let lv = art.part("leaves") {
                let pv = lv.pivot, s1 = k * sinf(time * 20 + ph), s2 = k * sinf(time * 17 + 1.3 + ph)
                emit(lv) { v, n, w in turn(v, n, about: pv, simd_quatf(angle: 0.16 * s1 * w, axis: SIMD3(0, 0, 1)) * simd_quatf(angle: 0.12 * s2 * w, axis: SIMD3(1, 0, 0))) }
            }
        case .clock:
            all(except: ["pendulum"])
            if let pd = art.part("pendulum") {
                let ang = 0.42 * k * sinf(t * 7.5)
                emit(pd) { v, n, _ in turn(v, n, about: clockPivot, simd_quatf(angle: ang, axis: SIMD3(0, 0, 1))) }
            }
        case .easel:
            all(except: ["canvas"])
            if let c = art.part("canvas") {
                let ang = 0.03 * a.peek * sinf(time * 5 + ph) + 0.035 * k * sinf(time * 13 + ph)
                emit(c) { v, n, _ in turn(v, n, about: canvasPivot, simd_quatf(angle: ang, axis: SIMD3(1, 0, 0))) }
            }
        case .aquarium:
            let sw = min(max(a.peek, k), 1)
            all(except: Set(["plants", "fish0", "fish1", "fish2"]))
            if let pl = art.part("plants") {
                let pv = pl.pivot, s1 = (0.04 + 0.06 * sw) * sinf(time * 2.2 + ph)
                emit(pl) { v, n, w in turn(v, n, about: pv, simd_quatf(angle: s1 * w, axis: SIMD3(0, 0, 1))) }
            }
            for i in 0..<3 {
                guard let f = art.part("fish\(i)") else { continue }
                let pv = f.pivot, p = Float(i) * 2.1 + ph, th = time * (1.7 + 0.35 * Float(i)) + p
                let dx = 0.20 * sw * sinf(th), dy = 0.03 * sw * sinf(th * 1.7)
                let yaw = Float.pi * (1 - sm3(-0.25, 0.25, cosf(th))) * sw
                let wag = (0.30 + 0.45 * sw) * sinf(time * 14 + p)
                emit(f) { v, n, w in
                    let r = simd_quatf(angle: wag * w, axis: SIMD3(0, 1, 0)), y = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
                    let (p1, n1) = turn(v, n, about: pv, r)
                    let (p2, n2) = turn(p1, n1, about: pv, y)
                    return (p2 + SIMD3(dx, dy, 0), n2)
                }
            }
            if sw > 0.03 { addBubbles(into: b, o: o, from: SIMD3(-0.30, 0.68, -0.06), rise: 0.66, time: time, count: 5, scale: sw, spread: 0.03) }
        case .bubblemachine:
            all(except: ["fan"])
            if let fan = art.part("fan") {
                let spin = t < 90 ? t * 16 : 0, q = simd_quatf(angle: spin, axis: bubbleDir), pv = fan.pivot
                emit(fan) { v, n, _ in turn(v, n, about: pv, q) }
            }
            if t < 3 { addMachineBubbles(into: b, o: o, t: t) }
        case .rockinghorse:
            let theta = arcTheta(a)
            let c = SIMD3<Float>(0, horseArcY, 0), q = simd_quatf(angle: -theta, axis: SIMD3(0, 0, 1)), roll = SIMD3<Float>(horseArcR * theta, 0, 0)
            func rock(_ v: SIMD3<Float>, _ n: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) { let (p, n2) = turn(v, n, about: c, q); return (p + roll, n2) }
            if let h = art.part("horse") { emit(h) { v, n, _ in rock(v, n) } }
            if let tl = art.part("tail") {
                let pv = tl.pivot, wag = 0.45 * k * sinf(t * 11 + 1)
                emit(tl) { v, n, w in
                    let (p1, n1) = turn(v, n, about: pv, simd_quatf(angle: wag * w, axis: SIMD3(0, 0, 1)))
                    return rock(p1, n1)
                }
            }
        case .jackinbox:
            let thumb = uid == 0           // the shop thumbnail shows the clown popped out
            let lidOpen = thumb ? 1 : sm3(0, 0.10, t) * (1 - sm3(1.35, 1.75, t))
            let ext0 = thumb ? 1 : sm3(0.06, 0.30, t) * (1 - sm3(1.25, 1.65, t))
            let ext = ext0 * (1 + (thumb ? 0 : 0.14 * sinf(t * 20) * expf(-3 * t)))
            all(except: ["crank", "lid", "jester"])
            if let cr = art.part("crank") {
                let ang = 4 * Float.pi * sm3(0, 1.1, t), pv = cr.pivot
                emit(cr) { v, n, _ in turn(v, n, about: pv, simd_quatf(angle: ang, axis: SIMD3(1, 0, 0))) }
            }
            if let lid = art.part("lid") {
                let pv = lid.pivot
                emit(lid) { v, n, _ in turn(v, n, about: pv, simd_quatf(angle: -2.0 * lidOpen, axis: SIMD3(1, 0, 0))) }
            }
            if let j = art.part("jester"), ext > 0.03 {
                let base: Float = 0.46, sway = thumb ? 0 : 0.20 * sinf(t * 12) * expf(-1.6 * t)
                emit(j) { v, n, _ in
                    let wy = min(max((v.y - base) / 0.65, 0), 1)
                    let p = SIMD3(v.x, base + (v.y - base) * ext, v.z)
                    return turn(p, n, about: SIMD3(0, base, 0), simd_quatf(angle: sway * wy, axis: SIMD3(0, 0, 1)))
                }
            }
        case .plushbear:
            let s = 0.12 * k * cosf(t * 14)
            func squash(_ v: SIMD3<Float>, _ n: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
                let w = min(max(v.y / 1.0, 0), 1)
                return (SIMD3(v.x * (1 + 0.5 * s * w), v.y * (1 - s * w), v.z * (1 + 0.5 * s * w)), n)
            }
            if let body = art.part("body") { emit(body) { v, n, _ in squash(v, n) } }
            if let head = art.part("head") {
                let pv = head.pivot, wob = 0.22 * k * sinf(t * 11)
                emit(head) { v, n, _ in
                    let (p1, n1) = turn(v, n, about: pv, simd_quatf(angle: wob, axis: SIMD3(0, 0, 1)))
                    return squash(p1, n1)
                }
            }
        case .toypiano:
            all(except: Set((0..<8).map { "key\($0)" } + (0..<5).map { "bkey\($0)" }))
            func press(_ at: Float) -> Float { 0.15 * sinf(Float.pi * min(max((t - at) / 0.24, 0), 1)) }
            for i in 0..<8 {
                guard let key = art.part("key\(i)") else { continue }
                let ang = press(0.075 * Float(i)), pv = key.pivot
                emit(key) { v, n, _ in turn(v, n, about: pv, simd_quatf(angle: ang, axis: SIMD3(1, 0, 0))) }
            }
            for (j, after) in pianoBlackAfter.enumerated() {
                guard let key = art.part("bkey\(j)") else { continue }
                let ang = press(0.075 * (Float(after) + 0.5)) * 0.8, pv = key.pivot
                emit(key) { v, n, _ in turn(v, n, about: pv, simd_quatf(angle: ang, axis: SIMD3(1, 0, 0))) }
            }
        case .pinwheel:
            all(except: ["wheel"])
            if let w = art.part("wheel") {
                let q = simd_quatf(angle: -a.spinAngle, axis: SIMD3(0, 0, 1)), pv = w.pivot
                emit(w) { v, n, _ in turn(v, n, about: pv, q) }
            }
        default:
            return addBatch4(kind, art, o: o, anim: a, time: time, uid: uid, into: b)          // (the fourth batch; any other kind: all parts as exported)
        }
        return true
    }

    // MARK: soap bubbles (plain opaque spheres: pale, a little tinted, rising and popping)

    /// One bubble: a small low-poly sphere with a pale tint (the room mesh has no transparency).
    private static func bubble(_ b: RoomMeshBuilder, at c: SIMD3<Float>, radius r: Float, tint: Float) {
        guard r > 0.004 else { return }
        let col = cream + (sky + (pink - sky) * tint - cream) * 0.28
        let rows = 5, segs = 8
        var ids: [[UInt32]] = []
        for i in 0...rows {
            let th = Float(i) / Float(rows) * .pi
            var row: [UInt32] = []
            for j in 0...segs {
                let ph = Float(j) / Float(segs) * 2 * .pi
                let n = SIMD3<Float>(sinf(th) * cosf(ph), cosf(th), sinf(th) * sinf(ph))
                row.append(b.vertex(c + n * r, n, ao: 1, color: col))
            }
            ids.append(row)
        }
        for i in 0..<rows { for j in 0..<segs { b.quad(ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]) } }
    }
    /// The aquarium's bubble stream: `count` bubbles rising from `from`, looping every 1.6 s, scaled by `scale`.
    private static func addBubbles(into b: RoomMeshBuilder, o: SIMD3<Float>, from p: SIMD3<Float>, rise: Float, time: Float, count: Int, scale: Float, spread: Float) {
        for i in 0..<count {
            let f = (time * 0.62 + Float(i) / Float(count)).truncatingRemainder(dividingBy: 1)
            let r = (0.016 + 0.010 * Float((i * 7) % 3)) * scale * (1 - sm3(0.9, 1.0, f))
            let c = o + p + SIMD3(spread * sinf(f * 9 + Float(i) * 1.7), rise * f, 0.012 * sinf(f * 7 + Float(i)))
            bubble(b, at: c, radius: r, tint: Float(i % 2))
        }
    }
    /// The bubble machine's burst: bubbles leave the nozzle one after another and rise, wobbling, then pop.
    private static func addMachineBubbles(into b: RoomMeshBuilder, o: SIMD3<Float>, t: Float) {
        for j in 0..<7 {
            let age = t - 0.1 * Float(j)
            guard age > 0, age < 1.2 else { continue }
            let base: Float = 0.06 + 0.035 * Float((j * 7) % 4)
            let r = base * sm3(0, 0.12, age) * (1 - sm3(1.05, 1.2, age))
            let wob = SIMD3<Float>(0.13 * sinf(age * 4 + Float(j) * 1.7), 0, 0.05 * cosf(age * 3 + Float(j)))
            let c = o + bubbleNozzle + bubbleDir * (0.10 + 0.78 * age) + SIMD3(0, 0.34 * age, 0) + wob
            bubble(b, at: c, radius: r, tint: Float(j % 2))
        }
    }
}
