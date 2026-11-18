//
//  RestStand.swift
//  Every lobby / wardrobe picture of a Jelmiko (MelonStage.renderSnapshot) is a clean front-facing stand: the body's undeformed shape upright on the floor, the arms at their rest nubs,
//  the feet the plain embedded feet (no walking bean, no shear / lobe offsets), whatever the live Jelmiko is doing when the picture is taken (eating, leaning, mid-step, lying asleep,
//  held, waving). The live particles, skin state and pose cache are saved and put back exactly, so the room never sees it.
//

import simd

enum RestStand {
    /// Puts `sim` at its rest stand over `xz` and `skinner` at its rest arms and feet. Returns what puts the live state back (call it once, after the picture).
    @discardableResult
    static func enter(sim: SoftBody, skinner sk: Skinner, xz: SIMD2<Float>) -> () -> Void {
        let liveX = sim.x, liveAtt = sim.attractor, liveFit = sim.poseWarmStart
        let live = (sk.beanBlend, sk.shearVec, sk.lobeD)
        sim.x = sim.restStandPositions(xz: xz)
        sim.attractor = Attractor()          // (the brain's live target pose is where he WAS: the feet / shoes are placed on the body's own rest pose)
        sim.poseWarmStart = SIMD4<Float>(0, 0, 0, 1)
        sim.invalidatePose()
        sk.beanBlend = 0; sk.shearVec = .zero; sk.lobeD = [.zero, .zero]
        return {
            sim.x = liveX; sim.attractor = liveAtt; sim.poseWarmStart = liveFit
            sim.invalidatePose()
            sk.beanBlend = live.0; sk.shearVec = live.1; sk.lobeD = live.2
        }
    }
}
