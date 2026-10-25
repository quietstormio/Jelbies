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
    // the second batch (2026-10-20): furniture ...
    case loveseat, petbed, pouf, rockingchair, armchair, swing, diningset, bookshelf, wardrobe, divider, floorlamp, slide, monstera
    // ... and toys
    case duck, blocks, spintop, toycar, yarnball, drum
    // soccer (2026-10-20, replaces the football): the ball is kicked with a stomp step, dribbled and passed; the goal is shot at (Room/DecorField+Soccer.swift)
    case soccerball, minigoal
    // batch 3 (2026-10-24, Room/DecorKind+Batch3.swift): more furniture and toys
    case roundtable, cushionpile, aquarium, plantstand, easel, mirror, clock
    case bubblemachine, rockinghorse, jackinbox, plushbear, toypiano, pinwheel
    // Park-only (2026-10-25, Park/ParkToys.swift): never sold; placed permanently in the Park
    case seesaw, springrider, sandbox

    /// The first eight pieces (circle placement geometry, as they were built).
    static let original: [DecorKind] = [.beanbag, .cushion, .plant, .ball, .rug, .toybox, .nightlight, .bouncymat]
    static let batch2: [DecorKind] = DecorKind.allCases.filter { !original.contains($0) }
    /// Which tab of the Shop / Bag lists it.
    enum Category: String, Sendable { case furniture, toys }
    var category: Category {
        switch self {
        case .seesaw, .springrider, .sandbox, .ball, .bouncymat, .duck, .blocks, .spintop, .toycar, .yarnball, .drum, .soccerball, .minigoal: return .toys
        default: return Self.batch3Toys.contains(self) ? .toys : .furniture
        }
    }
    /// Pieces that roll when kicked (the ball and its cousins).
    var rolls: Bool { self == .ball || self == .yarnball || self == .toycar || self == .soccerball }
    /// Round things a pair of Jellies may pass to each other.
    var isBallLike: Bool { self == .ball || self == .yarnball || self == .soccerball }
    /// Radius of the rolling piece for the wall bounce and the roll angle.
    var rollRadius: Float {
        switch self {
        case .ball: return 0.27; case .yarnball: return 0.30; case .soccerball: return SoccerTuning.radius; case .toycar: return 0.42
        default: return 0.27
        }
    }

    var storeID: String { "decor-" + rawValue }
    init?(storeID id: String) {
        guard id.hasPrefix("decor-"), let k = DecorKind(rawValue: String(id.dropFirst(6))) else { return nil }
        self = k
    }
    /// The seating and sleeping pieces were authored for Jellies at about 0.8 scale: in game they are drawn, measured and used 1.25x (art, footprint, sit points, pivots, slide path, sleep point).
    static let bigScale: Float = 1.25
    var scale: Float {
        switch self {
        case .loveseat, .swing, .rockingchair, .armchair, .pouf, .diningset, .petbed, .slide: return Self.bigScale
        case .seesaw: return 1.4          // (Park toys are drawn and measured bigger so they read next to the Jelbies)
        case .springrider: return 1.35
        case .sandbox: return 1.15
        default: return 1
        }
    }
    /// Width scale: the loveseat's art is 1.4x wide (1.25x in depth and height) so two bodies of ~1.3 sit side by side between its arms.
    var scaleX: Float { self == .loveseat ? 1.4 : scale }
    var spec: DecorSpec {
        var s = baseSpec
        let k = scale
        if k != 1 {
            let h0 = s.half
            s.half *= k; s.height *= k; s.corner *= k
            s.half.x = h0.x * scaleX
            // The room has no space for a swing 2.4 deep (between the sofa and the meal core there is ~1.9) or a slide 2.0 wide in portrait: their frames keep the
            // authored depth / width as walking footprints (the art is 1.25x; only the footprint of the legs / rails stays), everything else scales whole.
            if self == .swing { s.half.y = h0.y }
            if self == .slide { s.half.x = h0.x }
            if self == .swing || self == .slide || self == .petbed { s.units = 3 }          // 1.25x: the swing, the slide and the pet bed take 3 room spots
        }
        return s
    }
    /// The footprints as authored (JSON `footprint_half`, before `scale`).
    private var baseSpec: DecorSpec {
        switch self {
        case .beanbag: return DecorSpec(half: SIMD2(0.72, 0.72), height: 0.73, solid: true, units: 2, corner: 0.72, reach: 1)
        case .cushion: return DecorSpec(half: SIMD2(0.37, 0.37), height: 0.24, solid: true, units: 1, corner: 0.2, reach: 0.55)
        case .plant: return DecorSpec(half: SIMD2(0.30, 0.31), height: 1.05, solid: true, units: 1, corner: 0.30, reach: 1)
        case .ball: return DecorSpec(half: SIMD2(0.27, 0.27), height: 0.54, solid: false, units: 1, corner: 0.27, reach: 1)
        case .rug: return DecorSpec(half: SIMD2(0.95, 0.67), height: 0.06, solid: false, units: 1, corner: 0.15, reach: 1)
        case .toybox: return DecorSpec(half: SIMD2(0.52, 0.41), height: 0.62, solid: true, units: 1, corner: 0.08, reach: 1)
        case .nightlight: return DecorSpec(half: SIMD2(0.26, 0.26), height: 0.68, solid: true, units: 1, corner: 0.20, reach: 1)
        case .bouncymat: return DecorSpec(half: SIMD2(0.88, 0.88), height: 0.14, solid: false, units: 2, corner: 0.2, reach: 1)
        // second batch: footprints are the JSON `footprint_half` / `spots` / `solid` (the sub-mesh bounds may stick out: leaves, an open door, the yarn strand)
        case .loveseat: return DecorSpec(half: SIMD2(1.35, 0.55), height: 1.06, solid: true, units: 2, corner: 0.2, reach: 1, box: true)
        case .petbed: return DecorSpec(half: SIMD2(1.07, 1.07), height: 0.58, solid: true, units: 2, corner: 1.07, reach: 1, box: true)
        case .pouf: return DecorSpec(half: SIMD2(0.6, 0.6), height: 0.48, solid: true, units: 1, corner: 0.6, reach: 1, box: true)
        case .rockingchair: return DecorSpec(half: SIMD2(0.68, 0.7), height: 1.28, solid: true, units: 1, corner: 0.2, reach: 1, box: true)
        case .armchair: return DecorSpec(half: SIMD2(0.88, 0.55), height: 1.305, solid: true, units: 1, corner: 0.2, reach: 1, box: true)
        case .swing: return DecorSpec(half: SIMD2(1.55, 0.95), height: 2.2, solid: true, units: 2, corner: 0.2, reach: 1, box: true)
        case .diningset: return DecorSpec(half: SIMD2(1.25, 0.62), height: 1.05, solid: true, units: 2, corner: 0.15, reach: 1, box: true)
        case .bookshelf: return DecorSpec(half: SIMD2(0.52, 0.24), height: 1.22, solid: true, units: 1, corner: 0.05, reach: 1, box: true)
        case .wardrobe: return DecorSpec(half: SIMD2(0.55, 0.3), height: 1.385, solid: true, units: 1, corner: 0.05, reach: 1, box: true)
        case .divider: return DecorSpec(half: SIMD2(0.9, 0.35), height: 1.55, solid: true, units: 1, corner: 0.05, reach: 1, box: true)
        case .floorlamp: return DecorSpec(half: SIMD2(0.29, 0.29), height: 1.515, solid: true, units: 1, corner: 0.29, reach: 1, box: true)
        case .slide: return DecorSpec(half: SIMD2(0.8, 1.4), height: 1.1, solid: true, units: 2, corner: 0.2, reach: 1, box: true)
        case .monstera: return DecorSpec(half: SIMD2(0.42, 0.42), height: 1.75, solid: true, units: 1, corner: 0.42, reach: 1, box: true)
        case .duck: return DecorSpec(half: SIMD2(0.34, 0.5), height: 0.9, solid: true, units: 1, corner: 0.3, reach: 1, box: true)
        case .blocks: return DecorSpec(half: SIMD2(0.26, 0.26), height: 1.5, solid: false, units: 1, corner: 0.26, reach: 1, box: true)
        case .spintop: return DecorSpec(half: SIMD2(0.34, 0.34), height: 0.82, solid: false, units: 1, corner: 0.34, reach: 1, box: true)
        case .toycar: return DecorSpec(half: SIMD2(0.38, 0.55), height: 0.69, solid: false, units: 1, corner: 0.2, reach: 1, box: true)
        case .yarnball: return DecorSpec(half: SIMD2(0.3, 0.3), height: 0.6, solid: false, units: 1, corner: 0.3, reach: 1, box: true)
        case .drum: return DecorSpec(half: SIMD2(0.42, 0.42), height: 0.55, solid: true, units: 1, corner: 0.42, reach: 1, box: true)
        case .soccerball: return DecorSpec(half: SIMD2(0.18, 0.18), height: 0.36, solid: false, units: 1, corner: 0.18, reach: 1, box: true)
        // the goal is a wall for walkers; the ball alone passes its mouth (DecorField+Soccer.swift handles its posts, side nets and back net)
        case .minigoal: return DecorSpec(half: SIMD2(0.8, 0.35), height: 0.9, solid: true, units: 2, corner: 0.05, reach: 1, box: true)
        default: return batch3Spec
        }
    }
    /// The footprint after `q` quarter turns (an odd count swaps the half extents).
    func spec(quarter q: Int) -> DecorSpec {
        var s = spec
        if q & 1 == 1 { s.half = SIMD2(s.half.y, s.half.x) }
        return s
    }
    /// What it does, in a sentence (shop and bag).
    var use: String {
        switch self {
        case .beanbag: return "A big squishy seat. Jelbies sink into it. Cozy-lite: love drains 15% slower while it is in the room."
        case .cushion: return "A soft cushion. Jelbies sit on it."
        case .plant: return "Jelbies sniff and boop it, and the leaves wiggle."
        case .ball: return "Jelbies kick it and it rolls across the room."
        case .rug: return "A cosy little rug. Small things can sit on it."
        case .toybox: return "Jelbies lean over to peek in at the toys."
        case .nightlight: return "A glowing mushroom for when the room goes dark."
        case .bouncymat: return "A big springy mat. Jelbies hop on it and it dips."
        case .loveseat: return "A two-seat sofa. Two friends hop up and cuddle."
        case .petbed: return "A cosy pet bed. A sleepy Jelbie hops in and curls up."
        case .pouf: return "A round pouf. Jelbies hop on and sit."
        case .rockingchair: return "Jelbies sit in it and the chair rocks."
        case .armchair: return "A comfy armchair. Jelbies hop up and sit."
        case .swing: return "A swing for two. Jelbies sit and sway."
        case .diningset: return "A little table with two stools, one seat for each Jelbie."
        case .bookshelf: return "Jelbies lean in to look at the books."
        case .wardrobe: return "Jelbies peek at the clothes inside; the door swings."
        case .divider: return "A painted screen. Jelbies walk round it."
        case .floorlamp: return "A floor lamp that glows when the room goes dark."
        case .slide: return "Climb the steps and whoosh down the slide."
        case .monstera: return "A big leafy plant. Jelbies boop it and the leaves wiggle."
        case .duck: return "A squeaky rubber duck. Boop it for a squeak."
        case .blocks: return "A tower of blocks. A kick sends them tumbling."
        case .spintop: return "Boop it and it spins, wobbles and falls over."
        case .toycar: return "A little car. Kick it and it rolls along."
        case .yarnball: return "A ball of yarn. It rolls and trails its strand."
        case .drum: return "A drum. Boop it for a thump."
        case .soccerball: return "A soccer ball. Jelbies kick it with their stubby legs, dribble it and pass it."
        case .minigoal: return "A little goal with a net. Jelbies line up and shoot; a goal puffs the net."
        default: return batch3Use
        }
    }
    var title: String {
        switch self {
        case .beanbag: return "Beanbag"; case .cushion: return "Floor cushion"; case .plant: return "Potted plant"; case .ball: return "Bouncy ball"
        case .rug: return "Small rug"; case .toybox: return "Toy box"; case .nightlight: return "Night light"; case .bouncymat: return "Bouncy mat"
        case .loveseat: return "Loveseat"; case .petbed: return "Pet bed"; case .pouf: return "Pouf"; case .rockingchair: return "Rocking chair"
        case .armchair: return "Armchair"; case .swing: return "Swing"; case .diningset: return "Dining set"; case .bookshelf: return "Bookshelf"
        case .wardrobe: return "Wardrobe"; case .divider: return "Room divider"; case .floorlamp: return "Floor lamp"; case .slide: return "Slide"
        case .monstera: return "Monstera"; case .duck: return "Rubber duck"; case .blocks: return "Block tower"; case .spintop: return "Spinning top"
        case .toycar: return "Toy car"; case .yarnball: return "Yarn ball"; case .drum: return "Drum"
        case .soccerball: return "Soccer ball"; case .minigoal: return "Mini goal"
        default: return batch3Title
        }
    }
}

extension DecorKind {
    /// Where a sitter's base goes, piece-local (x, seat height, z), from the exports' `sit_points`; empty for a piece that is not hopped onto.
    var sitPoints: [SIMD3<Float>] { baseSitPoints.map { SIMD3($0.x * scaleX, $0.y * scale, $0.z * scale) } }
    private var baseSitPoints: [SIMD3<Float>] {
        switch self {
        case .beanbag: return [SIMD3(0, DecorModels.bagSeatY, DecorModels.bagSeatZ)]
        case .pouf: return [SIMD3(0, 0.45, 0)]
        case .armchair: return [SIMD3(0, 0.52, 0.3)]
        case .loveseat: return [SIMD3(-0.57, 0.52, 0.3), SIMD3(0.57, 0.52, 0.3)]          // (x 1.4x: seats 1.6 apart, two bodies of ~1.3 do not touch)
        case .diningset: return [SIMD3(-0.85, 0.47, 0), SIMD3(0.85, 0.47, 0)]
        case .rockingchair: return [SIMD3(0, 0.6, 0.2)]
        case .swing: return [SIMD3(-0.62, 0.6, 0), SIMD3(0.62, 0.6, 0)]
        default: return batch3SitPoints
        }
    }
    /// The pet bed's lying point (piece-local): the base of a curled sleeper on the mattress.
    /// How far behind the slide's centre he stands to climb it (the JSON's approach point, scaled).
    static let slideApproach: Float = (1.28 * DecorKind.slide.scale) + 0.57
    static let sleepPoint = SIMD3<Float>(0, 0.12 * DecorKind.petbed.scale, 0.05)
    /// The seat faces this way (yaw about +y from +z): the dining stools face the table, everything else the camera.
    func seatFacing(_ seat: Int) -> Float? { self == .diningset ? (seat == 0 ? .pi / 2 : -.pi / 2) : nil }
    /// Sideways distance from the piece's centre to where a Jelly stands for it (the seat off to one side).
    var standOffsetX: Float { sitPoints.map { abs($0.x) }.max() ?? 0 }
    /// A piece a Jelly hops onto (a bottom-sit on its seat point, like the beanbag) as opposed to the cushion's plain sit.
    var hopSit: Bool { !sitPoints.isEmpty }
    /// The pieces whose Jelly behaviour is wired (the rest are scenery that is walked round).
    static let wired: Set<DecorKind> = Set(DecorKind.allCases)
    /// What a Jelly may actually pick with it right now (`interaction` for a wired piece).
    var activeInteraction: IdleKind? { Self.wired.contains(self) ? interaction : nil }
    /// Does a Jelly's `move` apply to this piece?
    func offers(_ move: IdleKind) -> Bool { activeInteraction == move }
    /// The interaction a Jelly may pick with it (nil = none).
    var interaction: IdleKind? {
        switch self {
        case .beanbag, .cushion, .pouf, .armchair, .loveseat, .diningset, .rockingchair, .swing: return .decorSit
        case .plant, .monstera, .duck, .drum, .spintop: return .decorBoop
        case .ball, .blocks, .toycar, .yarnball: return .decorKick
        case .toybox, .bookshelf, .wardrobe: return .decorPeek
        case .bouncymat: return .decorHop
        case .slide: return .decorSlide
        case .soccerball: return .soccerKick
        case .seesaw, .springrider, .sandbox: return .decorSit
        case .petbed, .rug, .nightlight, .divider, .floorlamp, .minigoal: return nil          // (the goal is shot at through the soccer ball's own behaviour)
        default: return batch3Interaction
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
    /// Placement geometry: the first eight pieces are circles round `radius` (as built); the second batch uses its rounded box (a loveseat is 2.7 wide but only 1.1 deep).
    var box = false
    /// The circle round the footprint.
    var radius: Float { max(half.x, half.y) }
    /// The rounded box placement tests use: inner half extents and the rounding radius (a circle = no inner box, the whole radius).
    var inner: SIMD2<Float> { box ? simd_max(half - SIMD2(repeating: min(corner, min(half.x, half.y))), .zero) : .zero }
    var round: Float { box ? min(corner, min(half.x, half.y)) : radius }
    var big: Bool { units >= 2 }
    var flat: Bool { height < 0.2 && !solid }
}

/// One piece of decor in the room, as it is saved.
nonisolated struct PlacedDecor: Codable, Equatable, Sendable {
    var uid: Int
    var kind: DecorKind
    var x: Float
    var z: Float
    /// Quarter turns about the vertical (0...3; nil = 0 so old saves decode).
    var turns: Int?
    var quarter: Int { (turns ?? 0) & 3 }
    var at: SIMD2<Float> { SIMD2(x, z) }
}

/// A piece as the walk resolver and the Jellies see it.
struct DecorFoot: Equatable, Sendable {
    var uid: Int
    var kind: DecorKind
    var centre: SIMD2<Float>
    /// Height it is lifted (sitting on the rug).
    var lift: Float = 0
    /// Quarter turns (see `PlacedDecor.turns`).
    var quarter = 0
    var yaw: Float { Float(quarter) * .pi / 2 }
    var spec: DecorSpec { kind.spec(quarter: quarter) }
    /// A piece-local offset (x, z) in the world, and a world offset in the piece's frame.
    func turned(_ v: SIMD2<Float>) -> SIMD2<Float> { DecorPlacement.turn(v, quarter) }
    func local(_ v: SIMD2<Float>) -> SIMD2<Float> { DecorPlacement.turn(v, (4 - quarter) & 3) }
    var radius: Float { spec.radius }
    var box: RoomLayout.FlatBox { .init(centre: centre, half: spec.half, height: spec.height + lift, radius: min(spec.corner, min(spec.half.x, spec.half.y))) }
    /// Distance from `p` to the edge of the footprint (negative inside).
    func distance(_ p: SIMD2<Float>) -> Float { RoomLayout.boxDistanceXZ(p, box) }
}

enum DecorTuning {
    /// A plausible 10-spot room (2 beanbags, the mat, a toy box, a plant, a night light, a cushion): the capture aid and the tests fill the room with it.
    static let fullRoom: [DecorKind] = [.beanbag, .beanbag, .bouncymat, .toybox, .plant, .nightlight, .cushion]
    /// The second batch, big furniture (10 spots; fits a portrait room): swing, loveseat, slide, rocking chair, bookshelf, floor lamp, duck.
    static let furnitureRoom: [DecorKind] = [.swing, .loveseat, .slide, .rockingchair, .bookshelf]
    /// The pet bed, the dining set and small pieces (10 spots).
    static let bedRoom: [DecorKind] = [.petbed, .armchair, .diningset, .pouf]
    /// The heaviest new meshes (triangles), 10 spots: the perf test's room.
    static let heaviestRoom: [DecorKind] = [.rockingchair, .loveseat, .diningset, .bookshelf, .toycar]
}

// MARK: - where things may go

enum DecorPlacement {
    /// A small front-centre box (the bowls at x +-0.9 z 1.9, the tray at x +-0.5 z 1.7..2.2, the come-here spot (0, 2.4)): solid decor stays out, from there to the front of the
    /// floor (z 14). The rest of the floor is free.
    static let coreMin = SIMD2<Float>(-1.25, 1.55), coreMax = SIMD2<Float>(1.25, 14)
    static let minZ: Float = -4.3, maxZ: Float = 3.0
    /// The front of the visible floor above the bottom HUD buttons (a piece's front edge may reach it): from the camera at this fraction of the screen height, never less than 3.0.
    static var frontZ: Float {
        let a = GameCamera.aspect, size = CGSize(width: CGFloat(1000 * a), height: 1000)
        let z = GameCamera.floorPoint(screen: CGPoint(x: size.width / 2, y: 880), size: size)?.y ?? maxZ
        return min(max(z, maxZ), 12)
    }
    /// Gap kept between two items and between an item and the sofa / table.
    static let gap: Float = 0.06

    /// Half of the visible floor width at depth `z` (the camera sees less of the floor near the front).
    static func visibleHalf(z: Float) -> Float { GameCamera.visibleHalfWidthAtBody(z: z) * 0.93 }
    /// The most |x| a piece may have at depth `z`: on screen, and (when a Jelly plays with it) where a Jelly's centre can go: he has to be
    /// able to stand at it (at its seat, for a seat off to one side).
    static func xLimit(_ kind: DecorKind, z: Float, quarter q: Int = 0) -> Float {
        let s = kind.spec(quarter: q), off = q & 1 == 0 ? kind.standOffsetX : 0
        let seen = visibleHalf(z: z) - (s.box ? s.half.x : s.radius)
        guard kind.interaction != nil || kind == .petbed || kind == .minigoal else { return laneWidened(kind, z: z, limit: seen, quarter: q) }
        return laneWidened(kind, z: z, limit: min(seen, GameCamera.visibleHalfWidthAtBody(z: z) * GameCamera.screenFill - max(GameCamera.bodyHalfExtent, 0.63) - off))
    }
    /// A wide solid piece (the slide, the goal) has to clear the core (|x| >= 2) with its whole footprint, so on a portrait screen the lane between the core and the
    /// screen edge was a sliver (~0.2 wide) and a finger could only ever land in one side's: the piece stuck on the left of the screen (2026-10-23). Such a piece may
    /// lean past the screen edge (its centre stays on screen, inside the walls) so the lane is at least `minLane` wide.
    static let minLane: Float = 0.45
    static func laneWidened(_ kind: DecorKind, z: Float, limit: Float, quarter q: Int = 0) -> Float {
        let s = kind.spec(quarter: q)
        guard s.solid, s.box else { return limit }
        let need = coreMax.x + s.inner.x + s.round + minLane
        let cap = min(GameCamera.visibleHalfWidthAtBody(z: z) * 0.97, RoomLayout.maxX - 0.02 - s.half.x)
        return max(limit, min(need, cap))
    }

    /// A piece-local offset (x, z) turned `q` quarter turns (yaw about +y from +z).
    static func turn(_ v: SIMD2<Float>, _ q: Int) -> SIMD2<Float> {
        switch q & 3 { case 1: return SIMD2(v.y, -v.x); case 2: return -v; case 3: return SIMD2(-v.y, v.x); default: return v }
    }

    /// Core: the footprint's rounded box against the core rectangle (for a circle piece this is the old circle test).
    static func inCore(_ p: SIMD2<Float>, radius r: Float) -> Bool {
        let q = simd_max(simd_max(coreMin - p, p - coreMax), .zero)
        return simd_length(q) < r
    }
    static func inCore(_ kind: DecorKind, at p: SIMD2<Float>, quarter q: Int = 0) -> Bool {
        let s = kind.spec(quarter: q)
        let q = simd_max(simd_max(coreMin - (p + s.inner), (p - s.inner) - coreMax), .zero)
        return simd_length(q) < s.round
    }

    /// Two footprints (rounded boxes; a circle for the first eight pieces) closer than `gap`.
    static func overlaps(_ a: DecorKind, _ pa: SIMD2<Float>, _ b: DecorKind, _ pb: SIMD2<Float>, gap g: Float = DecorPlacement.gap, qa: Int = 0, qb: Int = 0) -> Bool {
        let sa = a.spec(quarter: qa), sb = b.spec(quarter: qb)
        let q = simd_max(simd_abs(pa - pb) - (sa.inner + sb.inner), .zero)
        return simd_length(q) < sa.round + sb.round + g
    }
    /// Clearance from the sofa for a footprint at `p` (negative = overlapping), sampled along its outline.
    static func sofaClearance(_ kind: DecorKind, at p: SIMD2<Float>, quarter q: Int = 0) -> Float {
        let s = kind.spec(quarter: q)
        guard s.box else { return RoomLayout.sofaDistanceXZ(p) - s.radius }
        var d = RoomLayout.sofaDistanceXZ(p)
        for o in outline(kind, at: p, quarter: q) { d = min(d, RoomLayout.sofaDistanceXZ(o)) }
        return d
    }
    /// Points round the footprint's rounded outline (every ~0.2).
    static func outline(_ kind: DecorKind, at p: SIMD2<Float>, quarter q: Int = 0) -> [SIMD2<Float>] {
        let s = kind.spec(quarter: q), r = s.round, i = s.inner
        var out: [SIMD2<Float>] = []
        let nx = max(1, Int((2 * i.x / 0.2).rounded(.up))), nz = max(1, Int((2 * i.y / 0.2).rounded(.up)))
        for k in 0...nx { let x = -i.x + 2 * i.x * Float(k) / Float(nx); out.append(p + SIMD2(x, -i.y - r)); out.append(p + SIMD2(x, i.y + r)) }
        for k in 0...nz { let z = -i.y + 2 * i.y * Float(k) / Float(nz); out.append(p + SIMD2(-i.x - r, z)); out.append(p + SIMD2(i.x + r, z)) }
        for (cx, cz) in [(Float(-1), Float(-1)), (1, -1), (-1, 1), (1, 1)] {
            for a in stride(from: Float(0.2), to: Float.pi / 2 - 0.1, by: 0.45) {
                out.append(p + SIMD2(cx * (i.x + r * cosf(a)), cz * (i.y + r * sinf(a))))
            }
        }
        return out
    }

    /// Lift (on the rug) of an item at `p`, or nil when it overlaps the rug's edge or the rug cannot host it.
    static func rugLift(_ kind: DecorKind, at p: SIMD2<Float>, others: [PlacedDecor], ignoring: Int?) -> Float {
        for o in others where o.uid != ignoring && o.kind == .rug && kind != .rug {
            if !kind.spec.big, simd_distance(p, o.at) + kind.spec.radius <= o.kind.spec.radius - 0.02 { return o.kind.spec.height }
        }
        return 0
    }

    static func isValid(_ kind: DecorKind, at p: SIMD2<Float>, among others: [PlacedDecor], ignoring uid: Int? = nil, quarter q: Int = 0) -> Bool {
        let s = kind.spec(quarter: q)
        let walked = kind.interaction != nil || kind == .petbed || kind == .minigoal          // (a Jelly walks to it: the pet bed too; the goal is shot at from in front)
        // A big deep piece (swing, slide, pet bed at 1.25x) may stand far back: it is its FRONT (where a Jelly stands for it, or the slide's climb behind it) that has to be on walkable floor
        let deep = s.box && s.half.y > 0.9
        let lowZ = walked ? (deep ? minZ : max(minZ, GameCamera.walkMinZ)) : minZ, highZ = frontZ - (s.box ? s.half.y : s.radius)          // (the piece's front edge may reach the front of the visible floor; a Jelly's stand spot is clamped onto walkable floor)
        guard p.y >= lowZ, p.y <= highZ, abs(p.x) <= xLimit(kind, z: p.y, quarter: q) else { return false }
        // inside the walls (the room is 10 wide; a landscape screen sees past them)
        guard abs(p.x) + (s.box ? s.half.x : s.radius) <= RoomLayout.maxX - 0.02 else { return false }
        // the slide is climbed from behind: that spot (1.85 back) has to be floor a Jelly can stand on
        if deep, walked, kind != .slide, p.y + s.half.y + 0.9 < GameCamera.walkMinZ { return false }
        if kind == .slide {
            let ap = p + turn(SIMD2(0, -DecorKind.slideApproach), q)          // (where a Jelly stands to climb it)
            if ap.y < GameCamera.walkMinZ + 0.1 || abs(ap.x) > visibleHalf(z: ap.y) { return false }
        }
        guard sofaClearance(kind, at: p, quarter: q) > gap else { return false }
        for c in RoomLayout.cylinders {
            let b = RoomLayout.FlatBox(centre: p, half: s.half, height: 1, radius: s.round)
            if RoomLayout.boxDistanceXZ(c.centre, b) < c.radius + gap { return false }
        }
        for o in others where o.uid != uid {
            let orad = o.kind.spec.radius, d = simd_distance(p, o.at)
            if !overlaps(kind, p, o.kind, o.at, qa: q, qb: o.quarter) { continue }
            // the rug hosts small things that sit fully on it
            if o.kind == .rug, kind != .rug, !s.big, d + s.radius <= orad - 0.02 { continue }
            if kind == .rug, o.kind != .rug, !o.kind.spec.big, d + orad <= s.radius - 0.02 { continue }
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
                    if inCore(kind, at: p) { cost += 6 }
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
        placed.map { p in DecorFoot(uid: p.uid, kind: p.kind, centre: p.at, lift: rugLift(p.kind, at: p.at, others: placed, ignoring: p.uid), quarter: p.quarter) }
    }
    /// The spot nearest `p` (within 1.5) where the piece fits after a turn to `q` quarters, nil when none does.
    static func spotAfterTurn(_ kind: DecorKind, at p: SIMD2<Float>, quarter q: Int, among others: [PlacedDecor], ignoring uid: Int) -> SIMD2<Float>? {
        if isValid(kind, at: p, among: others, ignoring: uid, quarter: q) { return p }
        var best: (SIMD2<Float>, Float)?
        for i in -15...15 { for j in -15...15 {
            let c = p + SIMD2(Float(i), Float(j)) * 0.1, d = simd_length(c - p)
            if d > 1.5 || (best.map { d >= $0.1 } ?? false) { continue }
            if isValid(kind, at: c, among: others, ignoring: uid, quarter: q) { best = (c, d) }
        } }
        return best?.0
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
    // --- the second batch ---
    /// A seat each (loveseat cushions, stools, swing seats): pressed in while somebody sits on it.
    var seatSink = SIMD2<Float>.zero
    var seatWant = SIMD2<Float>.zero
    /// Rocking chair / swing: how hard it is rocking (0...1, eased to `rockWant`), and its clock.
    var rockAmp: Float = 0
    var rockWant: Float = 0
    var rockT: Float = 0
    /// Spinning top: angular speed, its turned angle, and the fall (0 = up; 0...1.6 = tipping over, lying, righting).
    var spin: Float = 0
    var spinAngle: Float = 0
    var fallT: Float = -1
    var fallAxis: Float = 0
    /// Toy car: heading (yaw so that its nose points along its travel) and the wheels' turn. Yarn ball: where its strand trails.
    var heading: Float = 0
    var wheel: Float = 0
    /// The block tower: nil = stacked. Time since it was knocked over.
    var blocks: [TumbleBlock] = []
    var tumbleT: Float = -1
    /// Soccer ball: who kicked it last (steer id, -1 none) and seconds since; the kicker is not bumped by his own ball as it leaves his toe.
    var kicker = -1
    var kickAge: Float = 99
    /// Soccer ball: inside a goal's mouth (its uid; -1 none): a crossing scores once, until it has rolled back out.
    var inGoal = -1
    var tumbling: Bool { tumbleT >= 0 }
    var active: Bool {
        sink > 0.002 || sinkWant > 0 || kick > 0.002 || peek > 0.002 || peekWant > 0 || moving || seatSink != .zero || seatWant != .zero
            || rockAmp > 0.002 || rockWant > 0 || spin > 0 || fallT >= 0 || tumbleT >= 0
    }
}

/// One block of the tumbling tower (position relative to the piece's origin).
struct TumbleBlock: Equatable, Sendable {
    var pos: SIMD3<Float>
    var vel: SIMD3<Float>
    var yaw: Float
    var yawV: Float
    var roll: Float
    var rollV: Float
    var rest = false
}

/// The room's decor as the sim reads it (main-thread, like `RoomLayout.dynamicBoxes`).
final class DecorField {
    static let shared = DecorField()

    private(set) var placed: [PlacedDecor] = []
    private(set) var feet: [DecorFoot] = []
    private(set) var anim: [Int: DecorAnim] = [:]
    /// Which Jelly (steer id) is using a piece.
    var occupant: [Int: Int] = [:]
    /// Seat by seat for the multi-seat pieces (loveseat, swing, dining stools): uid -> seat -> steer id. `occupant` also holds one of them.
    var seatOccupant: [Int: [Int: Int]] = [:]
    /// A Jelly may start using it: a single-seat piece nobody uses, or a multi-seat one with a seat free.
    func available(_ f: DecorFoot) -> Bool {
        guard f.uid != held else { return false }
        if f.kind.sitPoints.count > 1 { return (seatOccupant[f.uid]?.count ?? 0) < f.kind.sitPoints.count }
        return occupant[f.uid] == nil
    }
    /// The lowest free seat (or nil).
    func freeSeat(_ f: DecorFoot, preferring side: Float = 0) -> Int? {
        let n = max(f.kind.sitPoints.count, 1)
        let free = (0..<n).filter { seatOccupant[f.uid]?[$0] == nil }
        guard !free.isEmpty else { return nil }
        if n > 1, side != 0 { return free.min { abs(f.kind.sitPoints[$0].x - side) < abs(f.kind.sitPoints[$1].x - side) } }
        return free.first
    }
    func take(_ uid: Int, seat: Int, by id: Int) { seatOccupant[uid, default: [:]][seat] = id; occupant[uid] = id }
    func leave(_ uid: Int, by id: Int) {
        if var s = seatOccupant[uid] {
            for (k, v) in s where v == id { s[k] = nil }
            seatOccupant[uid] = s.isEmpty ? nil : s
            if occupant[uid] == id { occupant[uid] = s.values.first }
        } else if occupant[uid] == id { occupant[uid] = nil }
    }
    /// World position of a seat (xz) and height of its surface right now.
    func seatWorld(_ uid: Int, seat: Int) -> SIMD3<Float>? {
        guard let f = foot(uid), !f.kind.sitPoints.isEmpty else { return nil }
        let p = DecorModels.seatPoint(f.kind, seat: seat, anim: anim[uid] ?? DecorAnim(), lift: f.lift)
        let w = f.turned(SIMD2(p.x, p.z))
        return SIMD3(f.centre.x + w.x, p.y, f.centre.y + w.y)
    }
    /// The piece the player has picked up in arrange mode: no Jelly starts using it meanwhile.
    var held: Int?
    /// Bumped when the pieces or their positions change; the mesh is rebuilt on it and while anything animates.
    private(set) var version = 0
    var animating: Bool { anim.values.contains { $0.active } }

    func set(_ list: [PlacedDecor]) {
        guard list != placed else { return }
        let oldKinds = Dictionary(placed.map { ($0.uid, $0.kind) }, uniquingKeysWith: { a, _ in a })
        placed = list
        if let h = held, !list.contains(where: { $0.uid == h }) { held = nil }
        feet = DecorPlacement.feet(list)
        var a: [Int: DecorAnim] = [:]
        for p in list {
            var x = anim[p.uid] ?? DecorAnim()
            if p.kind == .yarnball, anim[p.uid] == nil { x.heading = .pi / 4 }          // (its strand as exported, until it rolls)
            if p.kind.rolls, !x.moving { x.pos = p.at }
            a[p.uid] = x
        }
        anim = a
        occupant = occupant.filter { o in a[o.key] != nil && list.first(where: { $0.uid == o.key })?.kind == oldKinds[o.key] }
        seatOccupant = seatOccupant.filter { so in a[so.key] != nil && list.first(where: { l in l.uid == so.key })?.kind == oldKinds[so.key] }
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
    func position(_ f: DecorFoot) -> SIMD2<Float> { f.kind.rolls ? (anim[f.uid]?.pos ?? f.centre) : f.centre }

    // hooks the Jellies call
    func sit(_ uid: Int, _ k: Float) { guard let w = anim[uid]?.sinkWant else { return }; anim[uid]?.sinkWant = max(w, k) }
    /// One seat of a multi-seat piece is sat in (0 / 1).
    func sit(_ uid: Int, seat: Int, _ k: Float) {
        guard anim[uid] != nil else { return }
        anim[uid]!.seatWant[min(max(seat, 0), 1)] = max(anim[uid]!.seatWant[min(max(seat, 0), 1)], k)
        anim[uid]!.sinkWant = max(anim[uid]!.sinkWant, k)
    }
    /// The rocking chair / swing is rocked (level 0...1).
    func rock(_ uid: Int, _ level: Float) { guard anim[uid] != nil else { return }; anim[uid]!.rockWant = max(anim[uid]!.rockWant, level) }
    /// A boop sets the spinning top going.
    func spinTop(_ uid: Int) { guard anim[uid] != nil else { return }; anim[uid]!.spin = 18; anim[uid]!.fallT = -1 }
    /// A kick knocks the block tower over (away from `dir`).
    func tumble(_ uid: Int, direction d: SIMD2<Float>) {
        guard anim[uid] != nil, !anim[uid]!.tumbling, let f = foot(uid), f.kind == .blocks else { return }
        let piv = DecorMeshes.loaded[.blocks]?.parts.map { $0.pivot } ?? [SIMD3(0, 0.18, 0), SIMD3(0, 0.525, 0), SIMD3(0, 0.84, 0), SIMD3(0, 1.125, 0), SIMD3(0, 1.375, 0)]
        var seed = UInt32(truncatingIfNeeded: uid &* 2654435761 &+ 12345)
        func r() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) }
        var out: [TumbleBlock] = []
        for (i, v) in piv.enumerated() {
            let sp = 1.5 + 0.6 * Float(i)
            let a = atan2f(d.x, d.y) + (r() - 0.5) * 0.9
            out.append(TumbleBlock(pos: v, vel: SIMD3(sinf(a) * sp * (0.7 + 0.5 * r()), 2.0 + 0.5 * Float(i), cosf(a) * sp * (0.7 + 0.5 * r())),
                                   yaw: 0, yawV: (r() - 0.5) * 9, roll: 0, rollV: (r() - 0.5) * 12))
        }
        anim[uid]!.blocks = out; anim[uid]!.tumbleT = 0
        onTopple?(f.centre)
    }
    /// The reaction bus hook (SocialRoster.link): the block tower was knocked over, at this floor spot.
    var onTopple: ((SIMD2<Float>) -> Void)?
    func kick(_ uid: Int, _ amount: Float = 1) { guard anim[uid] != nil else { return }; anim[uid]!.kick = max(anim[uid]!.kick, amount); anim[uid]!.kickT = 0 }
    func peek(_ uid: Int, _ k: Float) { guard let w = anim[uid]?.peekWant else { return }; anim[uid]?.peekWant = max(w, k) }
    func kickBall(_ uid: Int, direction d: SIMD2<Float>, speed: Float, by kicker: Int = -1) {
        guard anim[uid] != nil else { return }
        anim[uid]!.vel = d * speed
        anim[uid]!.kicker = kicker; anim[uid]!.kickAge = 0
    }

    /// One step: eases the sits, decays the kicks, rolls the ball (it stays on the visible floor and bounces off solid pieces and the sofa).
    func tick(dt: Float) {
        SoccerState.shared.advance(dt)
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
                // the second batch
                a.seatSink += (a.seatWant - a.seatSink) * min(1, dt * 5)
                for k in 0..<2 where a.seatWant[k] == 0 && a.seatSink[k] < 0.002 { a.seatSink[k] = 0 }
                a.seatWant = .zero
                a.rockT += dt
                if a.rockWant > 0 { a.rockAmp += (a.rockWant - a.rockAmp) * min(1, dt * 2.5) } else { a.rockAmp *= expf(-dt * 0.9); if a.rockAmp < 0.002 { a.rockAmp = 0 } }
                a.rockWant = 0
                if f.kind == .spintop { Self.tickTop(&a, dt: dt) }
                if f.kind == .pinwheel { a.spinAngle += a.spin * dt; a.spin *= expf(-0.7 * dt); if a.spin < 0.4 { a.spin = 0 } }          // (batch 3: it spins down; a boop sets `spin`)
                if f.kind == .blocks { Self.tickBlocks(&a, dt: dt, uid: uid, held: held == uid) }
                if f.kind == .soccerball, a.moving { Self.rollSoccer(&a, dt: dt, uid: uid, feet: feet, bodies: bodies) }
                else if f.kind.rolls, a.moving { Self.roll(&a, dt: dt, ignoring: uid, feet: feet, kind: f.kind) }
                if f.kind == .toycar, a.moving {
                    let want = atan2f(-a.vel.x, -a.vel.y)
                    var d = want - a.heading
                    while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
                    a.heading += d * min(1, dt * 10)
                    a.wheel += simd_length(a.vel) * dt / 0.17
                }
                if f.kind == .yarnball, a.moving {
                    let want = atan2f(-a.vel.x, -a.vel.y)
                    var d = want - a.heading
                    while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
                    a.heading += d * min(1, dt * 6)
                }
                anim[uid] = a
            }
            if f.kind == .soccerball { soccerRestTick(uid, dt: dt) }
        }
    }

    /// The Jellies' floor positions (steer id, xz) this step, for the soccer ball's gentle bumps (the stage sets it in `tickDecor`; the tests set it by hand).
    var bodies: [(id: Int, pos: SIMD2<Float>)] = []
    /// (DecorField+Soccer.swift writes a piece's animation back.)
    func setAnim(_ uid: Int, _ a: DecorAnim) { if anim[uid] != nil { anim[uid] = a } }

    /// The top: spins down, wobbling more as it slows, tips over, lies a moment, rights itself.
    static func tickTop(_ a: inout DecorAnim, dt: Float) {
        if a.fallT >= 0 {
            a.fallT += dt
            if a.fallT > 1.7 { a.fallT = -1; a.spin = 0 }
            return
        }
        guard a.spin > 0 else { return }
        a.spinAngle += a.spin * dt
        a.spin *= expf(-0.45 * dt)
        if a.spin < 2 { a.fallT = 0; a.fallAxis = a.spinAngle.truncatingRemainder(dividingBy: 6.28) }
    }
    /// How far the top leans (rad) and about which horizontal angle: a wobble that grows as it slows, then the fall.
    static func topTilt(_ a: DecorAnim) -> (angle: Float, axis: Float) {
        if a.fallT >= 0 {
            let t = a.fallT
            let tip = t < 0.3 ? smooth(0, 0.3, t) : (t < 1.2 ? 1 : 1 - smooth(1.2, 1.7, t))
            return (0.07 + 0.28 * tip, a.fallAxis)
        }
        if a.spin <= 0 { return (0, 0) }          // at rest it stands upright
        return (0.07 * (1 + 2 * (1 - min(a.spin, 18) / 18)), a.spinAngle * 0.15)
    }

    /// The tower: gravity, a floor, friction; at rest for ~20 s, then it eases back into a stack.
    static let blockRest: [Float] = [0.18, 0.165, 0.15, 0.135, 0.115]
    static func tickBlocks(_ a: inout DecorAnim, dt: Float, uid: Int, held: Bool) {
        guard a.tumbleT >= 0 else { return }
        if held { a.blocks = []; a.tumbleT = -1; return }
        a.tumbleT += dt
        if a.tumbleT > 21.6 { a.blocks = []; a.tumbleT = -1; return }
        guard a.tumbleT < 20 else { return }
        for i in a.blocks.indices {
            var b = a.blocks[i]
            if b.rest { continue }
            b.vel.y -= 9 * dt
            b.pos += b.vel * dt
            b.yaw += b.yawV * dt; b.roll += b.rollV * dt
            let rest = blockRest[min(i, 4)]
            if b.pos.y <= rest {
                b.pos.y = rest
                if b.vel.y < -0.8 { b.vel.y *= -0.3 } else { b.vel.y = 0 }
                let k = expf(-4 * dt)
                b.vel.x *= k; b.vel.z *= k; b.yawV *= k; b.rollV *= k
                if b.vel.y == 0, simd_length(SIMD2(b.vel.x, b.vel.z)) < 0.08, abs(b.rollV) < 0.2 {
                    b.vel = .zero; b.rest = true
                    b.roll = (b.roll / (.pi / 2)).rounded() * (.pi / 2)         // settles flat on a face
                }
            }
            a.blocks[i] = b
        }
    }
    static func roll(_ a: inout DecorAnim, dt: Float, ignoring uid: Int, feet: [DecorFoot], kind: DecorKind = .ball) {
        let r = kind.rollRadius
        a.vel *= expf(kind == .toycar ? -1.4 * dt : -1.15 * dt)
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
        for f in feet where f.kind.rolls {
            if let a = anim[f.uid], !a.moving, simd_distance(a.pos, f.centre) > 0.05 { return (f.uid, a.pos) }
        }
        return nil
    }
}
