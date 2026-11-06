//
//  ContactDemo.swift
//  Capture aid only (launch arguments; nothing happens without them): force one touching emote between chosen Jelbies in the real app.
//    -ContactDemo <SocialKind raw value (chase too) | lieDown | flop | sleepPile; groupHug, circleDance, groupCheer take the whole cast>   e.g. swayHug, noseBoop, backToBack, cuddleLean, groupHug, lieDown
//    -ContactDemoIds 0,1[,2]                          roster slots of the cast; the first one starts it (default: everyone, in order)
//    -ContactCam low|side|perp|top                    camera; works without -ContactDemo. low = the player's 3/4 view, side = steep orbit,
//                                                     perp = tracks the cast, side-on (perpendicular to the cast's axis, on the room side), near body height;
//                                                     top = the same tracking from nearly straight above
//    -ContactDemoDelay <s>                            wait before it starts (default 4)
//    -ContactDemoPark 1 (+ -StartPark 1, -ContactDemoVisitors N, -ContactDemoVisitorSpecies wings,daisy,none)   the same in the PARK: cast = the NewGame Jelbie(s) + N chosen visitors
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

    /// Gap sampling for the cast (cm, + apart): per pair i<j the drawn-skin gap with features (wings / tail / ears) and without. Needs the contact engine's ContactField.
    @MainActor final class GapLog {
        let brains: [BlobBrain]
        var pairs: [(Int, Int)] = []
        struct Sample { var touching: Bool; var ph: Int; var withF: [Float]; var body: [Float]; var hand: [Float] }
        var samples: [Sample] = []
        init(_ b: [BlobBrain]) { brains = b; for i in 0..<b.count { for j in (i + 1)..<b.count { pairs.append((i, j)) } } }
        func cm(_ v: Float?) -> Float { v.map { $0 * 100 } ?? .nan }
        /// One tick: returns the text for the tick line and remembers the sample (touching = the closest root distance <= 1.55).
        func sample(ph: Int, dmin: Float) -> String {
            let f = pairs.map { cm(ContactField.gap(brains[$0.0].steerID, brains[$0.1].steerID, features: true)) }
            let b = pairs.map { cm(ContactField.gap(brains[$0.0].steerID, brains[$0.1].steerID, features: false)) }
            // the hand gap (user rule 2): the least, over both directions, of a drawn hand tip to the other body's skin outline (+ hovers, 0 rests on the skin, - inside); nan = no arm drawn
            let h: [Float] = pairs.map { p in
                let x = [ContactField.handGap(brains[p.0].steerID, against: brains[p.1].steerID), ContactField.handGap(brains[p.1].steerID, against: brains[p.0].steerID)].compactMap { $0 }
                return x.isEmpty ? Float.nan : (x.min()! * 100)
            }
            samples.append(Sample(touching: dmin <= 1.55, ph: ph, withF: f, body: b, hand: h))
            return " gaps[" + pairs.enumerated().map { String(format: "%d-%d:%.1f/%.1f", $1.0, $1.1, f[$0], b[$0]) }.joined(separator: " ") + "]cm(feat/body) hand[" + pairs.enumerated().map { String(format: "%d-%d:%.1f", $1.0, $1.1, h[$0]) }.joined(separator: " ") + "]cm"
        }
        /// The scene's summary, per pair: min gap over the touching ticks, median over the hold ticks, both with and without features. The hold ticks are the ticks in a HOLD step of the stance table
        /// (`isHold(phase)`, from ContactStance: the step whose target is the plush press), not the phase with the most touching ticks (a long walk-in phase used to win that); without a table
        /// (lie-down, sleep pile) the touching ticks of the phase that has the most of them.
        func summary(isHold: ((Int) -> Bool)? = nil) {
            let touch = samples.filter(\.touching)
            var count: [Int: Int] = [:]; for s in touch { count[s.ph, default: 0] += 1 }
            var holdPh = count.max { $0.value < $1.value }?.key
            var hold = touch.filter { $0.ph == holdPh }
            if let isHold {
                hold = samples.filter { isHold($0.ph) }
                holdPh = hold.first?.ph ?? -1
            }
            func med(_ a: [Float]) -> Float { let v = a.filter { !$0.isNaN }.sorted(); return v.isEmpty ? .nan : v[v.count / 2] }
            func mn(_ a: [Float]) -> Float { a.filter { !$0.isNaN }.min() ?? .nan }
            for (k, p) in pairs.enumerated() {
                ContactDemo.note(" summary pair=%d-%d touchTicks=%d holdPh=%d holdTicks=%d (%@) minGapFeat=%.1f minGapBody=%.1f medHoldFeat=%.1f medHoldBody=%.1f cm minHand=%.1f medHoldHand=%.1f cm(hand tip to the other skin, - = inside)", p.0, p.1, touch.count, holdPh ?? -1, hold.count, isHold == nil ? "most-touching-phase" : "stance-table-hold",
                                 mn(touch.map { $0.withF[k] }), mn(touch.map { $0.body[k] }), med(hold.map { $0.withF[k] }), med(hold.map { $0.body[k] }), mn(touch.map { $0.hand[k] }), med(hold.map { $0.hand[k] }))
                // the WHOLE run, not only the ticks where the root distance said "touching" (round 2: leapfrog's summary read -0.2 while its own ticks went to -7.0, because the overlapping ticks were not "touching" ticks)
                ContactDemo.note(" summaryAll pair=%d-%d ticks=%d minAllFeat=%.1f minAllBody=%.1f minAllHand=%.1f cm(every tick of the scene)", p.0, p.1, samples.count, mn(samples.map { $0.withF[k] }), mn(samples.map { $0.body[k] }), mn(samples.map { $0.hand[k] }))
            }
        }
    }

    /// Wall-clock start / end of the emote (epoch seconds) for the host to trim the clip: the session is over when the first brain's `social` is nil again.
    @MainActor static func logSpan(_ started: Bool, _ lead: BlobBrain, _ cast: [BlobBrain], kind: SocialKind? = nil) async {
        guard started else { return }
        note(" startEpoch=%.3f", Date().timeIntervalSince1970)
        var i = 0
        let gl = GapLog(cast)
        while lead.social != nil && i < 6000 {
            if i % 2 == 0 {          // every 0.2 s: the session phase and the smallest root distance between two of the cast (the touching window starts when it is <= ~1.55)
                var dmin: Float = 99
                for (x, p) in cast.enumerated() { for q in cast[(x + 1)...] { dmin = min(dmin, simd_distance(p.position, q.position)) } }
                let ph = lead.social?.phase ?? -1
                note(" tick t=%.2f ph=%d d=%.2f%@", Date().timeIntervalSince1970, ph, dmin, gl.sample(ph: ph, dmin: dmin))
                if ProcessInfo.processInfo.environment["CONTACT_PARK_DIAG"] != nil || UserDefaults.standard.integer(forKey: "ContactDemoDiag") != 0 {
                    note(" diag %@", cast.map { b in String(format: "[id%d (%.2f,%.2f) valid=%d partners=%@ pass=%d scr=%@ act=%@]", b.steerID, b.position.x, b.position.y, ContactField.isValid(b.steerID) ? 1 : 0, "\(b.contactPartnerIDs().sorted())", b.socialBook.passThrough ? 1 : 0, "\(b.script)", "\(b.activity)") }.joined(separator: " "))
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000); i += 1
        }
        note(" endEpoch=%.3f", Date().timeIntervalSince1970)
        let table = kind.flatMap { ContactStance.entry($0) }
        gl.summary(isHold: table.map { t in { ph in t.step(at: ph)?.target == ContactStance.hold } })
    }

    /// `-ContactDemoPark 1` (needs `-StartPark 1`, the simulator's own go-to-the-park hook): waits for the trip to be on, then swaps the random visitors for `-ContactDemoVisitors N`
    /// chosen ones (`-ContactDemoVisitorSpecies wings,daisy,none` = pool visitors by signature, in order; yellow/tail/spines has NO pool visitor, so it falls back to a plain one and says so).
    /// Returns the cast: the room's Jelbie(s) that came, then the visitors. Logs each visitor's species, colour and worn item.
    @MainActor static func parkCast(care: GameCare, d: UserDefaults) async -> [JellyActor] {
        for _ in 0..<900 where care.park.phase != .playing { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard care.park.phase == .playing else { note(" park not reached (phase %@)", "\(care.park.phase)"); return [] }
        try? await Task.sleep(nanoseconds: 2_000_000_000)          // (everyone placed, the arrival hops done)
        let book = care.parkBook
        let n = max(d.integer(forKey: "ContactDemoVisitors"), 1)
        let want = (d.string(forKey: "ContactDemoVisitorSpecies") ?? "wings,daisy").split(separator: ",").map { String($0).lowercased() }
        func feature(_ w: String) -> JellyFeature { switch w { case "wings", "purple", "lavender": return .wings; case "daisy", "green": return .daisy; case "spines", "tail", "yellow": return .spines; default: return .none } }
        var chosen: [ParkVisitor] = []
        for k in 0..<n {
            let w = k < want.count ? want[k] : "none", f = feature(w)
            if let v = book.visitors.first(where: { $0.signature == f && !chosen.map(\.id).contains($0.id) }) { chosen.append(v) }
            else if let v = book.visitors.first(where: { $0.signature == .none && !chosen.map(\.id).contains($0.id) }) { note(" park: no pool visitor with %@, using plain %@", w, v.name); chosen.append(v) }
        }
        book.work.giftState = 0          // (no friend walks over with a present mid-scene)
        for a in book.actors { care.visitorPutAway(a) }
        let roster = book.roster.filter { $0.brain != nil }
        let spots = ParkLayout.spots(count: roster.count + chosen.count).dropFirst(roster.count)
        book.cast = chosen.map(\.id)
        book.actors = book.spawn?(chosen, Array(spots)) ?? []
        for (a, v) in zip(book.actors, chosen) { note(" park visitor body=%d %@ colour=%@ species=%@ wear=%@", a.id, v.name, v.colour.rawValue, "\(v.signature)", v.wear.map { "\($0)" } ?? "none") }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        for a in book.actors { a.brain?.autonomy = false; a.brain?.idleForced = true }
        return roster + book.actors
    }

    @MainActor static func run(care: GameCare) async {
        let d = UserDefaults.standard
        applyCamera()
        guard let name = d.string(forKey: "ContactDemo"), !name.isEmpty else { return }
        try? await Task.sleep(nanoseconds: UInt64((d.double(forKey: "ContactDemoDelay") > 0 ? d.double(forKey: "ContactDemoDelay") : 4) * 1e9))
        let park = d.integer(forKey: "ContactDemoPark") != 0
        let cast: [JellyActor]
        if park {
            cast = await parkCast(care: care, d: d)
        } else {
            for _ in 0..<300 where care.raceBook.actors.count < 2 || care.raceBook.actors.contains(where: { $0.brain == nil }) { try? await Task.sleep(nanoseconds: 100_000_000) }          // (the roster may still be loading)
            let actors = care.raceBook.actors
            let ids = d.string(forKey: "ContactDemoIds").map { $0.split(separator: ",").compactMap { Int($0) } } ?? Array(actors.indices)
            cast = ids.compactMap { actors.indices.contains($0) ? actors[$0] : nil }.filter { $0.brain != nil }
        }
        if name == "soccerKick" { await soccerKickScene(care: care, cast: cast); return }          // (capture aid: ONE Jelbie, a ball, one kick)
        guard cast.count >= 2 else { note(" cast too small (%d)", cast.count); return }
        for a in cast { a.brain?.autonomy = false; a.brain?.idleForced = true }
        if name != "lieDown" && name != "flop" && name != "sleepPile" { Task { @MainActor in await keepNeedsFull(cast) } }          // (a full-needs Jelbie may not lie down at all)
        if let c = d.string(forKey: "ContactCam"), c == "perp" || c == "top" { let bs = cast.compactMap(\.brain); Task { @MainActor in await track(bs, top: c == "top") } }
        // side by side across the screen first (a pair along the camera axis hides the touch): spots at z -0.9 (the camera's look-at depth), 2.6 u apart (3: 2.4 u)
        let half: Float = (name == "lieDown" || name == "flop" || name == "sleepPile") ? 0.65 : 1.3          // (the lie-down / sleep placement wants them ~1.2 u apart, as the Lab does)
        let xs: [Float] = cast.count == 2 ? [-half, half] : (0..<cast.count).map { (Float($0) - Float(cast.count - 1) / 2) * 1.8 }
        let spots = xs.map { SIMD2<Float>($0, park ? 1.2 : -0.9) }          // (the park: the middle of its play floor)
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
            // (round 2: the sleep pile's demolog was 113 bytes, no ticks and no SUMMARY, so nothing could be read from the real app) every 0.5 s for 40 s, then the same summary the other scenes print
            note(" startEpoch=%.3f", Date().timeIntervalSince1970)
            let bs = cast.compactMap(\.brain)
            let gl = GapLog(bs)
            for i in 0..<80 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                var dmin: Float = 99
                for (x, p) in bs.enumerated() { for q in bs[(x + 1)...] { dmin = min(dmin, simd_distance(p.position, q.position)) } }
                note(" sleep t=%.1f %@%@", Double(i + 1) * 0.5, bs.map { String(format: "[%@ ph=%d]", "\($0.idleState.kind.map { "\($0)" } ?? "none")", $0.idleState.phase) }.joined(separator: " "), gl.sample(ph: bs.first?.idleState.phase ?? -1, dmin: dmin))
            }
            note(" endEpoch=%.3f", Date().timeIntervalSince1970)
            gl.summary()
            return
        }
        if name == "lieDown" || name == "flop" {          // (flop = the quick plop-down pair; both go through the lie-down clearance)
            var ok = true
            let idle: IdleKind = name == "flop" ? .flop : .lieDown
            for a in cast { ok = (a.brain?.idleStart(idle, a.sim) ?? false) && ok }
            note(" %@ started=%d", name, ok ? 1 : 0)
            note(" startEpoch=%.3f", Date().timeIntervalSince1970)
            let bs = cast.compactMap(\.brain)
            let gl = GapLog(bs)
            for i in 0..<80 {          // every 0.5 s for 40 s: who is lying (kind / phase / k / yielding / a pending request), to see why one never lies down
                try? await Task.sleep(nanoseconds: 500_000_000)
                let s = bs.map { String(format: "[%@ ph=%d k=%.2f y=%d pend=%d]", "\($0.idleState.kind.map { "\($0)" } ?? "none")", $0.idleState.phase, $0.idleState.k, $0.idleState.yielding ? 1 : 0, $0.pending != nil ? 1 : 0) }.joined(separator: " ")
                var dmin: Float = 99
                for (x, p) in bs.enumerated() { for q in bs[(x + 1)...] { dmin = min(dmin, simd_distance(p.position, q.position)) } }
                note(" lie t=%.1f %@%@", Double(i + 1) * 0.5, s, gl.sample(ph: bs.first?.idleState.phase ?? -1, dmin: dmin))
            }
            gl.summary()
            return
        }
        guard let kind = SocialKind(rawValue: name), let a = cast.first, let ab = a.brain, let bb = cast[1].brain else { note(" unknown kind %@", name); return }
        if kind.isGroup {          // (a group: everyone else in the cast joins; socialStart(kind, with: one) only finds the near ones)
            let ok = ab.socialStartGroup(kind, with: cast.dropFirst().compactMap(\.brain), a.sim)
            note(" %@ started=%d crew=%d", name, ok ? 1 : 0, cast.count)
            await logSpan(ok, ab, cast.compactMap(\.brain), kind: kind)
            return
        }
        let ok = ab.socialStart(kind, with: bb, a.sim)
        note(" %@ started=%d", name, ok ? 1 : 0)
        await logSpan(ok, ab, cast.compactMap(\.brain), kind: kind)
    }

    /// `-ContactDemo soccerKick` (one Jelbie): places the store's soccer ball, sends him to kick it and logs the wall-clock time of the kick (" fire epoch=") and, every ~40 ms,
    /// each sole's distance from its stand spot (" leg epoch= ext0= ext1="), so a screen recording can be lined up with the leg.
    @MainActor static func soccerKickScene(care: GameCare, cast: [JellyActor]) async {
        guard let a = cast.first, let b = a.brain else { note(" soccerKick: no Jelbie"); return }
        care.store.grant("decor-soccerball")
        let placed = care.store.place("decor-soccerball")
        note(" soccerKick ball placed=%d", placed != nil ? 1 : 0)
        DecorField.shared.set(care.store.placedDecor)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        b.soccerModeForce = 0; b.idleForced = true; b.autonomy = false
        b.abortScript(a.sim, a.skinner); b.pending = nil; b.idleReset(a.skinner)          // (whatever autonomy had begun)
        var ok = b.idleStart(.soccerKick, a.sim)
        for _ in 0..<8 where !ok { try? await Task.sleep(nanoseconds: 1_500_000_000); b.abortScript(a.sim, a.skinner); b.pending = nil; b.idleReset(a.skinner); ok = b.idleStart(.soccerKick, a.sim) }
        note(" soccerKick started=%d", ok ? 1 : 0)
        note(" startEpoch=%.3f", Date().timeIntervalSince1970)
        var fired = false, i = 0
        while i < 1000 {
            try? await Task.sleep(nanoseconds: 40_000_000); i += 1
            let now = Date().timeIntervalSince1970
            if !fired, i % 25 == 0 { note(" wait kind=%@ stage=%d script=%@ pos=(%.2f,%.2f)", "\(String(describing: b.idleState.kind))", b.idleState.soccer.stage, "\(b.script)", b.position.x, b.position.y) }
            if !fired, b.idleState.kind == .soccerKick, b.idleState.soccer.fired { fired = true; note(" fire epoch=%.3f", now) }
            if fired {
                let e = (0..<2).map { simd_distance(b.feet.pos[$0], SIMD2(b.px, b.pz) + rotXZ(b.geom.off[$0], b.yaw)) }
                note(" leg epoch=%.3f ext0=%.3f ext1=%.3f", now, e[0], e[1])
                if i > 0, b.idleState.kind == nil { break }
            }
        }
        // 4 s after the move ends (a later move may re-plant the foot: say so)
        for _ in 0..<100 {
            try? await Task.sleep(nanoseconds: 40_000_000)
            let e = (0..<2).map { simd_distance(b.feet.pos[$0], SIMD2(b.px, b.pz) + rotXZ(b.geom.off[$0], b.yaw)) }
            note(" leg epoch=%.3f ext0=%.3f ext1=%.3f after-move", Date().timeIntervalSince1970, e[0], e[1])
        }
        note(" endEpoch=%.3f", Date().timeIntervalSince1970)
    }
}
