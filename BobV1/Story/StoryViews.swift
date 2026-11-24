//
//  StoryViews.swift
//  The Profile's housemate-note slots, built for the FIXED SKELETON (the owner's rule: the page never moves because a line is longer or shorter):
//    StoryFriendRow: one housemate: two small heads, the names (one line) and the note (two lines of space); StoryFriendRow.placeholder keeps a row's height when there is nobody.
//  The guard (StoryGuard.fitsLines) rejects any text that would need a third line at the narrowest phone width, so nothing is ever cut with "...".
//

import SwiftUI

/// The measurements the guard uses (iPhone SE class width, 375 pt): the card's inner width is 375 - 2 x 16 - 2 x 14 = 315.
nonisolated enum StoryLayout {
    static let narrowPhone: CGFloat = 375
    static let cardInner: CGFloat = narrowPhone - 32 - 28
    /// The width / size the (retired, unshown) About text was checked against; StoryGuard's About kind still uses them.
    static let lineWidth: CGFloat = cardInner - 24 - 14 - 8
    static let lineSize: CGFloat = 15
    /// A friend note's text column: the two heads (72) and the gap (10) are beside it.
    static let noteWidth: CGFloat = cardInner - 72 - 10
    static let noteSize: CGFloat = 13
    static let headsWidth: CGFloat = 72
}

/// The mark in front of / beside a text: ONLY text written by the on-device model carries the Apple Intelligence sparkle (with its label). Pre-written text carries nothing: the same
/// fixed slot is kept empty, so the box is exactly the same size either way.
struct StoryMark: View {
    var byModel: Bool
    var body: some View {
        Group {
            if byModel { Image(systemName: "sparkle").font(.system(size: 13, weight: .black)).foregroundStyle(ShowUI.goldDeep).accessibilityLabel("Written on this iPhone") }
            else { Color.clear.accessibilityHidden(true) }
        }
        .frame(width: 14, height: 18)
    }
}

struct StoryFriendRow<Heads: View>: View {
    var names: String
    var note: String
    var byModel = false
    @ViewBuilder var heads: () -> Heads
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            heads().frame(width: StoryLayout.headsWidth, height: 40, alignment: .leading).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(names.isEmpty ? " " : names).font(SK.font(14, .black)).foregroundStyle(SK.ink).lineLimit(1, reservesSpace: true)
                    Spacer(minLength: 0)
                    StoryMark(byModel: byModel)
                }
                Text(note.isEmpty ? " " : note).font(SK.font(StoryLayout.noteSize, .semibold)).foregroundStyle(SK.muted).lineLimit(2, reservesSpace: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(names). \(note)" + (byModel ? ". Written on this iPhone" : ""))
    }
}

struct StoryFriendPlaceholder: View {
    var body: some View {
        StoryFriendRow(names: "A new friend", note: "Still finding out") { Circle().fill(SK.muted.opacity(0.18)).frame(width: 40, height: 40) }
            .opacity(0.7)
    }
}
