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
        let single = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))     // game: a tap on the floor cancels a pending Blob selection
        single.cancelsTouchesInView = false
        single.delaysTouchesBegan = false
        single.delaysTouchesEnded = false
        single.delegate = self
        single.require(toFail: dbl)
        addGestureRecognizer(single)
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
        guard g.state == .ended else { return }
        if controller?.game == true { controller?.gameDoubleTap(g.location(in: self)) }     // game: a double tap on a Blob selects it (no camera reset)
        else { controller?.resetCamera() }
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        if g.state == .ended, controller?.game == true { controller?.gameSingleTap(g.location(in: self)) }
    }

    func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool { true }

    deinit {
        // The enclosing scroll view must never stay locked if the stage disappears mid-touch.
        MainActor.assumeIsolated { release() }
    }
}

// MARK: - Controller

private enum DragMode { case none, grab, orbit, pet, pending, cheeks }

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
    private var dbgBrain: Double = 0, dbgStepOnly: Double = 0, dbgTouch: Double = 0, dbgHaptic: Double = 0
    // touch play (focus mode): the pet finger
    private var petPoint = CGPoint.zero
    private var restSurface: RestSurface?
    // the gesture decides the action (TouchGesture.swift): pet / tap / pick up / throw / cheeks pinch
    private var gesture = TouchGesture()
    private var gestureHit: SIMD3<Float>?
    private var cheekFingers: [(id: ObjectIdentifier, p: CGPoint)] = []
    private var tapUntil: CFTimeInterval = 0
    private var grabSamples: [(t: CFTimeInterval, q: SIMD3<Float>)] = []
    private var liftHeight: Float = 0
    private var throwHold: Float = 0
    private var touchSize = CGSize.zero

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
    /// Capture aid: -BlobIdleMood happy|okay|grumpy pins the mood the idle behaviours read.
    private static let idleMoodOverride: BlobMood? = UserDefaults.standard.string(forKey: "BlobIdleMood").flatMap(BlobMood.init(rawValue:))
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
            if game {      // room life (BlobBrain+Idle.swift): mood picks the idle behaviours; focus mode and a meal on the tray hold them back
                brain.idleMood = Self.idleMoodOverride ?? model.care.mood
                brain.idleBlocked = model.care.focus.isActive || model.care.trayOut
            }
            if brain.followsStudioCamera { brain.cameraPosXZ = SIMD2(rig.target.x, rig.target.z) + SIMD2(sinf(rig.azimuth), cosf(rig.azimuth)) * 10 }
            let b0 = CACurrentMediaTime()
            throwHold = max(0, throwHold - sim.stepDt)
            brain.tick(sim: sim, skinner: skinner, dt: sim.stepDt, touched: mode == .grab || sim.grabbing || throwHold > 0 || model.touch.holdsBrain)
            dbgBrain += CACurrentMediaTime() - b0
            renderer?.mouthOpen = brain.mouthOpen
            if game { model.care.tick(brain: brain, renderer: renderer, dt: sim.stepDt, sim: sim) }
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

        let tt0 = CACurrentMediaTime()
        touchDemo(now: now)
        touchTick(dt: dt, now: now)
        dbgTouch += CACurrentMediaTime() - tt0

        // fixed-step simulation
        let s0 = CACurrentMediaTime()
        if !paused {
            acc += dt * (m.slow ? 0.25 : 1)
            // At most 2 steps per frame; leftover time is dropped so one slow frame cannot snowball into more work.
            let maxSteps = 2
            var steps = 0
            while acc >= sim.stepDt && steps < maxSteps { hopTick(reduce: reduce); let st0 = CACurrentMediaTime(); sim.step(); dbgStepOnly += CACurrentMediaTime() - st0; acc -= sim.stepDt; steps += 1 }
            if steps == maxSteps { acc = min(acc, sim.stepDt) }
            if game, steps > 0, let brain, brain.enabled { model.care.refreshHeld(brain: brain, sim: sim, renderer: renderer) }
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
        let cam = game ? GameCamera.camera(aspect: Float(pts.width / max(pts.height, 1)), focus: model.care.focus.blend) : rig.camera(viewSize: pts, safeRect: safe)
        lastCam = cam
        haveCam = true
        if game, model.care.select.count > 1 || model.care.select.isSelecting { model.care.select.publish(viewProj: cam.viewProj, size: pts) { bobScreenPoints(pts, cam.viewProj) } }   // also with 1 Blob while a highlight is up: his real outline
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
            if game {
                let hc = model.touch.haptics.takeCost()
                NSLog("%@", String(format: "[touch] perf: sim step %.3f ms, brain %.3f ms/step, touch frame %.3f ms (haptics update %.4f ms) per frame",
                                   dbgSteps > 0 ? dbgStepOnly / Double(dbgSteps) * 1000 : 0, dbgSteps > 0 ? dbgBrain / Double(dbgSteps) * 1000 : 0,
                                   dbgTouch / f * 1000, hc.ms))
            }
            dbgBrain = 0; dbgStepOnly = 0; dbgTouch = 0
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

    // MARK: Multi-Blob select (the highlight itself is BlobSelect / SelectionOverlay)

    /// Double tap in the game: select the Blob under the finger (roaming only; with one Blob there is no select step).
    func gameDoubleTap(_ p: CGPoint) {
        guard game, !model.care.focus.isActive, let id = model.care.select.hit(p) else { return }
        model.care.select.doubleTap(id)
    }

    /// A tap on the floor (not on a Blob) cancels a pending selection.
    func gameSingleTap(_ p: CGPoint) {
        let sel = model.care.select
        if game, sel.isSelecting, sel.hit(p) == nil { sel.cancel() }
    }

    /// The real Blob's render vertices projected to screen points (for his outline).
    private func bobScreenPoints(_ size: CGSize, _ vp: simd_float4x4) -> [CGPoint] {
        guard let renderer else { return [] }
        let d = renderer.dynPointer
        var out: [CGPoint] = []
        out.reserveCapacity(renderMesh.vertexCount)
        for i in 0..<renderMesh.vertexCount {
            let o = 6 * i
            let q = vp * SIMD4<Float>(d[o], d[o + 1], d[o + 2], 1)
            if q.w > 1e-4 { out.append(CGPoint(x: CGFloat(q.x / q.w * 0.5 + 0.5) * size.width, y: CGFloat(1 - (q.y / q.w * 0.5 + 0.5)) * size.height)) }
        }
        return out
    }

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

    private func dragTarget(_ p: CGPoint, _ size: CGSize, limited: Bool = true) -> SIMD3<Float>? {
        let ray = unproject(ndc: ndc(p, size), invViewProj: lastCam.invViewProj)
        let den = simd_dot(ray.d, planeN)
        if abs(den) < 1e-5 { return nil }
        let t = simd_dot(planeP - ray.o, planeN) / den
        var q = ray.o + ray.d * t
        let dx = q.x - rig.target.x, dz = q.z - rig.target.z, lim: Float = 3.4
        let dl = (dx * dx + dz * dz).squareRoot()
        if dl > lim { q.x = rig.target.x + dx / dl * lim; q.z = rig.target.z + dz / dl * lim }
        if !limited { return q }                        // the raw point under the finger (the throw speed is measured on it)
        q.y = min(max(q.y, 0.02), 3.2)
        if game, model.care.focus.isFocused {
            // he stays near the close-up's spot while lifted
            let sx = GameCamera.callSpot.x, sz = GameCamera.callSpot.y
            q.x = min(max(q.x, sx - 0.5), sx + 0.5); q.z = min(max(q.z, sz - 0.5), sz + 0.5)
            q.y = min(q.y, planeP.y + 0.4)            // lifted a hand's width: feet clear of the floor, still whole in the close-up frame
        }
        if game {
            // keep the held patch over the visible floor (and off the sofa / props)
            let k = GameCamera.constrain(SIMD3<Float>(q.x, 0, q.z), radius: 0.35)
            q.x = k.x; q.z = k.z
        }
        return q
    }

    private func applyGrab(_ p: CGPoint, _ size: CGSize) {
        if let q = dragTarget(p, size) {
            sim.moveGrab(target: q, rot: rotMat(lastCam.fwd, twist))
            liftHeight = q.y - planeP.y
        }
        if let raw = dragTarget(p, size, limited: false) {
            grabSamples.append((CACurrentMediaTime(), raw)); if grabSamples.count > 8 { grabSamples.removeFirst() }
        }
    }

    private func cancelGrab() {
        if mode == .grab { sim.endGrab(); mode = .none; dragID = nil; second = nil }
    }

    /// The point on his body under a screen point (the rendered mesh first, then the nearest particle within a fingertip).
    private func pickBody(_ p: CGPoint, _ size: CGSize) -> SIMD3<Float>? {
        guard let renderer else { return nil }
        let ray = unproject(ndc: ndc(p, size), invViewProj: lastCam.invViewProj)
        return pickRay(origin: ray.o, dir: ray.d, dyn: renderer.dynPointer, index: renderMesh.index,
                       bodyIndexCount: renderMesh.body.first + renderMesh.body.count)
            ?? pickNear(screenPoint: SIMD2<Float>(Float(p.x), Float(p.y)), viewProj: lastCam.viewProj,
                        viewSize: SIMD2<Float>(Float(size.width), Float(size.height)), x: sim.x, maxPx: 34)
    }

    // Capture aid (not DEBUG-only so the Release sim build can film it): -TouchDemo pet strokes him on a 14 s loop once he is in focus mode.
    private let touchDemoName = UserDefaults.standard.string(forKey: "TouchDemo")
    private var tdT0: CFTimeInterval = 0
    private var tdDown = false

    private func screenPoint(_ w: SIMD3<Float>, _ size: CGSize) -> CGPoint {
        let c = lastCam.viewProj * SIMD4<Float>(w.x, w.y, w.z, 1)
        return CGPoint(x: CGFloat(c.x / c.w * 0.5 + 0.5) * size.width, y: CGFloat(0.5 - c.y / c.w * 0.5) * size.height)
    }

    private func touchDemo(now: CFTimeInterval) {
        guard game, let name = touchDemoName, haveCam, let stage = stageView else { return }
        let A = ObjectIdentifier(self), B = ObjectIdentifier(stage)
        guard model.care.focus.isFocused else {
            if tdDown { pointerUp(id: A); pointerUp(id: B); tdDown = false }
            return
        }
        if tdT0 == 0 { tdT0 = now }
        guard now - tdT0 > 1.5 else { return }
        let size = stage.bounds.size
        let c = sim.centroid()
        let right = SIMD3<Float>(lastCam.view.columns.0.x, lastCam.view.columns.1.x, lastCam.view.columns.2.x)
        let up = SIMD3<Float>(lastCam.view.columns.0.y, lastCam.view.columns.1.y, lastCam.view.columns.2.y)
        func at(_ x: Float, _ y: Float) -> CGPoint { screenPoint(c + right * x + up * y, size) }
        func sm(_ v: Double) -> Float { let k = Float(min(1, max(0, v))); return k * k * (3 - 2 * k) }
        let el = now - tdT0 - 1.5
        switch name {
        case "pet":
            let t = el.truncatingRemainder(dividingBy: 14)
            if t < 9 {
                let k = Float(min(1, t / 0.6)), ph = Float(t)
                let pt = at(0.4 * sinf(2 * .pi * 0.8 * ph) * k, 0.25 * sinf(2 * .pi * 0.4 * ph) * k)
                if !tdDown { tdDown = true; pointerDown(id: A, point: pt, size: size) } else { pointerMove(id: A, point: pt, size: size) }
            } else if tdDown { pointerUp(id: A); tdDown = false }
        case "pickup":      // press and hold on the crown, drag up, hang there wiggling, let go (14 s loop)
            let t = el.truncatingRemainder(dividingBy: 14)
            if t < 6 {
                let lift = 0.45 * sm((t - 0.5) / 1.2)
                let sway: Float = 0
                if !tdDown { tdDown = true; pointerDown(id: A, point: at(0, 0.62), size: size) }
                else { pointerMove(id: A, point: at(sway, 0.62 + lift), size: size) }
            } else if tdDown { pointerUp(id: A); tdDown = false }
        case "throw":       // lift, then a fast flick up and to the side on release; he gets back up on his own (28 s loop)
            let t = el.truncatingRemainder(dividingBy: 28)
            if t < 2.15 {
                let lift = 0.4 * sm((t - 0.5) / 0.8)
                if !tdDown { tdDown = true; pointerDown(id: A, point: at(0, 0.62), size: size) }
                else if t < 1.9 { pointerMove(id: A, point: at(0, 0.62 + lift), size: size) }
                else { let k = Float(min(1, (t - 1.9) / 0.25)); pointerMove(id: A, point: at(1.1 * k, 0.62 + lift + 1.0 * k), size: size) }   // ~1.5 u in 0.2 s: a flick
            } else if tdDown { pointerUp(id: A); tdDown = false }
        case "cheeks":      // two fingers on the cheeks pinch together, hold, let go (9 s loop)
            let t = el.truncatingRemainder(dividingBy: 9)
            if t < 4 {
                let g = 0.5 - 0.3 * sm((t - 0.5) / 1.0)
                if !tdDown { tdDown = true; pointerDown(id: A, point: at(-0.5, 0.16), size: size); pointerDown(id: B, point: at(0.5, 0.16), size: size) }
                else { pointerMove(id: A, point: at(-g, 0.16), size: size); pointerMove(id: B, point: at(g, 0.16), size: size) }
            } else if tdDown { pointerUp(id: A); pointerUp(id: B); tdDown = false }
        default: break
        }
    }

    /// Once per frame, before the fixed steps: the touch play of focus mode (the pet finger's dent, his reactions, the haptics).
    private func touchTick(dt: Float, now: CFTimeInterval) {
        guard game, let brain, brain.enabled else { return }
        let f = model.care.focus
        let play = model.touch
        play.haptics.setWarm(f.phase == .approaching || f.phase == .focused)
        play.mood = model.care.mood; play.attentionWanted = model.care.wantedNeed == .attention      // a grumpy Blob is touched with an annoyed reaction
        // getting back up: after a throw (or if he is left lying) he rights himself and walks back to the spot
        let held = mode == .grab || sim.grabbing || mode == .pet || mode == .pending || mode == .cheeks
        play.holdsBrain = play.getUpFrame(dt: dt, now: now, held: held, focusSpot: f.isFocused ? GameCamera.callSpot : nil, sim: sim, brain: brain)
        if !f.isFocused || model.paused {
            if mode == .pet || mode == .pending || mode == .cheeks { mode = .none }
            cheekFingers = []; gesture.cancel()
            DeviceMotionFeed.shared.setRunning(false)
            if !play.holdsBrain { play.cancel(sim: sim, brain: brain, skinner: skinner) }
            return
        }
        if restSurface == nil { restSurface = RestSurface(mesh: renderMesh) }
        // phone tilt / shake (the -TouchDemo tilt capture aid feeds a scripted tilt and shakes instead of the sensors)
        var gx: Float, shk: Float
        if touchDemoName == "tilt" {
            if tdT0 == 0 { tdT0 = now }
            let t = Float(now - tdT0)
            gx = max(-1, min(1, 0.9 * sinf(t * 1.3))) * (t > 2 ? 1 : 0)
            shk = (t > 8 && t < 10.5 && Int(t * 4) % 2 == 0) ? 2.6 : 0
        } else {
            let feed = DeviceMotionFeed.shared
            feed.setRunning(true)
            gx = feed.gravityX; shk = feed.shake
        }
        if gx != 0 || shk != 0 || play.isActive {
            play.motionFrame(dt: dt, now: now, gravityX: gx, shake: shk, sim: sim, brain: brain, skinner: skinner)
        }
        gesture.tick(t: now)
        // the fingertip dent: a stroke, a press that has not decided yet, or the last moment of a tap
        var ray: (o: SIMD3<Float>, d: SIMD3<Float>)?
        var scr: SIMD2<Float>?
        if (mode == .pet || mode == .pending || now < tapUntil), touchSize.width > 0 {
            let r = unproject(ndc: ndc(petPoint, touchSize), invViewProj: lastCam.invViewProj)
            ray = (r.o, r.d)
            scr = SIMD2(Float(petPoint.x / touchSize.width), Float(petPoint.y / touchSize.height))
        }
        if mode == .cheeks || play.pinch > 0 || play.visPinch != 0 {
            var rays: [(o: SIMD3<Float>, d: SIMD3<Float>)]?
            var gap: Float = 0
            if mode == .cheeks, cheekFingers.count == 2, touchSize.width > 0 {
                rays = cheekFingers.map { let r = unproject(ndc: ndc($0.p, touchSize), invViewProj: lastCam.invViewProj); return (r.o, r.d) }
                gap = Float(hypot(cheekFingers[0].p.x - cheekFingers[1].p.x, cheekFingers[0].p.y - cheekFingers[1].p.y))
            }
            play.cheeksFrame(dt: dt, now: now, rays: rays, gap: gap, sim: sim, brain: brain, skinner: skinner, surface: restSurface)
        } else if mode != .grab, !sim.grabbing {
            play.petFrame(dt: dt, now: now, ray: ray, screen: scr, sim: sim, brain: brain, skinner: skinner, surface: restSurface)
        }
        // pick up / throw: the stretch he is under, the excitement while he is held up, the landing thump
        play.trackImpacts(now: now, sim: sim)
        if sim.grabbing {
            play.squishDepth = min(0.5, sim.deformation() * TouchPlay.liftDepthGain)
            play.petFrameIdle(dt: dt, now: now)
        } else if play.squishDepth > 0 {
            play.squishDepth = 0; play.petFrameIdle(dt: dt, now: now)
        }
        play.heldFrame(dt: dt, now: now, grabbing: sim.grabbing, liftHeight: liftHeight, sim: sim, brain: brain, skinner: skinner)
    }

    private func beginPickUp(_ p: CGPoint, _ size: CGSize) {
        guard let hit = gestureHit else { return }
        model.touch.releaseContact(sim: sim)
        mode = .grab
        twist = 0
        planeP = hit
        planeN = lastCam.fwd
        liftHeight = 0
        grabSamples = []
        sim.beginGrab(hit: hit, radius: 0.4)
        applyGrab(p, size)
    }

    /// Let go of a held Bob: a fast flick throws him, anything else drops him.
    private func releaseGrab(_ r: TouchGesture.Release) {
        sim.endGrab()
        mode = .none
        if case .throwIt = r, grabSamples.count >= 2, let a = grabSamples.first(where: { grabSamples.last!.t - $0.t < 0.1 }), let b = grabSamples.last, b.t - a.t > 0.01 {
            var v = (b.q - a.q) / Float(b.t - a.t)
            v.x *= 0.35; v.z *= 0.35
            v.y = max(v.y, 2.5)
            let sp = simd_length(v)
            if sp > 6 { v *= 6 / sp }
            sim.launch(velocity: v, spin: SIMD3<Float>(0, 0, v.x > 0 ? -3.5 : 3.5))
            throwHold = 1.0
            model.touch.thrown = true
            model.touch.haptics.transient(now: CACurrentMediaTime(), intensity: 0.5, sharpness: 0.5)       // the release
        }
        grabSamples = []; liftHeight = 0
    }

    func pointerDown(id: ObjectIdentifier, point p: CGPoint, size: CGSize) {
        guard haveCam, size.width > 0, size.height > 0 else { return }
        if game {
            // touch play only acts inside focus mode (Come here): a roaming Bob is not grabbed, and nothing orbits or zooms.
            // The GESTURE decides the action (pet / tap / pick up / throw / cheeks), never switching mid-gesture.
            let f = model.care.focus
            guard f.isFocused, !model.paused else { return }
            let now = CACurrentMediaTime()
            if mode == .none {
                guard model.touch.getUpPhase == .off, let hit = pickBody(p, size) else { return }
                mode = .pending; dragID = id; last = p; petPoint = p; touchSize = size; gestureHit = hit
                gesture.down(t: now, p: p)
            } else if mode == .pending, id != dragID, pickBody(p, size) != nil, gesture.secondDown(t: now) {
                mode = .cheeks; touchSize = size
                model.touch.releaseContact(sim: sim)
                cheekFingers = [(dragID!, petPoint), (id, p)]
            }
            return
        }
        if mode == .grab, id != dragID {
            if second == nil {
                second = (id, p)
                twist0 = twist - Float(atan2(p.y - last.y, p.x - last.x))
            }
            return
        }
        if mode != .none { return }
        let hit: SIMD3<Float>? = model.paused ? nil : pickBody(p, size)
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
        if let k = cheekFingers.firstIndex(where: { $0.id == id }) { cheekFingers[k].p = p; touchSize = size; return }
        if game, id == dragID {
            let now = CACurrentMediaTime()
            touchSize = size; last = p
            switch mode {
            case .pending:
                petPoint = p
                gesture.move(t: now, p: p)
                if gesture.kind == .pet { mode = .pet }
                else if gesture.kind == .pickUp { beginPickUp(p, size) }
            case .pet: petPoint = p; gesture.move(t: now, p: p)
            case .grab: gesture.move(t: now, p: p); applyGrab(p, size)
            default: break
            }
            return
        }
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
        if let k = cheekFingers.firstIndex(where: { $0.id == id }) {
            cheekFingers.remove(at: k)
            if cheekFingers.count < 2, mode == .cheeks { mode = .none; dragID = nil; gesture.cancel() }
            return
        }
        if game, id == dragID {
            let now = CACurrentMediaTime()
            let r = gesture.up(t: now)
            switch mode {
            case .pending:
                if r == .tap { model.touch.tap(now: now); tapUntil = now + 0.22 }
                mode = .none
            case .grab: releaseGrab(r)
            default: mode = .none
            }
            dragID = nil
            return
        }
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
