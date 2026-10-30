//
//  MelonStage+SocialDemo.swift
//  Capture aid for the touching round (2026-10-30): `-SocialDemo leapfrog` starts that social between two Jelbies of the room (or park) as soon as they are free, again and again
//  (the seats swap each time, so each is the crouched one and the jumper), and logs the deepest overlap of the drawn bodies and of Pip's tail tube ("[touch] ..." lines).
//  `-SocialPair 0,1` picks the two body ids (default 0,1); `-SocialDemoGap 3` seconds between plays. Nothing runs without the launch argument.
//

import Foundation
import simd

@MainActor
private final class SocialDemoState {
    var next: CFTimeInterval = 0, plays = 0, seat = 0
    var depth: Float = 0, tail: Float = 0, running = false, frame = 0
}

extension MelonController {
    private static let demoState = SocialDemoState()
    static let socialDemoKind: SocialKind? = UserDefaults.standard.string(forKey: "SocialDemo").flatMap { SocialKind(rawValue: $0) }

    /// After the frame's skin: start the demo social when both are free, and measure the pair while it runs.
    func socialDemoTick(now: CFTimeInterval) {
        guard game, let kind = Self.socialDemoKind, let renderer, haveCam else { return }
        let st = Self.demoState
        let ids = (UserDefaults.standard.string(forKey: "SocialPair") ?? "0,1").split(separator: ",").compactMap { Int($0) }
        let all = actors + parkActors
        guard ids.count == 2, ids.allSatisfy({ $0 < all.count }) else { return }
        let a = all[ids[st.seat % 2]], b = all[ids[(st.seat + 1) % 2]]
        guard let ba = a.brain, let bb = b.brain else { return }
        if st.next == 0 { st.next = now + 5 }
        if !st.running {
            guard now >= st.next, ba.socialFree, bb.socialFree else { return }
            ba.autonomy = true; bb.autonomy = true
            if ba.socialStart(kind, with: bb, a.sim) { st.running = true; st.depth = 0; st.tail = 0; st.plays += 1; NSLog("[touch] %@ play %d starts (seat %d crouches/leads)", kind.rawValue, st.plays, st.seat % 2) }
            else { st.next = now + 1 }
            return
        }
        st.frame += 1
        if st.frame % 3 == 0 {
            let n = renderMesh.vertexCount
            let tf = renderMesh.armCapsule?.tailFirst ?? -1
            let skip = tf >= 0 ? tf..<(tf + TailBean.vertexCount) : 0..<0
            let pa = renderer.skinPointer(body: a.id), pb = renderer.skinPointer(body: b.id)
            let d = ContactMetric.mutualDepth(pa, pb, vertices: n, skip: skip)
            if d > st.depth + 0.01 { st.depth = d }
            if tf >= 0 {
                for (p, o) in [(pa, pb), (pb, pa)] where (p == pa ? a : b).skinner.tailOn { st.tail = max(st.tail, ContactMetric.tailIntrusion(tail: p, first: tf, other: o, vertices: n, skip: skip)) }
            }
        }
        if ba.social == nil, bb.social == nil {
            NSLog("[touch] %@ play %d ends: depth %.3f tail %.3f", kind.rawValue, st.plays, st.depth, st.tail)
            st.running = false; st.seat += 1
            st.next = now + max(1, UserDefaults.standard.double(forKey: "SocialDemoGap") > 0 ? UserDefaults.standard.double(forKey: "SocialDemoGap") : 3)
        }
    }
}
