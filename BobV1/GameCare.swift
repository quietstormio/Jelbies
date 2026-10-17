//
//  GameCare.swift
//  Care actions of the game screen (feed / drink / call / wave). The SwiftUI menu calls feed(_:) / drink(_:) / call();
//  the stage controller calls tick() once per fixed sim step, which talks to Bob's brain and pops the meal TRAY in and out.
//
//  A meal: Feed / Drink -> a short little tray pops in (puff) at the front spot with the chosen food or bottle -> he walks to his place,
//  turns, eats (berries or pizza by hand) or sips (his own straw), a happy finish -> the tray poofs away. One tray at a time.
//

import Foundation
import Observation
import simd

@MainActor
@Observable
final class GameCare {
    /// A tray is out (or about to be): Feed and Drink are disabled until it has poofed away.
    private(set) var trayOut = false
    /// Mirrors the brain's activity for the menu / tests.
    private(set) var busy = false
    var foodOut: Bool { trayOut && servingKind == .food }
    var waterOut: Bool { trayOut && servingKind == .drink }
    /// True while a tray is out (the debug script waits on it).
    var bowlOut: Bool { trayOut }
    private(set) var servingKind: ConsumableKind?

    @ObservationIgnored private var queued: [BlobRequest] = []      // one-shot brain requests (wave / come)
    @ObservationIgnored private var hooked = false
    @ObservationIgnored private var callRunning = false
    @ObservationIgnored private var finished: [BlobRequest] = []
    @ObservationIgnored private var wanted: Consumable?             // picked, the tray not out yet
    @ObservationIgnored private var meal: Consumable?               // the tray is out and he is working on it
    @ObservationIgnored private var mealAge: Float = 0
    @ObservationIgnored private var idleT: Float = 0
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var mealRequested = false
    /// The walk to the stand before the tray pops in (see `serveWanted`).
    @ObservationIgnored private var standRequested = false
    @ObservationIgnored private var standIdle: Float = 0
    @ObservationIgnored private var standSettle: Float = 0
    @ObservationIgnored private var standRetries = 0
    @ObservationIgnored private var wantedAge: Float = 0
    @ObservationIgnored private var wantedOrigin: SIMD2<Float>?

    /// The meal tray (one shared serving scaled for N Blobs; drinks come with a straw per Blob).
    let dining = DiningSet()
    /// Focus mode (Come here): phase, dock selection and the camera spring. See TouchMode.swift.
    let focus = BlobFocus()
    /// Multi-Blob select (outline highlight, confirm chip). One Blob in the game for now: the action button is then always visible.
    let select = BlobSelect()
    @ObservationIgnored private var approachIdle: Float = 0
    @ObservationIgnored private var approachRetries = 0
    @ObservationIgnored private var savedAutonomy = true
    @ObservationIgnored private var wantHop = false
    @ObservationIgnored private var afterRelease: Consumable?        // Feed / Drink asked inside focus: release first, then the tray flow
    /// Needs + mood (hunger / thirst / attention). `needs.mood` and `needs.wantedNeed` are what the touch reactions read.
    let needs = BlobNeeds()
    var mood: BlobMood { needs.mood }
    var wantedNeed: NeedKind? { needs.wantedNeed }
    /// The need whose thought bubble is up right now (nil = none), and how the last bubble ended (the view poofs it, with a sparkle when fixed).
    private(set) var bubbleNeed: NeedKind?
    struct BubbleEnd: Equatable { var serial = 0; var need: NeedKind = .hunger; var fixed = false }
    private(set) var bubbleEnd = BubbleEnd()
    @ObservationIgnored private(set) var schedule = BubbleSchedule()
    /// The touch model, read-only: petting in focus mode restores attention (set by the screen).
    @ObservationIgnored weak var touchPlay: TouchPlay?
    /// Where the bubble anchors: the top of his head in the world (the same projection as the hearts / outline), and his floor spot for the highlight.
    @ObservationIgnored private(set) var headWorld = SIMD3<Float>(0, BlobShape.H, 1)
    @ObservationIgnored private(set) var bodyFloor = SIMD3<Float>(0, 0, 1)
    /// Other Blobs' needs (preview Blobs only, in memory); id 0 is `needs`.
    @ObservationIgnored private var otherNeeds: [Int: BlobNeeds] = [:]
    func needs(for id: Int) -> BlobNeeds {
        if id == 0 { return needs }
        if let n = otherNeeds[id] { return n }
        let n = BlobNeeds(persists: false)
        n.set(NeedKind(rawValue: id % 3) ?? .thirst, 0.2)          // stand-ins differ: Pip is thirsty, Moss wants love
        otherNeeds[id] = n
        return n
    }
    /// The food / drink the player last picked (consumable ids).
    private(set) var selectedFoodID = Consumables.berries.id
    private(set) var selectedDrinkID = Consumables.water.id
    #if DEBUG || DINING_PREVIEW
    @ObservationIgnored private var preview = DiningPreview.fromLaunchArguments()
    #endif

    /// A meal that gets nowhere (he keeps being picked up) is cleared away after this long.
    static let mealTimeout: Float = 60

    /// Voice v1: his name, tricks, listen mode and the reaction queue (VoiceCoordinator.swift). Run from `tick`.
    let voice: VoiceCoordinator

    init(voice: VoiceCoordinator? = nil) {
        let v = voice ?? VoiceCoordinator()
        self.voice = v
        v.care = self
    }

    // Not isolated: Swift 6.2's implicit isolated deinit (swift_task_deinitOnExecutor) aborts on the iOS 26.2 runtime; see MelonModel.
    nonisolated deinit {}

    /// A grumpy Bob ignored an order: the thought bubble of the need he is wanting comes up now (nothing if none).
    func showNeedBubble() { if !focus.isActive { applyBubble(schedule.showNow()) } }

    func feed() { feed(selectedFoodID) }
    func water() { drink(selectedDrinkID) }
    /// Picker entry points: pop the tray in with the chosen consumable (ignored while a tray is out).
    func feed(_ id: String) { if let c = Consumables.with(id: id), c.kind == .food { selectedFoodID = id; order(c) } }
    func drink(_ id: String) { if let c = Consumables.with(id: id), c.kind == .drink { selectedDrinkID = id; order(c) } }
    func water(_ id: String) { drink(id) }
    /// A tap on the thought bubble: opens the matching care action. Feed / Drink return the action so the screen can open the care menu on that
    /// picker; the attention bubble calls him over right here. The bubble goes away until its next turn.
    @discardableResult
    func tapBubble() -> BubbleAction? {
        guard let n = bubbleNeed else { return nil }
        let a = n.action
        if a != .comeHere, trayOut || focus.isActive { return nil }         // a meal is already on: the bubble only waits for it
        applyBubble(schedule.dismiss())
        if a == .comeHere { comeHere() }
        return a
    }
    /// The roster: tapping a card plays the outline highlight on that Blob (works with one Blob too), then the action button shows for him.
    func rosterPick(_ id: Int) {
        guard !focus.isActive else { return }
        select.highlight(id)
    }
    private func applyBubble(_ events: [BubbleSchedule.Event]) {
        for e in events {
            switch e {
            case .appeared(let n): bubbleNeed = n
            case .disappeared(let n):
                bubbleNeed = nil; bubbleEnd = BubbleEnd(serial: bubbleEnd.serial + 1, need: n, fixed: false)
            case .fixed(let n, _):
                bubbleNeed = nil; bubbleEnd = BubbleEnd(serial: bubbleEnd.serial + 1, need: n, fixed: true)
            }
        }
    }
    private func tickNeeds(brain: BlobBrain, sim: SoftBody?, dt: Float) {
        var petting = false, purring = false
        if focus.isFocused, let tp = touchPlay {
            petting = tp.contact && tp.speed > TouchPlay.strokeSpeed * 0.5
            purring = tp.isPurring
        }
        needs.step(dt: dt, petting: petting, purring: purring)
        // where his head is (for the bubble) and his floor spot (for the highlight)
        var c = SIMD3<Float>(brain.position.x, BlobShape.H * 0.5, brain.position.y)
        if let sim { c = sim.centroid() }
        bodyFloor = SIMD3(c.x, 0, c.z); select.bodyFloor = bodyFloor
        headWorld = SIMD3(c.x, c.y + BlobShape.H * 0.5, c.z)
        // a bubble is held back in focus mode and while a highlight is up; it stays while his meal for that need is on
        var pinned = false
        if let n = needs.wantedNeed, trayOut, let k = servingKind { pinned = (k == .food && n == .hunger) || (k == .drink && n == .thirst) }
        let suppressed = (focus.isActive || select.isSelecting) && !pinned
        applyBubble(schedule.update(wanted: needs.wantedNeed, dt: dt, suppressed: suppressed, pinned: pinned))
    }

    func wave() { if meal == nil, wanted == nil, !focus.isActive { queued = [.wave] } }
    /// "Come here": calls him to the front spot, then focus mode starts (camera close-up, actions dock, release button).
    /// A meal in progress is dropped first: the tray poofs, the piece he held goes with it.
    func comeHere() {
        guard focus.phase == .roaming else { return }
        select.cancel()
        focus.beginApproach()
        approachIdle = 0; approachRetries = 0
        queued = [.come(to: GameCamera.callSpot)]
    }
    /// Old name of `comeHere()` (the menu and the capture scripts).
    func call() { comeHere() }

    /// "Let Bob go": the only way out of focus mode. The camera eases out, he hops, and he resumes roaming.
    func release() {
        guard focus.phase == .focused || focus.phase == .approaching else { return }
        let wasFocused = focus.phase == .focused
        focus.release()
        if wasFocused { wantHop = true }
        else { queued.removeAll { if case .come = $0 { return true }; return false }; callRunning = false }
    }

    private func order(_ c: Consumable) {
        if focus.isActive {                          // Feed / Drink from inside focus ends focus first
            release()
            if focus.isActive { afterRelease = c; return }
        }
        guard wanted == nil, meal == nil, dining.phase == .absent else { return }
        wanted = c; servingKind = c.kind; trayOut = true
        retries = 0                                  // a fresh tap: the re-serve budget (`Self.maxReserves`) starts over
        resetStandWalk()
    }
    private func resetStandWalk() { standRequested = false; standIdle = 0; standSettle = 0; standRetries = 0; wantedAge = 0; wantedOrigin = nil }

    /// Floor obstacle for the brain's resolver: pushes a point out of the tray.
    /// Sipping stands `sipCloser` nearer the tray (his mouth only reaches a straw tip that close); his belly may overlap the tray's rim by that much.
    static let sipCloser: Float = 0.08
    /// Eating stands a little FARTHER back than the layout's stand (negative = away from the tray): measured, the berries are reached with less miss.
    static let eatCloser: Float = -0.03
    func obstacle(_ p: SIMD3<Float>, radius: Float) -> SIMD3<Float> { dining.obstacle(p, radius: radius * RoomLayout.lowPropRadiusScale) }
    /// The footprint the brain's resolver uses while a drink is out is a little smaller (the room's own tray collider is in `base`).
    private func footprint(_ r: Float) -> Float { r - (servingKind == .drink ? Self.sipCloser * 1.5 : 0) }

    /// The brain's dining hooks wired to a tray (the same wiring the tests use).
    static func hooks(for c: Consumable, tray d: DiningSet, place i: Int = 0) -> BlobBrain.DineHooks {
        var h = BlobBrain.DineHooks(
            piece: { _ in d.pieceAnchorWorld(place: i, index: d.nextPiece(place: i)) },
            begin: { d.beginBite(place: i) },
            finish: { d.finishBite(place: i) },
            cancel: { d.cancelBite(place: i); d.release(.piece, place: i) },
            hold: { m in d.hold(.piece, place: i, transform: m) })
        switch c.eatStyle {
        case .finger: break
        case .fork:
            h.fork = true
            h.piece = { _ in d.forkBitePoint(place: i) }
            h.cancel = { d.cancelBite(place: i); d.poofFork(place: i) }
            h.forkAppear = { p in d.appearFork(place: i, at: p) }
            h.holdFork = { m in d.hold(.fork, place: i, transform: m) }
            h.releaseFork = { d.poofFork(place: i) }
            h.launch = { d.launchBite(place: i) }
            h.holdBite = { m in d.hold(.bite, place: i, transform: m) }
        case .sip:
            h.straw = { d.strawTip(place: i) ?? .zero }
            h.level = { f in d.setDrunk(place: i, f) }
        }
        return h
    }

    private func mealRequest(_ c: Consumable) -> BlobRequest { Self.mealRequest(c, tray: dining, place: 0) }
    /// The brain request for place `i` of tray `d` (sip stands a little closer, eating a little farther back).
    static func mealRequest(_ c: Consumable, tray dining: DiningSet, place i: Int) -> BlobRequest {
        var place = dining.places[i]
        switch c.eatStyle {
        case .sip:
            place.stand += SIMD2(sinf(place.yaw), cosf(place.yaw)) * sipCloser
            let left = Int(((1 - dining.drunk[i]) * Float(DiningTiming.gulpsPerDrink)).rounded(.up))
            return .sip(place: place, gulps: max(left, 1))
        default:
            place.stand += SIMD2(sinf(place.yaw), cosf(place.yaw)) * eatCloser
            return .dine(place: place, bites: max(dining.bitesLeft[i] + (dining.forkBite[i] ? 1 : 0), 1))
        }
    }

    private func enterFocus(brain: BlobBrain) {
        savedAutonomy = brain.autonomy
        brain.autonomy = false                       // he stays on the front spot until released
        focus.arrive()
    }

    /// Focus bookkeeping per fixed step: a stuck walk is retried, the camera spring runs, release hops and resumes roaming.
    private func tickFocus(brain: BlobBrain, sim: SoftBody?, dt: Float) {
        switch focus.phase {
        case .approaching:
            // the come request can be cancelled (for example he was grabbed): ask again a couple of times, then give up
            let act = brain.activity
            if !callRunning, queued.isEmpty, act == .idle || act == .lookingAround || act == .steppingInPlace {
                approachIdle += dt
                if approachIdle > 0.8 {
                    approachIdle = 0
                    let d = simd_length(brain.position - GameCamera.callSpot)
                    if d < 0.5 { enterFocus(brain: brain) }
                    else if approachRetries < 2 { approachRetries += 1; queued = [.come(to: GameCamera.callSpot)] }
                    else { focus.cancelApproach() }
                }
            } else { approachIdle = 0 }
        case .leaving:
            if wantHop, let sim {
                wantHop = false
                brain.autonomy = savedAutonomy
                brain.startHopPlay(sim: sim, distance: 0.25)
            } else if wantHop, sim == nil { wantHop = false; brain.autonomy = savedAutonomy }
        default: break
        }
        if focus.step(dt: dt) {
            if let c = afterRelease { afterRelease = nil; order(c) }
        }
    }

    /// Clears the meal. Does NOT touch `retries`: a re-serve goes endMeal -> wanted -> serveWanted -> spawn, and the count has to survive that
    /// round trip or the loop is never bounded. `retries` restarts only on a fresh tap (`order`), a finished meal, or a dropped one (Come here).
    private func endMeal() {
        dining.despawn()
        meal = nil; mealRequested = false; idleT = 0
    }
    /// A meal that fails (he is displaced / his request keeps being cancelled) is served again at most this many times, then given up on.
    static let maxReserves = 2

    /// After the frame's last sim step: what he holds goes back onto his nub for the pose the body has now, and the tray mesh is refreshed.
    func refreshHeld(brain: BlobBrain, sim: SoftBody, renderer: MelonRenderer?) {
        guard meal != nil else { return }
        brain.refreshHeld(sim: sim)
        if let room = renderer?.room, let f = dining.frame(theme: room.theme) { room.setDining(f) }
    }

    /// Where he is on the floor now: the body's centroid when it is free (just put down after a grab: the brain's own position is stale until it
    /// starts its next job), else the brain's root.
    static func floorPos(_ brain: BlobBrain, _ sim: SoftBody?) -> SIMD2<Float> {
        guard let sim, brain.poseW <= 0 else { return brain.position }
        let c = sim.centroid(); return SIMD2(c.x, c.z)
    }
    /// How far past his stand line (toward the camera) he may be for the tray to pop in at once: his belly already hangs that far over the
    /// tray's back edge at the stand itself (by design), so this is "he is at, or behind, his place".
    static let popTolerance: Float = 0.03
    /// The walk-to-stand target sits this far behind the stand, so the final step forward to the stand happens with the tray already out.
    static let approachBack: Float = 0.25
    /// After a walk to the stand he stands still this long before the tray pops in.
    static let popSettle: Float = 0.45

    /// The tray never pops in where he would have to cross it. The visible floor beside the 1.56-wide tray is only ~0.2 u wide, so there is NO
    /// on-screen way around it for a body 1.4 wide: instead the tray waits until he is at (or behind) his stand line. If he is in front of
    /// it (or on the spot where it pops in) he first walks to his place with no tray out, then it pops in front of him.
    private func serveWanted(_ c: Consumable, brain: BlobBrain, here: SIMD2<Float>, act: BlobActivity, dt: Float) {
        let layout = DiningLayout.make(n: 1)
        if wantedOrigin == nil { wantedOrigin = DiningSpot.choose(bob: SIMD2(99, 99), layout: layout) }
        let origin = wantedOrigin ?? DiningSpot.preferred
        var stand = origin + layout.places[0].rel
        stand.y += c.eatStyle == .sip ? Self.sipCloser : Self.eatCloser
        wantedAge += dt
        if wantedAge > Self.mealTimeout { wanted = nil; retries = 0; resetStandWalk(); return }
        if here.y <= stand.y + Self.popTolerance {
            // he walked here because he was in front: let him come to rest first (the soft body overshoots toward the tray while it stops)
            if standRequested {
                if act == .idle || act == .lookingAround || act == .steppingInPlace { standSettle += dt } else { standSettle = 0 }
                guard standSettle >= Self.popSettle else { return }
            }
            if dining.phase == .absent, dining.spawn(serving: c, n: 1, bobAt: SIMD2(99, 99), forcedOrigin: origin) {
                wanted = nil; meal = c; mealAge = 0; idleT = 0; resetStandWalk()
                brain.dineHooks = Self.hooks(for: c, tray: dining)
                brain.requestNow(mealRequest(c)); mealRequested = true
            }
            return
        }
        // in front of his place: walk there first (the tray is not out yet, so nothing is in the way)
        let approach = SIMD2(stand.x, stand.y - Self.approachBack)
        if !standRequested {
            standRequested = true; standIdle = 0
            brain.requestNow(.goTo(approach))
        } else if act == .idle || act == .lookingAround || act == .steppingInPlace {
            standIdle += dt
            if standIdle > 0.8 {
                standIdle = 0
                if standRetries < 3 { standRetries += 1; brain.requestNow(.goTo(approach)) } else { wanted = nil; resetStandWalk() }
            }
        } else { standIdle = 0 }
    }

    func tick(brain: BlobBrain, renderer: MelonRenderer?, dt: Float, sim: SoftBody? = nil) {
        tickFocus(brain: brain, sim: sim, dt: dt)
        tickNeeds(brain: brain, sim: sim, dt: dt)
        select.tick(dt: dt)
        if let id = select.takeHopRequest(), id == 0, let sim, !focus.isActive { brain.startHopPlay(sim: sim, distance: 0.0001) }   // "he hops" (the real Blob)
        if !hooked {
            hooked = true
            brain.onFinished = { [weak self] r in self?.finished.append(r) }
            let base = brain.resolve
            brain.resolve = { [weak self] p, r in
                let rr = self?.footprint(r) ?? r
                let q = base(p, rr)
                return self?.obstacle(q, radius: rr) ?? q
            }
        }
        let act = brain.activity
        busy = act != .idle && act != .lookingAround && act != .steppingInPlace

        // finished jobs
        for r in finished {
            switch r {
            case .come:
                callRunning = false; retries = 0
                if UserDefaults.standard.integer(forKey: "GameFeedAfterCall") != 0 { feed() }          // capture aid: serve a meal once he has come
                if focus.phase == .approaching { enterFocus(brain: brain) }
            case .goTo:
                voice.goFinished()                  // a voice walk ends facing the camera
            case .dine, .sip:
                if let m = meal {                    // a finished meal (not a dropped one) restores the need
                    needs.restore(m.kind == .food ? .hunger : .thirst)
                    endMeal(); retries = 0
                }
            default: break
            }
        }
        finished.removeAll()

        // one-shot requests (a Call drops the meal first so the tray poofs and the held piece goes with it)
        if let r = queued.first {
            var isCome = false
            if case .come = r { isCome = true }
            if isCome, meal != nil { endMeal(); retries = 0 }
            if isCome, wanted != nil { wanted = nil; retries = 0; resetStandWalk() }        // a pending tray (he is still walking to his place) is dropped too
            if isCome, dining.isPresent {
                // the tray is poofing (its collider is already gone): he starts walking once it has gone, so he never walks through it
            } else {
                queued.removeFirst()
                brain.requestNow(r)
                if isCome { callRunning = true }
            }
        }

        // pop the tray in once he is at (or behind) his place; in front of it he walks there first
        if let c = wanted, !callRunning, queued.isEmpty { serveWanted(c, brain: brain, here: Self.floorPos(brain, sim), act: act, dt: dt) }

        if let c = meal {
            mealAge += dt
            if mealAge > Self.mealTimeout { endMeal(); retries = 0 }
            else if !callRunning, queued.isEmpty, mealRequested {
                // the request was cancelled (for example he was grabbed): ask again a couple of times, then give up
                if act == .idle || act == .lookingAround || act == .steppingInPlace {
                    idleT += dt
                    if idleT > 0.8 {
                        idleT = 0
                        if retries < Self.maxReserves, let st = dining.places.first?.stand, Self.floorPos(brain, sim).y > st.y + Self.popTolerance + 0.05 {
                            // dropped in front of his place (the tray is between him and it): the tray poofs, he walks back, it pops in again
                            retries += 1; endMeal(); wanted = c; resetStandWalk()
                        }
                        else if retries < Self.maxReserves { retries += 1; brain.dineHooks = Self.hooks(for: c, tray: dining); brain.requestNow(mealRequest(c)) }
                        else { endMeal(); retries = 0 }          // out of re-serves: the tray poofs, he is left at rest
                    }
                } else { idleT = 0 }
            }
        }

        #if DEBUG || DINING_PREVIEW
        preview?.tick(dining: dining, bob: brain.position, dt: dt)
        #endif
        dining.update(dt: dt)
        if let room = renderer?.room, let f = dining.frame(theme: room.theme) { room.setDining(f) }
        let out = wanted != nil || meal != nil || dining.isPresent
        if out != trayOut { trayOut = out }
        if !out, servingKind != nil { servingKind = nil }
        voice.tick(care: self, brain: brain, sim: sim, dt: dt)
    }
}
