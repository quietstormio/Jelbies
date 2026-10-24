//
//  GameCamera.swift
//  Fixed Nintendogs-style camera for the game screen: low (~18 deg), looking straight at the back wall.
//  Also the visible-floor bounds Bob (and the brain) must stay within.
//

import simd
import QuartzCore
import Foundation

enum GameCamera {
    /// The roaming camera. One Jelly keeps `baseEye` / `baseTarget` exactly; 2-3 Jellies get a wider pose (`configureRoom`), set once when the stage starts.
    nonisolated(unsafe) static var eye = baseEye                 // the pose in use: `roomEye` pulled back by the portrait-wide factor (see `camera(aspect:)`)
    nonisolated(unsafe) static var target = baseTarget
    nonisolated(unsafe) static var roomEye = baseEye             // the pose chosen by `configureRoom`, before the portrait widening
    /// Portrait widening for 2-3 Jellies (`-RoomWide 0|1|2`, default 2): horizontal coverage x1.35 (W1) or x1.6 (W2) over the room pose (A), by distance only
    /// (same angle, same fov, so the look and every close-up stay put). 0 = off. Landscape (aspect >= 1) is untouched.
    static var wideLaunch: Int { UserDefaults.standard.object(forKey: "RoomWide") == nil ? 2 : min(max(UserDefaults.standard.integer(forKey: "RoomWide"), 0), 2) }
    static func wideScale(_ w: Int) -> Float { w == 1 ? 1.35 : (w == 2 ? 1.6 : 1) }
    nonisolated(unsafe) static var roomWideScale: Float = 1
    nonisolated(unsafe) static var roomTarget = baseTarget
    /// W2 only: the camera rises this much (same angle) in portrait, so the room sits lower on screen and the empty foreground floor shrinks.
    static func wideLift(_ w: Int) -> Float { w == 2 ? 1.5 : 0 }
    nonisolated(unsafe) static var roomWideLift: Float = 0
    /// 1 in a portrait phone (aspect <= 0.8), 0 from square up, eased between so a rotation does not jump.
    static func portraitAmount(_ aspect: Float) -> Float { let t = min(max((1.0 - aspect) / 0.2, 0), 1); return t * t * (3 - 2 * t) }
    static let baseEye = SIMD3<Float>(0, 7.2, 14)
    static let baseTarget = SIMD3<Float>(0, 0.0, -0.3)

    /// Roaming camera choices for 2-3 Jellies (`-RoomCam A|B`, default A). `current` is the one-Jelly pose.
    enum RoomCam: String { case current, A, B
        static var launch: RoomCam { RoomCam(rawValue: (UserDefaults.standard.string(forKey: "RoomCam") ?? "A").uppercased().replacingOccurrences(of: "CURRENT", with: "current")) ?? .A }
    }
    /// A: about 20% further out, same angle. B: about 15% further out and 9 degrees higher (more top-down). Both look at a point nearer the camera,
    /// so the rug and the play area sit nearer the screen centre.
    static let roomLookZ: Float = -1.0
    static func roomPose(_ o: RoomCam) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let v = baseEye - baseTarget, L = simd_length(v), e0 = atan2f(v.y, v.z)
        switch o {
        case .current: return (baseEye, baseTarget)
        case .A:
            let t = SIMD3<Float>(0, 0, roomLookZ)
            return (t + v * 1.2, t)
        case .B:
            let t = SIMD3<Float>(0, 0, roomLookZ), e = e0 + 9 * .pi / 180
            return (t + SIMD3(0, sinf(e), cosf(e)) * (L * 1.15), t)
        }
    }
    /// Sets the roaming camera and the floor the Jellies use for `count` Jellies. Call before the brains are made (`forGame` reads `roamRect`).
    static func configureRoom(count: Int, option: RoomCam = RoomCam.launch, wide: Int = wideLaunch) {
        roamFloor = nil; RoomLayout.setFront(z: RoomLayout.maxZ)          // (a new set-up: the old fixed floor until `refreshRoam`)
        if count <= 1 || option == .current {
            eye = baseEye; target = baseTarget; roomEye = baseEye; roomTarget = baseTarget; roomWideScale = 1; roomWideLift = 0
            walkMaxZ = 3.0; arenaCenter = SIMD2(0, 0.5); arenaRadius = 3.3; roamRect = (SIMD2(-2.2, -2.3), SIMD2(2.2, 3.1)); roamRectWide = (SIMD2(-3.2, -2.6), SIMD2(3.2, 3.1))
            return
        }
        let p = roomPose(option)
        eye = p.eye; target = p.target; roomEye = p.eye; roomTarget = p.target; roomWideScale = wideScale(wide); roomWideLift = wideLift(wide)
        walkMaxZ = 3.6; arenaCenter = SIMD2(0, 0.8); arenaRadius = 3.9      // the foreground floor is used too
        roamRect = (SIMD2(-2.2, -2.3), SIMD2(2.2, 3.5)); roamRectWide = (SIMD2(-3.2, -2.6), SIMD2(3.2, 3.5))
    }
    nonisolated(unsafe) static var roamRect: (min: SIMD2<Float>, max: SIMD2<Float>) = (SIMD2(-2.2, -2.3), SIMD2(2.2, 3.1))
    /// The wander pick's box (2026-10-18): wider than the frame; goals the frame clamp would drag in are rejected, so the whole visible floor is used.
    nonisolated(unsafe) static var roamRectWide: (min: SIMD2<Float>, max: SIMD2<Float>) = (SIMD2(-3.2, -2.6), SIMD2(3.2, 3.1))

    static let fovY: Float = 34 * .pi / 180
    /// The aspect the close-up poses (focus, bath, race) are SIZED for. A phone on its side (aspect >= 1.2) keeps the portrait framing's height, so the Jelly / track is
    /// the same size on the screen's short side and the extra width shows more room, not a face-filling zoom. Below that nothing changes (portrait, the widget's square).
    static let landscapeFramingAspect: Float = 0.56
    static func framingAspect(_ a: Float) -> Float { a >= 1.2 ? landscapeFramingAspect : a }
    // MARK: Bath close-up

    /// Close-up of Bob in the washtub: one source of truth, `BathSet.closeUpPose`.
    static func bathPose(aspect: Float) -> (eye: SIMD3<Float>, target: SIMD3<Float>) { BathSet.closeUpPose(aspect: aspect) }

    /// Key light for the room (toward the light): front, upper left. Fixed, since the camera is.
    static let keyDir = simd_normalize(SIMD3<Float>(-0.5, 0.8, 0.55))
    /// Default portrait aspect (iPhone 17 Pro Max); the stage updates this from its real size.
    nonisolated(unsafe) static var aspect: Float = 440.0 / 956.0

    /// `focus` 0 = the normal low room camera; 1 = the focus-mode close-up on the front spot (see `focusPose`); in between the two poses are blended.
    static func camera(aspect: Float, focus: Float = 0, bath: Float = 0, race: Float = 0, drillAt: SIMD3<Float>? = nil, raceFollow: RaceFollowPose? = nil,
                       show: Float = 0, showFrame: ShowFrame? = nil) -> CameraState {
        self.aspect = aspect
        if roomWideScale != 1 {
            let pa = portraitAmount(aspect), lift = SIMD3<Float>(0, roomWideLift * pa, 0)
            target = roomTarget + lift
            eye = roomTarget + (roomEye - roomTarget) * (1 + (roomWideScale - 1) * pa) + lift
        }
        var e = eye, t = target, up = SIMD3<Float>(0, 1, 0)
        if focus != 0 {
            var p = focusSpots.count > 1 ? focusPose(aspect: aspect, spots: focusSpots) : focusPose(aspect: aspect)
            if let f = trainFrame, focusSpots.count <= 1 {          // the Train card is up: frame the whole Jelbie in the free area beside / above it
                let k = trainBlend(), tp = focusTrainPose(aspect: aspect, frame: f)
                p = (p.eye + (tp.eye - p.eye) * k, p.target + (tp.target - p.target) * k)
            }
            e += (p.eye - e) * focus
            t += (p.target - t) * focus
        }
        if bath != 0 {                                      // the clean-up close-up: snapped under the white fade (0 or 1), never blended on screen
            let p = bathPose(aspect: aspect)
            e += (p.eye - e) * bath
            t += (p.target - t) * bath
        }
        if race != 0 {                                      // the Waddle Sprint track: a fixed wide frame, snapped under the white fade (0 or 1)
            if let f = raceFollow, drillAt == nil {          // a curved course: the follow camera (Race/RaceCamera.swift), banking into the bends
                let p = f.camera(aspect: aspect)
                e += (p.eye - e) * race; t += (p.target - t) * race; up = p.up
            } else {
                let p = drillAt.map { drillPose(aspect: aspect, at: $0) } ?? racePose(aspect: aspect)      // the practice drill follows its Jelly closer
                e += (p.eye - e) * race
                t += (p.target - t) * race
            }
        }
        if show != 0 {                                      // the Jelly Show's stage: the focus close-up's maths on the stage spots, snapped under the white fade
            let p = showPose(aspect: aspect, frame: showFrame ?? .look)
            e += (p.eye - e) * show
            t += (p.target - t) * show
        }
        var c = CameraState()
        c.view = M4.lookAt(eye: e, at: t, up: up)
        c.viewProj = M4.mul(M4.perspective(fovy: fovY, aspect: aspect, near: 0.3, far: race != 0 ? 260 : 60), c.view)      // the track's far hills and sky wall are ~100 u away
        c.invViewProj = M4.invert(c.viewProj)
        c.pos = e
        c.fwd = simd_normalize(t - e)
        return c
    }

    // MARK: Screen <-> floor (arrange mode, tests)

    /// The floor point (x, z) under a screen point of a view of `size` (the room camera), or nil when the ray misses the floor. The inverse of `screenPoint`.
    static func floorPoint(screen: CGPoint, size: CGSize) -> SIMD2<Float>? {
        guard size.width > 1, size.height > 1 else { return nil }
        let cam = camera(aspect: Float(size.width / size.height))
        let ndc = SIMD2<Float>(Float(screen.x / size.width) * 2 - 1, 1 - Float(screen.y / size.height) * 2)
        let ray = unproject(ndc: ndc, invViewProj: cam.invViewProj)
        guard abs(ray.d.y) > 1e-4 else { return nil }
        let t = -ray.o.y / ray.d.y
        guard t > 0 else { return nil }
        let p = ray.o + ray.d * t
        return SIMD2(p.x, p.z)
    }

    /// Where a floor point (x, z; at height `y`) lands on the screen of a view of `size`; nil when it is behind the camera.
    static func screenPoint(floor: SIMD2<Float>, y: Float = 0, size: CGSize) -> CGPoint? {
        guard size.width > 1, size.height > 1 else { return nil }
        let cam = camera(aspect: Float(size.width / size.height))
        let c = cam.viewProj * SIMD4<Float>(floor.x, y, floor.y, 1)
        guard c.w > 1e-4 else { return nil }
        return CGPoint(x: CGFloat((c.x / c.w * 0.5 + 0.5)) * size.width, y: CGFloat((1 - (c.y / c.w * 0.5 + 0.5))) * size.height)
    }

    // MARK: Race track (Jelly Circuit)

    /// Camera elevation over the track (rad) and the z the view is centred on (a third of the way up the track).
    static let raceElevation: Float = 19 * .pi / 180
    static let raceTargetZ: Float = RaceTuning.startZ + RaceTuning.length * 0.40
    /// Half the width (world units) the frame must hold at the finish line, which is the nearest thing: three lanes, a body either side and the gantry;
    /// it fills `raceFill` of the screen's half width there.
    static let raceHalfWidth: Float = 3.5, raceFill: Float = 0.94
    /// One static frame for the whole sprint: behind the finish line, looking back down the track (the Jellies run toward the camera, faces to the viewer).
    /// Portrait phones are tall and narrow, so the track runs along the screen's height; the distance is set by the width it must hold at the finish line.
    static func racePose(aspect: Float) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let th = tanf(fovY / 2)
        let toFinish = raceHalfWidth / (raceFill * th * max(framingAspect(aspect), 0.2))                    // depth of the finish line along the view axis
        let dist = toFinish + (RaceTuning.finishZ - raceTargetZ) * cosf(raceElevation)
        let t = SIMD3<Float>(0, 0.4, raceTargetZ)
        return (t + SIMD3(0, sinf(raceElevation), cosf(raceElevation)) * dist, t)
    }

    // MARK: Drill follow camera (Rhythm Steps)

    /// Distance from the followed Jelly to the eye. The race frame is ~33 u from the middle of the track; this is ~2.1x closer (2.5x at the start line), so the Jelly is that much bigger.
    static let drillDistance: Float = 16
    /// Where the Jelly sits on screen, measured from the top (0...1): above the prompt strip and the foot buttons, below the stat card.
    static let drillScreenY: Float = 0.40
    /// The race's elevation, the Jelly framed at `drillScreenY`. `at` is the Jelly's centroid on the track. The race camera is untouched.
    static func drillPose(aspect: Float, at: SIMD3<Float>) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let th = tanf(fovY / 2)
        let drop = (0.5 - drillScreenY) * 2 * th * drillDistance             // the target sits below the Jelly by this much, so he rides high
        let dir = SIMD3<Float>(0, sinf(raceElevation), cosf(raceElevation))
        let up = SIMD3<Float>(0, cosf(raceElevation), -sinf(raceElevation))
        let t = SIMD3<Float>(at.x, 0.45, at.z) - up * drop
        return (t + dir * drillDistance + up * drop, t)
    }

    // MARK: Focus close-up

    /// Share of the screen width Bob's body (2R wide) fills in the close-up. A portrait phone is about as tall as Bob is wide, so the
    /// width, not the height, limits the zoom: ~36% of the screen height at 0.86 of the width.
    static let focusWidthFill: Float = 0.86
    /// Where Bob's middle sits on screen (0 top ... 1 bottom): a little above centre, the actions dock takes the bottom.
    static let focusBodyScreenY: Float = 0.44
    /// Camera elevation in the close-up (rad): low, like the room camera, so the room stays softly visible behind him.
    static let focusElevation: Float = 0.17

    /// Eye / target of the close-up: centred on the front spot, facing him.
    static func focusPose(aspect: Float, spot: SIMD2<Float> = callSpot) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let visW = 2 * BobShape.R / focusWidthFill
        let visH = visW / max(framingAspect(aspect), 0.2)
        let dist = visH / (2 * tanf(fovY / 2))
        let mid = 0.5 * BobShape.H
        let ty = mid - (0.5 - focusBodyScreenY) * visH           // below his middle -> he sits above the screen centre
        let t = SIMD3<Float>(spot.x, ty, spot.y)
        let e = t + SIMD3<Float>(0, sinf(focusElevation), cosf(focusElevation)) * dist
        return (e, t)
    }

    // MARK: Focus close-up while the Train card is up (r1023-polish)

    /// The free area (fractions of the whole screen, 0...1) the trained Jelbie must sit inside, face and feet: set by GameScreen from the card's frame, nil = the normal close-up.
    struct TrainFrame: Equatable { var minX: Float, maxX: Float, minY: Float, maxY: Float }
    nonisolated(unsafe) static var trainFrame: TrainFrame? = nil { didSet { if (oldValue == nil) != (trainFrame == nil) { trainSince = CACurrentMediaTime() } } }
    nonisolated(unsafe) static var trainSince: Double = 0
    /// Reduce Motion: the camera does not glide (GameScreen sets it with the frame).
    nonisolated(unsafe) static var trainInstant = false
    /// 0 -> 1 over 0.45 s after the card appears (instant with Reduce Motion), 1 -> 0 is instant (the close-up is ending anyway).
    static func trainBlend(now: Double = CACurrentMediaTime()) -> Float {
        guard trainFrame != nil else { return 0 }
        if trainInstant { return 1 }
        let t = min(max(Float((now - trainSince) / 0.45), 0), 1)
        return t * t * (3 - 2 * t)
    }
    /// Never bigger than the normal close-up; the whole body (H) must fit the frame's height with a margin for a head ornament, and 2R its width.
    static func focusTrainPose(aspect: Float, frame f: TrainFrame, spot: SIMD2<Float> = callSpot) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let normal = focusPose(aspect: aspect, spot: spot)
        let normalVisH = 2 * simd_length(normal.eye - normal.target) * tanf(fovY / 2)
        let margin: Float = 1.12
        let freeH = max(f.maxY - f.minY, 0.12), freeW = max(f.maxX - f.minX, 0.2)
        let visH = max(normalVisH, BobShape.H * margin / freeH, 2 * BobShape.R * 1.08 / (freeW * aspect))
        let dist = visH / (2 * tanf(fovY / 2))
        let cx = (f.minX + f.maxX) / 2, cy = (f.minY + f.maxY) / 2
        let ty = 0.5 * BobShape.H - (0.5 - cy) * visH
        let t = SIMD3<Float>(spot.x + (0.5 - cx) * visH * aspect, ty, spot.y)
        let e = t + SIMD3<Float>(0, sinf(focusElevation), cosf(focusElevation)) * dist
        return (e, t)
    }

    // MARK: Focus close-up of several Jellies ("Everyone, come here")

    /// The spots (x, z) of every focused Jelly while the close-up frames more than one; empty = the one-Jelly close-up on `callSpot`.
    /// Set by GameCare when the focus begins and cleared when the camera is home (the hearts / bubbles project through `camera`, so it is global like `aspect`).
    nonisolated(unsafe) static var focusSpots: [SIMD2<Float>] = []
    /// Share of the screen width the row of Jellies fills in the wide close-up (a little looser than the single one).
    static let focusRowFill: Float = 0.90
    /// Where the row's middle sits on screen (0 top ... 1 bottom): lower than the single close-up so the pulled-back camera does not see past the room's near edge.
    static let focusRowScreenY: Float = 0.46
    /// Distance between neighbouring Jellies' centres in the "everyone" row (body width 2R plus a gap).
    static let focusRowSpacing: Float = 1.15
    /// How far behind the front Jelly the two side ones stand (a shallow group-photo arc), and the hard gap between Jellies while the group is on.
    static let focusRowBack: Float = 0.35, focusRowGap: Float = 1.0

    /// Where each of `ids` stands in the "everyone" row: abreast on the front line, in id order, centred on the call spot.
    /// Index 0 is the front Jelly (centre, on the call spot); the rest alternate left, right, a little behind.
    static func focusRowSpots(count n: Int) -> [SIMD2<Float>] {
        (0..<max(n, 0)).map { k in
            if k == 0 { return callSpot }
            let side: Float = k % 2 == 1 ? -1 : 1, rank = Float((k + 1) / 2)
            return SIMD2(callSpot.x + side * rank * focusRowSpacing, callSpot.y - focusRowBack)
        }
    }

    /// Eye / target framing every spot: the row's width (plus a body) fills the screen; a single spot is exactly `focusPose(spot:)`.
    static func focusPose(aspect: Float, spots: [SIMD2<Float>]) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        guard spots.count > 1 else { return focusPose(aspect: aspect, spot: spots.first ?? callSpot) }
        var lo = spots[0], hi = spots[0]
        for s in spots { lo = simd_min(lo, s); hi = simd_max(hi, s) }
        let mid = (lo + hi) * 0.5
        let visW = (hi.x - lo.x + 2 * BobShape.R) / focusRowFill
        let visH = visW / max(framingAspect(aspect), 0.2)
        let dist = visH / (2 * tanf(fovY / 2))
        let ty = 0.5 * BobShape.H - (0.5 - focusRowScreenY) * visH
        let t = SIMD3<Float>(mid.x, ty, callSpot.y)
        let e = t + SIMD3<Float>(0, sinf(focusElevation), cosf(focusElevation)) * dist
        return (e, t)
    }

    // MARK: The Jelly Show's stage

    /// Eye / target framing the show's spots: the row's width (plus a body) fills `frame.fill` of the screen width, the bodies' middle sits at
    /// `frame.screenY`; the camera stays as low as the close-up so the backdrop fills the picture. A phone on its side keeps the portrait height.
    static func showPose(aspect: Float, frame: ShowFrame) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let spots = frame.spots.isEmpty ? [ShowStage.playerSpot] : frame.spots
        var lo = spots[0], hi = spots[0]
        for s in spots { lo = simd_min(lo, s); hi = simd_max(hi, s) }
        let mid = (lo + hi) * 0.5
        // a phone on its side: the bodies are drawn bigger (the screen is short), the solo rounds put him on the left third so the cards have the right
        let land = aspect >= 1.2
        let fill = land ? frame.landFill : frame.fill
        let screenY = land ? frame.landScreenY : frame.screenY
        let visW = (hi.x - lo.x + 2 * BobShape.R) / max(fill, 0.2)
        let visH = visW / max(framingAspect(aspect), 0.2)
        let dist = visH / (2 * tanf(fovY / 2))
        let ty = 0.5 * BobShape.H - (0.5 - screenY) * visH
        let tx = mid.x + (land && frame.landLeft ? 0.22 * visH * aspect : 0)
        let t = SIMD3<Float>(tx, ty, hi.y)
        let e = t + SIMD3<Float>(0, sinf(focusElevation), cosf(focusElevation)) * dist
        return (e, t)
    }

    /// Key light + shadow / height maps centred on Bob (same extents the studio uses).
    /// Direction used only to build the shadow map: steeper than the shading key, so the cast shadow stays short.
    static let shadowDir = simd_normalize(SIMD3<Float>(-0.18, 1.0, 0.22))

    static func light(centroid c: SIMD3<Float>) -> LightState { light(centre: c, half: 2.2, topHalf: 2.4) }

    /// Several Jellies: the shadow / height boxes are centred on the middle of their bounding box and grown to cover all of them (at least the
    /// single-body size, so one Jelly is exactly `light(centroid:)`).
    static func light(centroids cs: [SIMD3<Float>]) -> LightState {
        guard cs.count > 1 else { return light(centroid: cs.first ?? SIMD3(0, 0, 0)) }
        var lo = cs[0], hi = cs[0]
        for c in cs { lo = simd_min(lo, c); hi = simd_max(hi, c) }
        let mid = (lo + hi) * 0.5
        let half = max(2.2, 0.5 * max(hi.x - lo.x, hi.z - lo.z) + shadowReach)
        return light(centre: mid, half: half, topHalf: half + 0.2)
    }
    /// How far past a Jelly's centre the shadow box must reach (body half width + the cast shadow's offset + the soft edge).
    static let shadowReach: Float = 1.8

    static func light(centre c: SIMD3<Float>, half: Float, topHalf: Float) -> LightState {
        let k = keyDir
        let at = SIMD3<Float>(c.x, 0.4 * BobShape.H, c.z)
        var l = LightState()
        l.dir = k
        l.intensity = 2.3
        l.lightVP = M4.mul(M4.ortho(l: -half, r: half, b: -half, t: half, n: 0.1, f: 14),
                           M4.lookAt(eye: at + shadowDir * 7, at: at, up: SIMD3<Float>(0, 0, 1)))
        l.topVP = M4.mul(M4.ortho(l: -topHalf, r: topHalf, b: -topHalf, t: topHalf, n: 0, f: 5),
                         M4.lookAt(eye: SIMD3<Float>(at.x, -1, at.z), at: SIMD3<Float>(at.x, 1, at.z), up: SIMD3<Float>(0, 0, -1)))
        return l
    }

    // MARK: Visible floor

    /// Walkable depth range (z) and the circular safety arena used by the sim.
    static let walkMinZ: Float = -2.6
    nonisolated(unsafe) static var walkMaxZ: Float = 3.0
    nonisolated(unsafe) static var arenaCenter = SIMD2<Float>(0, 0.5), arenaRadius: Float = 3.3
    /// Bob's half width (rest) ~0.8.
    static let bobRadius: Float = 0.8

    /// Half width of the visible floor strip at depth z (world units, camera looks down -z).
    static func visibleHalfWidth(z: Float, aspect: Float = GameCamera.aspect) -> Float {
        let v = M4.lookAt(eye: eye, at: target, up: SIMD3(0, 1, 0))
        let p = v * SIMD4<Float>(0, 0, z, 1)
        return -p.z * tanf(fovY / 2) * aspect
    }

    /// Half width of the screen at the height of Bob's widest part (y 0.65), a little nearer than his centre.
    static func visibleHalfWidthAtBody(z: Float, aspect: Float = GameCamera.aspect) -> Float {
        let v = M4.lookAt(eye: eye, at: target, up: SIMD3(0, 1, 0))
        let p = v * SIMD4<Float>(0, 0.65, z + 0.3, 1)
        return -p.z * tanf(fovY / 2) * aspect
    }
    /// Projected half extent Bob needs sideways (body + sway + jiggle) and the fraction of the screen half width he may use.
    static let bodyHalfExtent: Float = 0.8, screenFill: Float = 0.9

    /// Clamps a floor position (centroid) so a body of `radius` stays on the visible floor, off the sofa and props.
    static func constrain(_ p: SIMD3<Float>, radius: Float = GameCamera.bobRadius, lowPropScale: Float = 1, openSides: Bool = false, ignoreDecor: Int? = nil) -> SIMD3<Float> {
        var q = RoomLayout.resolve(position: p, radius: radius, lowPropScale: lowPropScale, ignoreDecor: ignoreDecor)
        q.z = min(max(q.z, roamMinZ), roamMaxZ)          // (the roaming polygon's back and front when the room camera set one: RoamFloor.swift)
        if openSides { return q }                    // the wide close-up row: the camera is pulled back, the sides are on screen there
        // the roaming polygon's width when the room camera built one (RoamFloor.swift; it already holds the body extent), else the one-Jelly rule
        let hw = roamFloor.map { max($0.halfWidth(at: q.z) + bodyHalfExtent - max(bodyHalfExtent, radius * 0.9), 0) }
            ?? max(visibleHalfWidthAtBody(z: q.z) * screenFill - max(bodyHalfExtent, radius * 0.9), 0)
        q.x = min(max(q.x, -hw), hw)
        return q
    }

    /// Good spots (x, z) on the visible floor, in room coordinates.
    static let centre = SIMD2<Float>(0, 0)
    /// Front-centre "come here" spot, close to the camera.
    static let callSpot = SIMD2<Float>(0, 2.4)
    /// Bowl spots (the bowls sit beside the call spot, near the front; just inside the screen).
    static let foodBowlSpot = SIMD2<Float>(-0.9, 1.9)
    static let waterBowlSpot = SIMD2<Float>(0.9, 1.9)
}
