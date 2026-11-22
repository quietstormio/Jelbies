//
//  StoryViews.swift
//  The Profile's two story slots, built for the FIXED SKELETON (the owner's rule: the page never moves because a line is longer or shorter):
//    StoryLivingBubble: the living line, ALWAYS the same box (two lines of space, the sparkle inside it, a tinted bubble that simply is not drawn when there is no line).
//    StoryFriendRow: one housemate: two small heads, the names (one line) and the note (two lines of space); StoryFriendRow.placeholder keeps a row's height when there is nobody.
//  The guard (StoryGuard.fitsLines) rejects any text that would need a third line at the narrowest phone width, so nothing is ever cut with "...".
//

import SwiftUI

/// The measurements the guard uses (iPhone SE class width, 375 pt): the card's inner width is 375 - 2 x 16 - 2 x 14 = 315.
nonisolated enum StoryLayout {
    static let narrowPhone: CGFloat = 375
    static let cardInner: CGFloat = narrowPhone - 32 - 28
    /// The living line's text column: bubble padding 12 x 2, the sparkle 14 and the gap 8.
    static let lineWidth: CGFloat = cardInner - 24 - 14 - 8
    static let lineSize: CGFloat = 15
    /// A friend note's text column: the two heads (72) and the gap (10) are beside it.
    static let noteWidth: CGFloat = cardInner - 72 - 10
    static let noteSize: CGFloat = 13
    static let headsWidth: CGFloat = 72
}

struct StoryLivingBubble: View {
    var text: String
    var byModel = false
    var tint: Color
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkle").font(.system(size: 13, weight: .black)).foregroundStyle(ShowUI.goldDeep).frame(width: 14, height: 18)
                .opacity(text.isEmpty ? 0 : 1).accessibilityHidden(true)
            Text(text.isEmpty ? " " : text).font(SK.font(StoryLayout.lineSize, .semibold)).foregroundStyle(SK.ink).lineSpacing(3).lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(text.isEmpty ? Color.clear : tint.opacity(0.3)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(text.isEmpty ? Color.clear : tint.opacity(0.5), lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.isEmpty ? "" : "Lately: \(text)" + (byModel ? ". Written on this iPhone" : ""))
        .accessibilityHidden(text.isEmpty)
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
                Text(names).font(SK.font(14, .black)).foregroundStyle(SK.ink).lineLimit(1, reservesSpace: true)
                Text(note).font(SK.font(StoryLayout.noteSize, .semibold)).foregroundStyle(SK.muted).lineLimit(2, reservesSpace: true)
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
