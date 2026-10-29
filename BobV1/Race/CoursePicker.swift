//
//  CoursePicker.swift
//  The Track lobby's course picker: one card per course (Puddle ... Tsunami) with its shape, its class, a lock on the ones not yet open (and what opens them), and the prizes of the picked one.
//  Picking writes RaceFlow.courseTier through GameCare.chooseCourse.
//

import SwiftUI
import simd

/// The shape of a course as a path: the centreline and the three lanes, scaled to fit a box, start dot and finish flag.
struct CourseMiniMap: View {
    let course: RaceCourse
    var lineWidth: CGFloat = 7
    var tint: Color = Color(hex: 0xE5A88E)

    /// The centreline points mapped into `size` with a margin, keeping proportion, in the race camera's orientation: world x to the right, world z
    /// DOWN the box (the start line far away at the top, the finish near the player at the bottom), so the card's shape is the track as seen from
    /// the finish end, with a right turn bending to the right.
    static func points(_ course: RaceCourse, in size: CGSize, lane: Int = 1, margin: CGFloat = 8) -> [CGPoint] {
        let pts = course.polyline(lane: lane, step: 0.3)
        let all = course.polyline(lane: 0, step: 0.5) + course.polyline(lane: 2, step: 0.5)
        var lo = SIMD2<Float>(.infinity, .infinity), hi = -lo
        for p in all { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        let w = max(hi.x - lo.x, 0.5), h = max(hi.y - lo.y, 0.5)
        let sc = min((size.width - 2 * margin) / CGFloat(w), (size.height - 2 * margin) / CGFloat(h))
        let ox = (size.width - CGFloat(w) * sc) / 2, oy = (size.height - CGFloat(h) * sc) / 2
        return pts.map { CGPoint(x: ox + CGFloat($0.x - lo.x) * sc, y: oy + CGFloat($0.y - lo.y) * sc) }
    }

    static func path(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let f = pts.first else { return p }
        p.move(to: f)
        for q in pts.dropFirst() { p.addLine(to: q) }
        return p
    }

    var body: some View {
        GeometryReader { g in
            let pts = Self.points(course, in: g.size)
            ZStack {
                Self.path(pts).stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                Self.path(pts).stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round, dash: [3, 3]))
                if let s = pts.first { Circle().fill(SK.mint).frame(width: lineWidth + 3, height: lineWidth + 3).position(s) }
                if let f = pts.last {
                    Image(systemName: "flag.checkered").font(.system(size: 11, weight: .black)).foregroundStyle(SK.ink).position(x: f.x, y: f.y + 8)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The Track lobby's course carousel (to the lobby mockups): "Course  N of 5 open", a card per course (its shape on a green field, its class and this runner's wins),
/// and the info line with the blurb and the prizes. A tap on a locked card shows what opens it for a few seconds. Picking writes RaceFlow.courseTier through GameCare.chooseCourse.
struct CoursePicker: View {
    let care: GameCare
    /// The runner whose wins are counted on the cards (his character).
    var runner: Int
    var bleed = true
    var hint: LobbyHint
    @Environment(\.dynamicTypeSize) private var typeSize
    private var progress: CourseProgress { care.race.progress }
    private var chosen: CourseTier { care.race.courseTier }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LobbyLabelRow(title: "Course", trailing: "\(progress.unlockedTiers.count) of \(CourseTier.allCases.count) open")
            LobbyCarousel(bleed: bleed, scrollTo: chosen.index >= 2 ? "course-card-\(chosen.rawValue)" : nil) {
                ForEach(CourseTier.allCases, id: \.rawValue) { t in card(t).id("course-card-\(t.rawValue)") }
            }
            LobbyInfoLine(text: hint.text ?? chosen.blurb, textID: "course-blurb", pillsBelow: true) {
                LobbyPill(label: "1st", amount: RaceTuning.drops(place: 1, tier: chosen), gold: true)
                LobbyPill(label: "2nd", amount: RaceTuning.drops(place: 2, tier: chosen))
                LobbyPill(label: "3rd", amount: RaceTuning.drops(place: 3, tier: chosen))
            }
            .accessibilityIdentifier("track-prizes")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("course-picker")
    }

    private func wins(_ t: CourseTier) -> Int { care.race.trophies.shelf(character: runner).raceRibbons(t).first ?? 0 }

    private func card(_ t: CourseTier) -> some View {
        let open = progress.unlocked(t), picked = t == chosen
        let w = wins(t)
        let sub = open ? (w > 0 ? "\(t.className) \u{00B7} \(w) win\(w == 1 ? "" : "s")" : t.className) : "Win at \(t.below?.title ?? "")"
        return Button {
            if open { if care.chooseCourse(t) { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap() } }
            else { hint.show(progress.requirement(t) ?? "Win at \(t.below?.title ?? "")") }
        } label: {
            LobbyCarouselCard(name: t.title, sub: sub, selected: picked && open, locked: !open) { CourseArt(tier: t) }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(open ? "\(t.title), \(sub.replacingOccurrences(of: " \u{00B7} ", with: ", "))" : "\(t.title), locked. Win at \(t.below?.title ?? "")")
        .accessibilityHint(open ? t.blurb : (progress.requirement(t) ?? ""))
        .accessibilityValue(picked ? "picked" : "")
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("course-\(t.rawValue)")
    }
}
