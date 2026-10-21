//
//  CommandExecutor.swift
//  A validated JellyCommand becomes game actions: existing GameCare calls (feed / drink / clean / roster pick / the Track), the store's wardrobe
//  (`StoreBook.wear`) and the brains' existing decor interactions (`BlobBrain.commandedDecor`: sit on the beanbag, kick the ball, bounce on the mat).
//  Locks are respected: a meal out, the bath, an approaching close-up, a race trip. A command whose object is not in the room (no beanbag placed, a
//  hat not owned) gets the confused head tilt and a line saying what is missing, never a half-done move. Feedback: the Jelly reacts (blink + perk,
//  or the "?" tilt) and the HUD shows the understood command briefly (`understood`).
//  The legacy actions (come, stop, praise, scold, play, goodnight = sleep, learned tricks) never reach here: `VoiceCoordinator.apply` turns them
//  into the usual VoiceDecision so the reliability roll, grumpy rules, trick pages and multi-Jelly hooks stay exactly as they were.
//

import Foundation
import QuartzCore

extension VoiceCoordinator {
    /// The command's Jelly ids (present ones only); empty when a named Jelly is not in the room.
    func ids(for who: JellyWho) -> [Int] {
        switch who {
        case .selected: return [selectedJellyID]
        case .everyone: return presentIDs
        case .jellies(let ids): return ids.allSatisfy { presentIDs.contains($0) } ? ids : []
        }
    }

    /// Runs one command now (called from `tick` once the hold is over). `brain` is Bob's.
    func execute(_ c: JellyCommand, care: GameCare, brain: BlobBrain) {
        let ids = ids(for: c.who)
        let names: (Int) -> String = { [weak care] in care?.jelly($0)?.name ?? "Jelly" }
        if VoiceCoordinator.logging { NSLog("AILOG execute %@ ids=%@ object=%@", c.action.key, ids.description, c.object ?? "-") }
        guard !ids.isEmpty else { confused(ids: [], reason: nil); return }                 // a name for a Jelly that is not here
        if case .jellies = c.who, !care.focus.isActive, ids.count == 1 { (onSelect ?? { care.rosterPick($0, quietHop: true) })(ids[0]) }
        if c.who == .everyone { onEveryone?(ids) }
        guard c.action.supportedNow else { confused(ids: ids, reason: Self.notYetLine(c, names: names)); return }
        if c.action.needsObject, c.object == nil { confused(ids: ids, reason: Self.missingLine(c)); return }         // "go to the beanbag": none placed
        let locked = care.trayOut || care.bath.active || (care.focus.isActive && care.focus.phase == .approaching)
        let held = care.touchPlay?.holdsBrain ?? false
        switch c.action {
        case .feed, .drink:
            guard !locked, !(care.focus.isActive && c.who == .everyone) else { confused(ids: ids, reason: care.trayOut ? "A meal is already out" : nil); return }
            let isFood = c.action == .feed
            let id = c.object ?? (isFood ? care.selectedFoodID : care.selectedDrinkID)
            let jelly: Int? = (c.who == .everyone && care.jellyCount > 1) ? nil : ids[0]
            if isFood { care.feed(id, jelly: jelly) } else { care.drink(id, jelly: jelly) }
            understand(c.summary(names: names), kind: .command(c.action), ids: ids)
        case .clean:
            let id = ids[0]
            guard care.canClean(jelly: id) else { confused(ids: ids, reason: nil); return }
            understand(c.summary(names: names), kind: .command(.clean), ids: ids)
            care.clean(jelly: id)
        case .goTo, .playWith:
            // the piece's own interaction (sit / boop / kick / bounce / peek / slide / throw) with the nearest free piece of that kind; a partner joins in
            guard !locked, !held, !care.raceBusy, !care.focus.isActive, let obj = c.object, let kind = DecorKind(storeID: obj) else { confused(ids: ids, reason: nil); return }
            guard let move = kind.activeInteraction else { confused(ids: ids, reason: "Nothing to do with the \(kind.title.lowercased())"); return }
            var who = ids
            if let p = c.partner, !who.contains(p), presentIDs.contains(p) { who.append(p) }
            let brains = who.compactMap { ai.brain($0) }
            guard !brains.isEmpty else { confused(ids: ids, reason: nil); return }
            for b in brains where !b.isSleeping && !b.reserved { b.commandedDecor = (move, kind) }
            understand(c.summary(names: names), kind: .command(c.action), ids: who)
        case .wear:
            guard let obj = c.object, let look = StoreCatalog.item(obj)?.wear, care.store.ownsLook(look) else { confused(ids: ids, reason: Self.missingLine(c)); return }
            guard !care.bath.active, !care.raceBusy else { confused(ids: ids, reason: nil); return }
            for id in ids { care.store.wear(look, on: id) }
            understand(c.summary(names: names), kind: .command(.wear), ids: ids)
        case .race, .train:
            // the Track panel for that Jelly (Race / Train are its buttons): the same screen Go out -> Track opens
            guard !locked, !held, !care.raceBusy, !care.focus.isActive, !care.arranging else { confused(ids: ids, reason: care.raceBusy ? "A race is already on" : nil); return }
            let id = ids[0]
            if !care.focus.isActive { (onSelect ?? { care.rosterPick($0, quietHop: true) })(id) }
            understand(c.summary(names: names), kind: .command(c.action), ids: [id])
            care.requestTown(.track)
        case .whoIs(let k):
            // the Jelly who wants it most answers: he lights up (the roster highlight), his bubble shows if it is Bob
            let wanting = presentIDs.filter { care.needs(for: $0).level(k) < NeedsTuning.wanting }
            if let who = wanting.min(by: { care.needs(for: $0).level(k) < care.needs(for: $1).level(k) }) {
                understand("\(names(who)) \(k == .attention ? "wants love" : k == .hunger ? "is hungry" : "is thirsty")", kind: .answer(k, who), ids: [who])
                if !care.focus.isActive { (onSelect ?? { care.rosterPick($0) })(who) }
                if who == 0 { care.showNeedBubble() }
            } else {
                understand(Self.nobodyLine(k), kind: .answer(k, nil), ids: ids)
            }
        case .come, .stop, .stopFighting, .praise, .scold, .play, .trick, .sleep, .none:
            confused(ids: ids, reason: nil)          // legacy actions never get here (see `apply`)
        }
    }

    /// The line for a parsed command whose object is not in the room / the wardrobe.
    static func missingLine(_ c: JellyCommand) -> String {
        switch c.action {
        case .goTo: return "No \(c.unknownObject ?? "furniture") in the room"
        case .wear: return "No \(c.unknownObject ?? "outfit") in the wardrobe"
        case .playWith: return c.unknownObject.map { "No \($0) in the room" } ?? "Nothing to play with"
        default: return "Not here"
        }
    }
    /// The "not yet" line for a parsed-but-unsupported command (nothing is gated today; kept for the next feature branch).
    static func notYetLine(_ c: JellyCommand, names: (Int) -> String) -> String {
        switch c.action {
        case .race: return "The race track isn't open yet"
        case .train: return "Training comes later"
        default: return "Not yet"
        }
    }
    static func nobodyLine(_ k: NeedKind) -> String {
        switch k { case .hunger: return "Nobody's hungry"; case .thirst: return "Nobody's thirsty"; case .attention: return "Everyone feels loved" }
    }

    /// The confused head tilt + "?" bubble (the existing puzzled reaction), with an optional HUD line saying what could not be done.
    func confused(ids: [Int], reason: String?) {
        if let r = reason { showUnderstood(r, ok: false) }
        enqueue(.puzzled, .unknown, ids: ids.isEmpty ? [] : ids)
        for id in ids where id != 0 { onRemote?(.puzzled, [id]) }
    }

    /// The understood line on the HUD + the Jelly's bubble.
    private func understand(_ line: String, kind: VoiceFeedback.Kind, ids: [Int]) {
        showUnderstood(line, ok: true)
        enqueue(.acknowledged, kind, ids: ids)
    }
}
