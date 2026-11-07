//
//  RivalNames.swift
//  The other people's Jelbies in the competitions (Jelly Circuit races, Jelly Show) draw their names and colours from ONE shared list (2026-11-07, "I don't want to meet
//  the same Jelbies ... in competitions"). It used to be 12 names, 9 of them also Park visitors; now ~50, none of them a Park visitor, and 12 hues (not 6).
//  Race also keeps a short memory of the last rivals met, so the next race skips them (RivalMemory).
//

import Foundation

nonisolated enum RivalNames {
    /// Competition names: disjoint from ParkWords.names, ParkNames.spare and ParkWords.extraNames (ParkVarietyTests checks it).
    static let all = ["Dumpling", "Pudding", "Fizz", "Gumdrop", "Squish", "Boba", "Jiggles", "Wobbles", "Zuzu", "Kipper", "Lollipop", "Bubba", "Gadget",
                      "Pippin", "Rascal", "Tumble", "Nugget", "Quincy", "Rocket", "Scout", "Tater", "Waddles", "Zephyr", "Biscotti", "Churro", "Cookie",
                      "Crumpet", "Dizzy", "Flapjack", "Fuzzy", "Giggles", "Hopper", "Mitten", "Nibbles", "Puddles", "Pogo", "Quackers", "Ravioli",
                      "Scooter", "Sundae", "Taco", "Whoopie", "Yoyo", "Zigzag", "Bonbon", "Cobbler", "Bloop", "Sherbet", "Jolly", "Squeak", "Marbles",
                      "Dandy", "Cuddles"]
    /// Pastel hues (0...1), each clearly inside one band of LocalRivalSource.signature(forTint:) (wings 0.60-0.85, spikes 0.10-0.17, daisy 0.17-0.45, else none):
    /// 5 plain (peach, pink, aqua, sky, rose), 3 wings, 1 spikes, 3 daisy.
    static let hues: [Float] = [0.05, 0.93, 0.50, 0.55, 0.97, 0.66, 0.72, 0.78, 0.13, 0.24, 0.31, 0.40]
}

/// The last rivals the player met in a race (names, newest last), kept on the device so the next race meets other faces.
nonisolated enum RivalMemory {
    static let key = "RaceRecentRivals.v1", keep = 9
    static func load(_ d: UserDefaults = .standard) -> [String] { d.stringArray(forKey: key) ?? [] }
    static func remember(_ names: [String], in d: UserDefaults = .standard) {
        d.set(Array((load(d) + names).suffix(keep)), forKey: key)
    }
}
