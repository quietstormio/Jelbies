//
//  GuestArrival.swift
//  The arrival moment of a friend over ("Invite a friend", Option A of the approved board). Seconds from the doorbell:
//    0.0  the doorbell rings once (the sound toggle decides)
//    0.6  the room dims a little and a cream card slides down from the top: a door, "Ding dong!", "<name> is here"
//    1.1  the card grows a divider, three dots and "getting the room ready...": the guest's BODY is made here (the 4th actor, its GPU slot, the first
//         limb tick), behind the card, while the household keeps running
//    1.8  the card slides away; the guest runs in from the left edge of the room (the run gait); the household turns to look
//    2.6  the household walks to him and bunches up (the group hug), hearts rise, a "Welcome!" pill fades out
//    3.4  done: he is a housemate like any other (the old `guestArriving` settle is not used on this path)
//  `ArrivalClock` is the pure timeline (tested); `GameCare.guestArrival*` does the work; `GuestArrivalOverlay` draws the dim, the card and the pill.
//

import SwiftUI
import UIKit
import simd
import QuartzCore

nonisolated enum ArrivalTuning {
    static let card: Float = 0.6, build: Float = 1.1, runIn: Float = 1.8, hug: Float = 2.6, done: Float = 3.4
    static let dim = 0.25, dimFade = 0.3
    static let welcomeLife = 1.2
    static let happyHold: Float = 2
    /// The hug is retried this long (seconds) for a guest still running before it falls back to the plain greeting.
    static let hugWait: Float = 0.7
}

nonisolated enum ArrivalEvent: Equatable, Sendable { case doorbell, showCard, build, hideCard, runIn, hug, finished }

/// The timeline of one arrival (no engine, no clock of its own): `advance` returns the events whose time has come.
nonisolated struct ArrivalClock: Sendable {
    static let schedule: [(at: Float, event: ArrivalEvent)] = [
        (0, .doorbell), (ArrivalTuning.card, .showCard), (ArrivalTuning.build, .build),
        (ArrivalTuning.runIn, .hideCard), (ArrivalTuning.runIn, .runIn), (ArrivalTuning.hug, .hug), (ArrivalTuning.done, .finished),
    ]
    private(set) var t: Float = 0
    private(set) var active = false
    private var next = 0

    /// False = an arrival is already running (a second one is ignored).
    @discardableResult
    mutating func start() -> Bool {
        guard !active else { return false }
        active = true; t = 0; next = 0
        return true
    }
    mutating func advance(_ dt: Float) -> [ArrivalEvent] {
        guard active else { return [] }
        t += dt
        var out = [ArrivalEvent]()
        while next < Self.schedule.count, Self.schedule[next].at <= t {
            out.append(Self.schedule[next].event); next += 1
        }
        if out.last == .finished { active = false }
        return out
    }
    mutating func cancel() { active = false; t = 0; next = 0 }
}

enum ArrivalCardStage: Equatable { case hidden, hello, building }

// MARK: the work

extension GameCare {
    /// Starts the moment (the knock is answered). False = one is running already.
    @discardableResult
    func guestArrivalBegin() -> Bool {
        guestBook.arrival.start()
    }

    /// Cancels it (an outing, a failed body): the card and the dim go; the guest, if made, is left to the usual rules.
    func guestArrivalCancel() {
        let g = guestBook
        g.arrival.cancel()
        g.arrivalCard = .hidden; g.arrivalDim = false; g.hugWait = nil
        if let b = g.actor?.brain { b.hurry = false; b.autonomy = true }
    }

    /// One fixed step of the arrival. Returns false when it ended (cancelled by a failed body).
    func guestArrivalStep(_ actors: [JellyActor], _ v: ParkVisitor, _ visit: GuestVisit, dt: Float) {
        let g = guestBook
        if g.arrival.active {
            let t0 = g.arrival.t
            for e in g.arrival.advance(dt) { guestArrivalEvent(e, actors, v, visit) }
            if Int(g.arrival.t * 10) != Int(t0 * 10) { NSLog("[arrival] t=%.1f", Float(Int(g.arrival.t * 10)) / 10) }          // (capture aid: nominal time per 0.1 s)
        }
        if let w = g.hugWait, let a = g.actor, let b = a.brain {
            let left = w - dt
            // the huddle starts the moment he is free (arrived and idle); a guest still running when the wait ends gets the plain walk-over instead
            let grouped = b.socialFree && guestArrivalGroup(actors, b)
            if grouped || left <= 0 || !g.arrival.active {
                g.hugWait = nil
                if !grouped { guestArrivalGather(actors, a, b) }
            } else { g.hugWait = left }
        }
    }

    private func guestArrivalEvent(_ e: ArrivalEvent, _ actors: [JellyActor], _ v: ParkVisitor, _ visit: GuestVisit) {
        let g = guestBook
        switch e {
        case .doorbell:
            AudioHub.shared.play(.doorbell)
            NSLog("[arrival] doorbell")
        case .showCard:
            g.arrivalName = v.name
            g.arrivalDim = true
            g.arrivalCard = .hello
        case .build:
            g.arrivalCard = .building
            // the body is made now, behind the card (the 4th actor, its GPU slot, the first limb tick), off the left edge of the room
            guestSpawn(actors, v, visit, overdue: false, arrival: true)
            if g.actor == nil { guestArrivalCancel() }
        case .hideCard:
            g.arrivalCard = .hidden; g.arrivalDim = false
        case .runIn:
            guard let a = g.actor, let b = a.brain else { return }
            let target = g.arrivalTarget ?? guestSpotNear(actors)
            b.hurry = true
            b.requestNow(.goTo(target))
            AudioHub.shared.chirp(jelly: a.id, .babble)
            // the household turns to look
            for r in actors {
                guard let rb = r.brain, !rb.isSleeping, rb.commandedIdle == nil, !rb.commanded else { continue }
                _ = rb.beginLook(at: b.position, hold: 0.9, resume: nil, face: .excited, kind: .watch)
            }
        case .hug:
            g.hugWait = ArrivalTuning.hugWait
            if let a = g.actor, let b = a.brain { guestArrivalCheer(actors, a, b) }
        case .finished:
            g.arrivalCard = .hidden; g.arrivalDim = false
            if let b = g.actor?.brain { b.autonomy = true; b.hurry = false }
            if g.hugWait != nil, let a = g.actor { g.hugWait = nil; if let b = a.brain { guestArrivalGather(actors, a, b) } }
        }
    }

    /// The cheer at the hug's moment: happy faces, hearts, the "Welcome!" pill.
    private func guestArrivalCheer(_ actors: [JellyActor], _ a: JellyActor, _ b: BlobBrain) {
        let g = guestBook
        g.phase = .here; g.phaseT = 0; g.greeted = true
        b.autonomy = true
        b.face(.happy, hold: ArrivalTuning.happyHold)
        for r in actors { r.brain?.face(.happy, hold: ArrivalTuning.happyHold) }
        let now = CACurrentMediaTime()
        touchPlay?.spawnHeart(now: now)
        for r in actors where r.id != 0 { bubbleHub.spawnHeart(for: r.id, now: now) }
        AudioHub.shared.chirp(jelly: a.id, .happy)
        g.welcomeAt = now
    }

    /// The group hug (the household walks to him and bunches up). False = not possible just now (fewer than three free, or he is still running).
    private func guestArrivalGroup(_ actors: [JellyActor], _ b: BlobBrain) -> Bool {
        let home = actors.compactMap(\.brain).filter { !$0.isSleeping }
        guard home.count >= 2, let starter = home.first(where: { $0.socialFree }), let sa = actors.first(where: { $0.brain === starter }) else { return false }
        return starter.socialStartGroup(.groupHug, with: home.filter { $0 !== starter } + [b], sa.sim)
    }

    /// No group hug (a household of one, or somebody busy): the Jelbies walk over to him and a few hop.
    private func guestArrivalGather(_ actors: [JellyActor], _ a: JellyActor, _ b: BlobBrain) {
        b.startHopPlay(sim: a.sim, distance: 0.0001)
        var sent = 0
        for r in actors {
            guard let rb = r.brain, !rb.isSleeping, rb.commandedIdle == nil, !rb.commanded else { continue }
            let toward = rb.position + (b.position - rb.position) * 0.7
            let spot = rb.fixed(toward)
            if simd_distance(spot, b.position) > 1.0 { rb.requestNow(.goTo(spot)); sent += 1 }
        }
    }

    /// Off the left edge of the room, at the depth of the spot he runs to (just past the screen's side, never past the invisible round wall).
    func guestArrivalEntry(toward target: SIMD2<Float>) -> SIMD2<Float> {
        let aspect = GameCamera.aspect
        let hw = GameCamera.visibleHalfWidthAtBody(z: target.y, aspect: aspect)
        let c = GameCamera.arenaCenter, r = GameCamera.arenaRadius
        let dz = target.y - c.y
        let wallX = c.x - sqrt(max(r * r - dz * dz, 0.25)) + 0.25
        return SIMD2(max(-(hw + 0.8), wallX), target.y)
    }
}

// MARK: the overlay (dim, card, pill)

struct GuestArrivalOverlay: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    private var calm: Bool { A11ySettings.shared.reduceMotion }

    var body: some View {
        let g = care.guestBook
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack(alignment: .top) {
                Color.black.opacity(g.arrivalDim ? ArrivalTuning.dim : 0).ignoresSafeArea()
                    .animation(.easeInOut(duration: ArrivalTuning.dimFade), value: g.arrivalDim)
                if g.arrivalCard != .hidden {
                    ArrivalCard(name: g.arrivalName, building: g.arrivalCard == .building, landscape: landscape, calm: calm)
                        .frame(width: landscape ? min(max(geo.size.width * 0.46, 330), 440) : min(geo.size.width * 0.85, 460))
                        .padding(.top, landscape ? 8 : max(geo.safeAreaInsets.top - 6, 8))
                        .transition(calm ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                WelcomePill(care: care).allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(calm ? .easeInOut(duration: 0.25) : .spring(response: 0.42, dampingFraction: 0.82), value: g.arrivalCard)
        }
        .allowsHitTesting(false)
        .onChange(of: g.arrivalCard) { _, c in
            if c == .hello { UIAccessibility.post(notification: .announcement, argument: "\(g.arrivalName) is here") }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guest-arrival")
    }
}

/// The cream card: a door on a warm circle, "Ding dong!" and "<name> is here"; later a divider, three dots and "getting the room ready...".
struct ArrivalCard: View {
    let name: String
    let building: Bool
    let landscape: Bool
    let calm: Bool
    private let brown = Color(red: 74 / 255, green: 46 / 255, blue: 30 / 255)
    private let brown2 = Color(red: 110 / 255, green: 80 / 255, blue: 60 / 255)

    var body: some View {
        let k: CGFloat = landscape ? 0.86 : 1
        VStack(spacing: 0) {
            HStack(spacing: 18 * k) {
                ZStack {
                    Circle().fill(building ? Color(red: 1, green: 226 / 255, blue: 160 / 255) : Color(red: 236 / 255, green: 222 / 255, blue: 200 / 255))
                        .frame(width: 64 * k, height: 64 * k)
                    DoorGlyph(open: building, ink: brown).frame(width: 25 * k, height: 40 * k)
                    if !building { SoundArcs(radius: 33 * k, ink: brown2) }
                }
                .frame(width: 64 * k, height: 64 * k)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ding dong!").font(SK.font(24 * k, .bold)).foregroundStyle(brown)
                    Text("\(name) is here").font(SK.font(18 * k, .regular)).foregroundStyle(brown2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20 * k).padding(.top, 15 * k).padding(.bottom, 15 * k)
            if building {
                Rectangle().fill(brown.opacity(0.16)).frame(height: 1.3).padding(.horizontal, 20 * k)
                HStack {
                    ThreeDots(ink: brown, calm: calm)
                    Spacer(minLength: 8)
                    Text("getting the room ready\u{2026}").font(SK.font(15 * k, .regular)).foregroundStyle(brown2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 28 * k).padding(.vertical, 12 * k)
                .transition(.opacity)
            }
        }
        .background(RoundedRectangle(cornerRadius: (landscape ? 22 : 30), style: .continuous).fill(SK.cream)
            .shadow(color: Color(red: 60 / 255, green: 35 / 255, blue: 20 / 255).opacity(0.28), radius: 10, y: 4))
        .animation(.easeInOut(duration: 0.25), value: building)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(building ? "\(name) is here. Getting the room ready." : "Ding dong! \(name) is here.")
        .accessibilityIdentifier("arrival-card")
    }
}

private struct ThreeDots: View {
    let ink: Color
    let calm: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { t in
            let i = calm ? 1 : Int(t.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { k in Circle().fill(ink.opacity(k == i ? 1 : 0.35)).frame(width: 8, height: 8) }
            }
        }
    }
}

/// A door: a rounded frame, a panel, a knob; open = a warm fill with the door leaf swung in.
private struct DoorGlyph: View {
    let open: Bool
    let ink: Color
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, lw = h * 0.09
            ZStack {
                if open {
                    RoundedRectangle(cornerRadius: h * 0.12, style: .continuous).fill(Color(red: 1, green: 214 / 255, blue: 130 / 255))
                    Path { p in
                        p.move(to: CGPoint(x: w * 0.05, y: h * 0.06)); p.addLine(to: CGPoint(x: w * 0.46, y: h * 0.16))
                        p.addLine(to: CGPoint(x: w * 0.46, y: h * 0.90)); p.addLine(to: CGPoint(x: w * 0.05, y: h * 0.98)); p.closeSubpath()
                    }.fill(ink)
                    RoundedRectangle(cornerRadius: h * 0.12, style: .continuous).strokeBorder(ink, lineWidth: lw)
                } else {
                    RoundedRectangle(cornerRadius: h * 0.12, style: .continuous).strokeBorder(ink, lineWidth: lw)
                    RoundedRectangle(cornerRadius: h * 0.05, style: .continuous).strokeBorder(ink, lineWidth: h * 0.05)
                        .frame(width: w * 0.6, height: h * 0.3).position(x: w / 2, y: h * 0.29)
                    Circle().fill(ink).frame(width: w * 0.12, height: w * 0.12).position(x: w * 0.76, y: h * 0.57)
                }
            }
        }
    }
}

/// Two sound arcs on each side of the door.
private struct SoundArcs: View {
    let radius: CGFloat
    let ink: Color
    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                let r = radius + CGFloat(i) * 9
                ArcShape(r: r, right: true).stroke(ink.opacity(1 - Double(i) * 0.28), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                ArcShape(r: r, right: false).stroke(ink.opacity(1 - Double(i) * 0.28), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .frame(width: radius * 2 + 40, height: radius * 2 + 40)
    }
    private struct ArcShape: SwiftUI.Shape {
        let r: CGFloat, right: Bool
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let c = CGPoint(x: rect.midX, y: rect.midY)
            p.addArc(center: c, radius: r, startAngle: .degrees(right ? -35 : 145), endAngle: .degrees(right ? 35 : 215), clockwise: false)
            return p
        }
    }
}

/// A translucent "Welcome!" over the huddle that fades out after 1.2 s.
private struct WelcomePill: View {
    let care: GameCare
    var body: some View {
        let g = care.guestBook
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { t in
            GeometryReader { geo in
                let age = g.welcomeAt > 0 ? CACurrentMediaTime() - g.welcomeAt : 99
                if age >= 0, age < ArrivalTuning.welcomeLife, let a = g.actor {
                    let c = a.sim.centroid()
                    if let p = ThoughtBubbleView.project(SIMD3(c.x, c.y + Float(BlobShape.H) * 1.9, c.z), size: geo.size, focus: care.focus.blend) {
                        let fade = age < 0.15 ? age / 0.15 : max(0, 1 - (age - 0.15) / (ArrivalTuning.welcomeLife - 0.15))
                        Text("Welcome!")
                            .font(SK.font(17, .semibold)).foregroundStyle(Color(red: 74 / 255, green: 46 / 255, blue: 30 / 255))
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Capsule().fill(SK.cream.opacity(0.85)))
                            .opacity(fade)
                            .position(x: p.x, y: p.y)
                            .accessibilityHidden(true)
                    }
                }
                let _ = t.date
            }
        }
    }
}
