//
//  CommandExecutor.swift
//  A validated JellyCommand becomes game actions: existing GameCare calls (feed / drink / clean / come here / roster pick) and existing brain
//  moves (sit, the nap). Locks are respected: a meal out, the bath, an approaching close-up. Anything the room cannot do yet (spin, decor, wardrobe,
//  soccer, races) gets the confused head tilt and a "not yet" line, never a half-done move. Feedback: the Jelly reacts (perk / move / tilt + "?"),
//  and the HUD shows the understood command briefly (`understood`).
//  The legacy actions (come, stop, praise, scold, play, learned tricks) never reach here: `VoiceCoordinator.apply` turns them into the usual
//  VoiceDecision so the reliability roll, grumpy rules and multi-Jelly hooks stay exactly as they were.
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
        guard c.action.supportedNow else {
            confused(ids: ids, reason: Self.notYetLine(c, names: names)); return
        }
        let locked = care.trayOut || care.bath.active || (care.focus.isActive && care.focus.phase == .approaching)
        switch c.action {
        case .feed, .drink:
            guard !locked, !(care.focus.isActive && c.who == .everyone) else { confused(ids: ids, reason: care.trayOut ? "A meal is already out" : nil); return }
            let isFood = c.action == .feed
            let id = c.object ?? (isFood ? care.selectedFoodID : care.selectedDrinkID)
            let jelly: Int? = (c.who == .everyone && care.jellyCount > 1) ? nil : ids[0]
            if isFood { care.feed(id, jelly: jelly) } else { care.drink(id, jelly: jelly) }
            understand(c.summary(names: names), kind: .command(c.action), ids: ids)
            for i in ids { ai.log.record(.obeyed, jelly: i, detail: isFood ? "eat" : "drink") }
        case .sleep:
            guard !locked, !care.focus.isActive else { confused(ids: ids, reason: nil); return }
            for i in ids { ai.requestNap(i) }
            understand(c.summary(names: names), kind: .command(.sleep), ids: ids)
            for i in ids { ai.log.record(.obeyed, jelly: i, detail: "sleep") }
        case .clean:
            let id = ids[0]
            guard care.canClean(jelly: id) else { confused(ids: ids, reason: nil); return }
            understand(c.summary(names: names), kind: .command(.clean), ids: ids)
            care.clean(jelly: id)
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
        case .come, .stop, .stopFighting, .praise, .scold, .play, .trick, .none, .spin, .goTo, .wear, .playWith, .race, .train:
            confused(ids: ids, reason: nil)          // legacy actions never get here (see `apply`); the unsupported ones were caught above
        }
    }

    /// The "not yet" line for a parsed-but-unsupported command.
    static func notYetLine(_ c: JellyCommand, names: (Int) -> String) -> String {
        switch c.action {
        case .spin: return "No spin move yet"
        case .goTo: return "No \(c.unknownObject ?? "furniture") to go to yet"
        case .wear: return "No \(c.unknownObject ?? "outfit") in the wardrobe yet"
        case .playWith: return c.unknownObject.map { "\($0.prefix(1).uppercased() + $0.dropFirst()) isn't here yet" } ?? "Playing together is coming soon"
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
