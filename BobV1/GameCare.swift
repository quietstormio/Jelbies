//
//  GameCare.swift
//  Care actions of the game screen (feed / drink / call / wave). The SwiftUI menu calls feed(_:) / drink(_:) / call();
//  the stage controller calls tick() once per fixed sim step, which talks to Bob's brain and pops the meal TRAY in and out.
//
//  A meal: Feed / Drink -> a short little tray pops in (puff) at the front spot with the chosen food or bottle -> he walks to his place,
//  turns, eats (berries by hand, cake with a fork) or sips (his own straw), a happy finish -> the tray poofs away. One tray at a time.
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

    // Not isolated: Swift 6.2's implicit isolated deinit (swift_task_deinitOnExecutor) aborts on the iOS 26.2 runtime; see MelonModel.
    nonisolated deinit {}

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
    }

    /// Floor obstacle for the brain's resolver: pushes a point out of the tray.
    /// Sipping stands `sipCloser` nearer the tray (his mouth only reaches a straw tip that close); his belly may overlap the tray's rim by that much.
    static let sipCloser: Float = 0.08
    /// Eating stands a little FARTHER back than the layout's stand (negative = away from the tray): measured, the berries are reached with less miss.
    static let eatCloser: Float = -0.03
    func obstacle(_ p: SIMD3<Float>, radius: Float) -> SIMD3<Float> { dining.obstacle(p, radius: radius * RoomLayout.lowPropRadiusScale) }
    /// The footprint the brain's resolver uses while a drink is out is a little smaller (the room's own tray collider is in `base`).
    private func footprint(_ r: Float) -> Float { r - (servingKind == .drink ? Self.sipCloser * 1.5 : 0) }

    /// The brain's dining hooks wired to a tray (the same wiring the tests use).
    static func hooks(for c: Consumable, tray d: DiningSet) -> BlobBrain.DineHooks {
        var h = BlobBrain.DineHooks(
            piece: { _ in d.pieceAnchorWorld(place: 0, index: d.nextPiece(place: 0)) },
            begin: { d.beginBite(place: 0) },
            finish: { d.finishBite(place: 0) },
            cancel: { d.cancelBite(place: 0); d.release(.piece, place: 0) },
            hold: { m in d.hold(.piece, place: 0, transform: m) })
        switch c.eatStyle {
        case .finger: break
        case .fork:
            h.fork = true
            h.piece = { _ in d.cakeBitePoint(place: 0) }
            h.cancel = { d.cancelBite(place: 0); d.poofFork(place: 0) }
            h.forkAppear = { p in d.appearFork(place: 0, at: p) }
            h.holdFork = { m in d.hold(.fork, place: 0, transform: m) }
            h.releaseFork = { d.poofFork(place: 0) }
            h.launch = { d.launchBite(place: 0) }
            h.holdBite = { m in d.hold(.bite, place: 0, transform: m) }
        case .sip:
            h.straw = { d.strawTip(place: 0) ?? .zero }
            h.level = { f in d.setDrunk(place: 0, f) }
        }
        return h
    }

    private func mealRequest(_ c: Consumable) -> BlobRequest {
        var place = dining.places[0]
        switch c.eatStyle {
        case .sip:
            place.stand += SIMD2(sinf(place.yaw), cosf(place.yaw)) * Self.sipCloser
            let left = Int(((1 - dining.drunk[0]) * Float(DiningTiming.gulpsPerDrink)).rounded(.up))
            return .sip(place: place, gulps: max(left, 1))
        default:
            place.stand += SIMD2(sinf(place.yaw), cosf(place.yaw)) * Self.eatCloser
            return .dine(place: place, bites: max(dining.bitesLeft[0] + (dining.forkBite[0] ? 1 : 0), 1))
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

    private func endMeal() {
        dining.despawn()
        meal = nil; mealRequested = false; retries = 0; idleT = 0
    }

    /// After the frame's last sim step: what he holds goes back onto his nub for the pose the body has now, and the tray mesh is refreshed.
    func refreshHeld(brain: BlobBrain, sim: SoftBody, renderer: MelonRenderer?) {
        guard meal != nil else { return }
        brain.refreshHeld(sim: sim)
        if let room = renderer?.room, let f = dining.frame(theme: room.theme) { room.setDining(f) }
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
            case .dine, .sip:
                if let m = meal {                    // a finished meal (not a dropped one) restores the need
                    needs.restore(m.kind == .food ? .hunger : .thirst)
                    endMeal()
                }
            default: break
            }
        }
        finished.removeAll()

        // one-shot requests (a Call drops the meal first so the tray poofs and the held piece goes with it)
        if let r = queued.first {
            queued.removeFirst()
            if case .come = r, meal != nil { endMeal() }
            brain.requestNow(r)
            if case .come = r { callRunning = true }
        }

        // pop the tray in (beside Bob if he stands on the front spot) and send him to his place
        if let c = wanted, !callRunning, queued.isEmpty {
            if dining.spawn(serving: c, n: 1, bobAt: brain.position) {
                wanted = nil; meal = c; mealAge = 0; idleT = 0; retries = 0
                brain.dineHooks = Self.hooks(for: c, tray: dining)
                brain.requestNow(mealRequest(c)); mealRequested = true
            }
        }

        if let c = meal {
            mealAge += dt
            if mealAge > Self.mealTimeout { endMeal() }
            else if !callRunning, queued.isEmpty, mealRequested {
                // the request was cancelled (for example he was grabbed): ask again a couple of times, then give up
                if act == .idle || act == .lookingAround || act == .steppingInPlace {
                    idleT += dt
                    if idleT > 0.8 {
                        idleT = 0
                        if retries < 2 { retries += 1; brain.dineHooks = Self.hooks(for: c, tray: dining); brain.requestNow(mealRequest(c)) }
                        else { endMeal() }
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
    }
}
