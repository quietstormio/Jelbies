//
//  ShowLobby.swift
//  What the Studio lobby (StudioScreen, ShowUI.swift) shows about the Jelly Show beyond the shared lobby frame: each rank's blurb, and the score estimate with its one-line tip.
//  (The separate "Jelly Show" lobby that used to follow "Enter Jelly Show" is gone: the Studio picks the rank and the contestant, and Enter Jelly Show starts the show.)
//

import SwiftUI

extension ShowRank {
    /// The line under the carousel for each rank.
    var lobbyBlurb: String {
        switch self {
        case .puddle: return "Judges a hat and shoes. The gentlest stage."
        case .pond: return "Adds a necklace. Still kind on the beat."
        case .lagoon: return "Adds glasses. Stricter on the beat."
        case .ocean: return "The whole outfit. Duchess Marmalade headlines."
        }
    }
}

extension GameCare {
    /// What the Studio's "Show ready" card says about the score: the estimate out of 300 (rounded to ten), the rivals' average, and the tip for the weakest round.
    func showForecast(jelly id: Int, rank: ShowRank, theme: ShowTheme) -> (total: Int, rivals: Int, tip: String) {
        let est = showEstimate(jelly: id, rank: rank, theme: theme)
        let p = showPlayerInput(jelly: id)
        let outfit = showOutfitTags(jelly: id)
        let items = rank.slotOrder.compactMap { outfit[$0] }
        let match = ShowScoring.outfitMatch(items: items, slots: rank.slots, theme: theme)
        let total = Int((est.total / 10).rounded()) * 10
        // the weakest round (ties: Look, Dance, Trick) and what to do about it
        let pts = [est.lookPts, est.dancePts, est.trickPts]
        let lowest = pts.firstIndex(of: pts.min() ?? 0) ?? 0
        let tip: String
        switch lowest {
        case 0: tip = match < 1 ? "Look is lowest. Wear \(theme.main.title) things." : (p.glow < 0.5 ? "Look is lowest. A Clean adds Glow." : "Look is lowest. \(theme.main.title) food helps.")
        case 1: tip = "Dance is lowest. Tap right on the beat."
        default: tip = "Trick is lowest. Pick harder tricks (more stars) and keep your Jelbie happy and clean."
        }
        return (total, rank.rivalEstimate, tip)
    }
}
