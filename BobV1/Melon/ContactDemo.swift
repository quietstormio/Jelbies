//
//  ContactDemo.swift
//  Capture aid only (launch arguments; nothing happens without them): force one touching emote between chosen Jelbies in the real app.
//    -ContactDemo <SocialKind raw value | lieDown | sleepPile; groupHug, circleDance, groupCheer take the whole cast>   e.g. swayHug, noseBoop, backToBack, cuddleLean, groupHug, lieDown
//    -ContactDemoIds 0,1[,2]                          roster slots of the cast; the first one starts it (default: everyone, in order)
//    -ContactCam low|side|perp|top                    camera; works without -ContactDemo. low = the player's 3/4 view, side = steep orbit,
//                                                     perp = tracks the cast, side-on (perpendicular to the cast's axis, on the room side), near body height;
//                                                     top = the same tracking from nearly straight above
//    -ContactDemoDelay <s>                            wait before it starts (default 4)
//  The cast is taken off autonomy so nothing else interrupts the scene. Used by BobV1UITests/ContactCaptureUITests.swift.
//

import Foundation
import simd

enum ContactDemo {
    /// The tracked camera pose (perp / top), read by GameCamera.camera every frame. Nil = not used.
    nonisolated(unsafe) static var pose: (eye: SIMD3<Float>, target: SIMD3<Float>)?

    /// Every ~1/30 s: aim at the midpoint of the cast's roots, from the side perpendicular to their principal axis (the side facing the room: +z), with the yaw, the
    /// target and the distance smoothed (~0.5 s) so nothing whips round; the distance makes the cast fill ~70% of the screen width.
    @MainActor static func track(_ brains: [BlobBrain], top: Bool) async {
        var yaw: Float? = nil, mid = SIMD2<Float>(0, 0), dist: Float = 12
        var first = true
        while !Task.isCancelled {
            let pts = brains.map { $0.position }
            let m = pts.reduce(SIMD2<Float>(0, 0), +) / Float(pts.count)
            var sxx: Float = 0, syy: Float = 0, sxy: Float = 0
            for q in pts { let d = q - m; sxx += d.x * d.x; syy += d.y * d.y; sxy += d.x * d.y }
            let axis = 0.5 * atan2f(2 * sxy, sxx - syy)          // principal axis angle in the x-z plane
            var n = SIMD2<Float>(-sinf(axis), cosf(axis))          // perpendicular
            if n.y < 0 { n = -n }                                  // the side facing the room (away from the back wall)
            let target = atan2f(n.x, n.y)
            let ext = (pts.map { abs(($0 - m).x * cosf(axis) + ($0 - m).y * sinf(axis)) }.max() ?? 0) * 2 + 1.5          // cast width along the axis + a body
            let tanH = tanf(GameCamera.fovY / 2) * GameCamera.aspect
            let want = max(ext / 0.75 / (2 * tanH), 3)
            let a = first ? 1 : 1 - expf(-(1.0 / 30) / 0.5)
            first = false
            if yaw == nil { yaw = target } else { var dy = target - yaw!; while dy > .pi { dy -= 2 * .pi }; while dy < -.pi { dy += 2 * .pi }; yaw! += dy * a }
            mid += (m - mid) * (mid == .zero ? 1 : a); dist += (want - dist) * a
            let el: Float = top ? 1.35 : 0.12
            let y = yaw!
            let tgt = SIMD3<Float>(mid.x, 0.6, mid.y)
            pose = (tgt + SIMD3(cosf(el) * sinf(y), sinf(el), cosf(el) * cosf(y)) * dist, tgt)
            try? await Task.sleep(nanoseconds: 33_000_000)
        }
    }

    /// Result line to the console and (simulator shares the host filesystem) to $CONTACTDEMO_LOG when set.
    static func note(_ f: String, _ a: CVarArg...) {
        let line = String(format: f, arguments: a)
        NSLog("[contactdemo] %@", line)
        if let p = ProcessInfo.processInfo.environment["CONTACTDEMO_LOG"], let h = FileHandle(forWritingAtPath: p) ?? { FileManager.default.createFile(atPath: p, contents: nil); return FileHandle(forWritingAtPath: p) }() { h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); h.closeFile() }
    }
    /// `-ContactCam low|side`: the Photo-mode orbit pose, set once (low = a low 3/4 view from the right, side = a steep orbit, nearly along the row of Jelbies).
    static func applyCamera() {
        guard let c = UserDefaults.standard.string(forKey: "ContactCam") else { return }
        PhotoCam.reset(); PhotoCam.active = true
        switch c {
        case "side": PhotoCam.yaw = 1.2; PhotoCam.pitch = -0.3; PhotoCam.zoom = 0.8; PhotoCam.pan = SIMD2(0, 0.45)
        default: PhotoCam.yaw = 0.45; PhotoCam.pitch = -0.3; PhotoCam.zoom = 0.8; PhotoCam.pan = SIMD2(0, 0.45)
        }
    }

    /// Keeps every need of the cast full (a thirst or hunger bubble interrupts the scene): topped up every 2 s while the scene runs.
    @MainActor static func keepNeedsFull(_ cast: [JellyActor]) async {
        while !Task.isCancelled {
            for a in cast { if let n = a.needs { for k in NeedKind.allCases where n.level(k) < 0.95 { n.restore(k) } } }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    /// Wall-clock start / end of the emote (epoch seconds) for the host to trim the clip: the session is over when the first brain's `social` is nil again.
    @MainActor static func logSpan(_ started: Bool, _ lead: BlobBrain, _ cast: [BlobBrain]) async {
        guard started else { return }
        note(" startEpoch=%.3f", Date().timeIntervalSince1970)
        var i = 0
        while lead.social != nil && i < 6000 {
            if i % 5 == 0 {          // every 0.5 s: the session phase and the smallest root distance between two of the cast (the touching window starts when it is <= ~1.55)
                var dmin: Float = 99
                for (x, p) in cast.enumerated() { for q in cast[(x + 1)...] { dmin = min(dmin, simd_distance(p.position, q.position)) } }
                note(" tick t=%.2f ph=%d d=%.2f", Date().timeIntervalSince1970, lead.social?.phase ?? -1, dmin)
            }
            try? await Task.sleep(nanoseconds: 100_000_000); i += 1
        }
        note(" endEpoch=%.3f", Date().timeIntervalSince1970)
    }

    @MainActor static func run(care: GameCare) async {
        let d = UserDefaults.standard
        applyCamera()
        guard let name = d.string(forKey: "ContactDemo"), !name.isEmpty else { return }
        try? await Task.sleep(nanoseconds: UInt64((d.double(forKey: "ContactDemoDelay") > 0 ? d.double(forKey: "ContactDemoDelay") : 4) * 1e9))
        for _ in 0..<300 where care.raceBook.actors.count < 2 || care.raceBook.actors.contains(where: { $0.brain == nil }) { try? await Task.sleep(nanoseconds: 100_000_000) }          // (the roster may still be loading)
        let actors = care.raceBook.actors
        let ids = d.string(forKey: "ContactDemoIds").map { $0.split(separator: ",").compactMap { Int($0) } } ?? Array(actors.indices)
        let cast = ids.compactMap { actors.indices.contains($0) ? actors[$0] : nil }.filter { $0.brain != nil }
        guard cast.count >= 2 else { note(" cast too small (%d)", cast.count); return }
        for a in cast { a.brain?.autonomy = false; a.brain?.idleForced = true }
        if name != "lieDown" && name != "sleepPile" { Task { @MainActor in await keepNeedsFull(cast) } }          // (a full-needs Jelbie may not lie down at all)
        if let c = d.string(forKey: "ContactCam"), c == "perp" || c == "top" { let bs = cast.compactMap(\.brain); Task { @MainActor in await track(bs, top: c == "top") } }
        // side by side across the screen first (a pair along the camera axis hides the touch): spots at z -0.9 (the camera's look-at depth), 2.6 u apart (3: 2.4 u)
        let half: Float = (name == "lieDown" || name == "sleepPile") ? 0.65 : 1.3          // (the lie-down / sleep placement wants them ~1.2 u apart, as the Lab does)
        let xs: [Float] = cast.count == 2 ? [-half, half] : (0..<cast.count).map { (Float($0) - Float(cast.count - 1) / 2) * 1.8 }
        let spots = xs.map { SIMD2<Float>($0, -0.9) }
        for a in cast { if let b = a.brain { note(" start (%.2f, %.2f)", b.position.x, b.position.y) } }
        for (a, g) in zip(cast, spots) { a.brain?.requestNow(.goTo(g)) }
        for _ in 0..<250 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if zip(cast, spots).allSatisfy({ a, g in a.brain.map { simd_distance($0.position, g) < 0.5 } ?? true }) { break }
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        for a in cast { if let b = a.brain { note(" at (%.2f, %.2f) steer=%d", b.position.x, b.position.y, b.steerID) } }
        if name == "sleepPile" {          // the first falls asleep, the others join him a few seconds later
            _ = cast[0].brain?.idleStart(.sleep, cast[0].sim); cast[0].brain?.sleep.hold = 600
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            for a in cast.dropFirst() { let ok = a.brain?.idleStart(.sleep, a.sim) ?? false; a.brain?.sleep.hold = 600; note(" sleepPile join=%d", ok ? 1 : 0) }
            return
        }
        if name == "lieDown" {
            var ok = true
            for a in cast { ok = (a.brain?.idleStart(.lieDown, a.sim) ?? false) && ok }
            note(" lieDown started=%d", ok ? 1 : 0)
            note(" startEpoch=%.3f", Date().timeIntervalSince1970)
            let bs = cast.compactMap(\.brain)
            for i in 0..<80 {          // every 0.5 s for 40 s: who is lying (kind / phase / k / yielding / a pending request), to see why one never lies down
                try? await Task.sleep(nanoseconds: 500_000_000)
                let s = bs.map { String(format: "[%@ ph=%d k=%.2f y=%d pend=%d]", "\($0.idleState.kind.map { "\($0)" } ?? "none")", $0.idleState.phase, $0.idleState.k, $0.idleState.yielding ? 1 : 0, $0.pending != nil ? 1 : 0) }.joined(separator: " ")
                note(" lie t=%.1f %@", Double(i + 1) * 0.5, s)
            }
            return
        }
        guard let kind = SocialKind(rawValue: name), let a = cast.first, let ab = a.brain, let bb = cast[1].brain else { note(" unknown kind %@", name); return }
        if kind == .groupHug || kind == .circleDance || kind == .groupCheer {          // (a group: everyone else in the cast joins; socialStart(kind, with: one) only finds the near ones)
            let ok = ab.socialStartGroup(kind, with: cast.dropFirst().compactMap(\.brain), a.sim)
            note(" %@ started=%d crew=%d", name, ok ? 1 : 0, cast.count)
            await logSpan(ok, ab, cast.compactMap(\.brain))
            return
        }
        let ok = ab.socialStart(kind, with: bb, a.sim)
        note(" %@ started=%d", name, ok ? 1 : 0)
        await logSpan(ok, ab, cast.compactMap(\.brain))
    }
}
