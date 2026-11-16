//
//  HeadPortraitFrameTests.swift
//  2026-11-15 (the user's Jelly Race lobby picture: "Why is it showing top view weird random bug"): a lobby avatar drawn while the Jelmiko lay, flopped or
//  flew showed its crown. HeadPortraitFrame stands the body up for the picture's camera and light. Held here: which bodies get a frame, where the stood body
//  faces and reaches, that the carried camera and light put a tipped body on the pixels and shadow texels of the same body standing, and that the stage's
//  avatar camera (its lines are repeated in `portraitCamera`: the stage itself needs a renderer) therefore draws a lying or mid-flop body like a standing one.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class HeadPortraitFrameTests: XCTestCase {
    /// A stand-in body about its centre. Up is +y, its front is +z. 0 crown, 1 nose, 2 and 3 arms, 4 and 5 soles, 6 back, then a belly ring.
    private static let rest: [SIMD3<Float>] = {
        var pts: [SIMD3<Float>] = [
            SIMD3<Float>(0, 1.10, 0.05),
            SIMD3<Float>(0, 0.35, 0.90),
            SIMD3<Float>(0.80, 0.10, 0.10),
            SIMD3<Float>(-0.75, 0.05, 0.12),
            SIMD3<Float>(0.30, -0.95, 0.10),
            SIMD3<Float>(-0.30, -0.95, 0.10),
            SIMD3<Float>(0, 0.00, -0.70),
        ]
        for i in 0..<12 {
            let a = Float(i) * (2 * Float.pi / 12)
            pts.append(SIMD3<Float>(0.7 * cosf(a), -0.2, 0.6 * sinf(a)))
        }
        return pts
    }()
    private static let crown = 0, nose = 1, sole = 4, back = 6
    private static let restTop: Float = 1.10
    private static let restLow: Float = -0.95
    private static let centre = SIMD3<Float>(1.2, 0.9, -0.4)
    private static let yaws: [Float] = [0, 0.9, -2.4]
    private static let axisX = SIMD3<Float>(1, 0, 0)
    private static let axisZ = SIMD3<Float>(0, 0, 1)
    /// Ways a body is caught off its feet: the rotation of the rest shape before its heading. (About +x a positive angle tips it onto its face.)
    private static let tips: [(String, simd_quatf)] = [
        ("napping on its back", simd_quatf(angle: -1.05, axis: axisX)),
        ("flat on its back", simd_quatf(angle: -Float.pi / 2, axis: axisX)),
        ("flopped forward", simd_quatf(angle: 1.05, axis: axisX)),
        ("flat on its face", simd_quatf(angle: Float.pi / 2, axis: axisX)),
        ("on one side", simd_quatf(angle: Float.pi / 2, axis: axisZ)),
        ("on the other side", simd_quatf(angle: -Float.pi / 2, axis: axisZ)),
        ("mid-flip", simd_quatf(angle: 2.4, axis: axisX)),
        ("tipped over a corner", simd_quatf(angle: 1.3, axis: simd_normalize(SIMD3<Float>(1, 0, 0.7)))),
    ]

    private func turn(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: SIMD3<Float>(0, 1, 0)) }

    /// The stand-in body's particles (xyz per particle, as SoftBody.x) under the rotation `q` about `c`.
    private func cloud(_ q: simd_quatf, _ c: SIMD3<Float>) -> [Float] {
        var x: [Float] = []
        for o in Self.rest {
            let p = c + q.act(o)
            x.append(p.x); x.append(p.y); x.append(p.z)
        }
        return x
    }

    private func point(_ x: [Float], _ i: Int) -> SIMD4<Float> { SIMD4<Float>(x[3 * i], x[3 * i + 1], x[3 * i + 2], 1) }
    private func point(_ p: SIMD3<Float>) -> SIMD4<Float> { SIMD4<Float>(p.x, p.y, p.z, 1) }

    private func near(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ tol: Float, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(simd_length(a - b), tol, what, file: file, line: line)
    }
    private func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ tol: Float, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(simd_length(a - b), tol, what, file: file, line: line)
    }

    // MARK: Which bodies get a frame

    func testAnUprightBodyKeepsTheCameraItAlwaysHad() {
        let c = Self.centre
        let leans: [Float] = [0, 0.1, -0.1, 0.19, -0.19]
        for yaw in Self.yaws {
            for axis in [Self.axisX, Self.axisZ] {
                for lean in leans {
                    let q = turn(yaw) * simd_quatf(angle: lean, axis: axis)
                    XCTAssertNil(HeadPortraitFrame(rotation: q, centroid: c, particles: cloud(q, c)), "a lean of \(lean) about \(axis), heading \(yaw): no frame")
                }
                for over in [Float(0.21), Float(-0.21)] {
                    let q = turn(yaw) * simd_quatf(angle: over, axis: axis)
                    XCTAssertNotNil(HeadPortraitFrame(rotation: q, centroid: c, particles: cloud(q, c)), "tipped \(over) about \(axis), heading \(yaw): stood up")
                }
            }
        }
        XCTAssertEqual(HeadPortraitFrame.minTilt, 0.2, accuracy: 1e-6)
    }

    func testAPoseThatCannotBeReadHasNoFrame() {
        let c = Self.centre
        let q = simd_quatf(angle: 1.2, axis: Self.axisX)
        let x = cloud(q, c)
        XCTAssertNotNil(HeadPortraitFrame(rotation: q, centroid: c, particles: x))
        XCTAssertNil(HeadPortraitFrame(rotation: q, centroid: c, particles: []), "no particles")
        XCTAssertNil(HeadPortraitFrame(rotation: q, centroid: SIMD3<Float>(Float.nan, 1, 0), particles: x), "a broken centre")
        XCTAssertNil(HeadPortraitFrame(rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 0), centroid: c, particles: x), "an empty rotation")
        XCTAssertNil(HeadPortraitFrame(rotation: simd_quatf(ix: Float.nan, iy: 0, iz: 0, r: 1), centroid: c, particles: x), "a broken rotation")
    }

    /// The same rotation written with the other sign or another length is the same frame.
    func testTheFrameDoesNotDependOnHowTheRotationIsWritten() throws {
        let c = Self.centre
        let q = turn(0.9) * simd_quatf(angle: 1.2, axis: Self.axisX)
        let x = cloud(q, c)
        let a = try XCTUnwrap(HeadPortraitFrame(rotation: q, centroid: c, particles: x))
        let b = try XCTUnwrap(HeadPortraitFrame(rotation: simd_quatf(vector: q.vector * -2), centroid: c, particles: x))
        near(a.forward, b.forward, 1e-5, "facing")
        XCTAssertEqual(a.topY, b.topY, accuracy: 1e-5); XCTAssertEqual(a.floorY, b.floorY, accuracy: 1e-5)
        let ma = a.stand, mb = b.stand
        for i in Self.rest.indices { near(ma * point(x, i), mb * point(x, i), 1e-4, "particle \(i)") }
    }

    // MARK: The stood body

    func testATippedBodyIsStoodUpAboutItsCentreFacingItsOwnHeading() throws {
        let c = Self.centre
        for yaw in Self.yaws {
            for (name, tipQ) in Self.tips {
                let q = turn(yaw) * tipQ
                let x = cloud(q, c)
                let what = "\(name), heading \(yaw)"
                let f = try XCTUnwrap(HeadPortraitFrame(rotation: q, centroid: c, particles: x), what)
                near(f.forward, SIMD3<Float>(sinf(yaw), 0, cosf(yaw)), 1e-4, "\(what): the stood body faces its heading")
                XCTAssertEqual(f.topY, c.y + Self.restTop, accuracy: 1e-4, "\(what): crown height of the stood body")
                XCTAssertEqual(f.floorY, c.y + Self.restLow, accuracy: 1e-4, "\(what): sole height of the stood body")
                near(f.centroid, c, 0, what)
                let m = f.stand
                for (i, o) in Self.rest.enumerated() {
                    near(m * point(x, i), point(c + turn(yaw).act(o)), 2e-4, "\(what): particle \(i) of the stood body")
                }
            }
        }
    }

    /// Turned exactly over, a body has no heading of its own: it still stands up whole, facing some level direction.
    func testAnUpsideDownBodyStillStandsUpWhole() throws {
        let c = Self.centre
        let q = turn(0.9) * simd_quatf(angle: Float.pi, axis: Self.axisX)
        let x = cloud(q, c)
        let f = try XCTUnwrap(HeadPortraitFrame(rotation: q, centroid: c, particles: x))
        XCTAssertEqual(simd_length(f.forward), 1, accuracy: 1e-4)
        XCTAssertEqual(f.forward.y, 0, accuracy: 1e-6)
        XCTAssertEqual(f.topY, c.y + Self.restTop, accuracy: 1e-4); XCTAssertEqual(f.floorY, c.y + Self.restLow, accuracy: 1e-4)
        let heading = atan2f(f.forward.x, f.forward.z)
        let m = f.stand
        for (i, o) in Self.rest.enumerated() {
            near(m * point(x, i), point(c + turn(heading).act(o)), 2e-4, "particle \(i): the rest shape, upright, facing the frame's heading")
        }
    }

    // MARK: Camera and light

    func testTheCarriedCameraAndLightShowTheTippedBodyAsTheStoodOne() throws {
        let c = Self.centre
        for yaw in Self.yaws {
            let xs = cloud(turn(yaw), c)          // the same body standing
            for (name, tipQ) in Self.tips {
                let q = turn(yaw) * tipQ
                let x = cloud(q, c)
                let what = "\(name), heading \(yaw)"
                let f = try XCTUnwrap(HeadPortraitFrame(rotation: q, centroid: c, particles: x), what)
                // any camera and the room's light, set up for the stood body
                let target = c + SIMD3<Float>(0.1, 0.4, -0.05)
                let eye = target + (f.forward * cosf(0.47) + SIMD3<Float>(0.2, sinf(0.47), 0)) * 5
                var ref = CameraState()
                ref.view = M4.lookAt(eye: eye, at: target, up: SIMD3<Float>(0, 1, 0))
                ref.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: 0.8, near: 0.2, far: 60), ref.view)
                ref.invViewProj = M4.invert(ref.viewProj)
                ref.pos = eye; ref.fwd = simd_normalize(target - eye)
                let refLight = GameCamera.light(centroid: c)
                var cam = ref
                var light = refLight
                f.carry(camera: &cam, light: &light)
                for i in Self.rest.indices {
                    let p = point(x, i), s = point(xs, i)
                    near(cam.view * p, ref.view * s, 1e-3, "\(what): particle \(i) in view space")
                    near(cam.viewProj * p, ref.viewProj * s, 2e-3, "\(what): particle \(i) on the stood body's pixel")
                    near(light.lightVP * p, refLight.lightVP * s, 1e-3, "\(what): particle \(i) on the stood body's shadow-map texel")
                    near(light.topVP * p, refLight.topVP * s, 1e-3, "\(what): particle \(i) on the stood body's height-map texel")
                    near(cam.invViewProj * (cam.viewProj * p), p, 2e-3, "\(what): particle \(i) unprojects to itself")
                }
                near(f.stand * point(cam.pos), point(ref.pos), 1e-3, "\(what): the eye is carried round with the body")
                near(f.tip.inverse.act(cam.fwd), ref.fwd, 1e-4, "\(what): the camera's forward")
                near(f.tip.inverse.act(light.dir), refLight.dir, 1e-4, "\(what): the key light falls on the body as on the stood one")
                XCTAssertEqual(light.intensity, refLight.intensity, "\(what): the light's strength is untouched")
            }
        }
    }

    /// The stage's avatar camera and light (MelonStage.renderSnapshot with a head-portrait key), its lines repeated: the stage needs a renderer, this does
    /// not. `floor`: the floor under the body (SoftBody.floorY). `action`: the Studio's action shot (the whole body; `quarter` = the pose's turn).
    private func portraitCamera(rotation: simd_quatf, centre c: SIMD3<Float>, particles x: [Float], aspect: Float, floor: Float,
                                action: Bool, quarter: Float) -> (cam: CameraState, light: LightState) {
        let stood = HeadPortraitFrame(rotation: rotation, centroid: c, particles: x)
        var fwd = rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
        fwd = simd_length(fwd) > 1e-3 ? simd_normalize(fwd) : SIMD3<Float>(0, 0, 1)
        if let stood { fwd = stood.forward }
        let dir = SIMD3<Float>(fwd.x * cosf(quarter) + fwd.z * sinf(quarter), 0, -fwd.x * sinf(quarter) + fwd.z * cosf(quarter))
        var topY = -Float.infinity
        var k = 1
        while k < x.count { topY = max(topY, x[k]); k += 3 }
        if let stood { topY = stood.topY }
        var span = HeadPortraitKey.span
        var focusY = topY - span * HeadPortraitKey.topFraction
        let down = GameCamera.baseEye - GameCamera.baseTarget
        var pitch = asinf(min(max(down.y / max(simd_length(down), 1e-3), 0), 0.9))
        if action {
            let floorY = stood?.floorY ?? floor
            span = max((topY - floorY) * 1.42, 1.3)
            let thA = tanf(GameCamera.fovY / 2), m = min(thA, thA * aspect), pt = HeadPortraitKey.actionPitch
            let kf = Float(2 * HeadPortraitKey.actionFloorFraction - 1)
            focusY = floorY + (kf * span / 2) / (cosf(pt) - kf * sinf(pt) * m)
            pitch = HeadPortraitKey.actionPitch
        }
        let th = tanf(GameCamera.fovY / 2)
        let dist = (span / 2) / min(th, th * aspect)
        let target = SIMD3<Float>(c.x, focusY, c.z)
        let eye = target + (dir * cosf(pitch) + SIMD3<Float>(0, sinf(pitch), 0)) * dist
        var camUp = SIMD3<Float>(0, 1, 0)
        let u = rotation.act(SIMD3<Float>(0, 1, 0))
        if simd_length(u) > 1e-3, u.y > 0.5 { camUp = simd_normalize(u) }
        if stood != nil { camUp = SIMD3<Float>(0, 1, 0) }
        var cam = CameraState()
        cam.view = M4.lookAt(eye: eye, at: target, up: camUp)
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.2, far: 60), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye; cam.fwd = simd_normalize(target - eye)
        var light = GameCamera.light(centroid: c)
        if let stood { stood.carry(camera: &cam, light: &light) }
        return (cam, light)
    }

    /// The bug: a Jelmiko lying, flopped or mid-flip when its avatar is drawn. It must come out as the same Jelmiko standing: every point on the same pixel
    /// and the same shadow texel, crown up, seen from the front.
    func testALyingOrMidFlopBodyIsPicturedLikeTheSameBodyStanding() {
        let c = Self.centre
        let floor = c.y + Self.restLow          // the standing body's soles are on it
        let aspects: [Float] = [1, 0.75]
        for yaw in Self.yaws {
            let standing = turn(yaw)
            let xs = cloud(standing, c)
            XCTAssertNil(HeadPortraitFrame(rotation: standing, centroid: c, particles: xs), "a standing body keeps the camera it always had")
            for aspect in aspects {
                for action in [false, true] {
                    let quarter: Float = action ? 0.35 : 0
                    let ref = portraitCamera(rotation: standing, centre: c, particles: xs, aspect: aspect, floor: floor, action: action, quarter: quarter)
                    // the standing picture itself: the right way up, seen from the front
                    let crown = ref.cam.viewProj * point(xs, Self.crown), sole = ref.cam.viewProj * point(xs, Self.sole)
                    let nose = ref.cam.viewProj * point(xs, Self.nose), back = ref.cam.viewProj * point(xs, Self.back)
                    XCTAssertGreaterThan(crown.y / crown.w, sole.y / sole.w, "standing: the crown is above the soles")
                    XCTAssertLessThan(nose.w, back.w, "standing: the nose is nearer the camera than the back")
                    for (name, tipQ) in Self.tips {
                        let q = standing * tipQ
                        let x = cloud(q, c)
                        let what = "\(name), heading \(yaw), aspect \(aspect), action shot \(action)"
                        // (the floor a lying body rests on is not under the stood body: a wrong floor here must not move the picture)
                        let got = portraitCamera(rotation: q, centre: c, particles: x, aspect: aspect, floor: -5, action: action, quarter: quarter)
                        for i in Self.rest.indices {
                            let p = point(x, i), s = point(xs, i)
                            near(got.cam.viewProj * p, ref.cam.viewProj * s, 2e-3, "\(what): particle \(i) on the standing body's pixel")
                            near(got.light.lightVP * p, ref.light.lightVP * s, 1e-3, "\(what): particle \(i) on the standing body's shadow-map texel")
                            near(got.light.topVP * p, ref.light.topVP * s, 1e-3, "\(what): particle \(i) on the standing body's height-map texel")
                        }
                        let tc = got.cam.viewProj * point(x, Self.crown), ts = got.cam.viewProj * point(x, Self.sole)
                        let tn = got.cam.viewProj * point(x, Self.nose), tb = got.cam.viewProj * point(x, Self.back)
                        XCTAssertGreaterThan(tc.y / tc.w, ts.y / ts.w, "\(what): the crown is above the soles (not a top view)")
                        XCTAssertLessThan(tn.w, tb.w, "\(what): seen from the front")
                    }
                }
            }
        }
    }
}
