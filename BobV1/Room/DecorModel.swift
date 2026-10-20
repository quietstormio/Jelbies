//
//  DecorModel.swift
//  Interactive decor (store, part B): the kinds, their floor footprints, where one may be put, and the live field the room and the Jellies share.
//
//  Kinds: beanbag (2 spots, big, a Jelly sinks into it), floor cushion (sit), potted plant (boop, leaves wiggle), ball (kick it, it rolls), small rug
//  (items sit on it), toy box (peek in), night light (glows at night), bouncy mat (2 spots, big, hop on it). Room capacity is `StoreTuning.roomCapacity`
//  spots; a big item takes 2.
//
//  OBSTACLES. Solid decor is a walking obstacle in `RoomLayout.resolve` (so wander, run goals, come-here, dining approach and the race-return spots all
//  go round it through the one floor resolver), and EVERY decor item (solid or flat) is kept clear of by sleep spots (`sleepFloorOK`). Flat decor
//  (rug, bouncy mat) and the ball are walked over. A Jelly that is about to use a piece (sit in the beanbag, hop on the mat) is exempt from that one
//  piece only (`BlobBrain.decorIgnore`).
//
//  PLACEMENT. Items go anywhere visible on the floor except: on the sofa / table / the room plant, over another item, and (solid items only) inside the
//  CORE (the middle of the rug and the front strip: the meal tray, the come-here spot, the bowls, the sleeping pile and the group row live there).
//  A small item may sit fully ON the rug; a big one may not straddle its edge.
//

import simd
import Foundation

nonisolated enum DecorKind: String, CaseIterable, Codable, Sendable {
    case beanbag, cushion, plant, ball, rug, toybox, nightlight, bouncymat

    var storeID: String { "decor-" + rawValue }
    init?(storeID id: String) {
        guard id.hasPrefix("decor-"), let k = DecorKind(rawValue: String(id.dropFirst(6))) else { return nil }
        self = k
    }
    var spec: DecorSpec {
        switch self {
        case .beanbag: return DecorSpec(half: SIMD2(0.72, 0.72), height: 0.73, solid: true, units: 2, corner: 0.72, reach: 1)
        case .cushion: return DecorSpec(half: SIMD2(0.37, 0.37), height: 0.24, solid: true, units: 1, corner: 0.2, reach: 0.55)
        case .plant: return DecorSpec(half: SIMD2(0.30, 0.31), height: 1.05, solid: true, units: 1, corner: 0.30, reach: 1)
        case .ball: return DecorSpec(half: SIMD2(0.27, 0.27), height: 0.54, solid: false, units: 1, corner: 0.27, reach: 1)
        case .rug: return DecorSpec(half: SIMD2(0.95, 0.67), height: 0.06, solid: false, units: 1, corner: 0.15, reach: 1)
        case .toybox: return DecorSpec(half: SIMD2(0.52, 0.41), height: 0.62, solid: true, units: 1, corner: 0.08, reach: 1)
        case .nightlight: return DecorSpec(half: SIMD2(0.26, 0.26), height: 0.68, solid: true, units: 1, corner: 0.20, reach: 1)
        case .bouncymat: return DecorSpec(half: SIMD2(0.88, 0.88), height: 0.14, solid: false, units: 2, corner: 0.2, reach: 1)
        }
    }
    /// What it does, in a sentence (shop and bag).
    var use: String {
        switch self {
        case .beanbag: return "A big squishy seat. Jellies sink into it. Cozy-lite: love drains 15% slower while it is in the room."
        case .cushion: return "A soft cushion. Jellies sit on it."
        case .plant: return "Jellies sniff and boop it, and the leaves wiggle."
        case .ball: return "Jellies kick it and it rolls across the room."
        case .rug: return "A cosy little rug. Small things can sit on it."
        case .toybox: return "Jellies lean over to peek in at the toys."
        case .nightlight: return "A glowing mushroom for when the room goes dark."
        case .bouncymat: return "A big springy mat. Jellies hop on it and it dips."
        }
    }
    var title: String {
        switch self {
        case .beanbag: return "Beanbag"; case .cushion: return "Floor cushion"; case .plant: return "Potted plant"; case .ball: return "Bouncy ball"
        case .rug: return "Small rug"; case .toybox: return "Toy box"; case .nightlight: return "Night light"; case .bouncymat: return "Bouncy mat"
        }
    }
}

extension DecorKind {
    /// The interaction a Jelly may pick with it (nil = none).
    var interaction: IdleKind? {
        switch self {
        case .beanbag, .cushion: return .decorSit
        case .plant: return .decorBoop
        case .ball: return .decorKick
        case .toybox: return .decorPeek
        case .bouncymat: return .decorHop
        case .rug, .nightlight: return nil
        }
    }
}

nonisolated struct DecorSpec: Sendable {
    /// Floor footprint half extents (x, z).
    var half: SIMD2<Float>
    var height: Float
    /// Blocks walking (flat things and the ball are walked over).
    var solid: Bool
    /// Room spots it takes (a big piece 2).
    var units: Int
    /// Corner radius of the footprint (= half.x for a round one).
    var corner: Float
    /// Fraction of a Jelly's footprint radius that has to keep off it (a low cushion: his round belly goes over it).
    var reach: Float
    /// The circle round the footprint (placement overlap tests).
    var radius: Float { max(half.x, half.y) }
    var big: Bool { units >= 2 }
    var flat: Bool { height < 0.2 && !solid }
}

/// One piece of decor in the room, as it is saved.
nonisolated struct PlacedDecor: Codable, Equatable, Sendable {
    var uid: Int
    var kind: DecorKind
    var x: Float
    var z: Float
    var at: SIMD2<Float> { SIMD2(x, z) }
}

/// A piece as the walk resolver and the Jellies see it.
struct DecorFoot: Equatable, Sendable {
    var uid: Int
    var kind: DecorKind
    var centre: SIMD2<Float>
    /// Height it is lifted (sitting on the rug).
    var lift: Float = 0
    var spec: DecorSpec { kind.spec }
    var radius: Float { spec.radius }
    var box: RoomLayout.FlatBox { .init(centre: centre, half: spec.half, height: spec.height + lift, radius: min(spec.corner, min(spec.half.x, spec.half.y))) }
    /// Distance from `p` to the edge of the footprint (negative inside).
    func distance(_ p: SIMD2<Float>) -> Float { RoomLayout.boxDistanceXZ(p, box) }
}

enum DecorTuning {
    /// A plausible 10-spot room (2 beanbags, the mat, a toy box, a plant, a night light, a cushion): the capture aid and the tests fill the room with it.
    static let fullRoom: [DecorKind] = [.beanbag, .beanbag, .bouncymat, .toybox, .plant, .nightlight, .cushion]
}

// MARK: - where things may go

enum DecorPlacement {
    /// The middle of the rug and the front strip (tray, come-here spot, bowls, the sleeping pile, the group row): solid decor stays out.
    static let coreMin = SIMD2<Float>(-2.0, -1.6), coreMax = SIMD2<Float>(2.0, 3.0)
    static let minZ: Float = -4.3, maxZ: Float = 3.0
    /// Gap kept between two items and between an item and the sofa / table.
    static let gap: Float = 0.06

    /// Half of the visible floor width at depth `z` (the camera sees less of the floor near the front).
    static func visibleHalf(z: Float) -> Float { GameCamera.visibleHalfWidthAtBody(z: z) * 0.93 }
    /// The most |x| a piece of radius `r` may have at depth `z`: on screen, and (when a Jelly plays with it) where a Jelly's centre can go: he has to be
    /// able to stand at it.
    static func xLimit(_ kind: DecorKind, z: Float) -> Float {
        let seen = visibleHalf(z: z) - kind.spec.radius
        guard kind.interaction != nil else { return seen }
        return min(seen, GameCamera.visibleHalfWidthAtBody(z: z) * GameCamera.screenFill - max(GameCamera.bodyHalfExtent, 0.63))
    }

    static func inCore(_ p: SIMD2<Float>, radius r: Float) -> Bool {
        let q = simd_max(simd_max(coreMin - p, p - coreMax), .zero)
        return simd_length(q) < r
    }

    /// Lift (on the rug) of an item at `p`, or nil when it overlaps the rug's edge or the rug cannot host it.
    static func rugLift(_ kind: DecorKind, at p: SIMD2<Float>, others: [PlacedDecor], ignoring: Int?) -> Float {
        for o in others where o.uid != ignoring && o.kind == .rug && kind != .rug {
            if !kind.spec.big, simd_distance(p, o.at) + kind.spec.radius <= o.kind.spec.radius - 0.02 { return o.kind.spec.height }
        }
        return 0
    }

    static func isValid(_ kind: DecorKind, at p: SIMD2<Float>, among others: [PlacedDecor], ignoring uid: Int? = nil) -> Bool {
        let s = kind.spec, r = s.radius
        let lowZ = kind.interaction != nil ? max(minZ, GameCamera.walkMinZ) : minZ, highZ = kind.interaction != nil ? min(maxZ, GameCamera.walkMaxZ) : maxZ
        guard p.y >= lowZ, p.y <= highZ, abs(p.x) <= xLimit(kind, z: p.y) else { return false }
        let L = RoomLayout.self
        guard L.sofaDistanceXZ(p) > r + gap else { return false }
        for c in L.cylinders where simd_distance(p, c.centre) < c.radius + r + gap { return false }
        if s.solid, inCore(p, radius: r) { return false }
        for o in others where o.uid != uid {
            let d = simd_distance(p, o.at), orad = o.kind.spec.radius
            if d >= r + orad + gap { continue }
            // the rug hosts small things that sit fully on it
            if o.kind == .rug, kind != .rug, !s.big, d + r <= orad - 0.02 { continue }
            if kind == .rug, o.kind != .rug, !o.kind.spec.big, d + orad <= r - 0.02 { continue }
            return false
        }
        return true
    }

    /// The free spot a new item goes to: a grid over the floor, nearest to the item's liking (solid pieces at the sides, balanced left and right;
    /// flat ones nearer the middle), deterministic. nil = nowhere to put it.
    static func findSpot(_ kind: DecorKind, among placed: [PlacedDecor]) -> SIMD2<Float>? {
        let s = kind.spec
        let left = placed.filter { $0.x < 0 }.count, right = placed.count - left
        let sideSign: Float = left <= right ? -1 : 1
        var best: (SIMD2<Float>, Float)?
        var z = minZ
        while z <= maxZ + 1e-4 {
            var x: Float = -5
            while x <= 5.0001 {
                let p = SIMD2<Float>(x, z)
                if isValid(kind, at: p, among: placed) {
                    // the sides first (left and right in turn), then the back, the middle of the floor last (flat pieces may go there, solid ones may not)
                    var cost = abs(z - 0.4) * 0.25 + (sideSign * x > 0 ? 0 : 3) + (3.6 - abs(x)) * 0.5 + max(0, 3.0 - simd_length(p)) * 0.3
                    if inCore(p, radius: s.radius) { cost += 6 }
                    if best == nil || cost < best!.1 - 1e-5 { best = (p, cost) }
                }
                x += 0.1
            }
            z += 0.1
        }
        return best?.0
    }

    /// The feet the room and the Jellies see for a list of placed pieces (items fully on the rug are lifted).
    static func feet(_ placed: [PlacedDecor]) -> [DecorFoot] {
        placed.map { p in DecorFoot(uid: p.uid, kind: p.kind, centre: p.at, lift: rugLift(p.kind, at: p.at, others: placed, ignoring: p.uid)) }
    }
}

// MARK: - the live field

/// What is animating on one piece.
struct DecorAnim: Equatable, Sendable {
    /// Sat in (beanbag, cushion): 0...1, eased toward `sinkWant` (the sitter sets it each step).
    var sink: Float = 0
    var sinkWant: Float = 0
    /// A boop or a landing: a decaying kick (leaves wiggle, the mat dips, the toys jump).
    var kick: Float = 0
    var kickT: Float = 0
    /// Toy box: peeked into.
    var peek: Float = 0
    var peekWant: Float = 0
    /// Ball: floor position, velocity and orientation.
    var pos = SIMD2<Float>.zero
    var vel = SIMD2<Float>.zero
    var rot = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
    var moving: Bool { simd_length_squared(vel) > 1e-4 }
    var active: Bool { sink > 0.002 || sinkWant > 0 || kick > 0.002 || peek > 0.002 || peekWant > 0 || moving }
}

/// The room's decor as the sim reads it (main-thread, like `RoomLayout.dynamicBoxes`).
final class DecorField {
    static let shared = DecorField()

    private(set) var placed: [PlacedDecor] = []
    private(set) var feet: [DecorFoot] = []
    private(set) var anim: [Int: DecorAnim] = [:]
    /// Which Jelly (steer id) is using a piece.
    var occupant: [Int: Int] = [:]
    /// The piece the player has picked up in arrange mode: no Jelly starts using it meanwhile.
    var held: Int?
    /// Bumped when the pieces or their positions change; the mesh is rebuilt on it and while anything animates.
    private(set) var version = 0
    var animating: Bool { anim.values.contains { $0.active } }

    func set(_ list: [PlacedDecor]) {
        guard list != placed else { return }
        let oldKinds = Dictionary(placed.map { ($0.uid, $0.kind) }, uniquingKeysWith: { a, _ in a })
        placed = list
        feet = DecorPlacement.feet(list)
        var a: [Int: DecorAnim] = [:]
        for p in list {
            var x = anim[p.uid] ?? DecorAnim()
            if p.kind == .ball, !x.moving { x.pos = p.at }
            a[p.uid] = x
        }
        anim = a
        occupant = occupant.filter { o in a[o.key] != nil && list.first(where: { $0.uid == o.key })?.kind == oldKinds[o.key] }
        RoomLayout.decorFeet = feet
        version &+= 1
    }
    func clear() { set([]) }

    func foot(_ uid: Int) -> DecorFoot? { feet.first { $0.uid == uid } }

    /// The piece a ray (from the camera through a touch) hits: the ray against each piece's footprint box (grown by `slack`, a finger is wider than a pixel) and its
    /// height; the nearest wins. `t` is the distance along `d` (a unit vector).
    func hit(origin o: SIMD3<Float>, dir d: SIMD3<Float>, slack: Float = 0.12) -> (uid: Int, t: Float)? {
        var best: (uid: Int, t: Float)?
        for f in feet {
            let c = position(f), h = f.spec.half
            let lo = SIMD3<Float>(c.x - h.x - slack, 0, c.y - h.y - slack), hi = SIMD3<Float>(c.x + h.x + slack, f.lift + f.spec.height + slack, c.y + h.y + slack)
            var t0: Float = 0, t1: Float = .infinity, ok = true
            for k in 0..<3 {
                if abs(d[k]) < 1e-6 { if o[k] < lo[k] || o[k] > hi[k] { ok = false; break } }
                else {
                    var a = (lo[k] - o[k]) / d[k], b = (hi[k] - o[k]) / d[k]
                    if a > b { swap(&a, &b) }
                    t0 = max(t0, a); t1 = min(t1, b)
                    if t0 > t1 { ok = false; break }
                }
            }
            if ok, best == nil || t0 < best!.t { best = (f.uid, t0) }
        }
        return best
    }
    /// The height of a piece's top surface right now (a beanbag squishes and wobbles when he lands on it).
    func topY(_ uid: Int) -> Float? {
        guard let f = foot(uid) else { return nil }
        return f.kind == .beanbag ? DecorModels.beanbagTop(lift: f.lift, anim: anim[uid] ?? DecorAnim()) : f.lift + f.spec.height
    }
    func kinds(_ k: DecorKind) -> [DecorFoot] { feet.filter { $0.kind == k } }

    /// Where a piece is right now (the ball moves).
    func position(_ f: DecorFoot) -> SIMD2<Float> { f.kind == .ball ? (anim[f.uid]?.pos ?? f.centre) : f.centre }

    // hooks the Jellies call
    func sit(_ uid: Int, _ k: Float) { guard let w = anim[uid]?.sinkWant else { return }; anim[uid]?.sinkWant = max(w, k) }
    func kick(_ uid: Int, _ amount: Float = 1) { guard anim[uid] != nil else { return }; anim[uid]!.kick = max(anim[uid]!.kick, amount); anim[uid]!.kickT = 0 }
    func peek(_ uid: Int, _ k: Float) { guard let w = anim[uid]?.peekWant else { return }; anim[uid]?.peekWant = max(w, k) }
    func kickBall(_ uid: Int, direction d: SIMD2<Float>, speed: Float) {
        guard anim[uid] != nil else { return }
        anim[uid]!.vel = d * speed
    }

    /// One step: eases the sits, decays the kicks, rolls the ball (it stays on the visible floor and bounces off solid pieces and the sofa).
    func tick(dt: Float) {
        for uid in Array(anim.keys) {
            guard var a = anim[uid], let f = foot(uid) else { continue }
            if a.active {
                a.sink += (a.sinkWant - a.sink) * min(1, dt * (a.sinkWant > a.sink ? 5 : 3.2))
                if a.sinkWant == 0, a.sink < 0.002 { a.sink = 0 }
                a.sinkWant = 0
                a.peek += (a.peekWant - a.peek) * min(1, dt * 4)
                if a.peekWant == 0, a.peek < 0.002 { a.peek = 0 }
                a.peekWant = 0
                a.kickT += dt
                a.kick *= expf(-dt * 3.2)
                if a.kick < 0.002 { a.kick = 0 }
                if f.kind == .ball, a.moving { Self.roll(&a, dt: dt, ignoring: uid, feet: feet) }
                anim[uid] = a
            }
        }
    }

    static func roll(_ a: inout DecorAnim, dt: Float, ignoring uid: Int, feet: [DecorFoot]) {
        let r = DecorKind.ball.spec.radius
        a.vel *= expf(-1.15 * dt)
        if simd_length(a.vel) < 0.06 { a.vel = .zero; return }
        var p = a.pos + a.vel * dt
        // the visible floor
        let zlo: Float = -2.4, zhi: Float = max(3.0, GameCamera.roamFloor?.maxZ ?? 3.0)
        if p.y < zlo + r { p.y = zlo + r; a.vel.y = abs(a.vel.y) * 0.7 }
        if p.y > zhi - r { p.y = zhi - r; a.vel.y = -abs(a.vel.y) * 0.7 }
        let lim = DecorPlacement.visibleHalf(z: p.y) - r
        if p.x < -lim { p.x = -lim; a.vel.x = abs(a.vel.x) * 0.7 }
        if p.x > lim { p.x = lim; a.vel.x = -abs(a.vel.x) * 0.7 }
        // the sofa and the solid pieces
        func bounce(_ sd: Float, _ grad: SIMD2<Float>) {
            guard sd < r else { return }
            let n = simd_length(grad) > 1e-6 ? simd_normalize(grad) : SIMD2<Float>(0, 1)
            p += n * (r - sd)
            let vn = simd_dot(a.vel, n)
            if vn < 0 { a.vel -= n * vn * 1.7 }
        }
        let e: Float = 1e-3
        func grad(_ f: (SIMD2<Float>) -> Float) -> SIMD2<Float> { SIMD2(f(p + SIMD2(e, 0)) - f(p - SIMD2(e, 0)), f(p + SIMD2(0, e)) - f(p - SIMD2(0, e))) }
        bounce(RoomLayout.sofaDistanceXZ(p), grad(RoomLayout.sofaDistanceXZ))
        for c in feet where c.uid != uid && c.spec.solid {
            bounce(c.distance(p), grad { c.distance($0) })
        }
        for c in RoomLayout.cylinders {
            let d = p - c.centre, len = simd_length(d)
            bounce(len - c.radius, len > 1e-6 ? d / len : SIMD2(0, 1))
        }
        let step = p - a.pos
        let dist = simd_length(step)
        if dist > 1e-6 {
            let dir = step / dist
            let axis = SIMD3<Float>(dir.y, 0, -dir.x)
            a.rot = simd_normalize(simd_quatf(angle: dist / r, axis: axis) * a.rot)
        }
        a.pos = p
    }

    /// The ball came to rest somewhere else: the piece's saved position follows.
    func restingBall() -> (uid: Int, at: SIMD2<Float>)? {
        for f in feet where f.kind == .ball {
            if let a = anim[f.uid], !a.moving, simd_distance(a.pos, f.centre) > 0.05 { return (f.uid, a.pos) }
        }
        return nil
    }
}
