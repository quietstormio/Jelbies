//
//  TrophyCase.swift
//  The trophy case's two player-facing pieces (trophy-case-r1):
//
//    SETTINGS   double-tap the case on the wall: the Trophy Shelf card (Trophies/TrophyShelfCard.swift): "Show trophy shelf in the room" (on by default, saved in TrophyBook) and a grid of the trophies.
//               Off: the shelf is not drawn; the same switch sits at the top of the Trophies sheet and in Settings > Game, so it can always be turned back on.
//    ENGRAVING  tap a trophy on the shelf (or its tile in the card): the camera eases in on it and an engraved plate shows the Jelmiko's name, the event and the date.
//               The dates are written at the win (JelbieTrophies.won); a win from before that shows "Won before <the day this save first got engravings>" (no other record keeps a date per win).
//
//  Nothing here changes how trophies are earned.
//

import SwiftUI
import simd

/// What the plate says about one trophy on the shelf.
nonisolated struct TrophyShelfItem: Equatable, Sendable, Identifiable {
    var id: String          // "cup.<tier>", "contest", "wins5" / "wins10" / "wins25" / "champion", "volley.<tier>"
    var event: String       // "Jelly Race (Puddle) \u{2013} 1st"
    var character: Int?     // who won it (nil: not known)
    var date: Date?         // nil: won before dates were kept
    var before: Date? = nil // the day this save first got engravings (TrophyBook.engravingSince): an undated win was won before it

    var dateLine: String { Self.dateText(date, before: before) }
    static func dateText(_ d: Date?, before: Date? = nil) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "d MMM yyyy"
        if let d { return f.string(from: d) }
        if let before { return "Won before \(f.string(from: before))" }
        return "Won earlier"
    }
}

extension TrophyBook {
    private static func ord(_ p: Int) -> String { p == 1 ? "1st" : p == 2 ? "2nd" : "3rd" }

    /// Every trophy drawn on the wall shelf for `spec`, with who won it and when (the same rules as `roomShelf`: the best place over every Jelmiko).
    /// `contestWho` = the Jelmiko holding the best Show cup (ShowProgress.bestCupCharacter).
    func shelfItems(spec: TrophyShelfSpec, contestWho: Int?) -> [TrophyShelfItem] {
        let books = shelves.compactMap { k, v in Int(k).map { ($0, v) } }.sorted { $0.0 < $1.0 }
        func earliest(_ key: String, among who: [Int]) -> (Int?, Date?) {
            var best: (Int, Date)?
            for (c, s) in books where who.contains(c) { if let d = s.won?[key], best == nil || d < best!.1 { best = (c, d) } }
            return (best?.0 ?? who.first, best?.1)
        }
        let since = engravingSince
        var out: [TrophyShelfItem] = []
        for (k, t) in CourseTier.allCases.enumerated() where spec.cups[k] != 0 {
            let p = Int(spec.cups[k])
            let holders = books.filter { $0.1.bestRace(t) == p }.map(\.0)
            let (c, d) = earliest("race.\(t.rawValue).\(p)", among: holders)
            out.append(TrophyShelfItem(id: "cup.\(t.rawValue)", event: "Jelly Race (\(t.title)) \u{2013} \(Self.ord(p))", character: c, date: d, before: since))
        }
        if spec.contest != 0 {
            let p = Int(spec.contest)
            var d: Date?
            if let w = contestWho, let s = shelves["\(w)"]?.won { d = ShowRank.allCases.compactMap { s["show.\($0.rawValue).\(p)"] }.min() }
            out.append(TrophyShelfItem(id: "contest", event: "Jelly Show \u{2013} \(Self.ord(p))", character: contestWho, date: d, before: since))
        }
        for (k, t) in [Trophy.wins5, .wins10, .wins25, .champion].enumerated() where spec.milestones[k] {
            let holders = books.filter { $0.1.has(t) }.map(\.0)
            let (c, d) = earliest("trophy.\(t.id)", among: holders)
            out.append(TrophyShelfItem(id: t.id, event: "Jelly Race \u{2013} \(t.title)", character: c, date: d, before: since))
        }
        for (k, t) in VolleyTier.allCases.enumerated() where spec.volley[k] {
            let holders = books.filter { $0.1.volleyWon(t) > 0 }.map(\.0)
            let (c, d) = earliest("volley.\(t.rawValue)", among: holders)
            out.append(TrophyShelfItem(id: "volley.\(t.rawValue)", event: "Beach Volleyball (\(t.title)) \u{2013} 1st", character: c, date: d, before: since))
        }
        return out
    }
}

extension ShowProgress {
    /// The Jelmiko with the best Show cup (lowest placing; the lowest id on a tie), nil when none.
    var bestCupCharacter: Int? {
        saved.trophies.compactMap { k, v in v.cups.values.min().flatMap { m in Int(k).map { ($0, m) } } }.sorted { ($0.1, $0.0) < ($1.1, $1.0) }.first?.0
    }
}

// MARK: - Shelf positions (wall units)

extension TrophyShelfGeometry {
    struct Slot: Equatable { var id: String; var x: Float; var y: Float }
    /// Where each trophy of `spec` stands on the wall (the middle of the cup), the same slots `add` draws them in. Empty when the room has no shelf.
    static func slots(_ spec: TrophyShelfSpec, def: RoomDef = RoomLayout.current) -> [Slot] {
        guard !spec.isEmpty, let sp = spot(def) else { return [] }
        let upperY = sp.y + 0.62, volleyY = upperY + 0.62, lift: Float = 0.11
        var out: [Slot] = []
        let slot = sp.width / Float(spec.cups.count)
        for (k, t) in CourseTier.allCases.enumerated() where spec.cups[k] != 0 { out.append(Slot(id: "cup.\(t.rawValue)", x: sp.x - sp.width / 2 + slot * (Float(k) + 0.5), y: sp.y + lift)) }
        let slot2 = sp.width / 5
        func x2(_ k: Int) -> Float { sp.x - sp.width / 2 + slot2 * (Float(k) + 0.5) }
        if spec.contest != 0 { out.append(Slot(id: "contest", x: x2(0), y: upperY + 0.2)) }
        for (k, t) in [Trophy.wins5, .wins10, .wins25, .champion].enumerated() where spec.milestones[k] { out.append(Slot(id: t.id, x: x2(k + 1), y: upperY + lift)) }
        let slot3 = sp.width / Float(spec.volley.count)
        for (k, t) in VolleyTier.allCases.enumerated() where spec.volley[k] { out.append(Slot(id: "volley.\(t.rawValue)", x: sp.x - sp.width / 2 + slot3 * (Float(k) + 0.5), y: volleyY + lift)) }
        return out
    }
    /// The case's whole face on the wall (all planks): a double tap anywhere on it opens the card.
    static func faceRect(_ spec: TrophyShelfSpec, def: RoomDef = RoomLayout.current) -> (x0: Float, x1: Float, y0: Float, y1: Float)? {
        guard !spec.isEmpty, let sp = spot(def) else { return nil }
        let top = (spec.volley.contains(true) ? sp.y + 1.24 : sp.y + 0.62) + 0.34
        return (sp.x - sp.width / 2, sp.x + sp.width / 2, sp.y - 0.12, top)
    }
}

// MARK: - Camera

extension GameCamera {
    /// 0 = the room camera, 1 = looking at one trophy (eased by `GameCare.tickTrophyFocus`; like `wallEditBlend`, global so the finger maths follow it).
    nonisolated(unsafe) static var trophyBlend: Float = 0
    /// The wall point (x, y) the trophy view looks at.
    nonisolated(unsafe) static var trophyAt = SIMD2<Float>(0, 3)
    /// Straight at the wall, close enough that a cup fills a good part of the screen; the cup sits above the middle so the plate has room below.
    static func trophyPose(aspect: Float) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let visibleH: Float = 2.6          // (the height of wall in view; the width follows the aspect)
        let d = visibleH * 0.5 / tanf(fovY / 2)
        let drop: Float = visibleH * (aspect > 1 ? 0.16 : 0.08)
        let t = SIMD3<Float>(trophyAt.x, trophyAt.y - drop, RoomLayout.minZ)
        return (t + SIMD3(0, 0, d), t)
    }
}

// MARK: - State

extension GameCare {
    /// The wall case as it is drawn: nothing when the player hid it.
    var shownTrophySpec: TrophyShelfSpec {
        race.trophies.caseVisible ? race.trophies.roomShelf(contestBest: show.progress.bestCup) : TrophyShelfSpec()
    }
    var trophyItems: [TrophyShelfItem] { race.trophies.shelfItems(spec: race.trophies.roomShelf(contestBest: show.progress.bestCup), contestWho: show.progress.bestCupCharacter) }
    var trophyFocused: TrophyShelfItem? { trophyFocusID.flatMap { id in trophyItems.first { $0.id == id } } }
    /// "Jelmiko name" for a plate: the Jelmiko's own name while he is home; "A Jelmiko" when he is not on the roster any more or the win predates records.
    func trophyWinnerName(_ item: TrophyShelfItem) -> String {
        guard let c = item.character else { return "A Jelmiko" }
        if let n = jellies.first(where: { $0.character == c })?.name { return n }
        if let n = GameCare.campSource().first(where: { $0.id == c })?.name, !n.isEmpty { return n }          // (at the Camp)
        if let n = (UserDefaults.standard.dictionary(forKey: "Circuit.retiredNames.v1") as? [String: String])?["\(c)"], !n.isEmpty { return n }          // (let go, trophies kept: read each time)
        return "A Jelmiko"
    }

    func openTrophyCard() { guard !trophyCardOpen else { return }; AudioHub.shared.uiTap(); trophyCardOpen = true; A11yEvents.say("Trophy shelf settings", .normal) }
    func closeTrophyCard() { trophyCardOpen = false; trophyFocusID = nil }
    func setTrophyCase(visible: Bool) {
        race.trophies.setCaseVisible(visible)
        if !visible { trophyFocusID = nil }
    }
    func focusTrophy(_ id: String) {
        guard race.trophies.caseVisible, let s = TrophyShelfGeometry.slots(race.trophies.roomShelf(contestBest: show.progress.bestCup)).first(where: { $0.id == id }) else { return }
        GameCamera.trophyAt = SIMD2(s.x, s.y)
        trophyFocusID = id
        AudioHub.shared.uiTap()
        if let it = trophyFocused { A11yEvents.say("\(trophyWinnerName(it)). \(it.event). \(it.dateLine)", .normal) }
    }
    func unfocusTrophy() { trophyFocusID = nil }

    /// Once per fixed step: eases the camera toward the focused trophy and back.
    func tickTrophyFocus(dt: Float) {
        let target: Float = trophyFocusID != nil ? 1 : 0
        guard trophyFocusT != target else { return }
        let step = dt / 0.5
        trophyFocusT = target > trophyFocusT ? min(trophyFocusT + step, 1) : max(trophyFocusT - step, 0)
        GameCamera.trophyBlend = trophyFocusT * trophyFocusT * (3 - 2 * trophyFocusT)
    }

    /// Where a tap on the wall lands on the case: a trophy (its id), or just the case's face (`face`), else nothing. `ndc`/`invViewProj` are from the frame on screen.
    func trophyHit(wall w: SIMD2<Float>) -> (item: String?, face: Bool) {
        let spec = race.trophies.roomShelf(contestBest: show.progress.bestCup)
        guard race.trophies.caseVisible, let f = TrophyShelfGeometry.faceRect(spec), w.x >= f.x0 - 0.05, w.x <= f.x1 + 0.05, w.y >= f.y0, w.y <= f.y1 else { return (nil, false) }
        let hit = TrophyShelfGeometry.slots(spec).filter { abs($0.x - w.x) < 0.12 && abs($0.y - w.y) < 0.2 }.min { simd_distance(SIMD2($0.x, $0.y), w) < simd_distance(SIMD2($1.x, $1.y), w) }
        return (hit?.id, true)
    }
}

// MARK: - Screens

/// The card (double tap on the case) and the plate (a focused trophy). Transparent to touches except the card, the plate and the focus view's "Back".
struct TrophyCaseOverlay: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    private var compact: Bool { vsc == .compact }

    var body: some View {
        GeometryReader { g in
            ZStack {
                if let item = care.trophyFocused {
                    TrophyGoldOutline(care: care, id: item.id).allowsHitTesting(false).accessibilityHidden(true)
                    Color.clear.contentShape(Rectangle()).onTapGesture { care.unfocusTrophy() }
                        .accessibilityHidden(true)
                    plate(item).frame(maxWidth: 360)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.horizontal, 16).padding(.bottom, compact ? 16 : g.size.height * 0.31)          // (portrait: above the left button rail; landscape: centred, clear of the rail)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if care.trophyCardOpen {
                    // portrait: lifted clear of the left button column (as the plate is); landscape: a wider card at the right, under the coin pill and left of the paw button's column
                    TrophyShelfCard(care: care, compact: compact, maxListHeight: compact ? g.size.height - 152 : g.size.height * 0.69 - 262)
                        .frame(maxWidth: compact ? 600 : 420)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .bottomTrailing : .bottom)
                        .padding(.leading, 12).padding(.trailing, compact ? 92 : 12).padding(.bottom, compact ? 12 : g.size.height * 0.31)
                        .transition(.move(edge: compact ? .trailing : .bottom).combined(with: .opacity))
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .animation(.easeInOut(duration: 0.25), value: care.trophyCardOpen)
            .animation(.easeInOut(duration: 0.25), value: care.trophyFocusID)
        }
        .allowsHitTesting(care.trophyCardOpen || care.trophyFocusID != nil)
    }

    /// The engraved brass plate.
    private func plate(_ item: TrophyShelfItem) -> some View {
        let name = care.trophyWinnerName(item), date = item.dateLine
        let brass = Color(red: 0.80, green: 0.62, blue: 0.28), dark = Color(red: 0.36, green: 0.24, blue: 0.08)
        return VStack(spacing: 10) {
            VStack(spacing: 6) {
                Text(name).font(SK.font(24, .black)).foregroundStyle(dark)
                Text(item.event).font(SK.font(16, .heavy)).foregroundStyle(dark).multilineTextAlignment(.center)
                Rectangle().fill(dark.opacity(0.35)).frame(height: 1).padding(.horizontal, 24)
                Text(date).font(SK.font(15, .bold)).foregroundStyle(dark.opacity(0.85))
            }
            .shadow(color: .white.opacity(0.55), radius: 0, x: 0, y: 1)          // (the engraved look: a light edge under dark letters)
            .padding(.horizontal, 22).padding(.vertical, 16).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(colors: [brass.opacity(0.95), Color(red: 0.93, green: 0.80, blue: 0.48), brass], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(dark.opacity(0.5), lineWidth: 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Engraved plate. \(name). \(item.event). \(date)")
            .accessibilityIdentifier("trophy-plate")
            Button { care.unfocusTrophy() } label: {
                Text("Back").font(SK.font(16, .black)).foregroundStyle(SK.ink).padding(.horizontal, 28).frame(minHeight: 44).background(Capsule().fill(SK.cream))
            }.buttonStyle(.plain).accessibilityIdentifier("trophy-plate-back")
        }
    }
}

/// The focused trophy's outline shape, made once per trophy from its own mesh (`TrophyShelfGeometry.singleMesh`, the same cup / rosette code that draws it on the wall):
/// the triangles are filled into a small mask (2.5 mm a cell, seen straight on), the mask grown one cell to close seams, its outer edge walked (Moore tracing),
/// then smoothed and thinned to ~130 points. Cached; the per-frame work is only projecting those points through the stage camera and pushing them out a few points.
nonisolated enum TrophyContour {
    static let cell: Float = 0.0025
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: (pts: [SIMD2<Float>], lift: Float)] = [:]

    /// The contour in wall units, relative to the trophy's foot at x = 0 (add the slot's x and the slot's y - lift), and the lift.
    static func get(_ id: String) -> (pts: [SIMD2<Float>], lift: Float)? {
        lock.lock(); defer { lock.unlock() }
        if let c = cache[id] { return c }
        guard let (mesh, lift) = TrophyShelfGeometry.singleMesh(id: id), let pts = build(mesh), pts.count > 8 else { return nil }
        cache[id] = (pts, lift)
        return (pts, lift)
    }

    private static func build(_ m: RoomMesh) -> [SIMD2<Float>]? {
        guard !m.vertices.isEmpty else { return nil }
        var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for v in m.vertices { lo = simd_min(lo, SIMD2(v.pos.x, v.pos.y)); hi = simd_max(hi, SIMD2(v.pos.x, v.pos.y)) }
        let closeR = 7, margin: Float = Float(closeR + 3) * cell          // (closeR: the closing radius below, in cells)
        let x0 = lo.x - margin, y1 = hi.y + margin
        let W = Int((hi.x - lo.x + 2 * margin) / cell) + 1, H = Int((hi.y - lo.y + 2 * margin) / cell) + 1
        var mask = [Bool](repeating: false, count: W * H)
        func px(_ p: SIMD4<Float>) -> SIMD2<Float> { SIMD2((p.x - x0) / cell, (y1 - p.y) / cell) }          // (cell units, y down)
        var i = 0
        while i + 2 < m.indices.count {
            let a = px(m.vertices[Int(m.indices[i])].pos), b = px(m.vertices[Int(m.indices[i + 1])].pos), c = px(m.vertices[Int(m.indices[i + 2])].pos)
            i += 3
            let minx = max(0, Int(min(a.x, b.x, c.x).rounded(.down))), maxx = min(W - 1, Int(max(a.x, b.x, c.x).rounded(.up)))
            let miny = max(0, Int(min(a.y, b.y, c.y).rounded(.down))), maxy = min(H - 1, Int(max(a.y, b.y, c.y).rounded(.up)))
            if minx > maxx || miny > maxy { continue }
            let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
            for y in miny...maxy {
                for x in minx...maxx {
                    let p = SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5)
                    if abs(area) < 1e-6 { continue }
                    let w0 = ((b.x - p.x) * (c.y - p.y) - (b.y - p.y) * (c.x - p.x)) / area
                    let w1 = ((c.x - p.x) * (a.y - p.y) - (c.y - p.y) * (a.x - p.x)) / area
                    let w2 = 1 - w0 - w1
                    if w0 >= -0.02 && w1 >= -0.02 && w2 >= -0.02 { mask[y * W + x] = true }
                }
            }
        }
        // grow one cell (3x3) so thin faces and seams close
        var g = mask
        for y in 0..<H { for x in 0..<W where mask[y * W + x] {
            for dy in -1...1 { for dx in -1...1 { let xx = x + dx, yy = y + dy; if xx >= 0, yy >= 0, xx < W, yy < H { g[yy * W + xx] = true } } }
        } }
        // morphological closing (grow, then shrink by the same disc, 7 cells = 1.75 cm) bridges the slits between a handle and the bowl so they read as one shape;
        // the open space beside the stem and the foot is far wider than the disc, so the waist stays
        var disc: [(Int, Int)] = []
        for dy in -closeR...closeR { for dx in -closeR...closeR where dx * dx + dy * dy <= closeR * closeR { disc.append((dx, dy)) } }
        var d = g
        for y in 0..<H { for x in 0..<W where g[y * W + x] {
            for (dx, dy) in disc { let xx = x + dx, yy = y + dy; if xx >= 0, yy >= 0, xx < W, yy < H { d[yy * W + xx] = true } }
        } }
        g = d
        for y in 0..<H { for x in 0..<W where d[y * W + x] {
            for (dx, dy) in disc { let xx = x + dx, yy = y + dy; if xx < 0 || yy < 0 || xx >= W || yy >= H || !d[yy * W + xx] { g[y * W + x] = false; break } }
        } }
        func on(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < W && y < H && g[y * W + x] }
        guard let start = (0..<(W * H)).first(where: { g[$0] }) else { return nil }
        let sx = start % W, sy = start / W
        // Moore tracing, clockwise on screen; directions E SE S SW W NW N NE
        let dirs: [(Int, Int)] = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
        var path: [(Int, Int)] = [(sx, sy)]
        var cx = sx, cy = sy, back = 4, firstDir = -1
        for _ in 0..<(W * H * 4) {
            var found = -1
            for k in 1...8 { let d = (back + k) % 8; if on(cx + dirs[d].0, cy + dirs[d].1) { found = d; break } }
            if found < 0 { break }          // (a single pixel)
            if cx == sx && cy == sy && firstDir >= 0 && found == firstDir { break }
            if firstDir < 0 { firstDir = found }
            let prev = (found + 7) % 8          // the last background neighbour looked at, as seen from the old pixel
            let nx = cx + dirs[found].0, ny = cy + dirs[found].1
            let bx = cx + dirs[prev].0 - nx, by = cy + dirs[prev].1 - ny
            back = dirs.firstIndex(where: { $0.0 == bx && $0.1 == by }) ?? ((found + 4) % 8)
            cx = nx; cy = ny
            if cx == sx && cy == sy { path.append((cx, cy)) } else { path.append((cx, cy)) }
        }
        if path.count > 1, path.last! == path.first! { path.removeLast() }
        var pts = path.map { SIMD2<Float>(x0 + (Float($0.0) + 0.5) * cell, y1 - (Float($0.1) + 0.5) * cell) }
        // smooth (circular moving average, twice) and thin
        for _ in 0..<2 {
            let n = pts.count, q = pts
            for j in 0..<n { var s = SIMD2<Float>(repeating: 0); for o in -3...3 { s += q[(j + o + n) % n] }; pts[j] = s / 7 }
        }
        return stride(from: 0, to: pts.count, by: 3).map { pts[$0] }
    }

    /// `pts` (screen, a closed loop) pushed outward by `d` points, then ironed once.
    static func grown(_ pts: [CGPoint], by d: CGFloat) -> [CGPoint] {
        let n = pts.count
        guard n > 8 else { return pts }
        var area: CGFloat = 0
        for j in 0..<n { let a = pts[j], b = pts[(j + 1) % n]; area += a.x * b.y - b.x * a.y }
        let sgn: CGFloat = area > 0 ? 1 : -1          // (y down: positive = clockwise on screen, whose outward normal is (ty, -tx))
        var out = (0..<n).map { j -> CGPoint in
            let a = pts[(j + n - 2) % n], b = pts[(j + 2) % n], p = pts[j]
            var nx = (b.y - a.y) * sgn, ny = -(b.x - a.x) * sgn
            let l = hypot(nx, ny)
            if l < 1e-6 { return p }
            nx /= l; ny /= l
            return CGPoint(x: p.x + nx * d, y: p.y + ny * d)
        }
        let q = out
        for j in 0..<n { let a = q[(j + n - 1) % n], b = q[(j + 1) % n]; out[j] = CGPoint(x: 0.25 * a.x + 0.5 * q[j].x + 0.25 * b.x, y: 0.25 * a.y + 0.5 * q[j].y + 0.25 * b.y) }
        return out
    }
}

/// The focused trophy's highlight: the selected Jelmiko's outline look (glow layers, a solid core, a white line, the 0.7 s soft pulse; Selection/SelectionOverlay.swift) in gold,
/// following the trophy's own silhouette (`TrophyContour`), projected through the stage's camera each frame. Follows the camera ease; gone when the focus ends.
struct TrophyGoldOutline: View {
    let care: GameCare
    let id: String
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.16)
    static let pad: CGFloat = 5          // (as the selected Jelmiko's: the gap between the true edge and the line's centre)
    var body: some View {
        let shape = TrophyContour.get(id)
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, _ in
                guard let shape, let proj = care.trophyProj, let s = TrophyShelfGeometry.slots(care.race.trophies.roomShelf(contestBest: care.show.progress.bestCup)).first(where: { $0.id == id }) else { return }
                let z = RoomLayout.minZ + 0.13, base = SIMD2(s.x, s.y - shape.lift)          // (z: the cup's axis, as `TrophyShelfGeometry.add`)
                let w = shape.pts.map { SIMD3<Float>(base.x + $0.x, base.y + $0.y, z) }
                let scr = Silhouette.project(w, viewProj: proj.vp, size: proj.size)
                guard scr.count == w.count else { return }
                let pts = TrophyContour.grown(scr, by: Self.pad)
                var p = Path(); p.move(to: pts[0]); for q in pts.dropFirst() { p.addLine(to: q) }; p.closeSubpath()
                let glow = A11ySettings.shared.reduceMotion ? 1.0 : 0.5 + 0.5 * sin(t * 2 * .pi / 0.7 - .pi / 2)
                let style = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
                for (w, a) in [(26.0, 0.10), (16.0, 0.18), (9.0, 0.30)] { ctx.stroke(p, with: .color(Self.gold.opacity(a * (0.55 + 0.45 * glow))), style: style(w)) }
                ctx.stroke(p, with: .color(Self.gold), style: style(4.6))
                ctx.stroke(p, with: .color(.white.opacity(0.85)), style: style(1.6))
            }
            .ignoresSafeArea()
        }
        .id(id)
    }
}

/// "Show trophy shelf in the room": the switch, on the card, in the Trophies sheet; Settings > Game has its own row on the same flag (care.setTrophyCase).
struct TrophyCaseToggle: View {
    let care: GameCare
    var body: some View {
        Toggle(isOn: Binding(get: { care.race.trophies.caseVisible }, set: { care.setTrophyCase(visible: $0) })) {
            Text("Show trophy shelf in the room").font(SK.font(15, .black)).foregroundStyle(SK.ink)
        }
        .tint(SK.sky)
        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.8)))
        .accessibilityIdentifier("trophy-case-toggle")
    }
}
