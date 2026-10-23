//
//  JelbieAccessibility.swift
//  The Jelbies as accessibility elements (round-1023 a11y). In the game the Metal view is a CONTAINER: [the room] + one element per Jelbie in the room.
//  Each Jelbie has a name + feature label (never just a colour), a value (where he is, mood, what he wants, what he is doing), a selected trait
//  while highlighted, a frame that follows his body, and custom actions routed to the existing care APIs (JelbieActions.swift).
//  Everything is lazy: no work at all unless VoiceOver / Switch Control / Voice Control (or a test) is asking.
//

import UIKit

/// What a Jelbie is doing, for the spoken value.
nonisolated enum JelbieActivity: String, Sendable {
    case asleep, eating, drinking, walking, playing, doingTrick, sitting, waving, coming, beingPetted, gettingUp, standing, beingWashed
    var phrase: String {
        switch self {
        case .asleep: return "Asleep"
        case .eating: return "Eating"
        case .drinking: return "Drinking"
        case .walking: return "Walking"
        case .playing: return "Playing"
        case .doingTrick: return "Doing a trick"
        case .sitting: return "Sitting"
        case .waving: return "Waving"
        case .coming: return "Coming over"
        case .beingPetted: return "Being petted"
        case .gettingUp: return "Getting up"
        case .standing: return "Standing"
        case .beingWashed: return "Being washed"
        }
    }
}

/// The words, with no UIKit (unit tested).
nonisolated enum JelbieA11yText {
    struct State: Sendable {
        var xFraction: Double = 0.5          // the body's centre across the screen, 0 left ... 1 right
        var front = true                     // on the near half of the floor
        var mood: BlobMood = .happy
        var wanting: [String] = []           // tier words of the needs he wants ("Hungry", "Lonely")
        var dirty = false
        var activity: JelbieActivity = .standing
        var highlighted = false
        var inCloseUp = false
    }

    /// "Pip, yellow with soft spines": the name and the feature, so no Jelbie is told apart by colour alone.
    static func label(name: String, character: Int) -> String {
        "\(name), \(description(character: character))"
    }
    static func description(character: Int) -> String {
        switch JellyRoster.feature(character) {
        case .none: return "blue and plain"
        case .spines: return "yellow with soft spines"
        case .daisy: return "green with a daisy on his head"
        case .wings: return "lavender with little wings"
        }
    }
    static func column(_ x: Double) -> String { x < 1.0 / 3 ? "Left" : x > 2.0 / 3 ? "Right" : "Middle" }

    static func value(_ s: State) -> String {
        var parts = ["\(column(s.xFraction)), \(s.front ? "front" : "back")", s.mood.word]
        parts.append(s.wanting.isEmpty ? "Needs are fine" : s.wanting.joined(separator: ", "))
        if s.dirty { parts.append("Coat is dirty") }
        parts.append(s.activity.phrase)
        if s.inCloseUp { parts.append("In close-up") }
        if s.highlighted { parts.append("Highlighted") }
        return parts.joined(separator: ". ") + "."
    }

    /// "Living room. Day. 3 Jelbies: Pip on the left, Moss in the middle, Lavender on the right."
    static func room(phase: String, placed: [(name: String, x: Double)]) -> String {
        guard !placed.isEmpty else { return "\(phase). No Jelbies in the room" }
        let who = placed.sorted { $0.x < $1.x }.map { "\($0.name) on the \(column($0.x).lowercased())" }.joined(separator: ", ")
        return "\(phase). \(placed.count) Jelbie\(placed.count == 1 ? "" : "s"): \(who)"
    }
}

/// Is an assistive technology that needs the elements running (or a test forcing it)?
@MainActor
enum A11yAssist {
    static var force = false
    static var active: Bool { force || UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning || UIAccessibility.isVoiceOverRunning }
}

final class JelbieAXElement: UIAccessibilityElement {
    let jellyID: Int
    private unowned let hub: JelbieA11yContainer
    init(id: Int, hub: JelbieA11yContainer, container: Any) {
        jellyID = id; self.hub = hub
        super.init(accessibilityContainer: container)
        accessibilityIdentifier = "jelbie-\(id)"
    }
    override var isAccessibilityElement: Bool { get { true } set {} }
    override var accessibilityLabel: String? { get { MainActor.assumeIsolated { hub.label(jellyID) } } set {} }
    override var accessibilityValue: String? { get { MainActor.assumeIsolated { hub.value(jellyID) } } set {} }
    override var accessibilityHint: String? { get { MainActor.assumeIsolated { hub.hint(jellyID) } } set {} }
    override var accessibilityTraits: UIAccessibilityTraits {
        get { MainActor.assumeIsolated { hub.isHighlighted(jellyID) } ? [.button, .selected] : .button }
        set {}
    }
    override var accessibilityFrameInContainerSpace: CGRect {
        get { MainActor.assumeIsolated { hub.rect(jellyID) } }
        set {}
    }
    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get { MainActor.assumeIsolated { hub.customActions(jellyID) } }
        set {}
    }
    override func accessibilityActivate() -> Bool { MainActor.assumeIsolated { hub.activate(jellyID) } }
}

final class RoomAXElement: UIAccessibilityElement {
    private unowned let hub: JelbieA11yContainer
    init(hub: JelbieA11yContainer, container: Any) {
        self.hub = hub
        super.init(accessibilityContainer: container)
        accessibilityIdentifier = "room"
    }
    override var isAccessibilityElement: Bool { get { true } set {} }
    override var accessibilityLabel: String? { get { "Living room" } set {} }
    override var accessibilityValue: String? { get { MainActor.assumeIsolated { hub.roomValue() } } set {} }
    override var accessibilityTraits: UIAccessibilityTraits { get { .staticText } set {} }
    override var accessibilityFrameInContainerSpace: CGRect { get { MainActor.assumeIsolated { hub.bounds } } set {} }
    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get { MainActor.assumeIsolated { hub.roomActions() } }
        set {}
    }
}

/// Owns the elements of one game stage. Held by `MelonController`.
@MainActor
final class JelbieA11yContainer {
    weak var controller: MelonController?
    weak var view: UIView?
    private var elements: [Int: JelbieAXElement] = [:]
    private var room: RoomAXElement?
    private var lastKey = ""
    private var rects: [Int: (rect: CGRect, at: Double)] = [:]
    private var lastTick = 0.0

    var bounds: CGRect { view?.bounds ?? .zero }
    private var care: GameCare? { controller?.model.care }

    nonisolated init() {}
    nonisolated deinit {}

    // MARK: which Jelbies are in the room right now

    /// The ids with an element: everyone who is in the room (not away at the track / show); in the bath only the one being washed.
    var presentIDs: [Int] {
        guard let c = controller, let care else { return [] }
        if care.tripActive { return [] }
        if care.bath.active { return c.a11yWasherID.map { [$0] } ?? [] }
        return c.actors.filter { $0.brain != nil }.map(\.id)
    }

    /// The accessibilityElements of the stage view (rebuilt cheaply; the element objects persist per Jelbie so VoiceOver focus is stable).
    func allElements() -> [Any] {
        guard let view else { return [] }
        let r = room ?? RoomAXElement(hub: self, container: view)
        room = r
        var out: [Any] = [r]
        for id in presentIDs {
            let e = elements[id] ?? JelbieAXElement(id: id, hub: self, container: view)
            elements[id] = e
            out.append(e)
        }
        return out
    }

    /// A few times a second while an assistive technology runs: the layout notification when the SET of elements changes, the announcer.
    func tick(now: Double) {
        guard now - lastTick > 0.25 else { return }
        lastTick = now
        care?.a11yEvents.poll(now: now)
        let key = presentIDs.map(String.init).joined(separator: ",") + (care.map { $0.focus.isActive ? "|c\($0.focusGroup.ids)" : "" } ?? "")
        if key != lastKey {
            let first = lastKey.isEmpty
            lastKey = key
            if !first { UIAccessibility.post(notification: .layoutChanged, argument: nil) }
        }
    }

    // MARK: reads

    private func profile(_ id: Int) -> JellyProfile? { care?.jelly(id) }

    func label(_ id: Int) -> String {
        guard let p = profile(id) else { return "Jelbie" }
        return JelbieA11yText.label(name: p.name, character: p.character)
    }

    func isHighlighted(_ id: Int) -> Bool { care?.highlightedJelly == id }

    func state(_ id: Int) -> JelbieA11yText.State {
        var s = JelbieA11yText.State()
        guard let care, let p = profile(id) else { return s }
        let r = rect(id)
        s.xFraction = bounds.width > 1 ? Double(r.midX / bounds.width) : 0.5
        let brain = care.selectBrain(id) ?? controller?.actors.first { $0.id == id }?.brain
        if let b = brain { s.front = Double(b.pz) > Double(RoomLayout.minZ + RoomLayout.maxZ) / 2 }
        s.mood = p.needs.mood
        s.wanting = NeedKind.allCases.filter { p.needs.isWanting($0) }.map { p.needs.tier($0).word($0) }
        let coat = care.coat(for: id)
        s.dirty = coat == .dirty || coat == .filthy
        s.activity = Self.activity(of: brain, washing: care.bath.active && controller?.a11yWasherID == id)
        s.highlighted = isHighlighted(id)
        s.inCloseUp = care.focus.isActive && care.focusGroup.ids.contains(id)
        return s
    }

    static func activity(of b: BlobBrain?, washing: Bool = false) -> JelbieActivity {
        if washing { return .beingWashed }
        guard let b else { return .standing }
        if b.isSleeping { return .asleep }
        switch b.activity {
        case .eating: return .eating
        case .drinking: return .drinking
        case .walking, .turning: return .walking
        case .playing: return .playing
        case .waving: return .waving
        case .coming: return .coming
        case .touched: return .beingPetted
        case .recovering: return .gettingUp
        default: break
        }
        switch b.idleState.kind {
        case .sit?, .decorSit?: return .sitting
        case .wander?, .look?, nil: return .standing
        case .sleep?: return .asleep
        default: return .doingTrick
        }
    }

    func value(_ id: Int) -> String { JelbieA11yText.value(state(id)) }

    func hint(_ id: Int) -> String? {
        guard let care else { return nil }
        if care.focus.isActive { return "Swipe up or down for actions like pet, pat and boop" }
        return "Double tap to highlight. Swipe up or down for actions like feed and call over"
    }

    func roomValue() -> String {
        guard let care else { return "" }
        let placed = presentIDs.compactMap { id -> (String, Double)? in
            guard let p = profile(id) else { return nil }
            let r = rect(id)
            return (p.name, bounds.width > 1 ? Double(r.midX / bounds.width) : 0.5)
        }
        return JelbieA11yText.room(phase: DayClock.shared.phase.rawValue.capitalized, placed: placed)
    }

    /// The body's box in the view's space (cached for a quarter second; a sensible fallback column while the camera is not up).
    func rect(_ id: Int) -> CGRect {
        let now = CACurrentMediaTime()
        if let c = rects[id], now - c.at < 0.25 { return c.rect }
        var r = controller?.a11yScreenRect(of: id, size: bounds.size)
        if r == nil || r!.isEmpty {
            let n = max(presentIDs.count, 1), k = presentIDs.firstIndex(of: id) ?? 0
            let w = bounds.width / CGFloat(n)
            r = CGRect(x: w * CGFloat(k), y: bounds.height * 0.35, width: w, height: bounds.height * 0.3)
        }
        let out = r!.insetBy(dx: -6, dy: -6).intersection(bounds.isEmpty ? r! : bounds)
        rects[id] = (out, now)
        return out
    }

    // MARK: actions

    func activate(_ id: Int) -> Bool {
        guard let care else { return false }
        if care.focus.isFocused { return perform(.pet, id) }
        return perform(.highlight, id)
    }

    func asleep(_ id: Int) -> Bool { care?.selectBrain(id)?.isSleeping ?? false }

    @discardableResult
    func perform(_ a: JelbieAction, _ id: Int) -> Bool {
        guard let care else { return false }
        return JelbieActions.perform(a, id: id, care: care, asleep: asleep(id)) { [weak self] kind, jelly in self?.controller?.startScripted(kind, jelly: jelly) ?? false }
    }

    func customActions(_ id: Int) -> [UIAccessibilityCustomAction] {
        guard let care, let name = profile(id)?.name else { return [] }
        return JelbieActions.available(care, id: id, asleep: asleep(id)).map { a in
            UIAccessibilityCustomAction(name: a.title(name)) { [weak self] _ in self?.perform(a, id) ?? false }
        }
    }

    func roomActions() -> [UIAccessibilityCustomAction] {
        guard let care, JelbieActions.busyReason(care) == nil, !care.focus.isActive else { return [] }
        var out: [UIAccessibilityCustomAction] = []
        out.append(UIAccessibilityCustomAction(name: "Everyone come here") { [weak care] _ in care?.comeHereEveryone(); return care != nil })
        out.append(UIAccessibilityCustomAction(name: "Bedtime for everyone") { [weak care] _ in
            guard let care else { return false }
            guard care.canBedtime else { A11yAnnounce.say("Bedtime is not possible right now", priority: .high); return false }
            care.bedtimeAll(); return true
        })
        out.append(UIAccessibilityCustomAction(name: "Open the curtains for the next time of day") { _ in DayClock.shared.skipToNextPhase(); return true })
        return out
    }

    // MARK: rotors

    func rotors() -> [UIAccessibilityCustomRotor] {
        [makeRotor("Jelbies") { _ in true }, makeRotor("Needs attention") { [weak self] id in !(self?.profile(id)?.needs.wantingCount == 0) }]
    }

    private func makeRotor(_ name: String, include: @escaping (Int) -> Bool) -> UIAccessibilityCustomRotor {
        UIAccessibilityCustomRotor(name: name) { [weak self] predicate in
            guard let self else { return nil }
            let ids = self.presentIDs.filter(include)
            guard !ids.isEmpty else { return nil }
            let current = (predicate.currentItem.targetElement as? JelbieAXElement)?.jellyID
            let forward = predicate.searchDirection == .next
            let idx: Int
            if let c = current, let i = ids.firstIndex(of: c) { idx = forward ? i + 1 : i - 1 } else { idx = forward ? 0 : ids.count - 1 }
            guard ids.indices.contains(idx), let e = self.elements[ids[idx]] else { return nil }
            return UIAccessibilityCustomRotorItemResult(targetElement: e, targetRange: nil)
        }
    }
}
