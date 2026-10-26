//
//  CoursePicker.swift
//  The Track panel's course picker: one card per course (Puddle, Ripple, Splash, Wave) with a mini map of its shape, its class, a lock on the
//  ones not yet open (and what opens them), and the prizes of the picked one. Picking writes RaceFlow.courseTier through GameCare.chooseCourse.
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
                    Image(systemName: "flag.checkered").font(.system(size: 11, weight: .semibold)).foregroundStyle(SK.ink).position(x: f.x, y: f.y + 8)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct CoursePicker: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    private var progress: CourseProgress { care.race.progress }
    private var chosen: CourseTier { care.race.courseTier }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Course").font(SK.font(15, .semibold)).foregroundStyle(SK.ink)
                Spacer()
                Text("\(chosen.title) · \(chosen.className) class").font(SK.font(12, .bold)).foregroundStyle(SK.muted).accessibilityIdentifier("course-chosen")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CourseTier.allCases, id: \.rawValue) { t in card(t) }
                }
                .padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
            Text(progress.requirement(chosen) ?? chosen.blurb).font(SK.font(11, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("course-blurb")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("course-picker")
    }

    private func card(_ t: CourseTier) -> some View {
        let open = progress.unlocked(t), picked = t == chosen
        let rec = progress.record(t)
        return Button { if care.chooseCourse(t) { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap() } } label: {
            VStack(spacing: 4) {
                ZStack {
                    CourseMiniMap(course: RaceCourse.course(t), lineWidth: 6, tint: open ? Color(hex: 0xE5A88E) : Color(hex: 0xC9BDB0))
                        .frame(width: 92, height: 64)
                    if !open {
                        Image(systemName: "lock.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(SK.ink.opacity(0.85))
                            .padding(6).background(Circle().fill(DT.card))
                    }
                }
                Text(t.title).font(SK.font(14, .semibold)).foregroundStyle(open ? SK.ink : SK.muted)
                Text(open ? (rec.wins > 0 ? "\(rec.wins) win\(rec.wins == 1 ? "" : "s")" : t.className) : "Locked").font(SK.font(10, .bold)).foregroundStyle(SK.muted)
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
            .frame(width: 112)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(picked ? SK.honey : Color.white.opacity(open ? 0.9 : 0.55)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(picked ? SK.honeyDeep : .clear, lineWidth: 2))
            .opacity(open ? 1 : 0.8)
            .overlay(alignment: .topTrailing) {
                if picked { Image(systemName: "checkmark.circle.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(SK.ink).padding(5) }          // not colour alone
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(picked ? "picked" : "")
        .accessibilityIdentifier("course-\(t.rawValue)")
        .accessibilityLabel("\(t.title), \(t.className) class\(open ? "" : ", locked")")
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityHint(progress.requirement(t) ?? t.blurb)
    }
}
