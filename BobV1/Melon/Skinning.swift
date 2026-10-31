//
//  Skinning.swift
//  Every render vertex (body, seeds, bubbles) follows its embedding tetrahedron.
//  Output layout per vertex: pos xyz + normalized normal xyz (6 floats). Port of skin().
//  Also owns the eyes' blink: after skinning, each eye (and its glint) is flattened toward the eye's skinned centre
//  along the eye's current local up axis. `setEyeOpenness` is the hook for expressions (squints, sleepy, wide).
//

import Foundation
import simd

nonisolated final class Skinner {
    let vertexCount: Int
    private let skinIdx: [Int32]    // 4 sim particle indices per vertex
    private let skinW: [Float]      // 4 barycentric weights per vertex

    // eyes
    private let eyeIdx: [[Int32]]
    private let glintIdx: [[Int32]]
    private let browIdx: [[Int32]]
    private let anchorIdx: [Int32]  // 4 particles per virtual point: [centre0, up0, centre1, up1]
    private let anchorW: [Float]
    private let hasEyes: Bool

    /// Closed eyes are this fraction of full height: reads as a lid line.
    static let closedHeight: Float = 0.08
    /// Expression openness per eye, 0 (shut) ... 1 (open). Combined with the automatic blink.
    private(set) var openness: (left: Float, right: Float) = (1, 1)
    /// Automatic blinking (random 2-6 s apart, ~120 ms, sometimes a double blink). Turn off for scripted expressions.
    var autoBlink = true
    let jelly = JellyJiggle()
    var dbgJellyOff = UserDefaults.standard.integer(forKey: "JellyOff") != 0
    /// Touch play: 0...1, blurs the skin normals over their neighbours while a finger dents him, so the dent reads as a soft dimple and the steep
    /// walls of the coarse sim mesh never shade as dark brown blotches. 0 = exactly the plain normals (the default, the cost is zero).
    var normalSmoothing: Float = 0
    /// Touch play: where the dent is (world) and how far it reaches. While `normalSmoothing` > 0 only the skin around this point is relaxed
    /// (positions: Taubin lambda|mu, so the folds the coarse sim mesh makes beside the sphere melt into a dimple; then the normals).
    var smoothCenter = SIMD3<Float>(0, 0, 0)
    static let dentInner: Float = 0.40, dentOuter: Float = 0.70
    static let normalPasses = 2, dentPasses = 4, eyeNormalPasses = 6
    private var eyeFixK: [Float] = [1, 1], eyeFixU: [SIMD3<Float>] = [.zero, .zero]
    private var eyeNbStart: [Int32] = [], eyeNb: [Int32] = [], eyeOwner: [Int8] = []
    static let normalInner: Float = 0.5, normalOuter: Float = 0.8
    private var bodyList: [Int32] = [], bodyW: [Float] = [], dentFrame = 0, dentBuiltAt = SIMD3<Float>(1e9, 0, 0)
    private var dentList: [Int32] = [], dentW: [Float] = [], dentTmp: [SIMD3<Float>] = []
    private var adjStart: [Int32] = [], adjList: [Int32] = [], smoothMask: [Bool] = [], smoothTmp: [Float] = []
    private var blinking = false
    private var blinkT: Float = 0             // seconds into the current blink
    private var gap: Float = 0                // pause between the two blinks of a double blink
    private var blinkWait: Float = 2.5
    private var doubleLeft = 0
    private var rng: UInt32 = 0x2F6E2B1
    /// Current eye height factors (closedHeight ... 1) after expression + blink (left, right).
    private(set) var eyeHeight: (left: Float, right: Float) = (1, 1)
    private var blinkOpen: Float = 1

    /// Animation hook (BlobBrain arm paths): additive world-space displacement of some render vertices, plus the AO value
    /// written to those vertices' mat channel (see `takeMatWrites`). Empty = off.
    var overrideVertices: [Int32] = []
    var overrideDelta: [SIMD3<Float>] = []
    var overrideMat: [Float] = []
    /// Touch play (cheek squeeze): additive world-space displacement of some render vertices, applied after skinning. Empty = off.
    var extraVertices: [Int32] = []
    var extraDelta: [SIMD3<Float>] = []
    /// Vertices of the eyes, glints and brows (a skin offset must not drag the face features around).
    var faceFeatureVertices: Set<Int32> { Set(eyeIdx.joined()).union(glintIdx.joined()).union(browIdx.joined()) }
    private var pendingRestore: [Int32] = []

    // MARK: foot beans
    // Each foot is a closed bean (FootBean) in the render mesh, hidden inside the belly at rest. While he moves his feet the brain hands over
    // the bean's world-space vertices (`beanPos`) and a blend 0...1: the bean grows from its hidden skinned shape to the working shape, and the
    // embedded foot's skin (`retractVertices`) is pushed (rest-space deltas, rotated by `retractMatrix`) onto the footless egg at the same time.
    // blend = 0: nothing is touched and the render is bit-identical to the plain skinning.
    var beanFirst: [Int] = []
    nonisolated(unsafe) static var dbgNoArmRetract = UserDefaults.standard.integer(forKey: "ArmNoRetract") != 0
    nonisolated(unsafe) static var dbgNoRetract = UserDefaults.standard.integer(forKey: "LegNoRetract") != 0
    var beanPos: [[SIMD3<Float>]] = [[], []]
    var beanStart: [[SIMD3<Float>]] = [[], []]         // the inset bean in the body-rigid foot pose: where each bean starts from at blend 0
    var beanBlend: Float = 0
    // Pip's tail (TailBean): a block of body vertices after the foot beans. Off (every Jelly but Pip), it is collapsed onto its base pole (zero-area, invisible).
    // On, it sways (walking), wags (happy) and bobs (vertical motion); `tailYaw` / `tailPitch` (deg) are read by the spike layer so the tail spikes ride it.
    var tailFirst = -1, tailOn = false, tailHappy = false
    private var tailLM: [Int] = [], tailLMRest: [SIMD3<Float>] = []
    /// Where Pip's tail block is and which three egg vertices carry it (see TailBean.landmarks).
    func configureTail(_ rm: RenderMesh) {
        guard let cap = rm.armCapsule, cap.tailFirst >= 0 else { return }
        tailFirst = cap.tailFirst
        tailLM = TailBean.landmarks(rest: rm.rest, eggLimit: cap.firstVertex.min() ?? rm.vertexCount)
        tailLMRest = tailLM.map { SIMD3(rm.rest[3 * $0], rm.rest[3 * $0 + 1], rm.rest[3 * $0 + 2]) }
        // the swell: the egg's own lower-back vertices near the tail root are pushed out along the tail's start direction (Gaussian falloff, lower back only:
        // TailBean.swellWeight), so the back flows into the tail root as one surface instead of a tube meeting a wall
        let limit = cap.firstVertex.min() ?? rm.vertexCount
        tailBump = []
        for v in 0..<min(limit, rm.rest.count / 3) {
            let d = TailBean.swellVector(SIMD3(rm.rest[3 * v], rm.rest[3 * v + 1], rm.rest[3 * v + 2]))
            if simd_length(d) > 0.003 { tailBump.append((v, d)) }
        }
    }
    private var tailBump: [(Int, SIMD3<Float>)] = []
    private var tailRotLast = matrix_identity_float3x3
    /// After the normal pass: pull the root rings' normals toward the egg's own normal there, so the shading flows from the back into the tail with no tonal step.
    private func blendTailNormals(_ dyn: UnsafeMutablePointer<Float>) {
        let f = tailFirst >= 0 ? tailFirst : TailBean.builtFirst, n = TailBean.vertexCount
        guard tailScale > 0.001, tailLM.count == 3, f >= 0, f + n <= vertexCount else { return }
        for i in 0..<n {
            let w = TailBean.normalBlend[i]
            if w <= 0.001 { continue }
            let o = 6 * (f + i) + 3
            let cur = SIMD3(dyn[o], dyn[o + 1], dyn[o + 2]), ref = tailRotLast * TailBean.bodyNormals[i]
            let m = simd_normalize(cur + (ref - cur) * w)
            if m.x.isFinite { dyn[o] = m.x; dyn[o + 1] = m.y; dyn[o + 2] = m.z }
        }
    }
    private(set) var tailYaw: Float = 0, tailPitch: Float = 0
    /// The tail's motion (TailMotion.swift): what the brain asks (`tailDrive`), the filters / clocks, and each ring's world rotation for the spike layer.
    var tailDrive = TailDrive(), tailMotion = TailMotion()
    /// The seat he stands on (TailSeat in TailMotion.swift): the floor-lying part of the tail lies on it; `tailSeatW` eases 0...1 so hops on / off never pop.
    var tailSeat = TailSeat(), tailSeatW: Float = 0, tailSeatOn = false
    private(set) var tailRingQ: [simd_quatf] = []
    func setTailTip(yaw: Float, pitch: Float) { tailYaw = yaw; tailPitch = pitch }
    func setTailRings(_ q: [simd_quatf]) { tailRingQ = q }
    var tailScaleNow: Float { tailScale }
    private var tailScale: Float = 0, tailInit = false, tailClock: Float = 0, tailLastB = SIMD3<Float>.zero, tailPrimed = false
    var retractVertices: [Int32] = []
    var retractRest: [SIMD3<Float>] = []              // rest-space delta of each retracting vertex onto the footless egg (sunk a little)
    var retractWeight: [Float] = []
    var retractSide: [Int8] = []                      // 0 / 1 = skinned to that foot's sim slab, -1 = belly skin
    var retractMatrix = matrix_identity_float3x3      // body-rigid pose (rotation * squash) that carries a rest delta into the world
    var retractShift: [SIMD3<Float>] = [.zero, .zero]  // how far each sim foot slab sits from the body-rigid pose (world): removed from its vertices
    func clearBeans() { beanBlend = 0; beanPos = [[], []]; beanStart = [[], []] }
    var beansActive: Bool { beanBlend > 0 && beanPos[0].count == FootBean.vertexCount && beanStart[0].count == FootBean.vertexCount && beanFirst.count == 2 }

    // MARK: drawn-space bean guard
    // 2026-10-28 (legs come off): the brain buries the beans against the REST egg in the fitted rigid pose (BlobBrain.attachBean), but what is drawn is the skinned soft
    // body (squash, retract, jiggle, sit / slide deformation): in a drawn-space audit the bean crown was seen 9 mm OUTSIDE the drawn belly while the rest-egg check said
    // -3 cm. So the last step of the skin looks at the DRAWN triangles near each foot: if the deepest sampled crown vertex lies less than `guardTrigger` inside the drawn body,
    // the whole bean is moved along that triangle's inward normal to `guardBury`. Per foot a precomputed list of the egg's triangles around the foot's rest place (no
    // allocation per frame; ~50 us per Jelly).
    static let guardTrigger: Float = 0.010, guardBury: Float = 0.014, guardMaxShift: Float = 0.05, guardReach: Float = 0.55
    static let guardCrown: [Int] = { let c = FootBean.crownIndices; let pole = FootBean.vertexCount - 1; return [pole] + c.enumerated().filter { $0.offset % 3 == 0 && $0.element != pole }.map { $0.element } }()
    var guardEnabled = true
    /// Extra burial while shoes are worn (set by the brain): the shoe shell is a little thicker than the bean, and its own top must lie in the body too.
    var guardExtra: Float = 0
    private(set) var guardTris: [[Int32]] = [[], []]
    private var guardCand: [Int32] = []
    /// What the guard moved each bean by last frame (world), for tests and captures.
    private(set) var guardShift: [SIMD3<Float>] = [.zero, .zero]
    var guardReady: Bool { !guardTris[0].isEmpty && !guardTris[1].isEmpty }
    /// `limit` = index count of the egg proper (RenderMesh.armCapsule.indexFirst): the arm / bean / tail blocks and the decals are not body.
    func configureBeanGuard(rest: [Float], index: [UInt32], limit: Int) {
        for s in 0..<2 {
            let sx: Float = s == 0 ? -1 : 1
            let c = SIMD3<Float>(sx * Float(BobForm.footX), 0.12, Float(BobForm.footZ))
            var list: [Int32] = []
            var t = 0
            while t + 2 < limit {
                var near = false
                for k in 0..<3 {
                    let v = 3 * Int(index[t + k])
                    if simd_distance_squared(SIMD3(rest[v], rest[v + 1], rest[v + 2]), c) < Self.guardReach * Self.guardReach { near = true; break }
                }
                if near { list.append(Int32(index[t])); list.append(Int32(index[t + 1])); list.append(Int32(index[t + 2])) }
                t += 3
            }
            guardTris[s] = list
        }
        guardCand = [Int32](repeating: 0, count: max(guardTris[0].count, guardTris[1].count) / 3 + 8)
    }

    private func applyBeanGuard(_ dyn: UnsafeMutablePointer<Float>) {
        guardShift[0] = .zero; guardShift[1] = .zero
        guard guardEnabled, guardReady, beansActive, beanBlend > 0.05 else { return }
        @inline(__always) func P(_ v: Int) -> SIMD3<Float> { SIMD3(dyn[6 * v], dyn[6 * v + 1], dyn[6 * v + 2]) }
        let crown = Self.guardCrown            // (the top pole first: nearly always the deepest vertex, so a buried bean costs one point against ~100 triangles)
        for s in 0..<2 {
            let f = beanFirst[s]
            guardTris[s].withUnsafeBufferPointer { tb in
                /// Triangles with a vertex within `r` of `c`.
                func gather(_ c: SIMD3<Float>, _ r: Float) -> Int {
                    var n = 0, t = 0
                    let R2 = r * r
                    while t < tb.count {
                        if simd_distance_squared(P(Int(tb[t])), c) < R2 { guardCand[n] = Int32(t); n += 1 }
                        t += 3
                    }
                    return n
                }
                /// Burial of `p` (+ inside) by its nearest candidate triangle and that triangle's inward normal.
                func burial(_ p: SIMD3<Float>, _ n: Int) -> (Float, SIMD3<Float>)? {
                    var bd = Float.infinity, sgn: Float = 1, nn = SIMD3<Float>(0, 1, 0)
                    for k in 0..<n {
                        let t = Int(guardCand[k])
                        let a = P(Int(tb[t])), b = P(Int(tb[t + 1])), cc = P(Int(tb[t + 2]))
                        let q = DrawnGeom.closest(p, a, b, cc).0
                        let dd = simd_distance_squared(p, q)
                        if dd < bd { bd = dd; let fn = simd_cross(b - a, cc - a); nn = fn; sgn = simd_dot(p - q, fn) >= 0 ? 1 : -1 }
                    }
                    guard bd.isFinite else { return nil }
                    let l = simd_length(nn)
                    return (-sgn * bd.squareRoot(), l > 1e-12 ? -nn / l : SIMD3(0, 1, 0))
                }
                // the pole: no triangle within 12 cm = buried by more than that
                let pole = P(f + crown[0])
                let n0 = gather(pole, 0.12)
                if n0 == 0 { return }
                var deepest = -Float.infinity, inward = SIMD3<Float>(0, 1, 0)
                if let r = burial(pole, n0) { deepest = r.0; inward = r.1 }
                if deepest >= Self.guardTrigger + guardExtra { return }
                // not clearly buried: the other crown vertices decide
                var c = SIMD3<Float>.zero
                for i in crown { c += P(f + i) }
                c /= Float(crown.count)
                var rho: Float = 0
                for i in crown { rho = max(rho, simd_distance(P(f + i), c)) }
                let n = gather(c, rho + 0.07)
                for i in crown.dropFirst() {
                    if let r = burial(P(f + i), n), r.0 > deepest { deepest = r.0; inward = r.1 }
                    if deepest >= Self.guardTrigger + guardExtra { return }
                }
                guard deepest.isFinite else { return }
                let sh = inward * min(Self.guardBury + guardExtra - deepest, Self.guardMaxShift)
                guardShift[s] = sh
                for i in 0..<FootBean.vertexCount { let o = 6 * (f + i); dyn[o] += sh.x; dyn[o + 1] += sh.y; dyn[o + 2] += sh.z }
            }
        }
    }


    // MARK: walking arm capsules
    // The same scheme for the arms: while the walking arm is active the brain poses the closed ArmCapsule of each side in world space (`armPos`,
    // blended from `armStart` = the rest nub by `armBlend`) and the rest nub's skin (`armRetract*`, rest-space deltas onto the ARMLESS egg, sunk a
    // little, rotated by `armRetractMatrix`) retracts under it at the same time, so the junction is a crease, not a fillet. blend = 0: untouched.
    var armFirst: [Int] = []
    var armPos: [[SIMD3<Float>]] = [[], []]
    var armStart: [[SIMD3<Float>]] = [[], []]
    var armBlend: Float = 0
    var armRetractVertices: [Int32] = []
    var armRetractRest: [SIMD3<Float>] = []
    var armRetractWeight: [Float] = []
    var armRetractMatrix = matrix_identity_float3x3
    /// Fillet collar (ArmCap.collar): the skin ring around each capsule arm's base, pushed outward along the egg normal (world delta per vertex, scaled by
    /// `armBlend`) so the base melts into the body like the wave's SDF fillet instead of showing a joint line.
    var armCollarVertices: [Int32] = []
    var armCollarDelta: [SIMD3<Float>] = []
    func clearArmCapsules() { armBlend = 0; armPos = [[], []]; armStart = [[], []]; armCollarDelta = [] }
    // W1d: render-side skin offsets (the physics version of the shear was eaten by the tets). `skinVerts` = body skin + face decals (not the capsules / beans);
    // `shearW` = (1 - y/Htop)^2 of the rest height, `lobeW[s]` = the lobe weight of leg s (Gaussian in the xz distance to that leg's rest footprint x a height falloff).
    // Per frame the brain sets `shearVec` (world offset at the floor) and `lobeD[s]` (world offset of the skin over foot s: the body 'picks up' with the foot).
    var skinVerts: [Int32] = []
    var shearW: [Float] = []
    var lobeW: [[Float]] = [[], []]
    var shearVec = SIMD3<Float>(0, 0, 0)
    var lobeD: [SIMD3<Float>] = [.zero, .zero]
    var armCapsulesActive: Bool { armBlend > 0 && armPos[0].count == ArmCapsule.vertexCount && armStart[0].count == ArmCapsule.vertexCount && armFirst.count == 2 }

    /// Render vertices embedded in a tet that touches any of `particles` (e.g. the foot slab prisms, whose corners are the sole particles).
    func vertices(touching particles: Set<Int32>) -> [Int32] {
        var out: [Int32] = []
        for v in 0..<vertexCount {
            let i4 = 4 * v
            if particles.contains(skinIdx[i4]) || particles.contains(skinIdx[i4 + 1]) || particles.contains(skinIdx[i4 + 2]) || particles.contains(skinIdx[i4 + 3]) { out.append(Int32(v)) }
        }
        return out
    }

    /// Switch the override off; the mat values written so far are restored by the next `takeMatWrites`.
    func clearOverride() {
        if !overrideVertices.isEmpty { pendingRestore = overrideVertices }
        overrideVertices = []; overrideDelta = []; overrideMat = []
    }

    /// What the renderer must write into its static mat channel now: the current AO values while an override runs, then
    /// (once) `values == nil` = restore the baked values of the vertices just released. nil = nothing to do.
    func takeMatWrites() -> (vertices: [Int32], values: [Float]?)? {
        if !overrideVertices.isEmpty { return (overrideVertices, overrideMat) }
        if !pendingRestore.isEmpty { let v = pendingRestore; pendingRestore = []; return (v, nil) }
        return nil
    }

    // antennae (Honey): rigid crown frame + spring-follow wobble
    private struct Antenna {
        var first: Int, count: Int
        var anchorIdx: [Int32]      // 3 points x 4 particles
        var anchorW: [Float]        // 3 points x 4 weights
        var local: [Float]          // per vertex, coordinates in the rest crown frame (3 each)
        var weights: [Float]
        var tipLocal: SIMD3<Float>
        var p = SIMD3<Float>(0, 0, 0), v = SIMD3<Float>(0, 0, 0)
        var started = false
    }
    private var antennae: [Antenna] = []
    private(set) var frameDt: Float = 1.0 / 60

    init(simTets: [UInt32], embedding: (tetOf: [UInt32], w: [Float]), vertexCount: Int, eyes: EyeRig? = nil,
         antennae rig: AntennaRig? = nil) {
        self.vertexCount = vertexCount
        var idx = [Int32](repeating: 0, count: vertexCount * 4)
        for v in 0..<vertexCount {
            let t = Int(embedding.tetOf[v])
            for k in 0..<4 { idx[4 * v + k] = Int32(simTets[4 * t + k]) }
        }
        skinIdx = idx
        skinW = embedding.w
        if let e = eyes {
            eyeIdx = e.eye; glintIdx = e.glint; browIdx = e.brow
            var ai = [Int32](repeating: 0, count: 16)
            for p in 0..<4 { let t = Int(e.anchorTet[p]); for k in 0..<4 { ai[4 * p + k] = Int32(simTets[4 * t + k]) } }
            anchorIdx = ai; anchorW = e.anchorW
            hasEyes = true
        } else {
            eyeIdx = [[], []]; glintIdx = [[], []]; browIdx = [[], []]; anchorIdx = []; anchorW = []; hasEyes = false
        }
        if let r = rig {
            for (k, info) in r.info.enumerated() {
                var ai = [Int32](repeating: 0, count: 12), aw = [Float](repeating: 0, count: 12)
                for p in 0..<3 {
                    let t = Int(r.anchorTet[3 * k + p])
                    for j in 0..<4 { ai[4 * p + j] = Int32(simTets[4 * t + j]); aw[4 * p + j] = r.anchorW[4 * (3 * k + p) + j] }
                }
                let bp = info.basePoints
                let c = SIMD3(bp[0], bp[1], bp[2]), u = SIMD3(bp[3], bp[4], bp[5]), sd = SIMD3(bp[6], bp[7], bp[8])
                let fr = Self.faceFrame(c, u, sd)
                var loc = [Float](repeating: 0, count: 3 * info.vertexCount)
                for i in 0..<info.vertexCount {
                    let v = info.firstVertex + i
                    let d = SIMD3(r.restVerts[3 * v], r.restVerts[3 * v + 1], r.restVerts[3 * v + 2]) - c
                    loc[3 * i] = simd_dot(d, fr.x); loc[3 * i + 1] = simd_dot(d, fr.y); loc[3 * i + 2] = simd_dot(d, fr.z)
                }
                let td = info.tip - c
                antennae.append(Antenna(first: info.firstVertex, count: info.vertexCount, anchorIdx: ai, anchorW: aw,
                                        local: loc, weights: info.weights,
                                        tipLocal: SIMD3(simd_dot(td, fr.x), simd_dot(td, fr.y), simd_dot(td, fr.z))))
            }
        }
    }

    private static func faceFrame(_ c: SIMD3<Float>, _ u: SIMD3<Float>, _ s: SIMD3<Float>) -> (x: SIMD3<Float>, y: SIMD3<Float>, z: SIMD3<Float>) {
        let y = simd_normalize(u - c)
        var x = s - c; x -= y * simd_dot(x, y)
        x = simd_length(x) < 1e-6 ? SIMD3(1, 0, 0) : simd_normalize(x)
        return (x, y, simd_cross(x, y))
    }

    // MARK: eye controls

    /// Expression hook: 0 = shut (lid line), 1 = fully open. Independent per eye (winks, squints).
    func setEyeOpenness(left: Float, right: Float) {
        openness = (max(0, min(1, left)), max(0, min(1, right)))
        refreshEyeHeight()
    }
    func setEyeOpenness(_ both: Float) { setEyeOpenness(left: both, right: both) }

    /// Start a blink now (optionally a quick double blink).
    func blinkNow(double: Bool = false, duration: Float = 0.12) {
        blinking = true; blinkT = 0; doubleLeft = double ? 1 : 0; gap = 0; blinkDur = duration; autoHold = 1.0
    }
    // W1c: while he walks the brows are kept RIGID to the face frame (the eye pair's frame) instead of following the jelly's local skin deformation,
    // which tilted the two brows differently (non-parallel) as the belly shears. `browsRigid` is set by the brain; the blend eases in / out over ~0.3 s.
    var browsRigid = false
    /// Dining only: while true, each brow whose slant as the fixed game camera sees it (inner end up, rad) falls below `browFloor` is turned in the
    /// screen plane (about the view axis, through its centre) up to that floor, so a leaning / turned head never reads angry. Eases in / out; off = the
    /// rest face, untouched.
    var browCounterOn = false
    static let browFloor: Float = 0.08          // a little friendly: the measured slant is only matched to ~0.13 rad on a heavily turned head
    private var browCW: Float = 0
    /// Lobby portraits: the plain rest face for one `update` (no brow tilt / raise, no rigid or counter-rotated brows, eyes fully open, no blink), whatever the mood is right now;
    /// the live face comes back after. The skinner's own blend state is saved and restored, so the next real frame is not disturbed.
    func withNeutralFace<T>(_ body: () -> T) -> T {
        let live = (browRaise, browTilt, openness, eyeHeight, blinking, blinkOpen, browW, browCW, browsRigid, browCounterOn)
        browRaise = [0, 0]; browTilt = [0, 0]; openness = (1, 1); eyeHeight = (1, 1); blinking = false; blinkOpen = 1
        browW = 0; browCW = 0; browsRigid = false; browCounterOn = false
        defer {
            browRaise = live.0; browTilt = live.1; openness = live.2; eyeHeight = live.3; blinking = live.4; blinkOpen = live.5
            browW = live.6; browCW = live.7; browsRigid = live.8; browCounterOn = live.9
        }
        return body()
    }
    /// The game camera as it is NOW (the screen-space brow measure multiplies by the live aspect, so the matrix must use it too: a frozen portrait one skews the slant in landscape).
    private static var gameViewProj: simd_float4x4 { M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: GameCamera.aspect, near: 0.3, far: 60),
                                                           M4.lookAt(eye: GameCamera.eye, at: GameCamera.target, up: SIMD3(0, 1, 0))) }
    private var browW: Float = 0
    private var browRest: [[SIMD3<Float>]] = [[], []]
    private var browMidRest = SIMD3<Float>(0, 0, 0)
    private var browFrameRest = simd_float3x3(1)
    private var browEyeRest: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(0, 0, 0)]
    var browsPrepared: Bool { !browRest[0].isEmpty }
    /// Expression brows (BlobBrain+Expression.swift): per brow (0 = -x) a raise along the face's up axis (rest units) and a tilt about the brow's own centre
    /// (rad, + = inner end up). Both 0 = exactly the existing brows (the rigid path runs only while `browsRigid` or an expression is on; off, `browW` decays to 0
    /// and the plain skinned brows are untouched). Ignored while the dining counter-rotation runs.
    var browRaise: [Float] = [0, 0]
    var browTilt: [Float] = [0, 0]
    var browExpressionOn: Bool { !browCounterOn && (browRaise[0] != 0 || browRaise[1] != 0 || browTilt[0] != 0 || browTilt[1] != 0) }
    /// Current blend of the rigid-brow path (tests).
    var browRigidBlend: Float { browW }
    private var browCentreOff: [SIMD3<Float>] = [.zero, .zero]
    /// Orthonormal frame (columns x, y, z) of the face: x along the eye line, y toward the brows (perpendicular to x), z = x cross y.
    private static func browFaceFrame(_ e0: SIMD3<Float>, _ e1: SIMD3<Float>, _ bm: SIMD3<Float>) -> simd_float3x3 {
        let xa = simd_normalize(e1 - e0)
        var y = bm - (e0 + e1) / 2; y -= xa * simd_dot(y, xa)
        let ya = simd_length(y) > 1e-6 ? simd_normalize(y) : SIMD3<Float>(0, 1, 0)
        return simd_float3x3(columns: (xa, ya, simd_cross(xa, ya)))
    }
    func prepareBrows(rest: [Float]) {
        guard hasEyes, browIdx[0].count > 0, browIdx[1].count > 0, eyeIdx[0].count > 0, eyeIdx[1].count > 0 else { return }
        func p(_ v: Int32) -> SIMD3<Float> { SIMD3(rest[3 * Int(v)], rest[3 * Int(v) + 1], rest[3 * Int(v) + 2]) }
        var m = SIMD3<Float>(0, 0, 0); var n: Float = 0
        for e in 0..<2 { for v in eyeIdx[e] { m += p(v); n += 1 } }
        browMidRest = m / max(n, 1)
        browRest = (0..<2).map { s in browIdx[s].map { p($0) } }
        func mean(_ a: [SIMD3<Float>]) -> SIMD3<Float> { a.reduce(SIMD3<Float>(0, 0, 0), +) / Float(max(1, a.count)) }
        let e0 = mean(eyeIdx[0].map { p($0) }), e1 = mean(eyeIdx[1].map { p($0) })
        let bm = (mean(browRest[0]) + mean(browRest[1])) / 2
        browEyeRest = [e0, e1]
        browFrameRest = Self.browFaceFrame(e0, e1, bm)
        let mid = (e0 + e1) / 2
        browCentreOff = [mean(browRest[0]) - mid, mean(browRest[1]) - mid]
    }
    /// While he walks (set by the brain): a short 0.08 s blink about every 2 s, never a double blink, never two within 1 s.
    var walkingBlinks = false
    private var blinkDur: Float = 0.12
    private var autoHold: Float = 0

    /// Advance the automatic blink; call once per rendered frame with the frame time.
    func tickBlink(dt: Float) {
        frameDt = max(1e-4, min(dt, 0.1))
        if blinking {
            blinkT += dt
            if blinkT >= blinkDur {
                blinking = false
                if walkingBlinks { doubleLeft = 0 }
                if doubleLeft > 0 { doubleLeft -= 1; gap = 0.1 } else { blinkWait = walkingBlinks ? 1.7 + 0.6 * nextRand() : 2 + 4 * nextRand() }
            }
        } else if gap > 0 {
            gap -= dt
            if gap <= 0 { blinking = true; blinkT = 0 }
        } else if autoBlink {
            autoHold = max(0, autoHold - dt)
            blinkWait -= dt
            if blinkWait <= 0 && autoHold <= 0 { blinking = true; blinkT = 0; blinkDur = walkingBlinks ? 0.112 : 0.12; doubleLeft = (!walkingBlinks && nextRand() < 0.2) ? 1 : 0 }
        }
        if blinking {
            // trapezoid: 12 ms to close, held closed, 12 ms to open (a 0.105 s walking blink is closed 0.081 s: two consecutive 24 fps frames)
            let ramp: Float = 0.012
            let k = min(1, max(0, min(blinkT, blinkDur - blinkT) / ramp))
            blinkOpen = 1 - k * k * (3 - 2 * k)
        } else { blinkOpen = 1 }
        refreshEyeHeight()
    }

    private func nextRand() -> Float {
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
        return Float(rng >> 8) / Float(1 << 24)
    }

    private func refreshEyeHeight() {
        let c = Self.closedHeight
        eyeHeight = (c + (1 - c) * openness.left * blinkOpen, c + (1 - c) * openness.right * blinkOpen)
    }

    // MARK: skinning

    /// `dst` must hold `vertexCount * 6` floats.
    func update(x: [Float], index: [UInt32], into dst: UnsafeMutablePointer<Float>) {
        x.withUnsafeBufferPointer { xb in
            update(x: xb.baseAddress!, index: index, into: dst)
        }
    }

    func update(x: UnsafePointer<Float>, index: [UInt32], into dyn: UnsafeMutablePointer<Float>) {
        skinIdx.withUnsafeBufferPointer { si in
            skinW.withUnsafeBufferPointer { sw in
                for v in 0..<vertexCount {
                    let i4 = 4 * v, o = 6 * v
                    let a = 3 * Int(si[i4]), b = 3 * Int(si[i4 + 1]), c = 3 * Int(si[i4 + 2]), d = 3 * Int(si[i4 + 3])
                    let w0 = sw[i4], w1 = sw[i4 + 1], w2 = sw[i4 + 2], w3 = sw[i4 + 3]
                    dyn[o] = x[a] * w0 + x[b] * w1 + x[c] * w2 + x[d] * w3
                    dyn[o + 1] = x[a + 1] * w0 + x[b + 1] * w1 + x[c + 1] * w2 + x[d + 1] * w3
                    dyn[o + 2] = x[a + 2] * w0 + x[b + 2] * w1 + x[c + 2] * w2 + x[d + 2] * w3
                    dyn[o + 3] = 0; dyn[o + 4] = 0; dyn[o + 5] = 0
                }
            }
        }
        if !overrideVertices.isEmpty {
            for (k, vi) in overrideVertices.enumerated() {
                let o = 6 * Int(vi), t = overrideDelta[k]
                dyn[o] += t.x; dyn[o + 1] += t.y; dyn[o + 2] += t.z
            }
        }
        if !extraVertices.isEmpty {                         // touch play: a smooth additive skin offset (cheek squeeze); empty = exactly the plain skin
            for (k, vi) in extraVertices.enumerated() {
                let o = 6 * Int(vi), t = extraDelta[k]
                dyn[o] += t.x; dyn[o + 1] += t.y; dyn[o + 2] += t.z
            }
        }
        if beansActive {
            let bl = beanBlend
            for s in 0..<2 {
                let f = beanFirst[s]
                for i in 0..<FootBean.vertexCount {
                    let o = 6 * (f + i), t = beanPos[s][i], a = beanStart[s][i]
                    dyn[o] = a.x + (t.x - a.x) * bl; dyn[o + 1] = a.y + (t.y - a.y) * bl; dyn[o + 2] = a.z + (t.z - a.z) * bl
                }
            }
            let M = retractMatrix
            for (k, vi) in retractVertices.enumerated() where !Skinner.dbgNoRetract {
                var d = M * retractRest[k]
                let sd = retractSide[k]
                if sd >= 0 { d -= retractShift[Int(sd)] }
                let o = 6 * Int(vi), w = retractWeight[k] * bl
                dyn[o] += d.x * w; dyn[o + 1] += d.y * w; dyn[o + 2] += d.z * w
            }
        }
        if armCapsulesActive {
            let bl = armBlend
            for s in 0..<2 {
                let f = armFirst[s]
                for i in 0..<ArmCapsule.vertexCount {
                    let o = 6 * (f + i), t = armPos[s][i], a = armStart[s][i]
                    dyn[o] = a.x + (t.x - a.x) * bl; dyn[o + 1] = a.y + (t.y - a.y) * bl; dyn[o + 2] = a.z + (t.z - a.z) * bl
                }
            }
            if armCollarDelta.count == armCollarVertices.count {
                for (k, vi) in armCollarVertices.enumerated() {
                    let o = 6 * Int(vi), d = armCollarDelta[k] * bl
                    dyn[o] += d.x; dyn[o + 1] += d.y; dyn[o + 2] += d.z
                }
            }
            let M = armRetractMatrix
            for (k, vi) in armRetractVertices.enumerated() where !Skinner.dbgNoArmRetract {
                let d = M * armRetractRest[k], o = 6 * Int(vi), w = armRetractWeight[k] * bl
                dyn[o] += d.x * w; dyn[o + 1] += d.y * w; dyn[o + 2] += d.z * w
            }
        }
        applyTail(dyn)
        eyeFixK[0] = 1; eyeFixK[1] = 1
        if hasEyes { applyEyes(x, dyn) }
        if !antennae.isEmpty { applyAntennae(x, dyn) }
        let hasShear = shearVec.x != 0 || shearVec.y != 0 || shearVec.z != 0, hasLobe = lobeD[0] != .zero || lobeD[1] != .zero
        if (hasShear || hasLobe) && lobeW[0].count == skinVerts.count && shearW.count == skinVerts.count {
            for (k, vi) in skinVerts.enumerated() {
                var d = SIMD3<Float>(0, 0, 0)
                if hasShear { d += shearVec * shearW[k] }
                if hasLobe { d += lobeD[0] * lobeW[0][k] + lobeD[1] * lobeW[1][k] }
                let o = 6 * Int(vi)
                dyn[o] += d.x; dyn[o + 1] += d.y; dyn[o + 2] += d.z
            }
        }
        if !dbgJellyOff { jelly.apply(dyn, count: vertexCount) }          // jelly follow-through (JellyJiggle.swift): a no-op unless he is moving
        if normalSmoothing > 0.001 { smoothDentPositions(dyn, index: index) }
        applyBeanGuard(dyn)
        if Skinner.scatterNormals { scatterNormals(dyn, index: index) } else { gatherNormals(dyn, index: index) }
        if eyeFixK[0] < 0.999 || eyeFixK[1] < 0.999 { smoothEyeNormals(dyn, index: index) }
        if normalSmoothing > 0.001 { smoothNormals(dyn, index: index) }
        blendTailNormals(dyn)
    }

    private func applyTail(_ dyn: UnsafeMutablePointer<Float>) {
        let f = tailFirst >= 0 ? tailFirst : TailBean.builtFirst, n = TailBean.vertexCount
        guard f >= 0, f + n <= vertexCount else { return }
        func P(_ i: Int) -> SIMD3<Float> { SIMD3(dyn[6 * (f + i)], dyn[6 * (f + i) + 1], dyn[6 * (f + i) + 2]) }
        let dt = frameDt
        // default OFF: a skinner nobody configured for the tail (test rigs, previews) or whose Jelbie is not Pip's .spines keeps the whole block collapsed on its base pole
        guard tailLM.count == 3, tailOn || tailScale > 0.002 else {
            let B = P(0)
            for i in 1..<n { let o = 6 * (f + i); dyn[o] = B.x; dyn[o + 1] = B.y; dyn[o + 2] = B.z }
            tailPrimed = false; tailYaw = 0; tailPitch = 0; tailScale = 0; tailRingQ = []
            return
        }
        // carry the tail rigidly on the frame of its three landmark egg vertices (rest -> skinned)
        func lm(_ k: Int) -> SIMD3<Float> { let o = 6 * tailLM[k]; return SIMD3(dyn[o], dyn[o + 1], dyn[o + 2]) }
        func frame(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> simd_float3x3 {
            let x = simd_normalize(b - a), z = simd_normalize(simd_cross(x, c - a)), y = simd_cross(z, x)
            return simd_float3x3(columns: (x, y, z))
        }
        let rr = tailLMRest, ss = [lm(0), lm(1), lm(2)]
        let Rot = frame(ss[0], ss[1], ss[2]) * frame(rr[0], rr[1], rr[2]).transpose
        let Cr = (rr[0] + rr[1] + rr[2]) / 3, Cs = (ss[0] + ss[1] + ss[2]) / 3
        tailRotLast = Rot
        // The long tail lies on the floor: its high part (the root) follows the body's tilt rigidly, but the low part only follows the body's heading and position
        // (a long lever would otherwise swing it through the floor whenever the egg sags or leans); the blend is by rest height.
        let fwd = Rot * SIMD3<Float>(0, 0, 1)
        let RotY = simd_quatf(angle: atan2f(fwd.x, fwd.z), axis: SIMD3(0, 1, 0))
        for i in 0..<n {
            let L = TailBean.localF[i]
            let full = Cs + Rot * (L - Cr)
            var flat = Cs + RotY.act(L - Cr); flat.y = L.y - TailBean.restFloor
            let w = 1 - simd_smoothstep(0.22, 0.5, TailBean.ringY[i])
            let p = full + (flat - full) * w
            let o = 6 * (f + i); dyn[o] = p.x; dyn[o + 1] = p.y; dyn[o + 2] = p.z
        }
        if tailScale > 0.001 { for (v, w) in tailBump {                                           // the swell (scaled by the tail's own ease in / out below through tailScale)
            let o = 6 * v, d = Rot * (w * tailScale)
            dyn[o] += d.x; dyn[o + 1] += d.y; dyn[o + 2] += d.z
        } }
        let B = P(0), T = P(n - 1)
        if !tailInit { tailScale = tailOn ? 1 : 0; tailInit = true }
        tailScale += max(-dt / 0.15, min(dt / 0.15, (tailOn ? 1 : 0) - tailScale))
        if !tailOn && tailScale <= 0.002 {                       // off: every vertex onto the base pole (inside the body)
            for i in 1..<n { let o = 6 * (f + i); dyn[o] = B.x; dyn[o + 1] = B.y; dyn[o + 2] = B.z }
            tailPrimed = false; tailYaw = 0; tailPitch = 0; tailRingQ = []
            return
        }
        let vel = tailPrimed ? (B - tailLastB) / dt : SIMD3<Float>.zero
        tailLastB = B; tailPrimed = true
        tailClock += dt
        let speed = (vel.x * vel.x + vel.z * vel.z).squareRoot()
        let pivot = Cs + Rot * (TailBean.rootF - Cr)                   // exactly where the tail leaves the back
        bendTail(dyn, first: f, n: n, speed: speed, vy: vel.y, heading: atan2f(fwd.x, fwd.z), pivot: pivot, base: B, tip: T, rot: Rot, cs: Cs, cr: Cr)       // the travelling-wave bend (TailMotion.swift)
    }

    // MARK: vertex normals
    // The original pass scattered every triangle's face normal onto its three vertices (nine read-modify-writes per triangle, chained through memory),
    // then normalised. `gatherNormals` gives the very same floats: the face normals once into a buffer, then per vertex the sum over its triangles in
    // ascending triangle order, which is exactly the order the scatter added them in, and the normalise in the same pass. ~2x faster.
    /// Perf A/B (SolverBenchTests): the original scatter pass.
    nonisolated(unsafe) static var scatterNormals = false
    private var faceNormals: UnsafeMutablePointer<Float>? = nil
    private var faceNormalCount = 0
    private var triAdj: TriangleAdjacency? = nil

    deinit { faceNormals?.deallocate() }

    private func gatherNormals(_ dyn: UnsafeMutablePointer<Float>, index: [UInt32]) {
        let nTri = index.count / 3
        if faceNormalCount < nTri {
            faceNormals?.deallocate(); faceNormals = UnsafeMutablePointer<Float>.allocate(capacity: max(nTri * 3, 1)); faceNormalCount = nTri
        }
        if triAdj == nil || triAdj!.triangleCount != nTri || triAdj!.vertexCount != vertexCount { triAdj = TriangleAdjacency.shared(index: index, vertexCount: vertexCount) }
        let fn = faceNormals!
        index.withUnsafeBufferPointer { ix in
            var t = 0, o = 0
            while t < ix.count {
                let a = 6 * Int(ix[t]), b = 6 * Int(ix[t + 1]), c = 6 * Int(ix[t + 2])
                let e1x = dyn[b] - dyn[a], e1y = dyn[b + 1] - dyn[a + 1], e1z = dyn[b + 2] - dyn[a + 2]
                let e2x = dyn[c] - dyn[a], e2y = dyn[c + 1] - dyn[a + 1], e2z = dyn[c + 2] - dyn[a + 2]
                fn[o] = e1y * e2z - e1z * e2y; fn[o + 1] = e1z * e2x - e1x * e2z; fn[o + 2] = e1x * e2y - e1y * e2x
                t += 3; o += 3
            }
        }
        let adj = triAdj!
        adj.start.withUnsafeBufferPointer { st in
            adj.tri.withUnsafeBufferPointer { tr in
                for v in 0..<vertexCount {
                    let o = 6 * v
                    var nx = dyn[o + 3], ny = dyn[o + 4], nz = dyn[o + 5]       // what the scatter would have started from (0 after the embed)
                    for j in Int(st[v])..<Int(st[v + 1]) {
                        let f = 3 * Int(tr[j])
                        nx += fn[f]; ny += fn[f + 1]; nz += fn[f + 2]
                    }
                    var l = (nx * nx + ny * ny + nz * nz).squareRoot()
                    if l == 0 { l = 1 }
                    dyn[o + 3] = nx / l; dyn[o + 4] = ny / l; dyn[o + 5] = nz / l
                }
            }
        }
    }

    private func scatterNormals(_ dyn: UnsafeMutablePointer<Float>, index: [UInt32]) {
        index.withUnsafeBufferPointer { ix in
            var t = 0
            while t < ix.count {
                let a = 6 * Int(ix[t]), b = 6 * Int(ix[t + 1]), c = 6 * Int(ix[t + 2])
                let e1x = dyn[b] - dyn[a], e1y = dyn[b + 1] - dyn[a + 1], e1z = dyn[b + 2] - dyn[a + 2]
                let e2x = dyn[c] - dyn[a], e2y = dyn[c + 1] - dyn[a + 1], e2z = dyn[c + 2] - dyn[a + 2]
                let nx = e1y * e2z - e1z * e2y, ny = e1z * e2x - e1x * e2z, nz = e1x * e2y - e1y * e2x
                dyn[a + 3] += nx; dyn[a + 4] += ny; dyn[a + 5] += nz
                dyn[b + 3] += nx; dyn[b + 4] += ny; dyn[b + 5] += nz
                dyn[c + 3] += nx; dyn[c + 4] += ny; dyn[c + 5] += nz
                t += 3
            }
        }
        var o = 0
        let total = vertexCount * 6
        while o < total {
            var l = (dyn[o + 3] * dyn[o + 3] + dyn[o + 4] * dyn[o + 4] + dyn[o + 5] * dyn[o + 5]).squareRoot()
            if l == 0 { l = 1 }
            dyn[o + 3] /= l; dyn[o + 4] /= l; dyn[o + 5] /= l
            o += 6
        }
    }

    /// Perf diagnostic (SolverBenchTests): the plain skin split into its passes, each timed (microseconds). Same output as `update` for a body
    /// without overrides / beans / arms / dent smoothing (those are skipped here).
    func profileUpdate(x: UnsafePointer<Float>, index: [UInt32], into dyn: UnsafeMutablePointer<Float>) -> [(String, Double)] {
        var out: [(String, Double)] = []
        var t0 = DispatchTime.now().uptimeNanoseconds
        func lap(_ s: String) { let t = DispatchTime.now().uptimeNanoseconds; out.append((s, Double(t - t0) / 1000)); t0 = t }
        skinIdx.withUnsafeBufferPointer { si in
            skinW.withUnsafeBufferPointer { sw in
                for v in 0..<vertexCount {
                    let i4 = 4 * v, o = 6 * v
                    let a = 3 * Int(si[i4]), b = 3 * Int(si[i4 + 1]), c = 3 * Int(si[i4 + 2]), d = 3 * Int(si[i4 + 3])
                    let w0 = sw[i4], w1 = sw[i4 + 1], w2 = sw[i4 + 2], w3 = sw[i4 + 3]
                    dyn[o] = x[a] * w0 + x[b] * w1 + x[c] * w2 + x[d] * w3
                    dyn[o + 1] = x[a + 1] * w0 + x[b + 1] * w1 + x[c + 1] * w2 + x[d + 1] * w3
                    dyn[o + 2] = x[a + 2] * w0 + x[b + 2] * w1 + x[c + 2] * w2 + x[d + 2] * w3
                    dyn[o + 3] = 0; dyn[o + 4] = 0; dyn[o + 5] = 0
                }
            }
        }
        lap("embed")
        eyeFixK[0] = 1; eyeFixK[1] = 1
        if hasEyes { applyEyes(x, dyn) }
        if !antennae.isEmpty { applyAntennae(x, dyn) }
        lap("eyes+antennae")
        if !dbgJellyOff { jelly.apply(dyn, count: vertexCount) }
        lap("jiggle")
        applyBeanGuard(dyn)
        if Skinner.scatterNormals { scatterNormals(dyn, index: index) } else { gatherNormals(dyn, index: index) }
        lap(Skinner.scatterNormals ? "normals (scatter+normalize)" : "normals (gather)")
        if eyeFixK[0] < 0.999 || eyeFixK[1] < 0.999 { smoothEyeNormals(dyn, index: index) }
        lap("eye normals")
        return out
    }

    /// Eye-only neighbours (built once from the triangle list).
    private func buildEyeAdjacency(_ index: [UInt32]) {
        eyeOwner = [Int8](repeating: -1, count: vertexCount)
        for e in 0..<2 { for v in eyeIdx[e] { eyeOwner[Int(v)] = Int8(e) } }
        var nb = [Int32: Set<Int32>]()
        var t = 0
        while t + 2 < index.count {
            let q = [index[t], index[t + 1], index[t + 2]]
            for a in 0..<3 { for b in 0..<3 where a != b {
                let va = Int(q[a]), vb = Int(q[b])
                if eyeOwner[va] >= 0 && eyeOwner[va] == eyeOwner[vb] { nb[Int32(va), default: []].insert(Int32(vb)) }
            } }
            t += 3
        }
        eyeNbStart = [Int32](repeating: 0, count: vertexCount + 1); eyeNb = []
        for v in 0..<vertexCount {
            let l = (nb[Int32(v)] ?? []).sorted()
            eyeNb.append(contentsOf: l); eyeNbStart[v + 1] = eyeNbStart[v] + Int32(l.count)
        }
    }

    /// A squashed eye's normals are the unsquashed (open) normals pushed through the squash (n' ~ n + (1/k - 1)(n.u)u), so the small per-vertex
    /// noise of the eye mesh's apex fan (the open eye has 0.07 mean / 0.19 worst between neighbours; it is hidden by the bead shading) is multiplied
    /// by ~1/k and one eye showed a radial star. Undo the squash on the normals, blur them over the eye's own neighbours, squash them again.
    private func smoothEyeNormals(_ dyn: UnsafeMutablePointer<Float>, index: [UInt32]) {
        if eyeNbStart.isEmpty { buildEyeAdjacency(index) }
        if smoothTmp.count < vertexCount * 3 { smoothTmp = [Float](repeating: 0, count: vertexCount * 3) }
        for e in 0..<2 where eyeFixK[e] < 0.999 {
            let k = max(eyeFixK[e], 0.02), u = eyeFixU[e]
            let t = min(1, (1 - k) / 0.08), w = 0.85 * t * t * (3 - 2 * t)
            let back = 1 - k, fwd = 1 / k - 1
            for v32 in eyeIdx[e] {                                  // un-squash
                let o = 6 * Int(v32)
                var n = SIMD3(dyn[o + 3], dyn[o + 4], dyn[o + 5])
                n -= u * (simd_dot(n, u) * back)
                n /= max(simd_length(n), 1e-9)
                dyn[o + 3] = n.x; dyn[o + 4] = n.y; dyn[o + 5] = n.z
            }
            for _ in 0..<Self.eyeNormalPasses {
                for v32 in eyeIdx[e] {
                    let v = Int(v32), o = 6 * v
                    var sx: Float = 0, sy: Float = 0, sz: Float = 0
                    let a = Int(eyeNbStart[v]), b = Int(eyeNbStart[v + 1])
                    for j in a..<b { let q = 6 * Int(eyeNb[j]); sx += dyn[q + 3]; sy += dyn[q + 4]; sz += dyn[q + 5] }
                    let inv = 1 / Float(max(b - a, 1))
                    var x = dyn[o + 3] + (sx * inv - dyn[o + 3]) * w, y = dyn[o + 4] + (sy * inv - dyn[o + 4]) * w, z = dyn[o + 5] + (sz * inv - dyn[o + 5]) * w
                    let l = (x * x + y * y + z * z).squareRoot()
                    if l > 1e-6 { x /= l; y /= l; z /= l }
                    smoothTmp[3 * v] = x; smoothTmp[3 * v + 1] = y; smoothTmp[3 * v + 2] = z
                }
                for v32 in eyeIdx[e] { let v = Int(v32); dyn[6 * v + 3] = smoothTmp[3 * v]; dyn[6 * v + 4] = smoothTmp[3 * v + 1]; dyn[6 * v + 5] = smoothTmp[3 * v + 2] }
            }
            for v32 in eyeIdx[e] {                                  // re-squash
                let o = 6 * Int(v32)
                var n = SIMD3(dyn[o + 3], dyn[o + 4], dyn[o + 5])
                n += u * (simd_dot(n, u) * fwd)
                n /= max(simd_length(n), 1e-9)
                dyn[o + 3] = n.x; dyn[o + 4] = n.y; dyn[o + 5] = n.z
            }
        }
    }

    private func buildAdjacency(_ index: [UInt32]) {
        var nb = [Set<Int32>](repeating: [], count: vertexCount)
        var t = 0
        while t + 2 < index.count {
            let a = Int(index[t]), b = Int(index[t + 1]), c = Int(index[t + 2])
            nb[a].insert(Int32(b)); nb[a].insert(Int32(c)); nb[b].insert(Int32(a)); nb[b].insert(Int32(c)); nb[c].insert(Int32(a)); nb[c].insert(Int32(b))
            t += 3
        }
        adjStart = [Int32](repeating: 0, count: vertexCount + 1)
        adjList = []
        for v in 0..<vertexCount { adjStart[v + 1] = adjStart[v] + Int32(nb[v].count); adjList.append(contentsOf: nb[v].sorted()) }
        smoothMask = [Bool](repeating: skinVerts.isEmpty, count: vertexCount)
        for v in skinVerts { smoothMask[Int(v)] = true }
        for v in faceFeatureVertices { smoothMask[Int(v)] = false }
        smoothTmp = [Float](repeating: 0, count: vertexCount * 3)
    }

    /// Relax the skin around the dent (before the normals are built): the region list + falloff weights, then Taubin passes on the positions.
    private func smoothDentPositions(_ dyn: UnsafeMutablePointer<Float>, index: [UInt32]) {
        if adjStart.isEmpty { buildAdjacency(index) }
        // the region lists are rebuilt only when the dent moved (or every 8th frame): the weights are shape-only, the ramp multiplies at use
        dentFrame += 1
        if dentList.isEmpty || dentFrame % 8 == 0 || simd_length(smoothCenter - dentBuiltAt) > 0.03 {
            dentBuiltAt = smoothCenter
            dentList.removeAll(keepingCapacity: true); dentW.removeAll(keepingCapacity: true)
            bodyList.removeAll(keepingCapacity: true); bodyW.removeAll(keepingCapacity: true)
            let r0 = Self.dentInner, r1 = Self.dentOuter, n0 = Self.normalInner, n1 = Self.normalOuter
            let c = smoothCenter, n1sq = n1 * n1
            for v in 0..<vertexCount where smoothMask[v] {
                let o = 6 * v
                let dx = dyn[o] - c.x, dy = dyn[o + 1] - c.y, dz = dyn[o + 2] - c.z
                let d2 = dx * dx + dy * dy + dz * dz
                if d2 >= n1sq { continue }
                let d = d2.squareRoot()
                let g = d <= n0 ? 1 : 1 - (d - n0) / (n1 - n0)
                bodyList.append(Int32(v)); bodyW.append(g * g * (3 - 2 * g))
                if d >= r1 { continue }
                let f = d <= r0 ? 1 : 1 - (d - r0) / (r1 - r0)
                dentList.append(Int32(v)); dentW.append(f * f * (3 - 2 * f))
            }
        }
        let k = min(1, normalSmoothing)
        if dentList.isEmpty { return }
        if dentTmp.count < dentList.count { dentTmp = [SIMD3<Float>](repeating: .zero, count: dentList.count) }
        dentTmp.withUnsafeMutableBufferPointer { tmp in
            adjStart.withUnsafeBufferPointer { st in
                adjList.withUnsafeBufferPointer { adj in
                    dentList.withUnsafeBufferPointer { list in
                        dentW.withUnsafeBufferPointer { dw in
                            for pass in 0..<Self.dentPasses {
                                let lam: Float = pass % 2 == 0 ? 0.55 : -0.58        // Taubin: smooth, then inflate back: folds go, the dimple volume stays
                                for n in 0..<list.count {
                                    let v = Int(list[n]), o = 6 * v
                                    let a = Int(st[v]), b = Int(st[v + 1])
                                    var sx: Float = 0, sy: Float = 0, sz: Float = 0
                                    for j in a..<b { let q = 6 * Int(adj[j]); sx += dyn[q]; sy += dyn[q + 1]; sz += dyn[q + 2] }
                                    let inv = 1 / Float(max(b - a, 1)), w = lam * dw[n] * k
                                    tmp[n] = SIMD3(dyn[o] + (sx * inv - dyn[o]) * w, dyn[o + 1] + (sy * inv - dyn[o + 1]) * w, dyn[o + 2] + (sz * inv - dyn[o + 2]) * w)
                                }
                                for n in 0..<list.count { let o = 6 * Int(list[n]); let t = tmp[n]; dyn[o] = t.x; dyn[o + 1] = t.y; dyn[o + 2] = t.z }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Blur the unit normals of the whole body skin (not the face features) over their mesh neighbours. The coarse sim mesh makes the skin normals
    /// jump along its tet boundaries as soon as the body is pushed (a faint dark vertical line), not only under the finger, so this is global.
    private func smoothNormals(_ dyn: UnsafeMutablePointer<Float>, index: [UInt32]) {
        if adjStart.isEmpty || bodyList.isEmpty { return }
        let kn = min(1, normalSmoothing)
        smoothTmp.withUnsafeMutableBufferPointer { tmp in
            adjStart.withUnsafeBufferPointer { st in
                adjList.withUnsafeBufferPointer { adj in
                    bodyList.withUnsafeBufferPointer { list in
                        bodyW.withUnsafeBufferPointer { bw in
                            for _ in 0..<Self.normalPasses {
                                for n in 0..<list.count {
                                    let v = Int(list[n]), o = 6 * v
                                    var x = dyn[o + 3], y = dyn[o + 4], z = dyn[o + 5]
                                    var sx: Float = 0, sy: Float = 0, sz: Float = 0
                                    let a = Int(st[v]), b = Int(st[v + 1])
                                    for j in a..<b { let q = 6 * Int(adj[j]); sx += dyn[q + 3]; sy += dyn[q + 4]; sz += dyn[q + 5] }
                                    let inv = 1 / Float(max(b - a, 1)), w = 0.95 * bw[n] * kn
                                    x += (sx * inv - x) * w; y += (sy * inv - y) * w; z += (sz * inv - z) * w
                                    let l = (x * x + y * y + z * z).squareRoot()
                                    if l > 1e-6 { x /= l; y /= l; z /= l }
                                    tmp[3 * v] = x; tmp[3 * v + 1] = y; tmp[3 * v + 2] = z
                                }
                                for n in 0..<list.count { let v = Int(list[n]); dyn[6 * v + 3] = tmp[3 * v]; dyn[6 * v + 4] = tmp[3 * v + 1]; dyn[6 * v + 5] = tmp[3 * v + 2] }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Carry each antenna rigidly with its crown frame, then add a damped spring-follow lag that grows toward the bobble.
    private func applyAntennae(_ x: UnsafePointer<Float>, _ dyn: UnsafeMutablePointer<Float>) {
        for k in 0..<antennae.count {
            var pts = (SIMD3<Float>.zero, SIMD3<Float>.zero, SIMD3<Float>.zero)   // no per-frame heap allocation
            for p in 0..<3 {
                var q = SIMD3<Float>(0, 0, 0)
                for j in 0..<4 {
                    let i = 3 * Int(antennae[k].anchorIdx[4 * p + j]), w = antennae[k].anchorW[4 * p + j]
                    q += SIMD3(x[i], x[i + 1], x[i + 2]) * w
                }
                if p == 0 { pts.0 = q } else if p == 1 { pts.1 = q } else { pts.2 = q }
            }
            let fr = Self.faceFrame(pts.0, pts.1, pts.2)
            let tip = pts.0 + fr.x * antennae[k].tipLocal.x + fr.y * antennae[k].tipLocal.y + fr.z * antennae[k].tipLocal.z
            // spring (semi-implicit, substepped): the bobble mass chases the rigidly carried tip
            if !antennae[k].started { antennae[k].p = tip; antennae[k].v = .zero; antennae[k].started = true }
            let sub = 4, h = frameDt / Float(sub), kS: Float = 380, cD: Float = 7
            for _ in 0..<sub {
                let a = (tip - antennae[k].p) * kS - antennae[k].v * cD
                antennae[k].v += a * h
                antennae[k].p += antennae[k].v * h
            }
            var D = antennae[k].p - tip
            let dl = simd_length(D)
            if dl > 0.3 { D *= 0.3 / dl; antennae[k].p = tip + D }
            let a = antennae[k]
            for i in 0..<a.count {
                let o = 6 * (a.first + i)
                let l = SIMD3(a.local[3 * i], a.local[3 * i + 1], a.local[3 * i + 2])
                let p = pts.0 + fr.x * l.x + fr.y * l.y + fr.z * l.z + D * a.weights[i]
                dyn[o] = p.x; dyn[o + 1] = p.y; dyn[o + 2] = p.z
            }
        }
    }

    /// Flatten each eye and its glint toward the eye's skinned centre along its current local up axis.
    private func applyEyes(_ x: UnsafePointer<Float>, _ dyn: UnsafeMutablePointer<Float>) {
        anchorIdx.withUnsafeBufferPointer { ai in
            anchorW.withUnsafeBufferPointer { aw in
                @inline(__always) func point(_ p: Int) -> (Float, Float, Float) {
                    var px: Float = 0, py: Float = 0, pz: Float = 0
                    for k in 0..<4 {
                        let i = 3 * Int(ai[4 * p + k]), w = aw[4 * p + k]
                        px += x[i] * w; py += x[i + 1] * w; pz += x[i + 2] * w
                    }
                    return (px, py, pz)
                }
                // rigid brows (W1c): the eye pair's frame carries the rest brows
                let exprOn = browExpressionOn
                browW += (((browsRigid || exprOn) ? 1 : 0) - browW) * 0.12
                if browW > 0.002 && browsPrepared {
                    // frame: the two eyes' SURFACE centres (mean of their skinned vertices; the anchor points sit inside the body) and the anchors' up direction
                    func mean(_ ids: [Int32]) -> SIMD3<Float> {
                        var a = SIMD3<Float>(0, 0, 0)
                        for vi in ids { let o = 6 * Int(vi); a += SIMD3(dyn[o], dyn[o + 1], dyn[o + 2]) }
                        return a / Float(max(1, ids.count))
                    }
                    let e0 = mean(eyeIdx[0]), e1 = mean(eyeIdx[1])
                    // brow centres of the SKINNED brows: their symmetric mean fixes the face's up direction (a shear that tilts one brow cancels in the pair)
                    let b0 = mean(browIdx[0]), b1 = mean(browIdx[1])
                    let m = (e0 + e1) / 2
                    let cur = Self.browFaceFrame(e0, e1, (b0 + b1) / 2)
                    let R = cur * browFrameRest.transpose
                    do {
                        for sd in 0..<2 {
                            // expression: the brow's rest offset is turned about its own centre (tilt) and lifted along the face's up axis (raise); both 0 skips this
                            let rise = exprOn ? browFrameRest.columns.1 * browRaise[sd] : SIMD3<Float>.zero
                            let tiltA = exprOn ? (sd == 0 ? browTilt[sd] : -browTilt[sd]) : 0
                            let tc = cosf(tiltA), ts = sinf(tiltA)
                            for (k, vi) in browIdx[sd].enumerated() {
                                var off: SIMD3<Float> = browRest[sd][k] - (browEyeRest[0] + browEyeRest[1]) / 2
                                if exprOn {
                                    if tiltA != 0 {
                                        let d = off - browCentreOff[sd]
                                        let fx = browFrameRest.columns.0, fy = browFrameRest.columns.1, fz = browFrameRest.columns.2
                                        let dx = simd_dot(d, fx), dy = simd_dot(d, fy), dz = simd_dot(d, fz)
                                        off = browCentreOff[sd] + fx * (dx * tc - dy * ts) + fy * (dx * ts + dy * tc) + fz * dz
                                    }
                                    off += rise
                                }
                                let t: SIMD3<Float> = m + R * off
                                let o = 6 * Int(vi)
                                dyn[o] += (t.x - dyn[o]) * browW; dyn[o + 1] += (t.y - dyn[o + 1]) * browW; dyn[o + 2] += (t.z - dyn[o + 2]) * browW
                            }
                        }
                    }
                }

                browCW += ((browCounterOn ? 1 : 0) - browCW) * (browCounterOn ? 0.35 : 0.12)
                if browCW > 0.002 && browIdx[0].count > 0 && browIdx[1].count > 0 {
                    let vp = Self.gameViewProj
                    let view = simd_normalize(GameCamera.target - GameCamera.eye)
                    for sd in 0..<2 {
                        // a thick, steeply slanted brow is measured by its extreme screen points, so turn it in two passes (the second removes what is left)
                        for _ in 0..<2 {
                            var c = SIMD3<Float>(0, 0, 0)
                            var lo = SIMD2<Float>(.infinity, 0), hi = SIMD2<Float>(-.infinity, 0)
                            for vi in browIdx[sd] {
                                let o = 6 * Int(vi), p = SIMD3(dyn[o], dyn[o + 1], dyn[o + 2])
                                c += p
                                let q = vp * SIMD4(p, 1), sc = SIMD2(q.x / q.w * GameCamera.aspect, q.y / q.w)
                                if sc.x < lo.x { lo = sc }
                                if sc.x > hi.x { hi = sc }
                            }
                            c /= Float(browIdx[sd].count)
                            let inner = sd == 0 ? hi : lo, outer = sd == 0 ? lo : hi
                            let raw = atan2f(inner.y - outer.y, abs(inner.x - outer.x))
                            let ang = max(0, Self.browFloor - raw) * browCW * (sd == 0 ? 1 : -1)
                            if ang == 0 { break }
                            let q = simd_quatf(angle: ang, axis: -view)
                            for vi in browIdx[sd] {
                                let o = 6 * Int(vi)
                                let p = c + q.act(SIMD3(dyn[o], dyn[o + 1], dyn[o + 2]) - c)
                                let n = q.act(SIMD3(dyn[o + 3], dyn[o + 4], dyn[o + 5]))
                                dyn[o] = p.x; dyn[o + 1] = p.y; dyn[o + 2] = p.z; dyn[o + 3] = n.x; dyn[o + 4] = n.y; dyn[o + 5] = n.z
                            }
                        }
                    }
                }
                for e in 0..<2 {
                    let k = e == 0 ? eyeHeight.left : eyeHeight.right
                    if k >= 0.999 { continue }
                    // The anchor points sit on the (extrapolated) body surface, so under a lean / dent / jiggle the skinned anchor drifts off the eye's
                    // own centre by a different amount per side; squashing toward it slid and crinkled one eye. The squash is about the eye's own
                    // skinned vertex centroid (at rest the centroid IS the anchor, so the rest face and the blink are unchanged); the anchors only
                    // give the up axis.
                    let cu = point(2 * e), u = point(2 * e + 1)
                    var c = cu
                    if !eyeIdx[e].isEmpty {
                        var mx: Float = 0, my: Float = 0, mz: Float = 0
                        for vi in eyeIdx[e] { let o = 6 * Int(vi); mx += dyn[o]; my += dyn[o + 1]; mz += dyn[o + 2] }
                        let inv = 1 / Float(eyeIdx[e].count)
                        c = (mx * inv, my * inv, mz * inv)
                    }
                    var ux = u.0 - cu.0, uy = u.1 - cu.1, uz = u.2 - cu.2
                    let ul = (ux * ux + uy * uy + uz * uz).squareRoot()
                    if ul < 1e-6 { continue }
                    ux /= ul; uy /= ul; uz /= ul
                    let squash = 1 - k
                    // glints vanish as the eye closes (scaled into the eyeball, behind its front surface)
                    let gt = min(1, max(0, (k - 0.3) / 0.25)), g = gt * gt * (3 - 2 * gt)
                    eyeFixK[e] = k; eyeFixU[e] = SIMD3(ux, uy, uz)
                    eyeIdx[e].withUnsafeBufferPointer { vs in
                        for vi in vs {
                            let o = 6 * Int(vi)
                            let dx = dyn[o] - c.0, dy = dyn[o + 1] - c.1, dz = dyn[o + 2] - c.2
                            let s = (dx * ux + dy * uy + dz * uz) * squash
                            dyn[o] -= s * ux; dyn[o + 1] -= s * uy; dyn[o + 2] -= s * uz
                        }
                    }
                    glintIdx[e].withUnsafeBufferPointer { vs in
                        for vi in vs {
                            let o = 6 * Int(vi)
                            let dx = dyn[o] - c.0, dy = dyn[o + 1] - c.1, dz = dyn[o + 2] - c.2
                            let s = (dx * ux + dy * uy + dz * uz) * squash
                            dyn[o] = c.0 + (dx - s * ux) * g; dyn[o + 1] = c.1 + (dy - s * uy) * g; dyn[o + 2] = c.2 + (dz - s * uz) * g
                        }
                    }
                }
            }
        }
    }
}

/// Vertex -> triangles (CSR, triangles ascending) of a render mesh, built once and shared by every Skinner that draws the same mesh.
nonisolated final class TriangleAdjacency {
    let vertexCount: Int
    let triangleCount: Int
    let start: [Int32]      // vertexCount + 1
    let tri: [Int32]        // index.count entries

    private init(index: [UInt32], vertexCount: Int) {
        self.vertexCount = vertexCount
        triangleCount = index.count / 3
        var count = [Int32](repeating: 0, count: vertexCount + 1)
        for i in index { count[Int(i) + 1] += 1 }
        for v in 0..<vertexCount { count[v + 1] += count[v] }
        start = count
        var fill = count
        var t = [Int32](repeating: 0, count: index.count)
        for (k, i) in index.enumerated() {               // triangles in ascending order per vertex: the scatter's addition order
            let v = Int(i); t[Int(fill[v])] = Int32(k / 3); fill[v] += 1
        }
        tri = t
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Int: TriangleAdjacency] = [:]
    /// Keyed by a hash of the index list; a different mesh gets its own.
    static func shared(index: [UInt32], vertexCount: Int) -> TriangleAdjacency {
        var h = Hasher(); h.combine(vertexCount); h.combine(index.count)
        index.withUnsafeBytes { h.combine(bytes: $0) }
        let key = h.finalize()
        lock.lock(); defer { lock.unlock() }
        if let a = cache[key], a.vertexCount == vertexCount, a.triangleCount == index.count / 3 { return a }
        let a = TriangleAdjacency(index: index, vertexCount: vertexCount)
        cache[key] = a
        return a
    }
}

/// Closest point on a triangle (Ericson, Real-Time Collision Detection) and its barycentric weights; shared by the bean guard and the drawn-space audit.
nonisolated enum DrawnGeom {
    static func closest(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 { return (a, SIMD3(1, 0, 0)) }
        let bp = p - b
        let d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 { return (b, SIMD3(0, 1, 0)) }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 { let v = d1 / (d1 - d3); return (a + ab * v, SIMD3(1 - v, v, 0)) }
        let cp = p - c
        let d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 { return (c, SIMD3(0, 0, 1)) }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 { let w = d2 / (d2 - d6); return (a + ac * w, SIMD3(1 - w, 0, w)) }
        let va = d3 * d6 - d5 * d4
        if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 { let w = (d4 - d3) / ((d4 - d3) + (d5 - d6)); return (b + (c - b) * w, SIMD3(0, 1 - w, w)) }
        let den = 1 / (va + vb + vc), v = vb * den, w = vc * den
        return (a + ab * v + ac * w, SIMD3(1 - v - w, v, w))
    }
}
