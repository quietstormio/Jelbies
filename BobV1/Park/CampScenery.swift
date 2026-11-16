//
//  CampScenery.swift
//  The Jelmiko Camp yard's scenery and camera (camp-yard-r1, step Y2). The yard is the park's scenery (ParkScenery.build(theme:camp: true): the same sky, hills, trees, back hedges, bench, lamp,
//  bushes and lawn) minus what a yard does not have (the gravel path inside the fence, the entrance hedges and stone piers, every toy) plus a fence ring (Blender posts and rails, an open gate at the
//  front with two taller gate posts) and a striped tent behind the back fence. The fence is VISUAL ONLY: the roam floor keeps the bodies inside (GameCamera.campCap), no collider is added.
//  The park's own mesh is untouched: every Camp branch is `if camp` / a defaulted parameter (ParkMeshGoldenTests pins the park's bytes).
//

import simd
import Foundation

enum CampScenery {
    typealias V2 = SIMD2<Float>
    /// The yard's fence rectangle (game units): sides at x +-4.2, back at z -5.1 (behind the bench, in front of the hedge at -6), front at z 5.9 (where the park's entrance hedge stood).
    static let halfWidth: Float = 4.2, backZ: Float = -5.1, frontZ: Float = 5.9
    /// The open gate in the front fence: centred on the old path's x, 1.9 wide (the two gate posts stand at its ends).
    static let gateX: Float = 0.63, gateHalf: Float = 0.95
    /// The tent: behind the back fence, in the middle of a bay (door +z, toward the yard).
    static let tent = SIMD3<Float>(-2.1, 0, -5.85)
    /// The art's own sizes (the Blender export): a rail is 1.25 long, posts are 0.20 wide.
    static let railLength: Float = 1.25, postWidth: Float = 0.20, railOverlap: Float = 0.15
    /// Posts about every 1.4: the bays per side (back 6, sides 8, front pieces 3 and 2).
    static let maxSpacing: Float = 1.4

    struct Layout {
        var posts: [V2] = []          // the ordinary posts
        var gatePosts: [V2] = []      // the two taller posts at the gate
        var rails: [(from: V2, to: V2)] = []          // one per bay (two bars in the art)
    }

    /// The ring as an open chain: back (left to right), right side (back to front), front right (to the gate), then from the gate's left post to the front left corner and up the left side.
    static func layout() -> Layout {
        var l = Layout()
        let g0 = V2(gateX - gateHalf, frontZ), g1 = V2(gateX + gateHalf, frontZ)
        let a = V2(-halfWidth, backZ), b = V2(halfWidth, backZ), c = V2(halfWidth, frontZ), d = V2(-halfWidth, frontZ)
        func run(_ p: V2, _ q: V2, bays: Int) -> [V2] { (0...bays).map { p + (q - p) * (Float($0) / Float(bays)) } }
        let chains: [[V2]] = [run(a, b, bays: 6) + run(b, c, bays: 8).dropFirst(), run(c, g1, bays: 2), run(g0, d, bays: 3) + run(d, a, bays: 8).dropFirst()]
        // chain 0 runs a ... c; chain 1 c ... g1; chain 2 g0 ... d ... a (the ring closes at `a`, which is already chain 0's first post)
        var seen: [V2] = []
        for (ci, chain) in chains.enumerated() {
            for (i, p) in chain.enumerated() {
                let isGate = (ci == 1 && i == chain.count - 1) || (ci == 2 && i == 0)
                if isGate { l.gatePosts.append(p) }
                else if !seen.contains(where: { simd_distance($0, p) < 0.01 }) { l.posts.append(p); seen.append(p) }
                if i > 0 { l.rails.append((from: chain[i - 1], to: p)) }
            }
        }
        // the last rail of chain 2 ends on `a`, the first post of chain 0 (already counted once)
        return l
    }

    /// The rail's x scale for a bay between two post centres (the art's rail is 1.25 for a 1.40 spacing: it reaches `railOverlap` into the posts' inner faces).
    static func railScale(from p: V2, to q: V2) -> Float { (simd_distance(p, q) - railOverlap) / railLength }

    private enum Art {
        static let post = DecorMeshes.load("camp_post", prefix: "park_")
        static let rail = DecorMeshes.load("camp_rail", prefix: "park_")
        static let gate = DecorMeshes.load("camp_gate_post", prefix: "park_")
        static let tent = DecorMeshes.load("camp_tent", prefix: "park_")
    }
    /// True when the four pieces loaded from the bundle.
    static var artLoaded: Bool { Art.post != nil && Art.rail != nil && Art.gate != nil && Art.tent != nil }

    /// Stamps the fence ring and the tent into the park mesh being built (static: no per-frame cost, no extra draw call).
    static func stamp(_ b: RoomMeshBuilder) {
        let l = layout()
        typealias V3 = SIMD3<Float>
        if let post = Art.post { for p in l.posts { ParkScenery.stamp(b, post, at: V3(p.x, 0, p.y), yaw: 0, k: 1, ky: 1, tint: [:]) } }
        if let gate = Art.gate { for p in l.gatePosts { ParkScenery.stamp(b, gate, at: V3(p.x, 0, p.y), yaw: 0, k: 1, ky: 1, tint: [:]) } }
        if let rail = Art.rail {
            for r in l.rails {
                let mid = (r.from + r.to) / 2, dir = r.to - r.from
                // the rail's own x runs along the bay; `stamp` scales x and z by k (the bar's depth varies by 2%, invisible), yaw turns local x onto the bay
                ParkScenery.stamp(b, rail, at: V3(mid.x, 0, mid.y), yaw: atan2f(-dir.y, dir.x), k: railScale(from: r.from, to: r.to), ky: 1, tint: [:])
            }
        }
        if let t = Art.tent { ParkScenery.stamp(b, t, at: tent, yaw: 0, k: 1, ky: 1, tint: [:]) }
    }
}

extension ParkScenery {
    /// The gravel path of the Camp yard starts here (z, going down the screen): only the bit from the gate down is kept.
    static let campPathFrom: Float = CampScenery.frontZ
}

extension GameCamera {
    /// The Camp yard's roam caps (nil = not in Camp): every roam row at most `halfWidth` wide and no row further back than `minZ`, whatever the screen shows (RoamFloor.refreshRoam).
    nonisolated(unsafe) static var campCap: (halfWidth: Float, minZ: Float)?
    /// The yard's landscape pull-in (the park's is 0.35): a little less, so the fence ring with its posts has a margin on an iPad's 4:3 landscape.
    static let campLandscapePull: Float = 0.32

    /// The yard's camera: the park's pose as is (portrait widening, landscape pull-in, the pan that puts the floor's front edge at 79% / 68.5% of the screen height), with the roam
    /// rectangles narrowed to the fence: >= 1 m between a body centre and the fence everywhere (1.5 m at the back). The caps make the roam floor itself no wider than the fence.
    static func configureCamp() {
        configurePark()
        roamRect = (SIMD2(-3.2, -3.6), SIMD2(3.2, 4.5)); roamRectWide = roamRect
        campCap = (3.2, -3.8)
    }
}

extension RoomCatalog {
    /// The Camp yard's room: the park's definition (same bench collider, theme, lamp) under its own id, so the renderer builds the yard's mesh. Like the park it is applied under the white wipe
    /// WITHOUT moving in (nothing is saved), and it is not in `RoomCatalog.all`.
    static let camp: RoomDef = {
        var d = RoomCatalog.park
        d.id = .camp; d.title = "Jelmiko Camp"; d.blurb = "A fenced yard where the Jelmiko who wait for a home play."
        return d
    }()
}
