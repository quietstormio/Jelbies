//
//  HUDControls.swift
//  The one main HUD control (the paw, side of the screen) as a pure model: with nobody highlighted it serves the GROUP
//  (Feed, Snacks, Drink, Play, Decor, Bedtime); with a Jelbie highlighted it serves HIM (Dress, Clean, Train, Compete, Come here).
//  CareMenu draws it; the tests drive it headless.
//

import SwiftUI

enum HUDMode: Equatable { case group, individual(Int) }

enum HUDItem: String, CaseIterable {           // the raw value is the accessibility identifier
    case feed = "care-feed", snacks = "care-snacks", drink = "care-water", play = "hud-play", decor = "hud-decor", bedtime = "hud-bedtime"
    case come = "hud-come", dress = "hud-dress", clean = "care-clean", train = "hud-train", compete = "hud-compete"
}

enum HUDRoute: Equatable {
    case none, picker(ConsumableKind), snacks, bag(BagSheet.BagTab, who: Int), town(TownScreen, who: Int), competeChips
}

@MainActor
enum HUDMenu {
    /// `.individual(id)` when a Jelbie is highlighted (a settled pick, or a draw in progress), else `.group`.
    static func mode(_ care: GameCare) -> HUDMode {
        if let id = care.select.highlighted ?? care.select.selectedID, care.jelly(id) != nil { return .individual(id) }
        return .group
    }

    /// Top to bottom. Six rows in the group menu, five in his (Come here last, nearest the thumb). Feed and Drink are the group's: a hungry / thirsty bubble drops the highlight and opens them there.
    static func items(_ mode: HUDMode) -> [HUDItem] {
        switch mode {
        case .group: return [.feed, .snacks, .drink, .play, .decor, .bedtime]
        case .individual: return [.dress, .clean, .train, .compete, .come]
        }
    }

    static func title(_ i: HUDItem, _ mode: HUDMode, care: GameCare) -> String {
        var name: String?
        if case .individual(let id) = mode { name = care.jelly(id)?.name }
        switch i {
        case .feed: return name.map { "Feed \($0)" } ?? "Feed"
        case .come: return "Come here"
        case .snacks: return "Snacks"
        case .drink: return name.map { "Water \($0)" } ?? "Drink"
        case .play: return "Play"
        case .decor: return "Decor"
        case .bedtime: return "Bedtime"
        case .dress: return "Dress"
        case .clean: return "Clean"
        case .train: return "Train"
        case .compete: return "Compete"
        }
    }

    /// What VoiceOver reads: the visible title, except Come here and Train name who they are for.
    static func spokenLabel(_ i: HUDItem, _ mode: HUDMode, care: GameCare) -> String {
        if case .individual(let id) = mode, let name = care.jelly(id)?.name {
            if i == .come { return "Call \(name) over" }
            if i == .train { return "Train \(name)" }
        }
        return title(i, mode, care: care)
    }

    private static func sym(_ name: String, _ fallback: String) -> String { UIImage(systemName: name) != nil ? name : fallback }
    static func symbol(_ i: HUDItem) -> String {
        switch i {
        case .feed: return "fork.knife"
        case .come: return sym("hand.wave.fill", "hand.raised.fill")
        case .snacks: return "bag.fill"
        case .drink: return CareMenu.waterSymbol
        case .play: return sym("teddybear.fill", "soccerball")
        case .decor: return sym("sofa.fill", "chair.lounge.fill")
        case .bedtime: return "moon.zzz.fill"
        case .dress: return "tshirt.fill"
        case .clean: return CareMenu.cleanSymbol
        case .train: return sym("graduationcap.fill", "star.fill")
        case .compete: return CareMenu.raceSymbol
        }
    }

    static func enabled(_ i: HUDItem, _ mode: HUDMode, care: GameCare) -> Bool {
        let id: Int = { if case .individual(let n) = mode { return n }; return care.targetJelly }()
        switch i {
        case .feed, .snacks, .drink: return !care.trayOut && !care.bath.active
        case .clean: return care.canClean(jelly: id)
        case .train: return !care.focus.isActive && !care.bath.active && !care.tripActive
        case .come: return care.focus.phase == .roaming && !care.bath.active && !care.tripActive && !care.raceBusy
        case .compete: return care.canRace(jelly: id) || care.canShow(jelly: id)
        case .bedtime: return !care.raceBusy && !care.trayOut && !care.bath.active
        case .play, .decor, .dress: return true
        }
    }

    /// Why a row is disabled, in words for VoiceOver (nil = it is enabled). Mirrors `enabled`.
    static func disabledReason(_ i: HUDItem, _ mode: HUDMode, care: GameCare) -> String? {
        guard !enabled(i, mode, care: care) else { return nil }
        let id: Int = { if case .individual(let n) = mode { return n }; return care.targetJelly }()
        switch i {
        case .feed, .snacks, .drink: return care.trayOut ? "Food is already out" : "Not while cleaning"
        case .clean:
            if care.bath.active { return "Already cleaning" }
            if care.trayOut { return "Not while food is out" }
            if care.tripActive { return "Not while racing" }
            if care.focus.isActive { return "Not in the close-up" }
            return "Not available right now"
        case .come:
            if care.focus.isActive { return "Already in the close-up" }
            if care.bath.active { return "Not while cleaning" }
            return "Not while racing"
        case .train:
            if care.focus.isActive { return "Already in the close-up" }
            if care.bath.active { return "Not while cleaning" }
            return "Not while racing"
        case .compete: return care.raceBlocker(jelly: id) ?? care.showBlocker(jelly: id) ?? "Not available right now"
        case .bedtime:
            if care.raceBusy { return "Already racing" }
            if care.trayOut { return "Food is already out" }
            return "Not while cleaning"
        case .play, .decor, .dress: return nil
        }
    }

    /// Runs a care action, or returns the UI route the screen must open.
    @discardableResult
    static func perform(_ i: HUDItem, _ mode: HUDMode, care: GameCare) -> HUDRoute {
        let id: Int = { if case .individual(let n) = mode { return n }; return care.targetJelly }()
        switch i {
        case .feed: return .picker(.food)
        case .drink: return .picker(.drink)
        case .snacks: return .snacks
        case .play: return .bag(.toys, who: id)
        case .decor: return .bag(.furniture, who: id)
        case .dress: return .bag(.wear, who: id)
        case .bedtime: care.bedtimeAll(); care.clearHighlight(); return .none
        case .clean: care.clean(jelly: id); return .none
        case .come: care.comeHere(jelly: id); return .none
        case .train: care.beginTraining(id); return .none
        case .compete: return .competeChips
        }
    }

    static func compete(_ dest: TownScreen, id: Int) -> HUDRoute { .town(dest, who: id) }
}
