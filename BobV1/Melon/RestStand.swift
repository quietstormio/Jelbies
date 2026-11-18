//
//  RestStand.swift
//  Every lobby / wardrobe picture of a Jelmiko (MelonStage.renderSnapshot) is a clean front-facing stand: the body's undeformed shape upright on the floor, the arms at their rest nubs,
//  the feet the body-rigid rest feet drawn the way the room draws a planted foot (the bean leg with the skin's foot retracted under it, so a worn shoe fits the drawn foot and the foot never
//  fights the shoe), whatever the live Jelmiko is doing when the picture is taken (eating, leaning, mid-step, lying asleep, held, waving). The live particles, skin state, brain's foot state and
//  pose cache are saved and put back exactly, so the room never sees it.
//

import simd

enum RestStand {
    /// Puts `sim` at its rest stand over `xz` and `skinner` at its rest arms and feet. Returns what puts the live state back (call it once, after the picture).
    @discardableResult
    static func enter(sim: SoftBody, skinner sk: Skinner, brain: BlobBrain? = nil, xz: SIMD2<Float>) -> () -> Void {
        let liveX = sim.x, liveAtt = sim.attractor, liveFit = sim.poseWarmStart
        let live = (sk.beanBlend, sk.shearVec, sk.lobeD, sk.beanPos, sk.beanStart, sk.retractMatrix, sk.retractShift)
        let liveBrain = brain.map { ($0.beanFitUsed, $0.beanSplay, $0.beanFitHold) }
        sim.x = sim.restStandPositions(xz: xz)
        sim.attractor = Attractor()          // (the brain's live target pose is where he WAS: the feet / shoes are placed on the body's own rest pose)
        sim.poseWarmStart = SIMD4<Float>(0, 0, 0, 1)
        sim.invalidatePose()
        sk.beanBlend = 0; sk.shearVec = .zero; sk.lobeD = [.zero, .zero]
        // the rest feet as the room draws a planted foot: the bean legs at the body-rigid pose, blended fully in, the embedded foot retracted under them (same maths as BlobBrain.commitBeans)
        if let b = brain, sk.beanFirst.count == 2 {
            if !b.geom.valid { b.geom = FootGeom(sim: sim) }
            if b.geom.valid {
                let empty = [SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount)
                var rigid = [empty, empty], start = [empty, empty]
                b.beanFitUsed = nil; b.beanSplay = 0; b.beanFitHold = 0
                b.fillBeansRigid(sim, into: &rigid, tuck: 0)
                b.fillBeansRigid(sim, into: &start, tuck: 0, scale: FootBean.startScale)
                sk.beanPos = rigid; sk.beanStart = start; sk.beanBlend = 1
                sk.retractMatrix = matrix_identity_float3x3; sk.retractShift = [.zero, .zero]
            }
        }
        return {
            sim.x = liveX; sim.attractor = liveAtt; sim.poseWarmStart = liveFit
            sim.invalidatePose()
            sk.beanBlend = live.0; sk.shearVec = live.1; sk.lobeD = live.2; sk.beanPos = live.3; sk.beanStart = live.4; sk.retractMatrix = live.5; sk.retractShift = live.6
            if let b = brain, let lb = liveBrain { b.beanFitUsed = lb.0; b.beanSplay = lb.1; b.beanFitHold = lb.2 }
        }
    }
}
