//
//  DiningSet.swift
//  The meal TRAY controller: a short little tray with ONE shared serving (food or drink, scaled for N Blobs) that pops in with a puff
//  at the front spot and poofs away when everyone is done. Props only; NO Bob motion lives here.
//
//  Hooks for the motion phase:
//    - places                 one per Blob: stand position, facing yaw and mouth anchor (world)
//    - strawTip(place:)       drinks: each Blob's own bendy straw ends exactly at that place's mouth anchor
//    - pieceAnchorWorld / forkRest   where berries / forks lie; hold(.piece / .fork, place:, transform:) makes one follow a world
//                             transform every frame ("sticks to the nub"); beginBite / finishBite are shared by every food
//    - RoomLayout.dynamicBoxes  the tray is a walk-resolver obstacle only while it exists
//

import simd
import Foundation

nonisolated struct DiningFrame {
    var opaque: RoomMesh
    var translucent: RoomMesh
}

nonisolated enum HeldKind { case piece, fork, bite }

/// One place around the tray in WORLD space.
nonisolated struct DiningPlace: Equatable {
    var stand: SIMD2<Float>
    var yaw: Float
    var mouth: SIMD3<Float>
}

/// Shared pop / poof curves (to move into BlobMotion's shared easing when the motion rework lands).
nonisolated enum DiningCurve {
    static let popDuration: Float = 0.25
    static let poofDuration: Float = 0.4
    /// Back-ease overshoot constant: peak ~1.085 (0 -> ~1.08 -> 1).
    static let overshoot: Float = 1.55
    static func pop(_ u: Float) -> Float {
        let x = min(max(u, 0), 1) - 1
        return 1 + (overshoot + 1) * x * x * x + overshoot * x * x
    }
    static func poof(_ u: Float) -> Float {
        let x = min(max(u, 0), 1)
        return 1 - x * x * (3 - 2 * x)
    }
}

/// Where the tray appears (centre x, z): the same front spot every time; beside / behind Bob if he stands on the tray.
nonisolated enum DiningSpot {
    static let preferred = SIMD2<Float>(0, 1.3)
    /// Bob's footprint radius for the overlap test against the tray itself (he is meant to stand at a PLACE, not on the tray).
    static let bobClearance: Float = 0.7
    static let minZ: Float = -1.0, maxZ: Float = 2.4
    static let ndcLimit: Float = 0.94

    /// Distance from a floor point to the tray rectangle (0 inside).
    static func distance(from p: SIMD2<Float>, origin o: SIMD2<Float>, layout L: TrayLayout) -> Float {
        let dx = max(abs(p.x - o.x) - L.half.x, 0), dz = max(abs(p.y - o.y) - L.half.y, 0)
        return (dx * dx + dz * dz).squareRoot()
    }

    static func viewProj(aspect: Float) -> simd_float4x4 {
        M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.3, far: 60),
               M4.lookAt(eye: GameCamera.eye, at: GameCamera.target, up: SIMD3(0, 1, 0)))
    }

    /// The tray at its pop overshoot, the serving, and every place (body width + head top) must project inside the screen.
    static func onScreen(origin o: SIMD2<Float>, layout L: TrayLayout, aspect: Float) -> Bool {
        let vp = viewProj(aspect: aspect), k: Float = 1.09
        var pts: [SIMD3<Float>] = []
        for sx in [Float(-1), 1] { for sz in [Float(-1), 1] { for y in [Float(0), 0.3 * k] {
            pts.append(SIMD3(o.x + sx * (L.half.x + 0.2) * k, y, o.y + sz * L.half.y * k))
        } } }
        pts.append(SIMD3(o.x, DiningDims.trayTop + 0.6 * L.scale, o.y))                      // top of the serving
        for p in L.places {
            let c = SIMD3(o.x + p.rel.x, 0, o.y + p.rel.y)
            pts.append(c + SIMD3(-0.62, 0.7, 0)); pts.append(c + SIMD3(0.62, 0.7, 0)); pts.append(c + SIMD3(0, DiningDims.headTop, 0)); pts.append(c)
        }
        for p in pts {
            let c = vp * SIMD4(p, 1)
            guard c.w > 0.1 else { return false }
            if abs(c.x / c.w) > ndcLimit || abs(c.y / c.w) > ndcLimit { return false }
        }
        return true
    }

    static func isClear(origin o: SIMD2<Float>, layout L: TrayLayout, of bob: SIMD2<Float>, aspect: Float) -> Bool {
        guard distance(from: bob, origin: o, layout: L) >= bobClearance else { return false }
        guard onScreen(origin: o, layout: L, aspect: aspect) else { return false }
        let b = L.bounds
        for x in [o.x + b.minX, o.x + b.maxX] where RoomLayout.sofaDistanceXZ(SIMD2(x, o.y + b.minZ)) < 0.05 { return false }
        for f in RoomLayout.decorFeet where f.spec.solid && distance(from: f.centre, origin: o, layout: L) < f.radius + 0.1 { return false }          // never on a beanbag or a toy box
        return o.y + b.minZ > RoomLayout.minZ + 0.2
    }

    /// The same front spot every time; if Bob stands on it, the nearest clear spot beside (or behind) him, always fully on screen.
    static func choose(bob: SIMD2<Float>, layout L: TrayLayout, aspect: Float = GameCamera.aspect) -> SIMD2<Float> {
        if isClear(origin: preferred, layout: L, of: bob, aspect: aspect) { return preferred }
        var best = preferred, bestCost = Float.infinity
        var fallback = preferred, fallbackD: Float = -1
        var x: Float = -1.6
        while x <= 1.6001 {
            var z = minZ
            while z <= maxZ + 1e-4 {
                let o = SIMD2<Float>(x, z)
                if onScreen(origin: o, layout: L, aspect: aspect) {
                    let d = distance(from: bob, origin: o, layout: L)
                    if d >= bobClearance {
                        let cost = abs(x - preferred.x) + 1.4 * abs(z - preferred.y)
                        if cost < bestCost - 1e-5 { bestCost = cost; best = o }
                    }
                    if d > fallbackD { fallbackD = d; fallback = o }
                }
                z += 0.1
            }
            x += 0.05
        }
        return bestCost < .infinity ? best : fallback
    }
}

final class DiningSet {
    enum Phase { case absent, popping, present, poofing }

    private(set) var phase: Phase = .absent
    private(set) var origin = DiningSpot.preferred          // tray centre on the floor (x, z)
    private(set) var scale: Float = 0
    private var t: Float = 0
    private var startScale: Float = 1
    private(set) var n = 1
    private(set) var layout = DiningLayout.make(n: 1)
    private(set) var serving: Consumable = Consumables.berries
    /// Bites left per Blob (every serving = 3 bites each).
    private(set) var bitesLeft: [Int] = [3]
    private(set) var pieceInHand: [Int?] = [nil]
    private(set) var forkBite: [Bool] = [false]
    /// Fraction of each Blob's share of the drink he has drunk (0...1). `drinkFill` is what is left in the container (1 full ... 0.3 empty).
    private(set) var drunk: [Float] = [0]
    var drinkFill: Float { 1 - 0.7 * (drunk.reduce(0, +) / Float(max(drunk.count, 1))) }
    private var piecePose: [simd_float4x4?] = [nil]
    private var forkPose: [simd_float4x4?] = [nil]
    /// Fork foods, the toss: the forkful flying off the tines into his mouth.
    private var biteFlight: [simd_float4x4?] = [nil]
    private var biteFlying: [Bool] = [false]
    var biteInFlight: [Bool] { biteFlying }
    /// Fork-foods: the fork is not on the tray; it poofs into his hand at the nub (`appearFork`) and poofs away at the end (`poofFork`).
    private var forkT: [Float] = [0]
    private var forkPhase: [Int] = [0]           // 0 none, 1 popping in, 2 in hand, 3 poofing out
    var forkVisible: [Bool] { forkPhase.map { $0 != 0 } }
    let puffs = PuffEffect()

    /// DEBUG slow motion for captures (1 = real time).
    var timeScale: Float = 1

    private var dirty = false
    private var cacheTint: SIMD3<Float>?
    private var puffSphere = RoomMesh()
    private var shadowTray = RoomMesh()
    private var groupKey = "", groupOpaque = RoomMesh(), groupTranslucent = RoomMesh()
    private var worldKey = "", worldOpaque = RoomMesh(), worldTranslucent = RoomMesh()
    private var forkMeshes: [Bool: RoomMesh] = [:]
    private var heldBerry: [String: RoomMesh] = [:]

    nonisolated deinit {}

    // MARK: Geometry of the set

    var isPresent: Bool { phase != .absent }
    var trayTop: Float { DiningDims.trayTop }

    /// The places around the tray in world space (stand, facing yaw, mouth anchor).
    var places: [DiningPlace] {
        layout.places.indices.map { i in
            let m = layout.mouthRel(i), p = layout.places[i]
            return DiningPlace(stand: origin + p.rel, yaw: p.yaw, mouth: SIMD3(origin.x + m.x, m.y, origin.y + m.z))
        }
    }
    /// Straw of place `i` in world space (drinks): the tip is exactly places[i].mouth once the tray is at full scale.
    func strawPathWorld(place i: Int) -> [SIMD3<Float>] {
        DiningModels.strawPath(layout: layout, drink: serving, place: i).map { SIMD3(origin.x + $0.x, $0.y, origin.y + $0.z) }
    }
    func strawTip(place i: Int) -> SIMD3<Float>? { strawPathWorld(place: i).last }

    /// World position of berry `j` of place `i` resting on the plate.
    func pieceAnchorWorld(place i: Int, index j: Int) -> SIMD3<Float> {
        let a = (serving.id == Consumables.pizza.id || serving.pizzaLayout) ? DiningModels.pizzaAnchor(layout: layout, place: i, index: j) : DiningModels.berryAnchor(layout: layout, place: i, index: j)
        return SIMD3(origin.x + a.x, a.y, origin.y + a.z)
    }
    /// Where place `i`'s fork lies on the tray (world position + yaw; tines point along (sin yaw, cos yaw)).
    func forkRestWorld(place i: Int) -> (pos: SIMD3<Float>, yaw: Float) {
        let r = DiningModels.forkRest(layout: layout, place: i)
        return (SIMD3(origin.x + r.pos.x, r.pos.y, origin.y + r.pos.z), r.yaw)
    }
    /// World point the fork stabs at for place `i`'s next forkful: the near part of a wedge-shaped fork food (the apex side toward the stands), on its top.
    /// (Dormant: no fork food in the catalogue now; was the cake: R = 0.3 s k, apex offset -0.14 s, top layer 0.152 s).
    func forkBitePoint(place i: Int) -> SIMD3<Float> {
        let s = layout.scale
        let frac = Float(max(totalBitesLeft, 1)) / Float(DiningTiming.bitesPerServing * n)
        let R = 0.3 * s * (0.4 + 0.6 * frac)
        return SIMD3(origin.x, DiningDims.plateFloorY + 0.16 * s, origin.y + (-0.14 * s + 0.35 * R))
    }
    /// Next piece place `i` will eat (finger foods).
    func nextPiece(place i: Int) -> Int { DiningTiming.bitesPerServing - bitesLeft[i] }
    var totalBitesLeft: Int { bitesLeft.reduce(0, +) }

    private func refreshColliders() {
        guard phase != .absent, phase != .poofing else { RoomLayout.dynamicBoxes = []; return }         // the collider goes the moment the tray starts to poof
        let s = max(scale, 0.001)
        RoomLayout.dynamicBoxes = [.init(centre: origin, half: layout.colliderHalf * s, height: (DiningDims.trayTop + DiningDims.trayRim) * s)]
    }

    /// Floor obstacle for a sphere (same math the walk resolver uses).
    func obstacle(_ p: SIMD3<Float>, radius: Float) -> SIMD3<Float> {
        var q = p
        for b in RoomLayout.dynamicBoxes { RoomLayout.pushOut(&q, radius: radius, box: b) }
        return q
    }

    // MARK: Spawn / despawn

    /// Pops the tray in at the front spot (beside Bob if he stands on it) with the shared serving for `n` Blobs. False if one is already out.
    @discardableResult
    func spawn(serving s: Consumable, n count: Int = 1, bobAt bob: SIMD2<Float>, aspect: Float = GameCamera.aspect, forcedOrigin: SIMD2<Float>? = nil) -> Bool {
        guard phase == .absent else { return false }
        n = min(max(count, 1), 3); layout = DiningLayout.make(n: n); serving = s
        bitesLeft = Array(repeating: DiningTiming.bitesPerServing, count: n)
        pieceInHand = Array(repeating: nil, count: n); forkBite = Array(repeating: false, count: n)
        piecePose = Array(repeating: nil, count: n); forkPose = Array(repeating: nil, count: n)
        biteFlight = Array(repeating: nil, count: n); biteFlying = Array(repeating: false, count: n)
        forkT = Array(repeating: 0, count: n); forkPhase = Array(repeating: 0, count: n)
        drunk = Array(repeating: 0, count: n)
        origin = forcedOrigin ?? DiningSpot.choose(bob: bob, layout: layout, aspect: aspect)
        phase = .popping; t = 0; scale = 0
        puffNow()
        AudioHub.shared.play(.setdown)          // the plate / cup lands on the floor
        refreshColliders(); dirty = true
        return true
    }

    /// Poofs the tray away (shrinks inside a puff, then it is gone).
    func despawn() {
        guard phase == .popping || phase == .present else { return }
        startScale = scale
        phase = .poofing; t = 0
        RoomLayout.dynamicBoxes = []                                  // the collider is gone at once
        puffNow()
        pieceInHand = Array(repeating: nil, count: n); piecePose = Array(repeating: nil, count: n)
        for i in 0..<n where forkPhase[i] != 0 && forkPhase[i] != 3 { poofFork(place: i) }          // a fork still in hand goes with the tray
        dirty = true
    }

    /// Instant removal (tests, abandoned screens).
    func reset() {
        phase = .absent; scale = 0; t = 0
        pieceInHand = Array(repeating: nil, count: n); forkPose = Array(repeating: nil, count: n); piecePose = Array(repeating: nil, count: n)
        forkBite = Array(repeating: false, count: n); biteFlying = Array(repeating: false, count: n); biteFlight = Array(repeating: nil, count: n)
        forkT = Array(repeating: 0, count: n); forkPhase = Array(repeating: 0, count: n)
        puffs.reset()
        RoomLayout.dynamicBoxes = []
        dirty = true
    }

    private func puffNow() {
        let s = layout.scale
        puffs.spawn(at: SIMD3(origin.x, 0.4, origin.y), radius: 0.6 * s)
        if n > 1 {
            puffs.spawn(at: SIMD3(origin.x - layout.half.x * 0.7, 0.35, origin.y), radius: 0.45)
            puffs.spawn(at: SIMD3(origin.x + layout.half.x * 0.7, 0.35, origin.y), radius: 0.45)
        }
    }

    // MARK: Bites (shared by every food: 3 per Blob)

    /// Starts place `i`'s next bite. Finger foods: that Blob's next berry lifts off the plate and is drawn at the piece pose. Fork foods:
    /// his fork takes a forkful (the food shrinks, the bite sits on the tines). False when nothing is left for him.
    @discardableResult
    func beginBite(place i: Int) -> Bool {
        guard i >= 0, i < n, bitesLeft[i] > 0, phase == .present || phase == .popping else { return false }
        switch serving.eatStyle {
        case .finger: guard pieceInHand[i] == nil else { return false }; pieceInHand[i] = nextPiece(place: i)
        case .fork: guard !forkBite[i] else { return false }; forkBite[i] = true; bitesLeft[i] -= 1
        case .sip: return false
        }
        dirty = true
        return true
    }

    /// Drinks: place `i` has drunk `fraction` (0...1) of his share; the container's level drops with it.
    func setDrunk(place i: Int, _ fraction: Float) {
        guard i >= 0, i < n else { return }
        let f = min(max(fraction, 0), 1)
        if Int(f * Float(DiningTiming.bitesPerServing)) > Int(drunk[i] * Float(DiningTiming.bitesPerServing)) { AudioHub.shared.play(.slurp) }       // a gulp
        if abs(f - drunk[i]) > 1e-4 { drunk[i] = f; dirty = true }
        // the bottle drains through ServingState.totalLeft: one step per gulp, half way into the gulp
        if serving.eatStyle == .sip { bitesLeft[i] = max(0, DiningTiming.bitesPerServing - Int((f * Float(DiningTiming.bitesPerServing)).rounded())); dirty = true }
    }

    /// The bite is swallowed: the piece / forkful is gone.
    func finishBite(place i: Int) {
        guard i >= 0, i < n else { return }
        switch serving.eatStyle {
        case .finger: if pieceInHand[i] != nil { bitesLeft[i] -= 1; pieceInHand[i] = nil; piecePose[i] = nil; AudioHub.shared.play(serving.chew, jelly: i) }
        case .fork: if forkBite[i] || biteFlying[i] { AudioHub.shared.play(.chomp, jelly: i) }; forkBite[i] = false; biteFlying[i] = false; biteFlight[i] = nil
        case .sip: break
        }
        dirty = true
    }

    /// The toss: the forkful leaves the tines (the fork is drawn without it) and flies; `hold(.bite, ...)` supplies its transform each frame.
    func launchBite(place i: Int) {
        guard i >= 0, i < n, forkBite[i] else { return }
        forkBite[i] = false; biteFlying[i] = true; dirty = true
    }

    // MARK: Held items ("stick to the nub")

    /// Supplies the world transform of place `i`'s held piece (needs a bite in progress) or fork (replaces the resting fork) for this frame.
    func hold(_ kind: HeldKind, place i: Int, transform m: simd_float4x4) {
        guard i >= 0, i < n else { return }
        switch kind {
        case .piece: piecePose[i] = m
        case .bite: if biteFlying[i] { biteFlight[i] = m }
        case .fork:
            if forkPhase[i] == 0 { forkPhase[i] = 2 }                        // supplied without `appearFork`: simply there
            if forkPhase[i] != 3 { forkPose[i] = m }
        }
        dirty = true
    }

    /// The bite is abandoned (he was grabbed): the piece in hand goes back on the plate, nothing is eaten.
    func cancelBite(place i: Int) {
        guard i >= 0, i < n else { return }
        if pieceInHand[i] != nil { pieceInHand[i] = nil; piecePose[i] = nil }
        if forkBite[i] || biteFlying[i] { forkBite[i] = false; biteFlying[i] = false; biteFlight[i] = nil; bitesLeft[i] += 1 }
        dirty = true
    }

    /// A small puff at his nub and the fork pops into his hand (same pop curve as the tray). Call `hold(.fork, ...)` every frame after this.
    func appearFork(place i: Int, at p: SIMD3<Float>) {
        guard i >= 0, i < n, forkPhase[i] == 0 else { return }
        forkPhase[i] = 1; forkT[i] = 0
        puffs.spawn(at: p, radius: 0.2)
        dirty = true
    }

    /// The fork poofs away (puff + shrink at its last pose). Finger pieces just let go.
    func poofFork(place i: Int) {
        guard i >= 0, i < n, forkPhase[i] != 0, forkPhase[i] != 3 else { return }
        forkPhase[i] = 3; forkT[i] = 0
        if let m = forkPose[i] { puffs.spawn(at: SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z), radius: 0.2) }
        dirty = true
    }

    /// Lets go instantly: a held fork or piece is simply removed (the game uses `poofFork` for the fork).
    func release(_ kind: HeldKind, place i: Int) {
        guard i >= 0, i < n else { return }
        switch kind {
        case .piece: piecePose[i] = nil
        case .bite: biteFlight[i] = nil; biteFlying[i] = false
        case .fork: forkPhase[i] = 0; forkPose[i] = nil                  // instant (the animated way out is `poofFork`)
        }
        dirty = true
    }

    // MARK: Update

    func update(dt rawDt: Float) {
        let dt = rawDt * timeScale
        if puffs.isActive { puffs.update(dt: dt); dirty = true }
        for i in 0..<n where forkPhase[i] != 0 {
            forkT[i] += dt; dirty = true
            if forkPhase[i] == 1, forkT[i] >= DiningCurve.popDuration { forkPhase[i] = 2 }
            if forkPhase[i] == 3, forkT[i] >= DiningCurve.poofDuration { forkPhase[i] = 0; forkPose[i] = nil }
        }
        switch phase {
        case .absent: break
        case .popping:
            t += dt
            scale = DiningCurve.pop(t / DiningCurve.popDuration)
            if t >= DiningCurve.popDuration { phase = .present; scale = 1 }
            refreshColliders(); dirty = true
        case .present: break
        case .poofing:
            t += dt
            scale = startScale * DiningCurve.poof(t / DiningCurve.poofDuration)
            if t >= DiningCurve.poofDuration {
                phase = .absent; scale = 0
                pieceInHand = Array(repeating: nil, count: n); forkBite = Array(repeating: false, count: n); biteFlying = Array(repeating: false, count: n); biteFlight = Array(repeating: nil, count: n)
            }
            refreshColliders(); dirty = true
        }
    }

    // MARK: Mesh for the renderer

    /// The set's current meshes (world space), or nil when nothing changed since the last call.
    func frame(theme: RoomTheme) -> DiningFrame? {
        guard dirty else { return nil }
        dirty = puffs.isActive || phase == .popping || phase == .poofing || forkPhase.contains { $0 != 0 }
        if cacheTint != theme.tint { rebuildStatics(theme) }
        let D = DiningModels.self
        let op = RoomMeshBuilder(), tr = RoomMeshBuilder()
        op.material = .plain; tr.material = .plain
        let s = scale
        if phase != .absent && s > 0.05 {
            let skipped = Set((0..<n).compactMap { i in pieceInHand[i].map { i * 3 + $0 } })
            let key = "\(serving.id)-\(n)-\(bitesLeft)-\(skipped.sorted())"
            if key != groupKey {
                groupKey = key
                let g = D.trayGroup(layout: layout, serving: serving, state: ServingState(n: n, bitesLeft: bitesLeft, skipped: skipped), theme: theme)
                groupOpaque = g.opaque; groupTranslucent = g.translucent
                trayShadow(theme)
            }
            let wk = "\(key)|\(origin.x),\(origin.y)"
            if phase == .present, wk == worldKey {
                op.mesh = worldOpaque; tr.mesh = worldTranslucent               // settled: reuse the world-space tray (cheap array copy)
            } else {
                let m = D.translation(SIMD3(origin.x, 0, origin.y), scale: s)
                D.append(groupOpaque, to: op, transform: m)
                D.append(groupTranslucent, to: tr, transform: m)
                D.append(shadowTray, to: tr, transform: m, alpha: min(s, 1))
                if phase == .present { worldKey = wk; worldOpaque = op.mesh; worldTranslucent = tr.mesh }
            }
            // held pieces / forks follow their transforms (shrinking with the tray while it poofs)
            let setScale = phase == .poofing ? s : 1
            for i in 0..<n {
                if let j = pieceInHand[i] {
                    let m = piecePose[i] ?? D.translation(pieceAnchorWorld(place: i, index: j))
                    D.append(heldBerryMesh(i * 3 + j), to: op, transform: m * Self.scaled(setScale))
                }
                if biteFlying[i], let m = biteFlight[i] { D.append(biteMesh(), to: op, transform: m * Self.scaled(setScale)) }
                if let m = forkPose[i], forkPhase[i] != 0 {
                    let k: Float = forkPhase[i] == 1 ? DiningCurve.pop(forkT[i] / DiningCurve.popDuration) : forkPhase[i] == 3 ? DiningCurve.poof(forkT[i] / DiningCurve.poofDuration) : 1
                    D.append(forkMesh(withBite: forkBite[i] && serving.eatStyle == .fork), to: op, transform: m * Self.scaled(max(k, 0.001)))
                }
            }
        }
        puffs.append(to: tr, sphere: puffSphere)
        return DiningFrame(opaque: op.mesh, translucent: tr.mesh)
    }

    static func scaled(_ s: Float) -> simd_float4x4 { simd_float4x4(diagonal: SIMD4(s, s, s, 1)) }

    private func rebuildStatics(_ theme: RoomTheme) {
        cacheTint = theme.tint
        puffSphere = DiningModels.puffSphere(theme: theme)
        shadowTray = RoomMesh()
        groupKey = ""; worldKey = ""; forkMeshes = [:]; heldBerry = [:]; biteChunk = nil
    }

    private func trayShadow(_ theme: RoomTheme) {
        shadowTray = DiningModels.contactShadow(halfX: layout.half.x + 0.2, halfZ: layout.half.y + 0.16, strength: 0.34, color: theme.swatches[0])
    }

    private func forkMesh(withBite: Bool) -> RoomMesh {
        if let m = forkMeshes[withBite] { return m }
        let m = DiningModels.fork(withBite: withBite); forkMeshes[withBite] = m; return m
    }
    private var biteChunk: RoomMesh?
    private func biteMesh() -> RoomMesh {
        if let m = biteChunk { return m }
        let b = RoomMeshBuilder(); b.material = .plain
        DiningModels.forkBiteChunk(b, centre: .zero)
        biteChunk = b.mesh; return b.mesh
    }
    private func heldBerryMesh(_ gi: Int) -> RoomMesh {
        let key = "\(serving.id)-\(gi)-\(n)"
        if let m = heldBerry[key] { return m }
        let m: RoomMesh
        if serving.id == Consumables.pizza.id { m = DiningModels.heldSlice(scale: layout.scale) }
        else if serving.pizzaLayout && serving.piece == nil { m = DiningModels.heldSlice(scale: layout.scale, palette: serving.palette) }
        else if serving.piece != nil { m = DiningModels.heldPiece(serving, index: gi, scale: layout.scale) }
        else { m = DiningModels.heldBerry(color: gi / 3 + gi % 3, scale: layout.scale) }
        heldBerry[key] = m; return m
    }
}
