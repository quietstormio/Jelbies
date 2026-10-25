//
//  DecorModels.swift
//  The decor's real 3D meshes, procedural, in the room's soft toy style and palette (cream #F7F0E0, ink #4D331F, sky #6EB3D1, pink #E98AA4,
//  honey #F9CC59, mint #9FD9B0). One builder per kind writes world-space triangles in the room's own vertex format ("plain" material, vertex colour
//  and baked AO; the night light's shade uses the lamp material so it glows exactly when the table lamp does). The same builder draws the shop and
//  bag thumbnails (at the origin, resting).
//
//  Animation comes from `DecorAnim`: a sat-in beanbag / cushion sinks and dimples, a booped plant's leaves wiggle, the mat dips on a landing, the
//  toy box's toys jump, the ball rolls (its pattern turns with it). Nothing is rebuilt unless a piece changed or is animating.
//

import simd
import Foundation

enum DecorModels {
    private static func hex(_ v: UInt32) -> SIMD3<Float> {
        OKLab.srgbToLinear(SIMD3(Float((v >> 16) & 255) / 255, Float((v >> 8) & 255) / 255, Float(v & 255) / 255))
    }
    static let cream = hex(0xF7F0E0), ink = hex(0x4D331F), sky = hex(0x6EB3D1), pink = hex(0xE98AA4), honey = hex(0xF9CC59), mint = hex(0x9FD9B0)
    private static let leafDark = hex(0x4E9A5E), leafLight = hex(0x9FD9B0)

    /// The whole room's decor in one mesh.
    static func build(feet: [DecorFoot], field: DecorField, time: Float) -> RoomMesh {
        let b = RoomMeshBuilder(); b.material = .plain
        for f in feet {
            let c = f.kind.rolls ? field.position(f) : f.centre, v0 = b.mesh.vertices.count
            add(f.kind, at: c, lift: f.lift, anim: field.anim[f.uid] ?? DecorAnim(), time: time, uid: f.uid, into: b)
            if f.quarter != 0 { turnVertices(&b.mesh, from: v0, about: c, yaw: f.yaw) }
        }
        return b.mesh
    }

    /// Turns the vertices added since `from` about the vertical through `c` (a placed piece's quarter turns; positions and normals).
    static func turnVertices(_ m: inout RoomMesh, from: Int, about c: SIMD2<Float>, yaw: Float) {
        let sn = sinf(yaw), cs = cosf(yaw)
        for i in from..<m.vertices.count {
            let p = m.vertices[i].pos, n = m.vertices[i].normal
            let dx = p.x - c.x, dz = p.z - c.y
            m.vertices[i].pos = SIMD4(c.x + dx * cs + dz * sn, p.y, c.y - dx * sn + dz * cs, p.w)
            m.vertices[i].normal = SIMD4(n.x * cs + n.z * sn, n.y, -n.x * sn + n.z * cs, n.w)
        }
    }

    /// One piece at the origin, resting (thumbnails).
    static func thumbnail(_ kind: DecorKind) -> RoomMesh {
        let b = RoomMeshBuilder(); b.material = .plain
        var a = DecorAnim(); a.peek = kind == .toybox ? 0.6 : 0
        add(kind, at: .zero, lift: 0, anim: a, time: 0.4, uid: 0, into: b)
        return b.mesh
    }

    static func add(_ kind: DecorKind, at p: SIMD2<Float>, lift: Float, anim a: DecorAnim, time: Float, uid: Int, into b: RoomMeshBuilder) {
        b.material = .plain
        if let art = DecorMeshes.loaded[kind], addArt(kind, art, at: p, lift: lift, anim: a, time: time, uid: uid, into: b) { b.material = .plain; return }
        switch kind {
        case .beanbag: beanbag(p, lift, a, b)
        case .cushion: cushion(p, lift, a, b)
        case .plant: plant(p, lift, a, time, uid, b)
        case .ball: ball(p, lift, a, b)
        case .rug: rug(p, b)
        case .toybox: toybox(p, lift, a, time, b)
        case .nightlight: nightlight(p, lift, b)
        case .bouncymat: bouncymat(p, lift, a, b)
        default: break          // (the second batch has no procedural fallback: it is only drawn from its art)
        }
    }

    // MARK: the Blender art (decor_<id>.bin), posed by the same DecorAnim as the procedural builders

    private static func rotated(_ v: SIMD3<Float>, _ n: SIMD3<Float>, about pivot: SIMD3<Float>, _ q: simd_quatf) -> (SIMD3<Float>, SIMD3<Float>) {
        (pivot + q.act(v - pivot), q.act(n))
    }
    /// Squish by weight: y *= 1 - amount*w, xz bulge by `bulge*amount*w`.
    private static func squished(_ amount: Float, bulge: Float) -> (SIMD3<Float>, SIMD3<Float>, Float) -> (SIMD3<Float>, SIMD3<Float>) {
        { v, n, w in
            let sy = 1 - amount * w, sx = 1 + bulge * amount * w
            let nn = simd_normalize(SIMD3(n.x / sx, n.y / sy, n.z / sx))
            return (SIMD3(v.x * sx, v.y * sy, v.z * sx), nn)
        }
    }
    /// How far the toy box's lid is thrown back past its exported pose while he peeks in, and how high the toys jump.
    static func toyLift(_ a: DecorAnim) -> Float { 0.08 * a.peek + 0.10 * a.kick * abs(sinf(a.kickT * 11)) }
    /// The goal net's bulge amount now (0...1, signed: it rings past neutral a little): a goal's `kick` decaying at 2.5 Hz.
    static func netBulge(_ a: DecorAnim) -> Float { min(a.kick, 1) * cosf(2 * .pi * SoccerTuning.netHz * a.kickT) }

    private static func addArt(_ kind: DecorKind, _ art: DecorMeshes.Art, at p: SIMD2<Float>, lift: Float, anim a: DecorAnim, time: Float, uid: Int, into b: RoomMeshBuilder) -> Bool {
        var o = SIMD3<Float>(p.x, lift, p.y)
        switch kind {
        case .beanbag:
            guard let bag = art.part("bag") else { return false }
            DecorMeshes.emit(bag, into: b, offset: o, pose: squished(bagSquish(a), bulge: 0.2))
        case .cushion:
            guard let c = art.part("cushion") else { return false }
            DecorMeshes.emit(c, into: b, offset: o, pose: squished(0.5 * a.sink, bulge: 0.25))
        case .plant:
            guard let pot = art.part("pot"), let lv = art.part("leaves") else { return false }
            DecorMeshes.emit(pot, into: b, offset: o)
            let k = a.kick, pv = lv.pivot
            let s1 = k * sinf(time * 15 + Float(uid) * 0.7), s2 = k * sinf(time * 13 + 1.3 + Float(uid) * 0.7)
            DecorMeshes.emit(lv, into: b, offset: o, pose: { v, n, w in
                let q = simd_quatf(angle: 0.45 * s1 * w, axis: SIMD3(0, 0, 1)) * simd_quatf(angle: 0.34 * s2 * w, axis: SIMD3(1, 0, 0))
                return rotated(v, n, about: pv, q)
            })
        case .ball:
            guard let ball = art.part("ball") else { return false }
            let q = a.rot, pv = ball.pivot
            DecorMeshes.emit(ball, into: b, offset: o, pose: { v, n, _ in rotated(v, n, about: pv, q) })
        case .rug:
            guard let rug = art.part("rug") else { return false }
            o.y = RoomLayout.rugHeight + 0.003                      // just over the big rug (as the procedural one)
            DecorMeshes.emit(rug, into: b, offset: o)
        case .toybox:
            guard let box = art.part("box"), let lid = art.part("lid") else { return false }
            DecorMeshes.emit(box, into: b, offset: o)
            // exported pose = lid open 57 degrees, toys up; a peek throws it a little wider (rotation about game-X through the back hinge)
            let q = simd_quatf(angle: -0.38 * a.peek, axis: SIMD3(1, 0, 0)), pv = lid.pivot
            DecorMeshes.emit(lid, into: b, offset: o, pose: { v, n, _ in rotated(v, n, about: pv, q) })
            let up = toyLift(a)
            for (name, scale) in [("toy_bear", Float(1.0)), ("toy_block", 1.1), ("toy_star", 1.3)] {
                if let t = art.part(name) { DecorMeshes.emit(t, into: b, offset: o + SIMD3(0, up * scale, 0)) }
            }
        case .nightlight:
            guard let base = art.part("base"), let glow = art.part("glow") else { return false }
            DecorMeshes.emit(base, into: b, offset: o)
            DecorMeshes.emit(glow, into: b, offset: o)              // the lamp material: it lights up with the table lamp
        case .bouncymat:
            guard let frame = art.part("frame"), let top = art.part("top") else { return false }
            DecorMeshes.emit(frame, into: b, offset: o)
            let dip = min(a.kick, 1) * abs(sinf(a.kickT * 9)) * 0.05
            DecorMeshes.emit(top, into: b, offset: o, pose: { v, n, w in (SIMD3(v.x, v.y - dip * w, v.z), n) })
        default:
            return addBatch2(kind, art, o: o, anim: a, time: time, uid: uid, into: b)
        }
        return true
    }

    // MARK: the second batch's poses

    /// Seat cushion compression for a sat-in seat (0...1 press): y *= 1 - 0.30 * amount * w about the cushion pivot.
    static func cushionAmount(_ press: Float) -> Float { 0.8 * press }
    static let rockPivot = SIMD3<Float>(0, 1.145, 0) * DecorKind.rockingchair.scale, swingPivot = SIMD3<Float>(0, 2.1, 0) * DecorKind.swing.scale
    /// The rocking chair's angle now (rad about game X) and the swing's.
    static func rockAngle(_ a: DecorAnim) -> Float { 0.14 * sinf(2 * .pi * a.rockT / 1.7) * min(a.rockAmp, 1) }
    static func swingAngle(_ a: DecorAnim) -> Float { 0.22 * sinf(2 * .pi * a.rockT / 2.6) * min(a.rockAmp, 1) }

    /// Where a sitter's base goes on seat `seat` of a piece (piece-local x, y, z; y includes the rug lift): it follows the squash and the rock / sway.
    static func seatPoint(_ kind: DecorKind, seat: Int, anim a: DecorAnim, lift: Float) -> SIMD3<Float> {
        let sp = kind.sitPoints[min(seat, kind.sitPoints.count - 1)]
        var p = sp
        func rel(_ pivot: SIMD3<Float>, _ ang: Float) -> SIMD3<Float> { pivot + simd_quatf(angle: ang, axis: SIMD3(1, 0, 0)).act(sp - pivot) }
        switch kind {
        case .beanbag: p.y = bagSeatY * (1 - bagSquish(a))
        case .pouf: p.y = sp.y * (1 - (0.10 * a.sink + 0.05 * min(a.kick, 1.2) * cosf(a.kickT * 13)))
        case .armchair: let c = 0.34 * kind.scale; p.y = c + (sp.y - c) * (1 - 0.30 * cushionAmount(a.sink))
        case .loveseat: let c = 0.34 * kind.scale; p.y = c + (sp.y - c) * (1 - 0.30 * cushionAmount(seat == 0 ? a.seatSink.x : a.seatSink.y))
        case .diningset: p.y = sp.y * (1 - 0.06 * (seat == 0 ? a.seatSink.x : a.seatSink.y))
        case .rockingchair: p = rel(rockPivot, rockAngle(a))
        case .swing: p = rel(swingPivot, swingAngle(a))
        default: break
        }
        p.y += lift
        return p
    }

    /// The pet bed's mattress top (the sleeper's floor): its lying point, a touch lower while the mattress is pressed.
    static func bedFloor(_ a: DecorAnim, lift: Float) -> Float { lift + 0.02 * DecorKind.petbed.scale + (DecorKind.sleepPoint.y - 0.02 * DecorKind.petbed.scale) * (1 - 0.35 * a.sink) }

    private static func rotX(_ pivot: SIMD3<Float>, _ ang: Float) -> (SIMD3<Float>, SIMD3<Float>, Float) -> (SIMD3<Float>, SIMD3<Float>) {
        let q = simd_quatf(angle: ang, axis: SIMD3(1, 0, 0))
        return { v, n, _ in rotated(v, n, about: pivot, q) }
    }

    private static func addBatch2(_ kind: DecorKind, _ art: DecorMeshes.Art, o: SIMD3<Float>, anim a: DecorAnim, time: Float, uid: Int, into b: RoomMeshBuilder) -> Bool {
        func all(_ pose: ((SIMD3<Float>, SIMD3<Float>, Float) -> (SIMD3<Float>, SIMD3<Float>))? = nil, except: Set<String> = []) {
            for part in art.parts where !except.contains(part.name) { DecorMeshes.emit(part, into: b, offset: o, pose: pose) }
        }
        func squish(_ part: String, _ pose: @escaping (SIMD3<Float>, SIMD3<Float>, Float) -> (SIMD3<Float>, SIMD3<Float>)) {
            if let p = art.part(part) { DecorMeshes.emit(p, into: b, offset: o, pose: pose) }
        }
        let k = a.kick, ph = Float(uid) * 0.7
        switch kind {
        case .loveseat:
            all(except: ["seat"])
            let l = cushionAmount(a.seatSink.x), r = cushionAmount(a.seatSink.y)
            let c0 = 0.34 * kind.scale
            squish("seat") { v, n, w in (SIMD3(v.x, c0 + (v.y - c0) * (1 - 0.30 * (v.x < 0 ? l : r) * w), v.z), n) }
        case .armchair:
            all(except: ["seat"])
            let m = cushionAmount(a.sink)
            let c0 = 0.34 * kind.scale
            squish("seat") { v, n, w in (SIMD3(v.x, c0 + (v.y - c0) * (1 - 0.30 * m * w), v.z), n) }
        case .pouf:
            let amt = 0.10 * a.sink + 0.05 * min(k, 1.2) * cosf(a.kickT * 13)
            squish("pouf") { v, n, w in (SIMD3(v.x * (1 + 0.5 * amt * w), v.y * (1 - amt), v.z * (1 + 0.5 * amt * w)), n) }
        case .rockingchair:
            all(rotX(rockPivot, rockAngle(a)))
        case .swing:
            all(rotX(swingPivot, swingAngle(a)), except: ["stand"])
            if let st = art.part("stand") { DecorMeshes.emit(st, into: b, offset: o) }
        case .diningset:
            all(except: ["stool_l", "stool_r"])
            for (name, press) in [("stool_l", a.seatSink.x), ("stool_r", a.seatSink.y)] {
                squish(name) { v, n, w in (SIMD3(v.x, v.y * (1 - 0.06 * press), v.z), n) }
            }
        case .petbed:
            all(except: ["mat"])
            let amt = 0.35 * a.sink
            let m0 = 0.02 * kind.scale
            squish("mat") { v, n, w in (SIMD3(v.x, m0 + (v.y - m0) * (1 - amt * w), v.z), n) }
        case .bookshelf:
            all(except: ["plant"])
            if let pl = art.part("plant") {
                let s1 = 0.12 * k * sinf(time * 16 + ph), pv = pl.pivot
                DecorMeshes.emit(pl, into: b, offset: o, pose: { v, n, w in rotated(v, n, about: pv, simd_quatf(angle: s1 * w, axis: SIMD3(0, 0, 1))) })
            }
        case .wardrobe:
            all(except: ["door_l", "clothes"])
            if let d = art.part("door_l"), let c = art.part("clothes") {
                let swing = 0.14 * k * sinf(time * 9 + ph) + 0.12 * a.peek, dp = d.pivot
                DecorMeshes.emit(d, into: b, offset: o, pose: { v, n, _ in rotated(v, n, about: dp, simd_quatf(angle: swing, axis: SIMD3(0, 1, 0))) })
                let sw = 0.12 * (k * sinf(time * 12 + ph) + 0.4 * a.peek * sinf(time * 5)), cp = c.pivot
                DecorMeshes.emit(c, into: b, offset: o, pose: { v, n, _ in rotated(v, n, about: cp, simd_quatf(angle: sw, axis: SIMD3(1, 0, 0))) })
            }
        case .monstera:
            all(except: ["leaves"])
            if let lv = art.part("leaves") {
                let pv = lv.pivot, s1 = k * sinf(time * 22 + ph), s2 = k * sinf(time * 19 + 1.3 + ph)
                DecorMeshes.emit(lv, into: b, offset: o, pose: { v, n, w in
                    rotated(v, n, about: pv, simd_quatf(angle: 0.10 * s1 * w, axis: SIMD3(0, 0, 1)) * simd_quatf(angle: 0.08 * s2 * w, axis: SIMD3(1, 0, 0)))
                })
            }
        case .duck:
            let s1 = 0.28 * k * sinf(time * 19 + ph), s2 = 0.20 * k * sinf(time * 17 + 1.1 + ph)
            all({ v, n, w in rotated(v, n, about: .zero, simd_quatf(angle: s1 * (0.35 + 0.65 * w), axis: SIMD3(0, 0, 1)) * simd_quatf(angle: s2 * (0.35 + 0.65 * w), axis: SIMD3(1, 0, 0))) })
        case .drum:
            all(except: ["head"])
            if let h = art.part("head") {
                let dip = 0.05 * k * abs(sinf(time * 19 + ph))
                DecorMeshes.emit(h, into: b, offset: o, pose: { v, n, _ in (SIMD3(v.x, v.y - dip, v.z), n) })
            }
        case .spintop:
            guard let t = art.part("top") else { return false }
            let tilt = DecorField.topTilt(a)
            let axis = SIMD3<Float>(cosf(tilt.axis), 0, sinf(tilt.axis))
            let q = simd_quatf(angle: tilt.angle, axis: axis) * simd_quatf(angle: a.spinAngle, axis: SIMD3(0, 1, 0))
            DecorMeshes.emit(t, into: b, offset: o, pose: { v, n, _ in (q.act(v), q.act(n)) })
        case .toycar:
            let yaw = simd_quatf(angle: a.heading, axis: SIMD3(0, 1, 0))
            for part in art.parts {
                if part.name.hasPrefix("wheel") {
                    let pv = part.pivot, q = simd_quatf(angle: -a.wheel, axis: SIMD3(1, 0, 0))
                    DecorMeshes.emit(part, into: b, offset: o, pose: { v, n, _ in let (p1, n1) = rotated(v, n, about: pv, q); return (yaw.act(p1), yaw.act(n1)) })
                } else {
                    DecorMeshes.emit(part, into: b, offset: o, pose: { v, n, _ in (yaw.act(v), yaw.act(n)) })
                }
            }
        case .yarnball:
            guard let ball = art.part("ball"), let strand = art.part("strand") else { return false }
            let q = a.rot, pv = ball.pivot
            DecorMeshes.emit(ball, into: b, offset: o, pose: { v, n, _ in rotated(v, n, about: pv, q) })
            // the strand trails opposite to the way it rolls (exported pointing toward +x +z)
            let sp = strand.pivot, yaw = simd_quatf(angle: a.heading - .pi / 4, axis: SIMD3(0, 1, 0))
            DecorMeshes.emit(strand, into: b, offset: o, pose: { v, n, _ in
                let c = SIMD3<Float>(0, sp.y, 0)
                return (c + yaw.act(v - c), yaw.act(n))
            })
        case .soccerball:
            guard let ball = art.part("ball") else { return false }
            let q = a.rot, pv = ball.pivot
            DecorMeshes.emit(ball, into: b, offset: o, pose: { v, n, _ in rotated(v, n, about: pv, q) })
        case .minigoal:
            guard let frame = art.part("frame"), let net = art.part("net") else { return false }
            DecorMeshes.emit(frame, into: b, offset: o)
            // the net puffs toward the back (-z) by w * 0.16 * amount and rings down at ~2.5 Hz (the decaying `kick` is the spring back)
            let puff = netBulge(a)
            if abs(puff) < 1e-4 { DecorMeshes.emit(net, into: b, offset: o) }
            else { DecorMeshes.emit(net, into: b, offset: o, pose: { v, n, w in (SIMD3(v.x, v.y, v.z - SoccerTuning.netPush * puff * w), n) }) }
        case .blocks:
            if a.tumbleT < 0 || a.blocks.isEmpty { all(); return true }
            let back: Float = a.tumbleT > 20 ? smooth(20, 21.5, a.tumbleT) : 0           // eases back into the stack
            for (i, part) in art.parts.enumerated() where i < a.blocks.count {
                let blk = a.blocks[i], pv = part.pivot
                let q = simd_quatf(angle: blk.yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: blk.roll, axis: SIMD3(1, 0, 0))
                let c = blk.pos + (pv - blk.pos) * back
                let qq = simd_slerp(q, simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), back)
                DecorMeshes.emit(part, into: b, offset: o, pose: { v, n, _ in (c + qq.act(v - pv), qq.act(n)) })
            }
        default:
            return addBatch3(kind, art, o: o, anim: a, time: time, uid: uid, into: b)          // (the third batch; any other kind: all parts as exported)
        }
        return true
    }

    // MARK: building blocks

    /// A surface of revolution with a per-row / per-segment colour and an outline other than a circle (squircle, ellipse). `pts` runs from the
    /// bottom centre outward and over the top (outward normals are derived).
    private static func lathe(_ b: RoomMeshBuilder, _ c: SIMD2<Float>, pts: [(r: Float, y: Float, ao: Float)], segments N: Int = 36,
                              outline: (Float) -> SIMD2<Float> = { SIMD2(cosf($0), sinf($0)) }, deform: ((SIMD3<Float>) -> SIMD3<Float>)? = nil,
                              color: (Int, Int) -> SIMD3<Float>) {
        var rows: [[UInt32]] = []
        for i in pts.indices {
            let a = pts[max(i - 1, 0)], d = pts[min(i + 1, pts.count - 1)]
            let t = SIMD2<Float>(d.r - a.r, d.y - a.y)
            let nn = simd_length(t) > 1e-6 ? simd_normalize(SIMD2<Float>(t.y, -t.x)) : SIMD2<Float>(0, 1)
            var row: [UInt32] = []
            for j in 0...N {
                let phi = Float(j) / Float(N) * 2 * .pi
                let o = outline(phi)
                let dir = simd_length(o) > 1e-6 ? o / simd_length(o) : SIMD2<Float>(1, 0)
                var pos = SIMD3<Float>(c.x + pts[i].r * o.x, pts[i].y, c.y + pts[i].r * o.y)
                if let deform { pos = deform(pos) }
                let n = simd_normalize(SIMD3<Float>(nn.x * dir.x, nn.y, nn.x * dir.y))
                row.append(b.vertex(pos, n, ao: pts[i].ao, color: color(i, j % N)))
            }
            rows.append(row)
        }
        for i in 0..<(rows.count - 1) { for j in 0..<N { b.quad(rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]) } }
    }

    private static func mixc(_ a: SIMD3<Float>, _ c: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (c - a) * min(max(t, 0), 1) }
    private static func bake(_ y: Float) -> Float { 0.55 + 0.45 * smooth(0, 0.3, y) }

    private static func sphere(_ b: RoomMeshBuilder, centre c: SIMD3<Float>, radius r: Float, rows: Int = 10, segs: Int = 16, scale s: SIMD3<Float> = SIMD3(1, 1, 1),
                               color: (SIMD3<Float>) -> SIMD3<Float>, ao: Float = 1) {
        var ids: [[UInt32]] = []
        for i in 0...rows {
            let th = Float(i) / Float(rows) * .pi
            var row: [UInt32] = []
            for j in 0...segs {
                let ph = Float(j) / Float(segs) * 2 * .pi
                let d = SIMD3<Float>(sinf(th) * cosf(ph), cosf(th), sinf(th) * sinf(ph))
                let n = simd_normalize(d / s)
                row.append(b.vertex(c + d * r * s, n, ao: ao, color: color(d)))
            }
            ids.append(row)
        }
        for i in 0..<rows { for j in 0..<segs { b.quad(ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]) } }
    }

    // MARK: beanbag

    /// How squashed the bag is: pressed down under him while he sits, plus the landing wobble (a squash that rings and dies out).
    private static func bagSquish(_ a: DecorAnim) -> Float { 0.14 * a.sink + 0.06 * min(a.kick, 1.2) * cosf(a.kickT * 13) }
    /// The seat: the lowest point of the hollow in the top, 0.408 above the floor in the Blender bag (seat_point), a little toward the camera.
    static let bagSeatY: Float = 0.408, bagSeatZ: Float = 0.09
    /// Height of the seat right now (his floor while he sits in the bag: it is pressed down and wobbles under him).
    static func beanbagTop(lift: Float, anim a: DecorAnim) -> Float { lift + bagSeatY * (1 - bagSquish(a)) }

    private static func beanbag(_ p: SIMD2<Float>, _ lift: Float, _ a: DecorAnim, _ b: RoomMeshBuilder) {
        // he sits IN the hollow of its top (bottom in the dip, feet out over the front lip): the bag stays whole under him; it is pressed down,
        // bulges out at the sides a little and wobbles when he lands
        let sq = bagSquish(a)
        let R: Float = 0.72 * (1 + 0.6 * sq), H: Float = 0.78 * (1 - sq)
        let y0 = lift
        let seatL = y0 + bagSeatY * (1 - sq)
        let hollow: (SIMD3<Float>) -> SIMD3<Float> = { v in
            let h = (v.y - y0) / H
            guard h > 0.45 else { return v }
            let dx = v.x - p.x, dz = v.z - p.y
            let w = 1 - smooth(0.30, 0.58, hypotf(dx, dz - bagSeatZ))                              // the round hollow
            var target = seatL
            if dz > 0.60 { target = max(seatL - 0.9 * (dz - 0.60), y0 + 0.22) }                       // out over the front lip: a slope down
            let front = (1 - smooth(0.50, 0.78, abs(dx))) * smooth(bagSeatZ, 0.30, dz)               // open to the front (a channel for his feet)
            let k = max(w, front)
            var o = v
            o.y = min(v.y, v.y + (target - v.y) * k)
            return o
        }
        var pts: [(r: Float, y: Float, ao: Float)] = []
        let n = 28
        for k in 0...n {
            let th = Float(k) / Float(n) * .pi
            // a stuffed sack: fullest low down, tapering toward a soft slumped top
            let taper = 1 - 0.30 * smooth(0.40 * .pi, .pi, th)
            let r = R * powf(sinf(th), 0.72) * taper
            var y = y0 + H * (1 - cosf(th)) / 2
            if th > .pi / 2 { y -= 0.07 * H * expf(-powf(r / (R * 0.5), 2)) }                              // the slump on top
            pts.append((max(r, 0), y, bake(y - y0)))
        }
        let panels = 6, segs = 36
        lathe(b, p, pts: pts, segments: segs, deform: hollow) { i, j in
            let th = Float(i) / Float(n) * .pi
            var col = (j / (segs / panels)) % 2 == 0 ? sky : mixc(sky, cream, 0.20)
            if j % (segs / panels) == 0 { col = mixc(col, ink, 0.22) }                                      // the seams
            col = mixc(col, ink, 0.30 * (1 - smooth(0.0, 0.07, th / .pi)))                                  // the dark foot
            return col
        }
        // the carry loop at the back
        b.roundedBox(centre: SIMD3(p.x, y0 + H * 0.80, p.y - R * 0.70), half: SIMD3(0.12, 0.03, 0.045), radius: 0.03, segments: 2, aoFloor: false, color: pink)
    }

    // MARK: cushion

    private static func cushion(_ p: SIMD2<Float>, _ lift: Float, _ a: DecorAnim, _ b: RoomMeshBuilder) {
        let hh: Float = 0.10 * (1 - 0.5 * a.sink)
        let sp = 1 + 0.10 * a.sink
        b.roundedBox(centre: SIMD3(p.x, lift + hh, p.y), half: SIMD3(0.37 * sp, hh, 0.37 * sp), radius: hh * 0.98, segments: 4, aoFloor: false, color: pink)
        // the honey button and the four corner tufts
        sphere(b, centre: SIMD3(p.x, lift + 2 * hh - 0.012, p.y), radius: 0.055, rows: 6, segs: 10, scale: SIMD3(1, 0.5, 1), color: { _ in honey })
        for sx in [Float(-1), 1] { for sz in [Float(-1), 1] {
            sphere(b, centre: SIMD3(p.x + sx * 0.37 * sp, lift + hh, p.y + sz * 0.37 * sp), radius: 0.045, rows: 5, segs: 8, color: { _ in mixc(pink, cream, 0.55) })
        } }
    }

    // MARK: plant

    private static func plant(_ p: SIMD2<Float>, _ lift: Float, _ a: DecorAnim, _ time: Float, _ uid: Int, _ b: RoomMeshBuilder) {
        let y0 = lift
        let pot: [(r: Float, y: Float, ao: Float)] = [(0, y0, 0.6), (0.17, y0, 0.6), (0.21, y0 + 0.03, 0.7), (0.27, y0 + 0.34, 0.95), (0.29, y0 + 0.37, 1), (0.285, y0 + 0.41, 1), (0.255, y0 + 0.42, 0.9), (0.23, y0 + 0.38, 0.6)]
        lathe(b, p, pts: pot, segments: 28) { i, _ in i >= 5 ? honey : mint }
        lathe(b, p, pts: [(0.23, y0 + 0.38, 0.6), (0, y0 + 0.385, 0.7)], segments: 20) { _, _ in hex(0x5A3D28) }
        let w = a.kick
        let count = 8
        for i in 0..<count {
            let az = Float(i) / Float(count) * 2 * .pi + 0.3 * Float(i % 2)
            let len: Float = 0.62 + 0.14 * Float(i % 3)
            let ph = Float(i) * 1.3
            let sway = w * sinf(time * 15 + ph)
            b.leaf(base: SIMD3(p.x, y0 + 0.40, p.y) + SIMD3(cosf(az), 0, sinf(az)) * 0.05, azimuth: az + 0.18 * sway, length: len, width: 0.24,
                   lean: 0.55 + 0.12 * Float(i % 3) + 0.28 * sway, colorBase: leafDark, colorTip: leafLight)
        }
    }

    // MARK: ball

    private static func ball(_ p: SIMD2<Float>, _ lift: Float, _ a: DecorAnim, _ b: RoomMeshBuilder) {
        let r: Float = 0.27
        let inv = a.rot.inverse
        sphere(b, centre: SIMD3(p.x, lift + r, p.y), radius: r, rows: 20, segs: 44, color: { d in
            let l = inv.act(d)
            if abs(l.y) > 0.9 { return cream }
            let sector = Int(floorf((atan2f(l.x, l.z) + .pi) / (.pi / 3)))
            return sector % 3 == 0 ? honey : (sector % 3 == 1 ? pink : sky)
        }, ao: 1)
    }

    // MARK: rug

    private static func rug(_ p: SIMD2<Float>, _ b: RoomMeshBuilder) {
        let ell: (Float) -> SIMD2<Float> = { SIMD2(cosf($0) * 1.46, sinf($0)) }
        let R: Float = 0.65
        let y0 = RoomLayout.rugHeight + 0.004                       // just over the big rug
        // the pad: a soft rounded edge, then flat annuli stacked a hair apart (each runs from its outer edge in, so it faces up)
        lathe(b, p, pts: [(R, y0, 0.6), (R * 1.0, y0 + 0.014, 0.8), (R * 0.985, y0 + 0.024, 1), (0, y0 + 0.024, 1)], segments: 44, outline: ell) { _, _ in pink }
        func ring(_ r0: Float, _ r1: Float, _ y: Float, _ col: SIMD3<Float>) {
            lathe(b, p, pts: [(r1, y, 1), (r0, y, 1)], segments: 44, outline: ell) { _, _ in col }
        }
        ring(R * 0.84, R * 0.94, y0 + 0.027, cream)
        ring(R * 0.66, R * 0.76, y0 + 0.030, sky)
        ring(0, R * 0.46, y0 + 0.033, honey)
    }

    // MARK: toy box

    private static func toybox(_ p: SIMD2<Float>, _ lift: Float, _ a: DecorAnim, _ time: Float, _ b: RoomMeshBuilder) {
        let y0 = lift, hx: Float = 0.50, hz: Float = 0.38, wall: Float = 0.055, h: Float = 0.50
        let inner = hex(0xE7D7B8)
        b.roundedBox(centre: SIMD3(p.x, y0 + 0.02, p.y), half: SIMD3(hx, 0.02, hz), radius: 0.02, segments: 2, aoFloor: false, color: inner * 0.8)
        for s in [Float(-1), 1] {
            b.roundedBox(centre: SIMD3(p.x + s * (hx - wall), y0 + h / 2, p.y), half: SIMD3(wall, h / 2, hz), radius: 0.04, segments: 3, color: honey)
            b.roundedBox(centre: SIMD3(p.x, y0 + h / 2, p.y + s * (hz - wall)), half: SIMD3(hx, h / 2, wall), radius: 0.04, segments: 3, color: s > 0 ? honey : mixc(honey, ink, 0.1))
        }
        // a sky stripe round the front and the rim trim
        b.roundedBox(centre: SIMD3(p.x, y0 + 0.27, p.y + hz - wall + 0.012), half: SIMD3(hx - 0.02, 0.05, wall), radius: 0.03, segments: 2, aoFloor: false, color: sky)
        // the lid stands open at the back
        b.roundedBox(centre: SIMD3(p.x, y0 + h + 0.15, p.y - hz + wall * 0.5), half: SIMD3(hx, 0.17, 0.03), radius: 0.03, segments: 3, aoFloor: false, color: sky)
        // toys: they jump when it is peeked into
        let up = 0.07 * a.peek + 0.10 * a.kick * abs(sinf(a.kickT * 11))
        sphere(b, centre: SIMD3(p.x - 0.22, y0 + 0.30 + up, p.y + 0.02), radius: 0.15, rows: 8, segs: 14, color: { d in d.y > 0.25 ? mixc(pink, cream, 0.4) : pink })
        b.roundedBox(centre: SIMD3(p.x + 0.20, y0 + 0.27 + up * 1.2, p.y - 0.06), half: SIMD3(0.10, 0.10, 0.10), radius: 0.03, segments: 2, aoFloor: false, color: mint)
        // a bunny's ears
        for e in [Float(-1), 1] {
            sphere(b, centre: SIMD3(p.x + 0.02 + e * 0.07, y0 + 0.42 + up * 1.6, p.y + 0.12), radius: 0.06, rows: 6, segs: 10, scale: SIMD3(0.55, 1.9, 0.5), color: { _ in cream })
        }
        sphere(b, centre: SIMD3(p.x + 0.02, y0 + 0.28 + up * 1.4, p.y + 0.12), radius: 0.12, rows: 8, segs: 12, color: { _ in cream })
    }

    // MARK: night light

    private static func nightlight(_ p: SIMD2<Float>, _ lift: Float, _ b: RoomMeshBuilder) {
        let y0 = lift
        lathe(b, p, pts: [(0, y0, 0.6), (0.19, y0, 0.6), (0.20, y0 + 0.02, 0.7), (0.19, y0 + 0.055, 0.9), (0.10, y0 + 0.075, 1), (0.07, y0 + 0.12, 1), (0.065, y0 + 0.26, 0.95)], segments: 24) { i, _ in i < 4 ? mixc(cream, ink, 0.12) : cream }
        // the glowing cap (the lamp material: it lights up with the table lamp)
        b.material = .lamp
        var dome: [(r: Float, y: Float, ao: Float)] = [(0.0, y0 + 0.24, 1), (0.27, y0 + 0.24, 1)]
        for k in 1...10 {
            let th = Float(k) / 10 * .pi / 2
            dome.append((0.27 * cosf(th), y0 + 0.24 + 0.25 * sinf(th), 1))
        }
        lathe(b, p, pts: dome, segments: 28) { _, _ in honey }
        b.material = .plain
        // little pink spots on the cap
        for k in 0..<5 {
            let az = Float(k) * 1.25 + 0.5
            sphere(b, centre: SIMD3(p.x + 0.17 * cosf(az), y0 + 0.40, p.y + 0.17 * sinf(az)), radius: 0.035, rows: 4, segs: 6, scale: SIMD3(1, 0.5, 1), color: { _ in pink })
        }
    }

    // MARK: bouncy mat

    private static func bouncymat(_ p: SIMD2<Float>, _ lift: Float, _ a: DecorAnim, _ b: RoomMeshBuilder) {
        let R: Float = 0.88
        let sq: (Float) -> SIMD2<Float> = { phi in
            let c = cosf(phi), s = sinf(phi)
            let k = 1 / powf(powf(abs(c), 4) + powf(abs(s), 4), 0.25)
            return SIMD2(c * k, s * k)
        }
        let dip = min(a.kick, 1) * abs(sinf(a.kickT * 9)) * 0.045
        let y0 = lift, h: Float = 0.11
        func top(_ r: Float) -> Float { y0 + h - dip * (1 - (r / R) * (r / R)) }
        let pts: [(r: Float, y: Float, ao: Float)] = [(R * 0.97, y0, 0.55), (R, y0 + 0.02, 0.7), (R * 1.0, y0 + h * 0.7, 0.85), (R * 0.97, top(R * 0.97) , 1), (R * 0.88, top(R * 0.88), 1),
                                                       (R * 0.6, top(R * 0.6), 1), (R * 0.3, top(R * 0.3), 1), (0, top(0), 1)]
        lathe(b, p, pts: pts, segments: 48, outline: sq) { i, _ in i <= 3 ? sky : (i == 4 ? mixc(sky, cream, 0.5) : sky) }
        // inlay: a cream ring and a honey centre
        func disc(_ r0: Float, _ r1: Float, _ col: SIMD3<Float>) {
            lathe(b, p, pts: [(r1, top(r1) + 0.004, 1), (r0, top(r0) + 0.004, 1)], segments: 40, outline: sq) { _, _ in col }
        }
        disc(R * 0.52, R * 0.60, cream)
        disc(0, R * 0.42, honey)
        // chevrons: two pink arrows on the honey
        for dz in [Float(-0.12), 0.12] {
            b.roundedBox(centre: SIMD3(p.x, top(0.1) + 0.012, p.y + dz), half: SIMD3(0.20, 0.008, 0.035), radius: 0.008, segments: 1, aoFloor: false, color: pink)
        }
    }
}
