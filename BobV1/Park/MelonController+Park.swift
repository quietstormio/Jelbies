//
//  MelonController+Park.swift
//  The stage's side of the park: the visitors' bodies (JellyActors whose ids continue after the roster's, held in `parkActors`), the peers the steering sees, who is
//  social with whom, and a tap on a visitor. The Jelbies' own bodies are untouched; everything the stage does for them it also does for `parkActors` (MelonStage.swift).
//

import Foundation
import simd

extension MelonController {
    /// Every brain a Jelbie may be social with: the room's (less the ones who stayed home while the park is on) and the park's visitors.
    func socialBrains() -> [BlobBrain] {
        guard !parkActors.isEmpty else { return actors.compactMap(\.brain) }
        return (actors.filter { !model.care.parkHides($0.id) } + parkActors).compactMap(\.brain)
    }

    /// Positions of everybody at the start of the step, the visitors after the roster by body id; a Jelbie at home is far away so nobody steers around him.
    func publishParkPeers() {
        let n = actors.count + parkActors.count
        if peerSnapshot.count != n { peerSnapshot = [(pos: SIMD2<Float>, walking: Bool)](repeating: (pos: .zero, walking: false), count: n) }
        let away = SIMD2<Float>(900, 900)
        for (i, a) in actors.enumerated() { peerSnapshot[i] = model.care.parkHides(a.id) ? (pos: away, walking: false) : (pos: a.floor, walking: a.isWalking) }
        for (k, a) in parkActors.enumerated() { peerSnapshot[actors.count + k] = (pos: a.floor, walking: a.isWalking) }
    }

    /// Makes the visitors' bodies (colour, signature, brain) and wires them in with the Jelbies. Returns them in order.
    func parkSpawn(_ specs: [ParkVisitor], spots: [SIMD2<Float>]) -> [JellyActor] {
        guard let renderer, !actors.isEmpty else { return [] }
        parkClear()
        let base = actors.count
        guard renderer.ensureBodies(base + specs.count) else { return [] }
        let book = model.care.parkBook
        for (k, v) in specs.enumerated() {
            let a = JellyActor(id: base + k, name: v.name, simMesh: simMesh, renderMesh: renderMesh, embedding: embedding, appearance: model.appearance,
                               firmness: Float(model.firmness), damping: Float(model.damping), spawn: k < spots.count ? spots[k] : .zero)
            a.care = model.care
            let palette = JellyPalettes.park(v.colour)
            a.appearance = palette
            a.sim.arenaCenter = GameCamera.arenaCenter
            a.sim.arenaRadius = GameCamera.arenaRadius
            let b = BlobBrain.forGame()
            b.demo = nil; b.runMoveDemo = nil
            b.autonomy = true
            model.care.wireWorld(b, isBob: false)
            a.brain = b
            parkActors.append(a)
            // a roster of one is not wired for company yet: the Jelbie joins the visitors (once)
            if actors.count == 1, !book.soloWired, let own = actors[0].brain { wireRoster(own, id: 0); book.soloWired = true }
            wireRoster(b, id: a.id)
            b.feature = v.signature
            b.personalityOverride = v.style.variety
            b.currentPose(a.sim)
            a.reset(drop: 0, shift: true)
            renderer.setPalette(palette, body: a.id)
            renderer.setHidden(false, body: a.id)
        }
        return parkActors
    }

    /// The visitors leave: their bodies are hidden (the slots stay for the next visit) and the peers are the roster again.
    func parkClear() {
        guard !parkActors.isEmpty else { return }
        for a in parkActors {
            renderer?.setHidden(true, body: a.id)
            renderer?.setMouth(0, body: a.id)
            a.brain?.abortAll(a.sim, a.skinner)
        }
        parkActors.removeAll()
        if actors.count == 1 { peerSnapshot.removeAll() }
    }

    /// A touch in the park: the visitor under it (by his body's screen circle) or nothing.
    func parkTap(_ p: CGPoint, _ size: CGSize) {
        guard haveCam, size.width > 1, size.height > 1 else { return }
        let v = lastCam.view
        let right = SIMD3<Float>(v.columns.0.x, v.columns.1.x, v.columns.2.x)
        func screen(_ w: SIMD3<Float>) -> CGPoint? {
            let q = lastCam.viewProj * SIMD4<Float>(w, 1)
            guard q.w > 1e-4 else { return nil }
            return CGPoint(x: CGFloat(q.x / q.w * 0.5 + 0.5) * size.width, y: CGFloat(1 - (q.y / q.w * 0.5 + 0.5)) * size.height)
        }
        var best: (id: Int, d: CGFloat)?
        for a in parkActors {
            let c = a.sim.centroid()
            guard let s = screen(c), let e = screen(c + right * 0.85) else { continue }
            let r = max(abs(e.x - s.x), 28)
            let d = hypot(p.x - s.x, p.y - s.y)
            if d <= r * 1.1, best == nil || d < best!.d { best = (a.id, d) }
        }
        model.care.parkTapped(best?.id)
    }
}
