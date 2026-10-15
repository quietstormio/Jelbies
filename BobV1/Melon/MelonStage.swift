//
//  MelonStage.swift
//  Metal stage: MTKView subclass with touch handling, the controller that owns simulation + renderer
//  and drives the frame loop (port of the pointer / frame logic of main.js).
//

import SwiftUI
import MetalKit
import QuartzCore
import simd

// MARK: - SwiftUI wrapper

struct MelonStage: UIViewRepresentable {
    let model: MelonModel

    func makeCoordinator() -> MelonController { MelonController(model: model) }

    func makeUIView(context: Context) -> MelonStageView {
        let controller = context.coordinator
        let view = MelonStageView(frame: .zero, device: controller.device)
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: MelonStageView, context: Context) {}
}

// MARK: - View

let bobScaleCm: Float = 6      // 1 sim unit ~ 6 cm
let bobDensity: Float = 1.1    // gummy, g/cm^3

final class MelonStageView: MTKView, UIGestureRecognizerDelegate {
    weak var controller: MelonController?
    private var activeTouches = 0
    private weak var heldScrollView: UIScrollView?

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        preferredFramesPerSecond = 60
        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = UIColor(red: 0xE2 / 255, green: 0xDF / 255, blue: 0xDA / 255, alpha: 1)
        clearColor = MTLClearColor(red: 0.886, green: 0.875, blue: 0.855, alpha: 1)
        isAccessibilityElement = true
        accessibilityLabel = "Interactive 3D jelly character Bob. Drag him to squish, stretch and twist."
        accessibilityHint = "Drag the jelly to stretch it, drag empty space to orbit, pinch to zoom, double tap to reset the view."
        accessibilityIdentifier = "melon-stage"

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delaysTouchesBegan = false
        pinch.delaysTouchesEnded = false
        pinch.delegate = self
        addGestureRecognizer(pinch)
        let dbl = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        dbl.numberOfTapsRequired = 2
        dbl.cancelsTouchesInView = false
        dbl.delaysTouchesBegan = false
        dbl.delaysTouchesEnded = false
        dbl.delegate = self
        addGestureRecognizer(dbl)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Start at the screen's native scale; draw(in:) drops to 2x if the frame interval stays > ~18 ms.
        let s = window?.screen.scale ?? traitCollection.displayScale
        contentScaleFactor = s
        // Deliver touches immediately even inside a ScrollView.
        var v: UIView? = superview
        while let cur = v {
            if let sv = cur as? UIScrollView { sv.delaysContentTouches = false; break }
            v = cur.superview
        }
    }

    // MARK: Scroll ownership

    private func enclosingScrollView() -> UIScrollView? {
        var v: UIView? = superview
        while let cur = v {
            if let sv = cur as? UIScrollView { return sv }
            v = cur.superview
        }
        return nil
    }

    private func claim() {
        guard activeTouches == 0 else { return }
        if let sv = enclosingScrollView(), sv.isScrollEnabled {
            heldScrollView = sv
            sv.isScrollEnabled = false
        }
    }

    private func release() {
        if let sv = heldScrollView { sv.isScrollEnabled = true }
        heldScrollView = nil
    }

    // MARK: Touches (UITouch identity = pointer id)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        claim()
        activeTouches += touches.count
        for t in touches {
            controller?.pointerDown(id: ObjectIdentifier(t), point: t.location(in: self), size: bounds.size)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            controller?.pointerMove(id: ObjectIdentifier(t), point: t.location(in: self), size: bounds.size)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }

    private func finish(_ touches: Set<UITouch>) {
        for t in touches { controller?.pointerUp(id: ObjectIdentifier(t)) }
        activeTouches = max(0, activeTouches - touches.count)
        if activeTouches == 0 { release() }
    }

    // MARK: Gestures

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        guard g.state == .changed, g.scale > 0 else { return }
        controller?.pinch(scale: Float(g.scale))
        g.scale = 1
    }

    @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
        if g.state == .ended { controller?.resetCamera() }
    }

    func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool { true }

    deinit {
        // The enclosing scroll view must never stay locked if the stage disappears mid-touch.
        MainActor.assumeIsolated { release() }
    }
}

// MARK: - Controller

private enum DragMode { case none, grab, orbit }

final class MelonController: NSObject, MTKViewDelegate {
    let model: MelonModel
    let device: MTLDevice?
    /// Game screen: living room backdrop, fixed camera, no orbit / zoom.
    let game: Bool

    private let simMesh: SimMesh
    private let renderMesh: RenderMesh
    private let sim: SoftBody
    private let skinner: Skinner
    private var renderer: MelonRenderer?
    private var rig = CameraRig()
    private weak var stageView: MelonStageView?

    // frame state
    private var lastTime: CFTimeInterval = 0
    private var acc: Float = 0
    private var simTime: Float = 0
    private var readoutT: Float = 0
    private var firstFrameDone = false
    private var lastNudge: Int
    private var lastReset: Int
    private var lastPaused = false
    private var lastCam = CameraState()
    private var haveCam = false
    private let massG: Float

    // drag state
    private var mode: DragMode = .none
    private var dragID: ObjectIdentifier?
    private var planeP = SIMD3<Float>(0, 0, 0)
    private var planeN = SIMD3<Float>(0, 0, -1)
    private var twist: Float = 0
    private var twist0: Float = 0
    private var second: (id: ObjectIdentifier, p: CGPoint)?
    private var last = CGPoint.zero

    // perf counters (all configurations; logged once per second)
    private var dbgFrames = 0
    private var dbgStart: CFTimeInterval = 0
    private var matCost = 0.0, matN = 0
    private var dbgCPU: Double = 0
    private var dbgSim: Double = 0
    private var dbgSteps = 0
    private var gpuSumMs: Double = 0
    private var gpuSamples = 0

    #if DEBUG
    private var autoDrag = false
    private var autoT0: CFTimeInterval = 0
    private var autoStart = CGPoint.zero
    private var autoEnd = CGPoint.zero
    private var autoPhase = 0
    private var demo = false
    private var demoT0: CFTimeInterval = 0
    private var demoStep = 0
    private var demoStepT0: Double = 0
    private var demoFresh = false
    private var demoAnchor = CGPoint.zero
    private var demoUp = CGVector(dx: 0, dy: -1)    // screen-space px per world unit (camera up)
    private var demoRight = CGVector(dx: 1, dy: 0)  // screen-space px per world unit (camera right)
    #endif

    // Hopping (fixed-step time, so it honours pause and quarter speed)
    private var hopper = GaitDriver()
    private var wasHopping = false

    // BEGIN brain hook
    /// Bob's autonomous brain (BlobBrain.swift). nil = the old hop-around. The game screen sets it (or flips `brain.enabled`);
    /// launching with `-BlobDemo wave|walk|idle|play|eat|drink|come|step|look` creates one with that scripted demo.
    var brain: BlobBrain? = BlobBrain.fromLaunchArguments()

    /// Called once before each fixed sim step.
    private func hopTick(reduce: Bool) {
        if game && brain == nil { brain = BlobBrain.forGame() }
        if let brain, brain.enabled {
            wasHopping = false
            if !brain.hasRenderMesh { brain.attach(renderMesh: renderMesh) }
            brain.amplitude = reduce ? 0.55 : 1
            if brain.followsStudioCamera { brain.cameraPosXZ = SIMD2(rig.target.x, rig.target.z) + SIMD2(sinf(rig.azimuth), cosf(rig.azimuth)) * 10 }
            brain.tick(sim: sim, skinner: skinner, dt: sim.stepDt, touched: mode == .grab || sim.grabbing)
            renderer?.mouthOpen = brain.mouthOpen
            if game { model.care.tick(brain: brain, renderer: renderer, dt: sim.stepDt) }
            return
        }
        renderer?.mouthOpen = 0
        if !model.hopping { wasHopping = false; hopper.cancel(sim); return }
        if !wasHopping { wasHopping = true; hopper.wander = true; hopper.start(sim) }
        hopper.tick(sim, held: mode == .grab || sim.grabbing, reduce: reduce)
    }
    // END brain hook

    #if DEBUG
    /// Launch arguments for viewing individuals: -MelonBreed berry|mint|honey, -MelonMarking 0...6, -MelonFeatureScale 0.8...1.25,
    /// -MelonFeatureCount n, -MelonFeatureSeed n, -MelonSize 0.95...1.05, -MelonShade -0.15...0.15
    static func debugAppearance(_ base: BlobAppearance) -> BlobAppearance {
        let d = UserDefaults.standard
        var a = base
        if let b = d.string(forKey: "MelonBreed") {
            switch b { case "mint": a = .mint; case "honey": a = .honey; case "berry": a = .berry; default: break }
        }
        if d.object(forKey: "MelonMarking") != nil, let m = BlobAppearance.Marking(rawValue: d.integer(forKey: "MelonMarking")) { a.marking = m }
        if d.object(forKey: "MelonFeatureScale") != nil { a.featureScale = Float(d.double(forKey: "MelonFeatureScale")) }
        if d.object(forKey: "MelonFeatureCount") != nil { a.featureCount = d.integer(forKey: "MelonFeatureCount") }
        if d.object(forKey: "MelonFeatureSeed") != nil { a.featureSeed = UInt32(truncatingIfNeeded: d.integer(forKey: "MelonFeatureSeed")) }
        if d.object(forKey: "MelonSize") != nil { a.sizeScale = Float(d.double(forKey: "MelonSize")) }
        if d.object(forKey: "MelonShade") != nil { a.shade = Float(d.double(forKey: "MelonShade")) }
        return a
    }
    #endif

    // Not isolated: Swift 6.2's implicit isolated deinit (swift_task_deinitOnExecutor) aborts on the iOS 26.2 runtime; see MelonModel.
    nonisolated deinit {}

    init(model: MelonModel) {
        self.model = model
        self.game = model.gameMode
        #if DEBUG
        model.appearance = MelonController.debugAppearance(model.appearance)
        #endif
        let ap = model.appearance
        let sm = buildSimMesh(appearance: ap)
        let rm = buildRenderMesh(appearance: ap)
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let body = SoftBody(mesh: sm, firmness: Float(model.firmness), damping: Float(model.damping))
        simMesh = sm
        renderMesh = rm
        sim = body
        skinner = Skinner(simTets: sm.tets, embedding: emb, vertexCount: rm.vertexCount,
                          eyes: buildEyeRig(render: rm, sim: sm, appearance: ap),
                          antennae: buildAntennaRig(render: rm, sim: sm))
        massG = body.totalRestVolume * powf(bobScaleCm, 3) * bobDensity
        lastNudge = model.nudgeTick
        lastReset = model.resetTick
        device = MTLCreateSystemDefaultDevice()
        super.init()
        if game {
            sim.arenaCenter = GameCamera.arenaCenter
            sim.arenaRadius = GameCamera.arenaRadius
        }
        sim.reset(drop: model.reduceMotion ? 0 : 0.35)
        model.particles = body.n
        model.tets = body.nT
        model.seeds = rm.seedCount
        model.mass = Double(massG)
        #if DEBUG
        autoDrag = UserDefaults.standard.integer(forKey: "MelonAutoDrag") != 0
        demo = UserDefaults.standard.integer(forKey: "MelonDemo") != 0
        if UserDefaults.standard.integer(forKey: "MelonHop") != 0 { model.hopping = true }
        #endif
    }

    func attach(to view: MelonStageView) {
        stageView = view
        view.controller = self
        guard let device else { fail("This device has no Metal GPU, so there is nothing to render with."); return }
        guard let r = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: renderMesh,
                                    simEdges: sim.edges, particleCount: sim.n, game: game) else {
            fail("The Metal renderer could not be created (shader library or pipeline failure).")
            return
        }
        renderer = r
        view.delegate = self
    }

    private func fail(_ reason: String) {
        let m = model
        Task { @MainActor in m.metalUnavailableReason = reason }
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    // Adaptive drawable scale: native first, 2x if the average frame interval over 2 s exceeds 18 ms.
    private var adaptStart: CFTimeInterval = 0
    private var adaptFrames = 0
    private var adaptDone = false

    private func adaptScale(_ stage: UIView, now: CFTimeInterval, dt: Double) {
        guard !adaptDone, stage.contentScaleFactor > 2 else { adaptDone = true; return }
        if dt >= 0.1 { adaptStart = 0; adaptFrames = 0; gpuSumMs = 0; gpuSamples = 0; return }   // ignore stalls (first frames, backgrounding)
        if adaptStart == 0 { adaptStart = now; adaptFrames = 0; gpuSumMs = 0; gpuSamples = 0; return }
        adaptFrames += 1
        let el = now - adaptStart
        guard el >= 2 else { return }
        let avgMs = el / Double(adaptFrames) * 1000
        // Lower the resolution only if the frames are slow AND the GPU is a real part of it (a CPU-bound or
        // Debug-build slowdown is not helped by fewer pixels).
        let g = (avgMs: gpuSamples > 0 ? gpuSumMs / Double(gpuSamples) : 0, frames: gpuSamples)   // from the 1 Hz perf log
        if avgMs > 18 && g.avgMs > 7 {
            stage.contentScaleFactor = 2
            NSLog("%@", String(format: "[melon] scale: %.1f ms/frame at %.0fx (gpu %.1f ms) -> dropping to 2x", avgMs, Double(stage.window?.screen.scale ?? 3), g.avgMs))
        } else {
            NSLog("%@", String(format: "[melon] scale: %.1f ms/frame -> keeping native %.0fx (gpu %.1f ms)", avgMs, Double(stage.contentScaleFactor), g.avgMs))
        }
        adaptDone = true
    }

    func draw(in view: MTKView) {
        guard let renderer, let stage = stageView, view.drawableSize.width >= 2, view.drawableSize.height >= 2,
              let drawable = view.currentDrawable else { return }
        let cpu0 = CACurrentMediaTime()
        let now = cpu0
        let dt = lastTime == 0 ? Float(1.0 / 60) : min(Float(now - lastTime), 0.1)
        lastTime = now
        adaptScale(stage, now: now, dt: Double(dt))

        renderer.beginFrame()
        let m = model
        let reduce = m.reduceMotion

        // model -> sim
        sim.firmness = Float(m.firmness)
        sim.damping = Float(m.damping)
        let paused = m.paused
        if paused != lastPaused {
            lastPaused = paused
            if paused { cancelGrab() }
        }
        if m.resetTick != lastReset {
            lastReset = m.resetTick
            sim.reset(drop: reduce ? 0 : 0.35)
            acc = 0
            mode = (mode == .grab) ? .none : mode
        }
        if m.nudgeTick != lastNudge {
            lastNudge = m.nudgeTick
            if !paused { sim.nudge(strength: reduce ? 0.45 : 1) }
        }

        #if DEBUG
        if autoDrag { runAutoDrag(now: now, stage: stage) }
        if demo { runDemo(now: now, stage: stage) }
        #endif

        // fixed-step simulation
        let s0 = CACurrentMediaTime()
        if !paused {
            acc += dt * (m.slow ? 0.25 : 1)
            // At most 2 steps per frame; leftover time is dropped so one slow frame cannot snowball into more work.
            let maxSteps = 2
            var steps = 0
            while acc >= sim.stepDt && steps < maxSteps { hopTick(reduce: reduce); sim.step(); acc -= sim.stepDt; steps += 1 }
            if steps == maxSteps { acc = min(acc, sim.stepDt) }
            simTime += dt * (m.slow ? 0.25 : 1) * (reduce ? 0.25 : 1)   // drives the lava colour drift
            dbgSteps += steps
        }
        dbgSim += CACurrentMediaTime() - s0

        skinner.tickBlink(dt: dt)
        skinner.update(x: sim.x, index: renderMesh.index, into: renderer.dynPointer)
        if let w = skinner.takeMatWrites() {
            let t0 = CACurrentMediaTime()
            renderer.writeMat(w.vertices, values: w.values)
            matCost += CACurrentMediaTime() - t0; matN += 1
        } else if matN > 0 {
            NSLog("%@", String(format: "[melon] wave arm mat writes: %.1f us per frame (%d frames)", matCost / Double(matN) * 1e6, matN))
            matCost = 0; matN = 0
        }
        let c = sim.centroid()
        if !game { rig.follow(centroid: c, dt: dt, grabbing: mode == .grab) }

        // camera + light
        let pts = stage.bounds.size
        let safe: CGRect
        if stage.traitCollection.horizontalSizeClass == .regular {
            safe = CGRect(x: pts.width * 0.05, y: pts.height * 0.12, width: pts.width * 0.62, height: pts.height * 0.70)
        } else {
            safe = CameraRig.fullSafeRect(pts)
        }
        let cam = game ? GameCamera.camera(aspect: Float(pts.width / max(pts.height, 1))) : rig.camera(viewSize: pts, safeRect: safe)
        lastCam = cam
        haveCam = true
        let light = game ? GameCamera.light(centroid: c) : rig.light(centroid: c)

        renderer.resize(width: Int(view.drawableSize.width), height: Int(view.drawableSize.height))
        var fp = FrameParams()
        fp.time = simTime
        fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
        fp.exposure = 1
        fp.meshAlpha = m.showMesh ? 0.32 : 0
        fp.bg = m.palette.palette.matte ? melonCreamLinear : melonBackgroundLinear
        renderer.setUniforms(camera: cam, light: light, palette: m.palette.palette, params: fp,
                             viewSize: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)))
        if m.showMesh { sim.x.withUnsafeBufferPointer { renderer.uploadParticles($0.baseAddress!) } }
        renderer.draw(drawable: drawable, showMesh: m.showMesh)

        if !firstFrameDone {
            firstFrameDone = true
            if m.status == .starting { m.status = paused ? .paused : .live }
        }

        readoutT += dt
        if readoutT > 0.12 {
            readoutT = 0
            publishReadouts()
        }

        dbgCPU += CACurrentMediaTime() - cpu0
        dbgFrames += 1
        if dbgStart == 0 { dbgStart = now }
        if now - dbgStart >= 1 {
            let el = now - dbgStart
            let f = Double(dbgFrames)
            let g = renderer.takeGPUStats()
            gpuSumMs += g.avgMs * Double(g.frames); gpuSamples += g.frames
            NSLog("%@", String(format: "[melon] perf: cpu %.2f ms, gpu %.2f ms, sim %.2f ms (%.2f ms/step, %d steps) | %.1f fps, interval %.2f ms",
                         dbgCPU / f * 1000, g.avgMs, dbgSim / f * 1000,
                         dbgSteps > 0 ? dbgSim / Double(dbgSteps) * 1000 : 0, dbgSteps, f / el, el / f * 1000))
            dbgFrames = 0; dbgStart = now; dbgCPU = 0; dbgSim = 0; dbgSteps = 0
            fflush(stdout)
        }
    }

    private func publishReadouts() {
        model.volumePct = Double(sim.volumeRatio() * 100)
        let ke = sim.kineticEnergy() / sim.totalMass * (massG / 1000) * powf(bobScaleCm / 100, 2)
        model.kineticMicroJ = Double(ke) * 1e6
        model.mass = Double(massG)
    }

    // MARK: Camera

    func pinch(scale: Float) {
        guard !game, mode != .grab, scale > 0 else { return }
        rig.applyZoom(factor: 1 / scale)
    }

    func resetCamera() { if !game { rig.reset() } }

    // MARK: Pointer handling (shared by touches and the DEBUG auto-drag)

    private func ndc(_ p: CGPoint, _ size: CGSize) -> SIMD2<Float> {
        SIMD2<Float>(Float(p.x / size.width) * 2 - 1, 1 - Float(p.y / size.height) * 2)
    }

    private func rotMat(_ a: SIMD3<Float>, _ ang: Float) -> [Float] {
        let c = cosf(ang), s = sinf(ang), t = 1 - c
        let x = a.x, y = a.y, z = a.z
        return [t * x * x + c, t * x * y - s * z, t * x * z + s * y,
                t * x * y + s * z, t * y * y + c, t * y * z - s * x,
                t * x * z - s * y, t * y * z + s * x, t * z * z + c]
    }

    private func dragTarget(_ p: CGPoint, _ size: CGSize) -> SIMD3<Float>? {
        let ray = unproject(ndc: ndc(p, size), invViewProj: lastCam.invViewProj)
        let den = simd_dot(ray.d, planeN)
        if abs(den) < 1e-5 { return nil }
        let t = simd_dot(planeP - ray.o, planeN) / den
        var q = ray.o + ray.d * t
        let dx = q.x - rig.target.x, dz = q.z - rig.target.z, lim: Float = 3.4
        let dl = (dx * dx + dz * dz).squareRoot()
        if dl > lim { q.x = rig.target.x + dx / dl * lim; q.z = rig.target.z + dz / dl * lim }
        q.y = min(max(q.y, 0.02), 3.2)
        if game {
            // keep the held patch over the visible floor (and off the sofa / props)
            let k = GameCamera.constrain(SIMD3<Float>(q.x, 0, q.z), radius: 0.35)
            q.x = k.x; q.z = k.z
        }
        return q
    }

    private func applyGrab(_ p: CGPoint, _ size: CGSize) {
        if let q = dragTarget(p, size) { sim.moveGrab(target: q, rot: rotMat(lastCam.fwd, twist)) }
    }

    private func cancelGrab() {
        if mode == .grab { sim.endGrab(); mode = .none; dragID = nil; second = nil }
    }

    func pointerDown(id: ObjectIdentifier, point p: CGPoint, size: CGSize) {
        guard haveCam, size.width > 0, size.height > 0 else { return }
        if mode == .grab, id != dragID {
            if second == nil {
                second = (id, p)
                twist0 = twist - Float(atan2(p.y - last.y, p.x - last.x))
            }
            return
        }
        if mode != .none { return }
        var hit: SIMD3<Float>? = nil
        if !model.paused, let renderer {
            let ray = unproject(ndc: ndc(p, size), invViewProj: lastCam.invViewProj)
            hit = pickRay(origin: ray.o, dir: ray.d, dyn: renderer.dynPointer, index: renderMesh.index,
                          bodyIndexCount: renderMesh.body.first + renderMesh.body.count)
                ?? pickNear(screenPoint: SIMD2<Float>(Float(p.x), Float(p.y)), viewProj: lastCam.viewProj,
                            viewSize: SIMD2<Float>(Float(size.width), Float(size.height)), x: sim.x, maxPx: 34)
        }
        dragID = id
        last = p
        if let hit {
            mode = .grab
            twist = 0
            planeP = hit
            planeN = lastCam.fwd
            sim.beginGrab(hit: hit, radius: 0.4)
        } else {
            mode = .orbit
        }
    }

    func pointerMove(id: ObjectIdentifier, point p: CGPoint, size: CGSize) {
        guard haveCam else { return }
        if let s = second, s.id == id {
            second = (id, p)
            twist = twist0 + Float(atan2(p.y - last.y, p.x - last.x))
            twist = max(-1.3, min(1.3, twist))
            applyGrab(last, size)
            return
        }
        guard id == dragID, mode != .none else { return }
        let dx = Float(p.x - last.x), dy = Float(p.y - last.y)
        last = p
        if mode == .grab {
            applyGrab(p, size)
        } else if !game {
            rig.orbit(dAzimuth: -dx * 0.006, dElevation: dy * 0.005)
        }
    }

    func pointerUp(id: ObjectIdentifier) {
        if let s = second, s.id == id { second = nil; return }
        guard id == dragID else { return }
        if mode == .grab { sim.endGrab() }
        mode = .none
        dragID = nil
        second = nil
    }

    // MARK: DEBUG auto-drag (launch argument -MelonAutoDrag 1)

    #if DEBUG
    private func project(_ w: SIMD3<Float>, _ size: CGSize) -> CGPoint {
        let c = lastCam.viewProj * SIMD4<Float>(w.x, w.y, w.z, 1)
        return CGPoint(x: CGFloat((c.x / c.w * 0.5 + 0.5)) * size.width, y: CGFloat((0.5 - c.y / c.w * 0.5)) * size.height)
    }

    /// t=1.5s grab the apex (highest particle), pull 1.5 units up (screen-up) over 1s, hold, release at t=4.5s.
    private func runAutoDrag(now: CFTimeInterval, stage: MelonStageView) {
        guard haveCam else { return }
        if autoT0 == 0 { autoT0 = now }
        let t = now - autoT0
        let size = stage.bounds.size
        let id = ObjectIdentifier(self)
        switch autoPhase {
        case 0 where t > 1.5:
            let tip = demoPos(demoApexIndex())
            // camera-up in world space
            let up = SIMD3<Float>(lastCam.view.columns.0.y, lastCam.view.columns.1.y, lastCam.view.columns.2.y)
            autoStart = project(tip, size)
            autoEnd = project(tip + up * 1.5, size)
            pointerDown(id: id, point: autoStart, size: size)
            autoPhase = 1
            NSLog("[melon] autodrag: grab at %@ mode=%@", "\(autoStart)", "\(mode)"); fflush(stdout)
        case 1:
            let k = CGFloat(min(1, max(0, (t - 1.5) / 1.0)))
            pointerMove(id: id, point: CGPoint(x: autoStart.x + (autoEnd.x - autoStart.x) * k,
                                               y: autoStart.y + (autoEnd.y - autoStart.y) * k), size: size)
            if t > 4.5 { pointerUp(id: id); autoPhase = 2; NSLog("[melon] autodrag: released"); fflush(stdout) }
        default: break
        }
    }

    // MARK: DEBUG choreographed demo (launch argument -MelonDemo 1)

    private func demoPos(_ i: Int) -> SIMD3<Float> { SIMD3<Float>(sim.x[3 * i], sim.x[3 * i + 1], sim.x[3 * i + 2]) }

    /// Highest particle (Bob's apex).
    private func demoApexIndex() -> Int {
        var best = 0, bh = -Float.greatestFiniteMagnitude
        for i in 0..<sim.n { let y = sim.x[3 * i + 1]; if y > bh { bh = y; best = i } }
        return best
    }

    /// Particle with the largest x among those near belly height (about 35% of the way up the body).
    private func demoSideIndex() -> Int {
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for i in 0..<sim.n { let y = sim.x[3 * i + 1]; lo = min(lo, y); hi = max(hi, y) }
        let belly = lo + (hi - lo) * 0.35
        var best = 0, bx = -Float.greatestFiniteMagnitude
        for i in 0..<sim.n {
            let p = demoPos(i)
            if abs(p.y - belly) > (hi - lo) * 0.15 { continue }
            if p.x > bx { bx = p.x; best = i }
        }
        return best
    }

    /// Screen-space offset (px) for a world-space move of (right, up) units, using the camera axes at step start.
    private func demoOffset(_ r: Double, _ u: Double) -> CGPoint {
        CGPoint(x: demoRight.dx * r + demoUp.dx * u, y: demoRight.dy * r + demoUp.dy * u)
    }

    private func demoSmooth(_ x: Double) -> Double { let k = min(1, max(0, x)); return k * k * (3 - 2 * k) }

    private func demoBegin(_ world: SIMD3<Float>, _ size: CGSize, _ id: ObjectIdentifier) {
        let a = project(world, size)
        let up = SIMD3<Float>(lastCam.view.columns.0.y, lastCam.view.columns.1.y, lastCam.view.columns.2.y)
        let right = SIMD3<Float>(lastCam.view.columns.0.x, lastCam.view.columns.1.x, lastCam.view.columns.2.x)
        let pu = project(world + up, size), pr = project(world + right, size)
        demoUp = CGVector(dx: pu.x - a.x, dy: pu.y - a.y)
        demoRight = CGVector(dx: pr.x - a.x, dy: pr.y - a.y)
        demoAnchor = a
        pointerDown(id: id, point: a, size: size)
    }

    private func runDemo(now: CFTimeInterval, stage: MelonStageView) {
        guard haveCam else { return }
        if demoT0 == 0 { demoT0 = now }
        let t = now - demoT0 - 1.5
        if t < 0 || demoStep >= 8 { return }
        let size = stage.bounds.size
        let A = ObjectIdentifier(self)
        let B = ObjectIdentifier(stage)
        func at(_ r: Double, _ u: Double) -> CGPoint {
            let o = demoOffset(r, u); return CGPoint(x: demoAnchor.x + o.x, y: demoAnchor.y + o.y)
        }
        // step durations (s)
        let durs: [Double] = [4.2, 4.0, 5.2, 3.6, 2.5, 5.5, 7.0, 0.1]
        let s = t - demoStepT0
        switch demoStep {
        case 0: // apex: stretch him tall (up + sideways), release, wobble
            if !demoFresh { demoFresh = true; NSLog("[bob] demo: a) grab apex, stretch up and sideways"); demoBegin(demoPos(demoApexIndex()), size, A) }
            if s < 1.8 { let k = demoSmooth(s / 1.2); pointerMove(id: A, point: at(-0.35 * k, 0.55 * k), size: size) }
            else if s < 1.85 { pointerUp(id: A); NSLog("[bob] demo: a) release, wobble") }
        case 1: // side wiggle
            if !demoFresh { demoFresh = true; NSLog("[bob] demo: b) grab side, wiggle"); demoBegin(demoPos(demoSideIndex()), size, A) }
            if s < 2.0 { let k = sin(4 * Double.pi * s / 2.0) * demoSmooth(s / 0.3); pointerMove(id: A, point: at(0.5 * k, 0), size: size) }
            else if s < 2.05 { pointerUp(id: A); NSLog("[bob] demo: b) release, wobble") }
        case 2: // top: lift + two-finger twist
            if !demoFresh { demoFresh = true; NSLog("[bob] demo: c) grab top, lift, twist"); demoBegin(demoPos(demoApexIndex()), size, A) }
            if s < 0.9 { let k = demoSmooth(s / 0.8); pointerMove(id: A, point: at(0, 0.45 * k), size: size) }
            else if s < 3.1 {
                let center = at(0, 0.45), rad = 90.0
                func f(_ th: Double) -> CGPoint { CGPoint(x: center.x + rad * cos(th), y: center.y + rad * sin(th)) }
                if second == nil { pointerDown(id: B, point: f(0), size: size) }
                let u = (s - 0.9) / 2.0
                // 0 -> +1.0 -> -1.0 -> 0 over 2 s
                let ang: Double
                if u < 0.25 { ang = demoSmooth(u / 0.25) }
                else if u < 0.75 { ang = 1 - 2 * demoSmooth((u - 0.25) / 0.5) }
                else { ang = -1 + demoSmooth((u - 0.75) / 0.25) }
                pointerMove(id: B, point: f(ang), size: size)
            } else if s < 3.15 { pointerUp(id: B); pointerUp(id: A); NSLog("[bob] demo: c) release both, wobble") }
        case 3: // orbit
            if !demoFresh {
                demoFresh = true; NSLog("[bob] demo: d) orbit camera")
                demoAnchor = CGPoint(x: size.width * 0.12, y: size.height * 0.88)
                pointerDown(id: A, point: demoAnchor, size: size)
            }
            if s < 3.0 {
                let u = s / 3.0
                let k = u < 0.5 ? demoSmooth(u / 0.5) : 1 - demoSmooth((u - 0.5) / 0.5)
                // azimuth change = -dx * 0.006; ~40deg = 0.70 rad -> dx = -116 px
                pointerMove(id: A, point: CGPoint(x: demoAnchor.x + 116 * k, y: demoAnchor.y), size: size)
            } else if s < 3.05 { pointerUp(id: A) }
        case 4: // nudge
            if !demoFresh { demoFresh = true; NSLog("[bob] demo: e) nudge"); model.nudge() }
        case 5: // squash: push the apex down toward the floor
            if !demoFresh { demoFresh = true; NSLog("[bob] demo: f) grab apex, push down to squash"); demoBegin(demoPos(demoApexIndex()), size, A) }
            if s < 2.5 { let k = demoSmooth(s / 1.6); pointerMove(id: A, point: at(0, -0.5 * k), size: size) }
            else if s < 2.55 { pointerUp(id: A); NSLog("[bob] demo: f) release, settle") }
        case 6: // hop around for a few seconds
            if !demoFresh { demoFresh = true; NSLog("[bob] demo: g) hop around"); model.hopping = true }
            if s > 6.6 && model.hopping { model.hopping = false; NSLog("[bob] demo: g) stop hopping") }
        default:
            NSLog("[bob] demo: ended"); fflush(stdout)
        }
        if s >= durs[demoStep] { demoStep += 1; demoStepT0 = t; demoFresh = false }
    }
    #endif
}
