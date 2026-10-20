//
//  DecorUI.swift
//  Arrange mode for the room's decor: after Bag "Place" (or "Arrange room") a transparent layer takes the touches (so the Jellies are not petted or
//  thrown), a finger picks a piece up and drags it over the floor (it snaps to valid spots and slides along obstacles), and a bar offers Put away and Done.
//

import SwiftUI

struct ArrangeOverlay: View {
    let care: GameCare
    @State private var grab: SIMD2<Float>?            // finger floor point minus the piece's centre at pick-up
    @State private var dragging: Int?

    private var book: StoreBook { care.store }
    private var selected: PlacedDecor? { care.arrangingUID.flatMap { id in book.placedDecor.first { $0.uid == id } } }

    /// The finger, in the overlay's own coordinates (drawn only by the capture aid `-ArrangeDemo`).
    @State private var finger: CGPoint?
    private static let demo = UserDefaults.standard.integer(forKey: "ArrangeDemo") != 0 || UserDefaults.standard.integer(forKey: "DoubleTapDemo") != 0

    /// A touch at `location` in a surface of `size` (the whole screen: this view ignores the safe area, so its coordinates are the stage's own).
    private func touch(_ location: CGPoint, size: CGSize) {
        guard let floor = care.floorPoint(screen: location, size: size) else { return }
        if dragging == nil {
            if let p = care.decorPiece(at: floor) {
                dragging = p.uid; care.arrangingUID = p.uid
                grab = floor - p.at
                DecorField.shared.kick(p.uid, 0.6)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } else { dragging = -1 }
        }
        if let id = dragging, id >= 0, let off = grab { care.dragDecor(id, to: floor - off) }
    }

    /// A soft ring on the floor round the picked-up piece (projected, so it is right at every aspect and orientation).
    private func ring(size: CGSize) -> some View {
        let sel = selected          // (read here, in the body, so the ring follows the piece)
        return Canvas { ctx, _ in
            guard let p = sel else { return }
            let c = p.at
            let r = p.kind.spec.radius + 0.18
            var path = Path()
            for k in 0...48 {
                let a = Float(k) / 48 * 2 * .pi
                guard let q = GameCamera.screenPoint(floor: SIMD2(c.x + cosf(a) * r, c.y + sinf(a) * r), size: size) else { return }
                if k == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            path.closeSubpath()
            ctx.fill(path, with: .color(SK.honey.opacity(0.28)))
            ctx.stroke(path, with: .color(SK.honey), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }

    var body: some View {
        GeometryReader { g in
            let inset = g.safeAreaInsets
            ZStack {
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in finger = v.location; touch(v.location, size: g.size) }
                        .onEnded { v in
                            if let id = dragging, id >= 0 { care.dropDecor(id) }
                            else if dragging == -1, hypot(v.translation.width, v.translation.height) < 12, !Self.demo { care.endArrange() }          // a tap on empty floor: let go, done
                            dragging = nil; grab = nil; finger = nil
                        })
                    .accessibilityIdentifier("arrange-surface")
                ring(size: g.size)
                VStack {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Arrange the room").font(SK.font(18, .black)).foregroundStyle(SK.ink)
                            Text(selected.map { "\($0.kind.title): drag to move" } ?? "Touch a piece and drag it").font(SK.font(12, .bold)).foregroundStyle(SK.muted)
                        }
                        Spacer(minLength: 0)
                        Text("\(book.roomUnitsUsed)/\(StoreTuning.roomCapacity) spots").font(SK.font(13, .heavy)).foregroundStyle(SK.muted)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SK.cream.opacity(0.94)).shadow(color: SK.shadow.opacity(0.2), radius: 6, y: 2))
                    .frame(maxWidth: 520)
                    .padding(.top, max(inset.top, 0) + 8)
                    Spacer()
                    HStack(spacing: 10) {
                        if let s = selected {
                            Button { UINotificationFeedbackGenerator().notificationOccurred(.success); care.putAwayDecor(s.uid) } label: {
                                Text("Put away").font(SK.font(16, .black)).foregroundStyle(SK.ink).padding(.horizontal, 20).frame(minHeight: 52)
                                    .background(Capsule().fill(SK.cream.opacity(0.96)))
                            }.buttonStyle(.plain).accessibilityIdentifier("arrange-putaway")
                        }
                        Button { AudioHub.shared.uiTap(); care.endArrange() } label: {
                            Text("Done").font(SK.font(18, .black)).foregroundStyle(SK.cream).padding(.horizontal, 34).frame(minHeight: 52)
                                .background(Capsule().fill(SK.ink))
                        }.buttonStyle(.plain).accessibilityIdentifier("arrange-done")
                    }
                    .padding(.bottom, max(inset.bottom, 0) + 12)
                }
                .padding(.leading, inset.leading + 16).padding(.trailing, inset.trailing + 16)
                if Self.demo, let f = finger {
                    Circle().strokeBorder(Color.red, lineWidth: 3).background(Circle().fill(Color.red.opacity(0.25))).frame(width: 44, height: 44).position(f).allowsHitTesting(false)
                }
            }
            .task(id: g.size) {
                // capture aid: pick the first piece up and drag it to the front-left floor (off the rug), then hold there
                guard Self.demo else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let start = care.store.placedDecor.first.flatMap { p -> CGPoint? in
                    let f = DecorField.shared.foot(p.uid).map { DecorField.shared.position($0) } ?? p.at
                    return GameCamera.screenPoint(floor: f, size: g.size)
                }
                guard let a = start else { return }
                let b = GameCamera.screenPoint(floor: SIMD2(-3.0, 2.6), size: g.size) ?? CGPoint(x: g.size.width * 0.3, y: g.size.height * 0.8)          // the front-left floor, off the rug
                for k in 0...20 {
                    let t = CGFloat(k) / 20
                    let pt = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                    finger = pt; touch(pt, size: g.size)
                    try? await Task.sleep(nanoseconds: 60_000_000)
                }
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .accessibilityIdentifier("arrange-overlay")
    }
}
