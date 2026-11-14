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

    /// The notices to show now: one per Jelbie of the close-up whose strokes are blocked; empty outside the close-up or once the need is met.
    var cuddleNotices: [String] {
        guard focus.isFocused else { return [] }
        return focusGroup.ids.compactMap { id in
            let n = needs(for: id)
            return Self.cuddleBlockLine(name: jelly(id)?.name ?? "Your Jelmiko", mood: n.mood, wanted: n.wantedNeed, hungry: n.isWanting(.hunger), thirsty: n.isWanting(.thirst))
        }
    }
}

/// The cream pill(s) under "Let them go" while strokes are blocked; same look as the refusal label.
struct CuddleNoticeView: View {
    let care: GameCare
    var body: some View {
        let lines = care.cuddleNotices
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .jFont(15, .bold)
                    .foregroundStyle(FocusStyle.brown)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.25), radius: 5, y: 2))
                    .transition(.scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity))
                    .accessibilityIdentifier("cuddle-notice")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: lines)
        .allowsHitTesting(false)
        .onChange(of: lines) { _, l in if let t = l.first { A11yAnnounce.say(t, priority: .normal) } }
    }
}

/// The HUD row for it: left-aligned under the top bar, empty (no height) when there is nothing to say.
struct CuddleNoticeRow: View {
    let care: GameCare
    var body: some View {
        if !care.cuddleNotices.isEmpty { HStack { CuddleNoticeView(care: care); Spacer() } }
    }
}
