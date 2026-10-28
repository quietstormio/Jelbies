//
//  MotionTestRig.swift
//  Shared headless rig for the motion suites (grounded / facing / slip / gait / wave shape / hop): a soft body, skinner and brain
//  ticked like the stage does, with per-step probes of his feet, root and heading. All lengths are world units; H = body height.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MotionRig {
    static let simMesh = buildSimMesh()
    static let renderMesh = buildRenderMesh()
    static let H = Float(BobForm.top)

    let sim: SoftBody
    let skinner: Skinner
    let brain: BlobBrain
    let game: Bool
    var t: Float = 0
    private(set) var feetIdx: [[Int]] = [[], []]
    /// The render mesh skinned like the stage does, so tests can look at what is actually drawn.
    var dyn: [Float]
    var core: [[Int32]] = [[], []]
    /// The foot bean vertices of each side (hidden inside the belly until the beans are out).
    var bean: [[Int32]] = [[], []]
    /// The vertices that form the visible foot now: the bean once it is out (the embedded foot is retracted into the belly), else the embedded foot.
    private var retractMag: [Int32: Float] = [:]
    var sole: [[Int32]] {
        guard skinner.beansActive else { return core }
        if retractMag.count != skinner.retractVertices.count {
            for (k, v) in skinner.retractVertices.enumerated() { retractMag[v] = skinner.retractWeight[k] * 0.1 }
        }
        // bean + the embedded foot's vertices that the retraction has not moved yet (a retracted vertex is belly skin under the bean)
        let b = skinner.beanBlend
        return (0..<2).map { s in bean[s] + core[s].filter { (retractMag[$0] ?? 0) * b < 0.004 } }
    }
    var renderSamples = true

    /// `game`: the game-screen brain (attention pitch, face-the-player idle, room bounds); otherwise the studio brain.
    init(game: Bool = false, settle: Float = 1.0) {
        let sm = Self.simMesh, rm = Self.renderMesh
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        skinner = Skinner(simTets: sm.tets, embedding: emb, vertexCount: rm.vertexCount,
                          eyes: buildEyeRig(render: rm, sim: sm), antennae: buildAntennaRig(render: rm, sim: sm))
        sim = SoftBody(mesh: sm, firmness: 0.95)
        sim.reset(drop: 0.35)
        for _ in 0..<300 { sim.step() }
        brain = game ? BlobBrain.forGame() : BlobBrain()
        brain.autonomy = false
        brain.attach(renderMesh: rm, synchronous: true)
        self.game = game
        dyn = [Float](repeating: 0, count: rm.vertexCount * 6)
        for a in sim.appendages where a.kind == .foot { feetIdx[a.side < 0 ? 0 : 1] += a.particles }
        core = [brain.footCoreVertices(0, sim: sim, skinner: skinner), brain.footCoreVertices(1, sim: sim, skinner: skinner)]
        if let cap = rm.armCapsule {
            for (k, side) in [-1, 1].enumerated() { let f = cap.beanFirst(side: side); bean[k] = (f..<(f + FootBean.vertexCount)).map { Int32($0) } }
        }
        run(settle)
    }

    func tick(touched: Bool = false) {
        brain.tick(sim: sim, skinner: skinner, dt: sim.stepDt, touched: touched)
        sim.step()
        brain.refitBeans(sim, skinner)          // (as the stage does after its steps)
        t += sim.stepDt
    }

    func run(_ seconds: Float, until: (() -> Bool)? = nil, each: (() -> Void)? = nil) {
        let n = Int(seconds * 60)
        for _ in 0..<n {
            tick()
            each?()
            if let until, until() { break }
        }
    }

    /// Skin the render mesh from the current sim state (as the renderer does each frame).
    func render() { skinner.update(x: sim.x, index: Self.renderMesh.index, into: &dyn) }
    /// Lowest y of a foot's rendered core (bean) vertices above the floor.
    func renderedFootGap(_ s: Int) -> Float { (sole[s].map { dyn[6 * Int($0) + 1] }.min() ?? 0) - sim.floorY }

    /// Mean xz of the lowest rendered core vertices of a foot (the visible sole contact).
    func renderedFootXZ(_ s: Int) -> SIMD2<Float> {
        let ids = sole[s]
        let lo = ids.map { dyn[6 * Int($0) + 1] }.min() ?? 0
        var a = SIMD2<Float>(0, 0), c: Float = 0
        for v in ids { let o = 6 * Int(v); if dyn[o + 1] < lo + 0.03 { a += SIMD2(dyn[o], dyn[o + 2]); c += 1 } }
        return c > 0 ? a / c : a
    }

    /// Lowest y of a foot's particles (side 0 = -x foot, 1 = +x foot).
    func footBottom(_ s: Int) -> Float { feetIdx[s].map { sim.x[3 * $0 + 1] }.min() ?? 0 }
    /// Mean xz of a foot's lowest particles (the sole contact).
    func footXZ(_ s: Int) -> SIMD2<Float> {
        let ys = feetIdx[s].map { sim.x[3 * $0 + 1] }
        let lo = ys.min() ?? 0
        var a = SIMD2<Float>(0, 0), c: Float = 0
        for (k, p) in feetIdx[s].enumerated() where ys[k] < lo + 0.03 { a += SIMD2(sim.x[3 * p], sim.x[3 * p + 2]); c += 1 }
        return c > 0 ? a / c : a
    }
    /// min(foot bottoms) - floor
    var groundGap: Float { min(footBottom(0), footBottom(1)) - sim.floorY }
    var root: SIMD2<Float> { let c = sim.centroid(); return SIMD2(c.x, c.z) }
    /// Heading of the body's face about world y.
    var poseYaw: Float { sim.bodyPose(iterations: 4).yaw }
    /// Camera-facing yaw for the brain's current root.
    var faceYaw: Float {
        let cam = brain.cameraPosXZ, r = root
        return atan2f(cam.x - r.x, cam.y - r.y)
    }
    /// Angle (rad) between the face normal's horizontal azimuth and the camera direction, from the commanded-free body pose
    /// (measured: apply the fitted rotation to the face normal and project on the camera's right / forward vectors).
    var apparentYaw: Float {
        let n = sim.bodyPose(iterations: 4).rotation.act(SIMD3<Float>(0, 0, 1))
        let cam = brain.cameraPosXZ - root
        let f = simd_normalize(SIMD2(cam.x, cam.y))
        let r = SIMD2(f.y, -f.x)
        return atan2f(simd_dot(SIMD2(n.x, n.z), r), simd_dot(SIMD2(n.x, n.z), f))
    }
}

/// Test-side log sink (stdout of the simulator test host is not captured by xcodebuild): appends to the file named by the
/// MOTION_LOG environment variable (pass it as TEST_RUNNER_MOTION_LOG), falling back to NSTemporaryDirectory.
enum MotionLog {
    static var path: String { ProcessInfo.processInfo.environment["MOTION_LOG"] ?? (NSTemporaryDirectory() + "motion.log") }
    static func write(_ s: String) {
        print(s)
        let line = s + "\n"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
    }
}

/// One sim step of a recorded scenario.
struct MotionSample {
    var t: Float
    var activity: BlobActivity
    var gap: [Float]            // foot bottoms above the floor (index 0 = -x foot)
    var rgap: [Float]           // the same for the RENDERED rigid foot (lowest bean vertex)
    var xz: [SIMD2<Float>]      // foot contact xz
    var root: SIMD2<Float>      // centroid xz
    var yawErr: Float           // pose yaw - camera yaw (rad)
    var apparent: Float         // face-normal azimuth vs camera ray (rad)
    var roll: Float             // lean of the body's up axis toward +x (rad)
    var openness: Float
    var waving: Bool
    var tipBack: Float          // face-normal elevation (rad): + = he looks up / is tipped back toward the viewer
}

extension MotionRig {
    func sample() -> MotionSample {
        let up = sim.bodyPose(iterations: 4).rotation.act(SIMD3<Float>(0, 1, 0))
        if renderSamples { render() }
        return MotionSample(t: t, activity: brain.activity, gap: [footBottom(0) - sim.floorY, footBottom(1) - sim.floorY],
                            rgap: renderSamples ? [renderedFootGap(0), renderedFootGap(1)] : [footBottom(0) - sim.floorY, footBottom(1) - sim.floorY],
                            xz: renderSamples ? [renderedFootXZ(0), renderedFootXZ(1)] : [footXZ(0), footXZ(1)], root: root, yawErr: wrapPi(poseYaw - faceYaw), apparent: apparentYaw,
                            roll: atan2f(up.x, up.y), openness: skinner.openness.left, waving: brain.isWaving, tipBack: asinf(max(-1, min(1, sim.bodyPose(iterations: 4).rotation.act(SIMD3<Float>(0, 0, 1)).y))))
    }
    /// Run `seconds` and record every step.
    func record(_ seconds: Float, until: (() -> Bool)? = nil) -> [MotionSample] {
        var out: [MotionSample] = []
        run(seconds, until: until) { out.append(self.sample()) }
        return out
    }
}

func wrapPi(_ a: Float) -> Float {
    var d = a
    while d > .pi { d -= 2 * .pi }
    while d < -.pi { d += 2 * .pi }
    return d
}
