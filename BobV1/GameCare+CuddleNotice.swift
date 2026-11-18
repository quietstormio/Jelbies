//
//  GameCare+CuddleNotice.swift
//  The close-up's "Teddy is too hungry to cuddle" pill. A Jelbie who is grumpy from hunger / thirst does not enjoy a stroke (no hearts, no purr: `BlobBrain.annoyed`);
//  this only SAYS so. The rule is read from the same inputs as the gate (mood == grumpy and the wanted need is not attention); the gate itself is unchanged.
//

import SwiftUI

extension GameCare {
    /// The pill text for one Jelbie, nil when his strokes are not blocked. `wanted` / `mood` are the gate's own inputs.
    static func cuddleBlockLine(name: String, mood: BlobMood, wanted: NeedKind?, hungry: Bool, thirsty: Bool) -> String? {
        guard mood == .grumpy, wanted != .attention, hungry || thirsty else { return nil }
        let what = hungry && thirsty ? "hungry and thirsty" : hungry ? "hungry" : "thirsty"
        return "\(name) is too \(what) to cuddle"
    }

    /// One line for a group: the names (up to three, then "and N more") and what they lack. Same need for all: "Violet, Alien and Pogo are too hungry and thirsty to cuddle"; mixed: "... too hungry or thirsty to cuddle".
    static func cuddleGroupLine(_ entries: [(name: String, hungry: Bool, thirsty: Bool)]) -> String? {
        guard !entries.isEmpty else { return nil }
        if entries.count == 1, let e = entries.first { return "\(e.name) is too \(e.hungry && e.thirsty ? "hungry and thirsty" : e.hungry ? "hungry" : "thirsty") to cuddle" }
        let both = entries.allSatisfy { $0.hungry && $0.thirsty }
        let allHungry = entries.allSatisfy { $0.hungry && !$0.thirsty }, allThirsty = entries.allSatisfy { $0.thirsty && !$0.hungry }
        let what = both ? "hungry and thirsty" : allHungry ? "hungry" : allThirsty ? "thirsty" : "hungry or thirsty"
        let names = entries.map(\.name)
        let list: String
        if names.count <= 3 { list = names.count == 2 ? "\(names[0]) and \(names[1])" : "\(names[0]), \(names[1]) and \(names[2])" }
        else { list = "\(names[0]), \(names[1]), \(names[2]) and \(names.count - 3) more" }
        return "\(list) are too \(what) to cuddle"
    }

    /// The notices to show now: ONE merged line for the Jelmiko of the close-up whose strokes are blocked; empty outside the close-up or once the need is met.
    var cuddleNotices: [String] {
        guard focus.isFocused else { return [] }
        let blocked: [(name: String, hungry: Bool, thirsty: Bool)] = focusGroup.ids.compactMap { id in
            let n = needs(for: id)
            guard Self.cuddleBlockLine(name: "x", mood: n.mood, wanted: n.wantedNeed, hungry: n.isWanting(.hunger), thirsty: n.isWanting(.thirst)) != nil else { return nil }
            return (jelly(id)?.name ?? "Your Jelmiko", n.isWanting(.hunger), n.isWanting(.thirst))
        }
        return Self.cuddleGroupLine(blocked).map { [$0] } ?? []
    }
}

/// Posts the close-up's cuddle line to the one message bar whenever it appears or changes (a zero-size view; the pills that used to stack under "Let them go" are gone).
struct CuddleNoticePoster: View {
    let care: GameCare
    var body: some View {
        let line = care.cuddleNotices.first
        Color.clear.frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
            .onChange(of: line, initial: true) { _, l in if let l { GameMessageCenter.shared.post(l, identifier: "cuddle-notice") } }
    }
}
