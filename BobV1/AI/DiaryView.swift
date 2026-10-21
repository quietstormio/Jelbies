//
//  DiaryView.swift
//  The Diary page: one tab per Jelly, their entries newest first as handwritten-looking pages (cream paper #F7F0E0, ink #4D331F, ruled lines,
//  the rounded font in italic). Opened from the HUD's diary button (top-right, next to the roster; it shows a dot when there is a new entry),
//  also while in a Jelly's close-up (then it opens on him). Reading a Jelly's page clears his dot. Portrait stacks the pages; landscape lays
//  them out two across.
//

import SwiftUI

enum DiaryStyle {
    static let paper = Color(hex: "#F7F0E0")
    static let ink = Color(hex: "#4D331F")
    static let rule = Color(hex: "#4D331F").opacity(0.10)
    static let margin = Color(red: 0.93, green: 0.55, blue: 0.60).opacity(0.55)
    static func hand(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .rounded).italic() }
}

/// Round HUD button with the unread dot.
struct DiaryButton: View {
    let care: GameCare
    let action: () -> Void
    var body: some View {
        let unread = care.voice.ai.diary.hasUnread
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
            action()
        } label: {
            Image(systemName: "book.pages.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.34, blue: 0.30))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(red: 0.97, green: 0.94, blue: 0.88)).opacity(0.92))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .overlay(alignment: .topTrailing) {
                    if unread {
                        Circle().fill(FocusStyle.pink).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(FocusStyle.cream, lineWidth: 2))
                            .offset(x: 2, y: -2)
                            .accessibilityIdentifier("diary-dot")
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("diary-button")
        .accessibilityLabel(unread ? "Diary, new entry" : "Diary")
    }
}

struct DiaryView: View {
    let care: GameCare
    @State var jelly: Int
    var close: () -> Void
    /// Fixed "today" for captures / tests (nil = the log's).
    var today: String? = nil

    private var book: DiaryBook { care.voice.ai.diary }
    private var jellies: [JellyProfile] { care.jellies }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height && geo.size.width > 600
            VStack(spacing: 0) {
                header
                ScrollView {
                    let entries = pages
                    if entries.isEmpty {
                        emptyPage.padding(.horizontal, 18).padding(.top, 10)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: wide ? 340 : 600), spacing: 16, alignment: .top)], alignment: .center, spacing: 16) {
                            ForEach(entries) { e in page(e) }
                        }
                        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 24)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(DiaryStyle.paper.opacity(0.6).background(FocusStyle.cream).ignoresSafeArea())
        .onAppear { book.markRead(jelly) }
        .onChange(of: jelly) { _, j in book.markRead(j) }
        .accessibilityIdentifier("diary-page")
    }

    private var pages: [DiaryEntry] {
        book.entries(jelly: jelly)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Diary")
                    .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(DiaryStyle.ink)
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(DiaryStyle.ink)
                        .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.75)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("diary-close").accessibilityLabel("Close diary")
            }
            HStack(spacing: 8) {
                ForEach(jellies, id: \.id) { p in
                    let on = p.id == jelly
                    let tint = JellyRoster.tint(p.id)
                    Button { withAnimation(CareMenu.spring) { jelly = p.id } } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Color(red: Double(tint.x), green: Double(tint.y), blue: Double(tint.z))).frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
                            Text(p.name).font(.system(size: 15, weight: .bold, design: .rounded))
                            if book.unread.contains(p.id) { Circle().fill(FocusStyle.pink).frame(width: 7, height: 7) }
                        }
                        .foregroundStyle(on ? Color.white : DiaryStyle.ink)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(on ? DiaryStyle.ink : Color.white.opacity(0.75)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("diary-tab-\(p.id)")
                    .accessibilityLabel("\(p.name)'s diary")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Spacer()
            }
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 6)
    }

    private func dayTitle(_ key: String) -> String {
        let t = today ?? EventLog.dayKey(book.now())
        if key == t { return "Today" }
        if key == EventLog.dayKey(book.now().addingTimeInterval(-86_400)) { return "Yesterday" }
        guard let d = EventLog.date(ofDay: key) else { return key }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func page(_ e: DiaryEntry) -> some View {
        let name = care.jelly(e.jelly)?.name ?? "Jelly"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dayTitle(e.day)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(DiaryStyle.ink.opacity(0.6))
                Spacer()
                if e.smart {
                    Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)).foregroundStyle(DiaryStyle.ink.opacity(0.45))
                        .accessibilityLabel("Written with Apple Intelligence")
                }
            }
            Text(e.text)
                .font(DiaryStyle.hand(19))
                .foregroundStyle(DiaryStyle.ink)
                .lineSpacing(9)
                .fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Text("– \(name)").font(DiaryStyle.hand(16)).foregroundStyle(DiaryStyle.ink.opacity(0.8)) }
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paperBackground)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("diary-entry-\(e.jelly)-\(e.day)")
        .accessibilityLabel("\(dayTitle(e.day)). \(e.text)")
    }

    private var emptyPage: some View {
        let name = care.jelly(jelly)?.name ?? "Jelly"
        return VStack(alignment: .leading, spacing: 10) {
            Text("Nothing here yet")
                .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(DiaryStyle.ink.opacity(0.6))
            Text("\(name) writes in the evening about the day: meals, naps, games and friends. Come back later!")
                .font(DiaryStyle.hand(18)).foregroundStyle(DiaryStyle.ink).lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paperBackground)
        .accessibilityIdentifier("diary-empty")
    }

    /// Cream paper with faint ruled lines and a soft shadow.
    private var paperBackground: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DiaryStyle.paper)
                .shadow(color: FocusStyle.shadow.opacity(0.16), radius: 8, y: 3)
            Canvas { ctx, size in
                var y: CGFloat = 46
                while y < size.height - 14 {
                    var p = Path(); p.move(to: CGPoint(x: 14, y: y)); p.addLine(to: CGPoint(x: size.width - 14, y: y))
                    ctx.stroke(p, with: .color(DiaryStyle.rule), lineWidth: 1)
                    y += 28
                }
                var m = Path(); m.move(to: CGPoint(x: 15, y: 10)); m.addLine(to: CGPoint(x: 15, y: size.height - 10))
                ctx.stroke(m, with: .color(DiaryStyle.margin), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
        }
    }
}
