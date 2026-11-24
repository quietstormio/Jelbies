//
//  GameCare+MealFeedback.swift
//  A Feed / Drink tap that cannot start a meal (or that goes to Jelbies who will not eat) says so at once, in the refusal label's style, instead of doing nothing visible.
//  The meal RULES are unchanged; this only reports them.
//

import Foundation

extension GameCare {
    /// Shows `text` over Bob's head for the usual refusal-label time (unless a meal's own label is up).
    func tapRefused(_ text: String) {
        if park.active { GameMessageCenter.shared.refuse(text); return }          // the park / camp: the Jelmiko may be away from the camera, so the one message bar says it
        guard meal == nil, notice == nil || noticeAtBob else { return }
        noticeAtBob = true
        notice = text; noticeSerial += 1; noticeAge = 0
    }

    /// The line for a food / drink request while a trip is on: the Park and the Camp have their own, the other trips keep "Not while racing".
    var tripMealLine: String {
        guard park.active else { return "Not while racing" }
        return park.place == .camp ? "No food or drinks at camp" : "No food or drinks at the park"
    }

    /// Why a Feed / Drink tap for `c` cannot start now (nil = it can).
    func orderBlocker(_ c: Consumable) -> String? {
        let what = c.kind == .drink ? "Drink" : "Food"
        if bath.active { return "Not while cleaning" }
        if tripActive { return tripMealLine }
        if wanted != nil || meal != nil || dining.phase != .absent || groupActive { return "\(what) is already out" }
        return nil
    }

    /// Jellies the tap is for who are not hungry / thirsty at all (tier Full / Quenched), as one sentence; nil when somebody will eat.
    func fullLine(_ c: Consumable, jelly: Int?) -> String? {
        let kind: NeedKind = c.kind == .food ? .hunger : .thirst
        let ids = jelly.map { [$0] } ?? Array(jellies.indices)
        guard !ids.isEmpty, ids.allSatisfy({ MealAppetite.pieces(needs(for: $0).tier(kind)) == 0 }) else { return nil }
        let names = ids.compactMap { self.jelly($0)?.name }
        let who = names.count == 1 ? "\(names[0]) isn't" : names.count == 2 ? "\(names[0]) and \(names[1]) aren't" : "Nobody is"
        var line = who + (kind == .hunger ? " hungry" : " thirsty")
        if kind == .hunger, let left = ids.compactMap({ self.jelly($0)?.perks.remaining(.fullBelly) }).min(), left > 60 { line += " (full belly, \(SK.timeLeft(left)) left)" }
        return line
    }
}
