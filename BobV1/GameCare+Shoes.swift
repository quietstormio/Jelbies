//
//  GameCare+Shoes.swift
//  Feeds the worn shoes (Room/ShoeModel.swift) to the room renderer: for every Jelly that wears a look in the feet slot, the shell is built from his
//  foot beans' world vertices and uploaded with the other props. Shoes show in the room AND on the track (only on the player's racer: the borrowed
//  rival bodies keep their tint and need no shoes), never in the wash.
//

import Foundation
import simd

extension GameCare {
    /// The 418 world vertices of each foot (nil until the body's foot geometry exists). The beans blend from the rigid rest foot to the world-driven bean.
    func footBeans(_ a: JellyActor) -> [[SIMD3<Float>]]? {
        guard let b = a.brain else { return nil }
        return Self.footBeans(brain: b, sim: a.sim, skinner: a.skinner)
    }
    static func footBeans(brain b: BlobBrain, sim: SoftBody, skinner sk: Skinner) -> [[SIMD3<Float>]]? {
        if !b.geom.valid { b.geom = FootGeom(sim: sim) }
        guard b.geom.valid else { return nil }
        var rigid: [[SIMD3<Float>]] = [[SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount), [SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount)]
        b.fillBeansRigid(sim, into: &rigid, tuck: 0)
        guard sk.beansActive else { return rigid }
        // the SAME blend the skin draws (Skinner.update): beanStart -> beanPos by the bean blend, so the shell is grown from the foot that is on screen
        let bl = sk.beanBlend
        guard sk.beanStart.count == 2, sk.beanStart[0].count == FootBean.vertexCount, sk.beanPos.count == 2, sk.beanPos[0].count == FootBean.vertexCount else { return rigid }
        for s in 0..<2 { for i in 0..<FootBean.vertexCount { let a = sk.beanStart[s][i]; rigid[s][i] = a + (sk.beanPos[s][i] - a) * bl } }
        return rigid
    }

    /// Does this actor wear shoes on screen right now?
    func shoeLook(for a: JellyActor) -> WearLook? {
        if race.active, a.id != race.playerID { return nil }
        if bath.active, bath.targetID == a.id { return nil }
        return store.worn(a.id, .feet)
    }

    /// What a foot's shoe looked like when it was last built: while the bean has not moved (a Jelly standing still, a sitter, a sleeper) the shell is reused.
    struct ShoeEntry { var look: WearLook; var floorY: Float; var bean: [SIMD3<Float>]; var mesh: RoomMesh }

    /// The world-space shoe mesh of every wearing Jelly (tests and captures).
    func shoeMesh(_ actors: [JellyActor], time: Float) -> RoomMesh { shoeFrame(actors, time: time).mesh }

    /// The mesh and whether it differs from the one drawn last frame (a foot moved, a look changed, someone put shoes on or took them off, glitter twinkles).
    func shoeFrame(_ actors: [JellyActor], time: Float) -> (mesh: RoomMesh, changed: Bool) {
        let b = RoomMeshBuilder(); b.material = .plain
        var changed = false, sig: [Int] = []
        for a in actors {
            guard let look = shoeLook(for: a), let beans = footBeans(a) else { continue }
            let li = WearLook.allCases.firstIndex(of: look) ?? 0
            let bodyCol = a.appearance?.flesh ?? SIMD3<Float>(0.35, 0.5, 0.9)
            for s in 0..<2 {
                let key = a.id * 2 + s
                sig.append(key * 16 + li)
                let w = beans[s], floorY = a.sim.floorY
                if look != .sneakerLightup, let e = shoeCache[key], e.look == look, e.floorY == floorY, e.bean.count == w.count, Self.sameBean(e.bean, w) {
                    shoeStats.reused += 1
                    let base = UInt32(b.mesh.vertices.count)
                    b.mesh.vertices += e.mesh.vertices
                    b.mesh.indices += e.mesh.indices.map { $0 + base }
                } else {
                    let sub = RoomMeshBuilder(); sub.material = .plain
                    ShoeModel.buildShell(look, bean: w, floorY: floorY, body: bodyCol, time: time, gpuPaint: true, into: sub)
                    shoeCache[key] = ShoeEntry(look: look, floorY: floorY, bean: w, mesh: sub.mesh)
                    shoeStats.rebuilt += 1; changed = true
                    let base = UInt32(b.mesh.vertices.count)
                    b.mesh.vertices += sub.mesh.vertices
                    b.mesh.indices += sub.mesh.indices.map { $0 + base }
                }
                if look == .glitterShoes { ShoeModel.addSparkles(b, bean: w, time: time, side: s); changed = true }
                if look == .sneakerLightup { changed = true }          // the glow cycles every frame
            }
        }
        if sig != shoeSig { changed = true; shoeSig = sig }
        return (b.mesh, changed)
    }
    static func sameBean(_ a: [SIMD3<Float>], _ b: [SIMD3<Float>]) -> Bool {
        for i in a.indices where simd_distance_squared(a[i], b[i]) > 1e-8 { return false }
        return true
    }

    /// After the frame's last sim step.
    func refreshShoes(_ actors: [JellyActor], renderer: MelonRenderer?, time: Float) {
        guard let room = renderer?.room else { return }
        let any = !room.bathVisible && actors.contains { shoeLook(for: $0) != nil }          // not in the wash scene (the bodies of the others are not drawn there); the track keeps them
        guard any || shoesDrawn else { return }
        if any {
            let f = shoeFrame(actors, time: time)
            if f.changed || !shoesDrawn { room.setShoes(f.mesh) }              // nothing moved: the buffer from last frame is still right
        } else {
            room.setShoes(RoomMesh()); shoeCache = [:]; shoeSig = []
        }
        shoesDrawn = any
    }
}
