//
//  RaceTrophiesSection.swift
//  The race section of a Jelmiko's Trophies sheet (the sheet opens from the "Trophies" card of his Profile). trophy-look-r1: one rosette per course tier, coloured by the best place won there
//  (gold 1st, silver 2nd, bronze 3rd, the place numeral in the middle so it never rests on colour alone), a small "x N" count when that place was won more than once, a faint silhouette until
//  a place is won; then the milestone badges (5 / 10 / 25 wins, Champion), faint with a small lock until won. The first win on a tier is the tier's gold rosette (the "<tier> winner" trophy is
//  always earned with it); the 2nd / 3rd counts and what earns a locked badge are in each tile's VoiceOver label. The contest cups (Show) are the Show section above.
//

import SwiftUI

struct RaceTrophiesSection: View {
    let care: GameCare
    var who: Int

    private static let ords = ["1st", "2nd", "3rd"]

    var body: some View {
        let shelf = care.race.trophies.shelf(character: care.jelly(who)?.character ?? who)
        CabinetSection(title: "Jelly Race", symbol: "flag.checkered", tint: Color(hex: 0x3FA7E8), identifier: "race-trophies") {
            CabinetRow {
                ForEach(CourseTier.allCases, id: \.rawValue) { t in
                    let r = shelf.raceRibbons(t)
                    let best = shelf.bestRace(t)
                    let n = best.map { r[$0 - 1] } ?? 0
                    let tone = CabinetTone.place(best ?? 1)
                    CabinetTile(label: t.title, earned: best != nil, count: n, glow: tone.base,
                                a11y: best == nil ? "\(t.title) ribbon, not yet" : "\(t.title) ribbons: \(r[0]) first, \(r[1]) second, \(r[2]) third. Best: \(Self.ords[(best ?? 1) - 1])",
                                id: "ribbons-\(t.rawValue)") {
                        CabinetRosette(base: tone.base, text: best.map(String.init) ?? "1")
                    }
                }
            }
            CabinetRow {
                ForEach([Trophy.wins5, .wins10, .wins25, .champion]) { t in CabinetMilestone.tile(t, has: shelf.has(t)) }
            }
        }
    }
}
