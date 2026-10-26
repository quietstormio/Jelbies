//
//  RaceTrophiesSection.swift
//  The race half of a Jelbie's Trophies sheet (the sheet opens from the "Trophies" row of his condition card): a ribbon row per course tier with how many
//  1st / 2nd / 3rd places he has (the place is written out, so it never rests on colour alone), and the milestone trophies as chips, dimmed with what
//  earns them until they are won. The contest ribbons (Show cups) are the sheet's own "Cups" row above it.
//

import SwiftUI

struct RaceTrophiesSection: View {
    let care: GameCare
    var who: Int

    private static let medal: [Color] = [Color(red: 0.98, green: 0.80, blue: 0.35), Color(red: 0.80, green: 0.84, blue: 0.90), Color(red: 0.90, green: 0.68, blue: 0.52)]
    private static let ords = ["1st", "2nd", "3rd"]

    var body: some View {
        let shelf = care.race.trophies.shelf(character: care.jelly(who)?.character ?? who)
        VStack(alignment: .leading, spacing: 10) {
            Text("Race ribbons").font(SK.font(13, .semibold)).foregroundStyle(SK.muted).textCase(.uppercase).accessibilityAddTraits(.isHeader)
            VStack(spacing: 6) {
                ForEach(CourseTier.allCases, id: \.rawValue) { t in
                    let r = shelf.raceRibbons(t)
                    HStack(spacing: 6) {
                        Text(t.title).font(SK.font(13, .semibold)).foregroundStyle(SK.ink).frame(width: 74, alignment: .leading)
                        ForEach(0..<3, id: \.self) { k in
                            HStack(spacing: 3) {
                                Image(systemName: UIImage(systemName: "rosette") != nil ? "rosette" : "seal.fill").font(.system(size: 12, weight: .semibold))
                                Text("\(Self.ords[k]) \u{00D7}\(r[k])").font(SK.font(11, .semibold)).monospacedDigit()
                            }
                            .foregroundStyle(r[k] > 0 ? SK.ink : SK.muted)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(Capsule().fill(r[k] > 0 ? Self.medal[k] : DT.card))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(t.title) ribbons: \(r[0]) first, \(r[1]) second, \(r[2]) third")
                    .accessibilityIdentifier("ribbons-\(t.rawValue)")
                }
            }
            Text("Race trophies").font(SK.font(13, .semibold)).foregroundStyle(SK.muted).textCase(.uppercase).accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 6) {
                ForEach(Trophy.all) { t in
                    let has = shelf.has(t)
                    HStack(spacing: 4) {
                        Image(systemName: has ? "trophy.fill" : "lock.fill").font(.system(size: 11, weight: .semibold))
                        Text(has ? t.title : t.detail).font(SK.font(12, .semibold))
                    }
                    .foregroundStyle(has ? SK.ink : SK.muted)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(has ? Self.medal[0] : DT.card))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(has ? "\(t.title), earned" : "\(t.detail), not yet")
                    .accessibilityIdentifier("trophy-\(t.id)")
                }
            }
            Text(shelf.raceWins == 0 ? "No race wins yet." : "\(shelf.raceWins) race win\(shelf.raceWins == 1 ? "" : "s") so far.").font(SK.font(12, .bold)).foregroundStyle(SK.muted)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("race-trophies")
    }
}
