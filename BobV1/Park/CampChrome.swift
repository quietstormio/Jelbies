//
//  CampChrome.swift
//  The Camp yard's screen furniture (camp-yard-r1 Y5 / Y6): the header "Jelmiko Camp n/6", the sound button and the coins, a chip per Camp creature (a "New!" mark on the newcomer until it is
//  tapped), the card of the selected creature (Bring home / Say goodbye / close), "Drop off" and "Home" at the bottom, the empty yard's one friendly line, and the sheets: "Who goes to Camp?" (the swap
//  when home is full, and Drop off) and "Say goodbye to <name>?" (press and hold). Views only: GameCare+Camp.swift owns the rules and goes through the core's wrappers. Every sheet reads the SAVED
//  lists (JellyRoster.savedIDs / JellyCamp.saved), never the live room.
//

import SwiftUI

@MainActor
@Observable
final class CampUI {
    static let shared = CampUI()
    enum Sheet: Equatable { case none, swap(incoming: Int), dropOff, goodbye(Int) }
    struct Leaving { enum Stage { case waving, walking, done }; var bodyID: Int; var instance: Int; var stage: Stage; var t: Float }
    /// The selected creature (instance id).
    var selected: Int?
    var sheet: Sheet = .none
    /// The yard's creatures, as copied when their bodies appeared (arrival order): the header count and the chips.
    var members: [CampCreature] = []
    /// The newcomer who gets a "New!" mark until tapped once.
    var arrival: Int?
    /// A move is under way (a goodbye walking, a wipe coming): the card and the buttons wait.
    var moving = false
    var pendingToast: String?
    @ObservationIgnored var leaving: Leaving? { didSet { moving = leaving != nil || moving } }
    @ObservationIgnored var entryHome: [Int]?
    /// The drag that began on a Camp body (stage touch): a stroke starts after 30 pt of movement.
    @ObservationIgnored var drag: (id: ObjectIdentifier, start: CGPoint, body: Int?)?
    /// The stroke in progress: the body id, when the finger last moved, the last heart.
    @ObservationIgnored var stroke: (body: Int, lastMove: Double, lastHeart: Double, began: Double)?
    @ObservationIgnored var strokeWasAutonomous: [Int: Bool] = [:]
    /// What the strokes asked for (the test counts these; the sounds are counted by `AudioHub.diagCounts`).
    @ObservationIgnored var strokeStats = (hearts: 0, haptics: 0, chirps: 0)
    nonisolated deinit {}

    func beginDrag(id: ObjectIdentifier, at p: CGPoint, body: Int?) { drag = (id, p, body) }
    /// A finger moved: true when this drag is a Camp drag (the stage does nothing else with it).
    func dragMoved(id: ObjectIdentifier, to p: CGPoint, now: Double) -> Bool {
        guard let d = drag, d.id == id else { return false }
        if let b = d.body, hypot(p.x - d.start.x, p.y - d.start.y) >= 30 { strokeMoved(body: b, now: now) }
        return true
    }
    func strokeMoved(body: Int, now: Double) {
        if stroke?.body != body { stroke = (body, now, now - 0.3, now) } else { stroke?.lastMove = now }
    }
    func endDrag(id: ObjectIdentifier) -> Bool { guard let d = drag, d.id == id else { return false }; drag = nil; return true }

    /// The Town square's sub-line.
    static func townSub(count: Int) -> String { count == 0 ? "Nobody here yet" : "\(count) at Camp" }
    func select(_ id: Int) { selected = id; if arrival == id { arrival = nil } }
    func reset(arrival: Int?) { drag = nil; stroke = nil; strokeWasAutonomous = [:]; selected = nil; sheet = .none; members = []; self.arrival = arrival; moving = false; leaving = nil; pendingToast = nil; entryHome = nil }
    /// A move is committed: the sheet closes, the card waits for the wipe.
    func finishMove() { sheet = .none; selected = nil; moving = true }
}

struct CampChrome: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    @State private var soundOpen = false
    @State private var picked: Int?
    private var park: ParkTrip { care.park }
    private var ui: CampUI { CampUI.shared }
    private let brown = Color(hex: 0x4A3020)

    private func tint(_ id: Int) -> Color { let t = JellyRoster.tint(id); return Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z)) }
    private var selectedCreature: CampCreature? { ui.selected.flatMap { s in ui.members.first { $0.id == s } } }

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width > g.size.height
            ZStack {
                if park.inScene {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            header
                            if wide { soundButton; countChip; chips.frame(maxWidth: .infinity) } else { Spacer(minLength: 0) }
                            DropsPill(wallet: care.bath.wallet).fixedSize().layoutPriority(3)
                        }
                        if !wide { HStack(spacing: 8) { soundButton; countChip; chips } }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                }
                if soundOpen, park.inScene {
                    VStack { HStack { SoundSettingsPanel(hub: AudioHub.shared) { withAnimation(CareMenu.spring) { soundOpen = false } }; Spacer() }; Spacer() }
                        .padding(.top, 60).padding(.leading, 12)
                }
                if park.phase == .playing {
                    TipAnchor("camp", ready: !ui.members.isEmpty, delay: 0.8)          // the first-time tip: once somebody is at Camp
                    if ui.members.isEmpty, ui.sheet == .none { emptyCard }
                    if let c = selectedCreature, ui.sheet == .none, !ui.moving {
                        if wide { HStack { Spacer(); card(c).frame(width: min(320, g.size.width * 0.37)).padding(.top, 70).padding(.bottom, 90).padding(.trailing, 8) } }
                        else { VStack { Spacer(); card(c).padding(.horizontal, 10).padding(.bottom, 14) } }
                    }
                    if ui.selected == nil, ui.sheet == .none, !ui.moving { bottomBar }
                    sheets(wide: wide)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .animation(.easeInOut(duration: 0.25), value: ui.selected)
            .animation(.easeInOut(duration: 0.25), value: ui.sheet)
        }
        .onChange(of: ui.sheet) { _, _ in picked = nil }
    }

    // MARK: top

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "tent.fill").font(.system(size: 15, weight: .heavy))
            Text("Jelmiko Camp").font(SK.font(17, .black)).lineLimit(1).fixedSize()
        }
        .foregroundStyle(SK.ink).padding(.horizontal, 12).frame(minHeight: 44).layoutPriority(1)
        .background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.2), radius: 5, y: 2))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .ignore).accessibilityLabel("Jelmiko Camp").accessibilityIdentifier("camp-header")
    }

    private var countChip: some View {
        Text("\(ui.members.count)/\(JellyCamp.cap)").font(SK.font(15, .black)).foregroundStyle(SK.ink).padding(.horizontal, 12).frame(minHeight: 44)
            .background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.2), radius: 5, y: 2))
            .accessibilityLabel("\(ui.members.count) of \(JellyCamp.cap) at Camp").accessibilityIdentifier("camp-count")
    }

    private var soundButton: some View {
        Button { AudioHub.shared.uiTap(); withAnimation(CareMenu.spring) { soundOpen.toggle() } } label: {
            Image(systemName: soundOpen ? "speaker.wave.2.fill" : "speaker.wave.2").font(.system(size: 21, weight: .semibold)).foregroundStyle(CareMenu.brown)
                .frame(width: 48, height: 44).background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.2), radius: 5, y: 2))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain).accessibilityLabel("Sound").accessibilityIdentifier("camp-sound-button")
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ui.members, id: \.id) { c in
                    Button { guard ui.sheet == .none, !ui.moving else { return }; AudioHub.shared.uiTap(); ui.select(c.id) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(tint(c.id)).frame(width: 22, height: 22).overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5))
                            Text(c.name).font(SK.font(13, .heavy)).foregroundStyle(SK.ink).lineLimit(1)
                            if ui.arrival == c.id { Text("New!").font(SK.font(10, .black)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(SK.pinkStrong)) }
                        }
                        .padding(.horizontal, 10).frame(minHeight: 44)
                        .background(Capsule().fill(ui.selected == c.id ? SK.honey : SK.cream.opacity(0.92)))
                    }
                    .buttonStyle(.plain).accessibilityLabel("\(c.name), at Camp" + (ui.arrival == c.id ? ", new" : "")).accessibilityAddTraits(ui.selected == c.id ? .isSelected : [])
                    .accessibilityIdentifier("camp-chip-\(c.id)")
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("camp-chips")
    }

    // MARK: cards and buttons

    private func card(_ c: CampCreature) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Circle().fill(tint(c.id)).frame(width: 52, height: 52).overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.name).font(SK.font(26, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                    Text("At Camp").font(SK.font(14, .heavy)).foregroundStyle(SK.muted)
                }
                Spacer(minLength: 0)
                Button { AudioHub.shared.uiTap(); ui.selected = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .black)).foregroundStyle(SK.ink).frame(width: 46, height: 46).background(Circle().fill(Color.white.opacity(0.85)))
                }
                .buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("camp-card-close")
            }
            HStack(spacing: 10) {
                Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); care.campBringHomeTapped(c.id) } label: {
                    HStack(spacing: 6) { Image(systemName: "house.fill"); Text("Bring home").lineLimit(1).minimumScaleFactor(0.5) }
                        .font(SK.font(19, .black)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 56)
                        .background(Capsule().fill(SK.honey))
                }
                .buttonStyle(.plain).accessibilityIdentifier("camp-bring-home")
                Button { AudioHub.shared.uiTap(); ui.sheet = .goodbye(c.id) } label: {
                    Text("Say goodbye").font(SK.font(16, .heavy)).foregroundStyle(SK.muted).lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 16).frame(minHeight: 56).background(Capsule().fill(Color.white.opacity(0.7)))
                }
                .buttonStyle(.plain).accessibilityIdentifier("camp-goodbye")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.25), radius: 10, y: 3))
        .accessibilityIdentifier("camp-card")
    }

    private var bottomBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); care.campDropOffTapped() } label: {
                    HStack(spacing: 8) { Image(systemName: "square.and.arrow.down"); Text("Drop off") }
                        .font(SK.font(17, .black)).foregroundStyle(SK.ink).padding(.horizontal, 20).frame(minHeight: 54)
                        .background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.25), radius: 6, y: 3))
                }
                .buttonStyle(.plain).accessibilityIdentifier("camp-dropoff")
                Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); park.goHome() } label: {
                    HStack(spacing: 8) { Image(systemName: "house.fill"); Text("Home") }
                        .font(SK.font(19, .black)).foregroundStyle(SK.ink).padding(.horizontal, 30).frame(minHeight: 54)
                        .background(Capsule().fill(SK.honey).shadow(color: SK.shadow.opacity(0.25), radius: 6, y: 3))
                }
                .buttonStyle(.plain).accessibilityIdentifier("camp-home")
            }
            .padding(.bottom, 24)
        }
        .transition(.opacity)
    }

    private var emptyCard: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "tent.fill").font(.system(size: 26, weight: .heavy)).foregroundStyle(SK.ink).frame(width: 64, height: 64).background(Circle().fill(SK.mint))
                Text("Nobody at Camp yet").font(SK.font(22, .black)).foregroundStyle(SK.ink)
                Text("When home is full, a new Jelmiko waits here. Find one at the Jelly Spring.").font(SK.font(15, .bold)).foregroundStyle(SK.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22).padding(.vertical, 18).frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.22), radius: 8, y: 3))
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader).accessibilityIdentifier("camp-empty")
            Spacer().frame(height: 170)
        }
    }

    // MARK: sheets (they read the SAVED lists)

    @ViewBuilder private func sheets(wide: Bool) -> some View {
        switch ui.sheet {
        case .none: EmptyView()
        case .swap(let incoming): pickSheet(title: "Who goes to Camp?", line: "\(JellyRoster.nameOf(incoming)) is coming home", incoming: incoming, button: "Swap", wide: wide) { out in care.campSwapConfirmed(incoming: incoming, out: out) }
        case .dropOff: pickSheet(title: "Who goes to Camp?", line: nil, incoming: nil, button: "Send to Camp", wide: wide) { id in care.campDropOffConfirmed(id) }
        case .goodbye(let id): goodbyeSheet(id: id)
        }
    }

    private func dim(_ close: @escaping () -> Void) -> some View {
        Color(red: 0.30, green: 0.20, blue: 0.14).opacity(0.42).ignoresSafeArea().onTapGesture(perform: close).accessibilityHidden(true)
    }

    private func pickSheet(title: String, line: String?, incoming: Int?, button: String, wide: Bool, go: @escaping (Int) -> Void) -> some View {
        let home = JellyRoster.savedIDs()
        return ZStack(alignment: .bottom) {
            dim { ui.sheet = .none }
            VStack(spacing: 14) {
                Capsule().fill(SK.muted.opacity(0.3)).frame(width: 44, height: 5)
                Text(title).font(SK.font(26, .black)).foregroundStyle(SK.ink).accessibilityAddTraits(.isHeader)
                if let line, let incoming {
                    HStack(spacing: 8) { Circle().fill(tint(incoming)).frame(width: 30, height: 30); Text(line).font(SK.font(17, .heavy)).foregroundStyle(SK.muted) }
                }
                HStack(spacing: 10) {
                    ForEach(home, id: \.self) { id in
                        let on = picked == id
                        Button { AudioHub.shared.uiTap(); picked = id } label: {
                            VStack(spacing: 6) {
                                Circle().fill(tint(id)).frame(width: 64, height: 64).overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 3))
                                Text(JellyRoster.nameOf(id)).font(SK.font(16, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(on ? SK.honey : Color.white))
                            .overlay(alignment: .topTrailing) { if on { Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(brown).padding(6) } }
                        }
                        .buttonStyle(.plain).accessibilityLabel(JellyRoster.nameOf(id)).accessibilityAddTraits(on ? .isSelected : []).accessibilityIdentifier("camp-pick-\(id)")
                    }
                }
                Button { if let p = picked { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); go(p) } } label: {
                    Text(button).font(SK.font(22, .black)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 58).background(Capsule().fill(brown))
                        .opacity(picked == nil ? 0.45 : 1)
                }
                .buttonStyle(.plain).disabled(picked == nil).accessibilityIdentifier("camp-sheet-go")
                Button { AudioHub.shared.uiTap(); ui.sheet = .none } label: { Text("Not now").font(SK.font(18, .heavy)).foregroundStyle(SK.muted).frame(minHeight: 44) }
                    .buttonStyle(.plain).accessibilityIdentifier("camp-sheet-cancel")
            }
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 16).frame(maxWidth: 560)
            .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color(hex: 0xFBF6EC)).ignoresSafeArea(edges: .bottom))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func goodbyeSheet(id: Int) -> some View {
        let name = ui.members.first { $0.id == id }?.name ?? JellyRoster.nameOf(id)
        return ZStack(alignment: .bottom) {
            dim { ui.sheet = .none }
            VStack(spacing: 10) {
                Capsule().fill(SK.muted.opacity(0.3)).frame(width: 44, height: 5)
                Text("Say goodbye to \(name)?").font(SK.font(26, .black)).foregroundStyle(SK.ink).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                VStack(spacing: 4) {
                    Text("\(name) goes back to the Jelly Spring for good.")
                    Text("\(name)'s tricks and trophies go too.")
                    Text("\(name)'s clothes go back to your bag.")
                }
                .font(SK.font(17, .bold)).foregroundStyle(SK.muted).multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Text("JC").font(SK.font(11, .black)).foregroundStyle(SK.ink).frame(width: 30, height: 30).background(Circle().fill(SK.honeyDeep))
                    Text("+\(JellyCamp.thankYouCoins) thank-you").font(SK.font(17, .heavy)).foregroundStyle(SK.ink)
                }
                .padding(.vertical, 4)
                Button { AudioHub.shared.uiTap(); ui.sheet = .none } label: {
                    Text("Keep \(name)").font(SK.font(22, .black)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 58).background(Capsule().fill(brown))
                }
                .buttonStyle(.plain).accessibilityIdentifier("camp-goodbye-keep")
                HoldToConfirm(title: "Hold to say goodbye", id: "camp-goodbye-hold", tint: Color(hex: 0x8C7565)) { care.campGoodbyeConfirmed(id) }
                    .padding(.horizontal, 24).padding(.top, 4)
            }
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 18).frame(maxWidth: 560)
            .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color(hex: 0xFBF6EC)).ignoresSafeArea(edges: .bottom))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
