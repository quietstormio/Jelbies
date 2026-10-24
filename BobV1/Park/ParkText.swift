//
//  ParkText.swift
//  The optional layer: Apple's on-device model (FoundationModels, the same availability check the voice commands use) writes a visitor's name, a one-line
//  personality and a greeting once, and a short line when a friendship levels up. Offline by design: no network, no accounts. The result is kept in the
//  visitor's saved record, so each is written once. When the model is missing, off or slow the hand-written words (ParkWords) stand; nothing waits on it.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What the model wrote for one visitor (already cleaned).
nonisolated struct ParkWrittenText: Sendable {
    var name: String, blurb: String, greeting: String
}

@MainActor
enum ParkText {
    /// The model can be asked right now (Apple Intelligence on, downloaded). `-VoiceNoModel 1` turns it off here too.
    static var available: Bool { AIAvailability.shared.refresh().isAvailable }

    private static let instructions = """
    You write tiny bits of text for cute jelly pet creatures in a kids' game. Keep everything gentle, kind and silly. \
    One short sentence at most. No emoji, no quotes, no hashtags, no real people, no brands.
    """

    /// A name, a personality line and a greeting for a new visitor. nil when the model is unavailable or the answer is unusable.
    static func write(colour: String, style: String, signature: String) async -> ParkWrittenText? {
        guard available else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let s = LanguageModelSession(instructions: instructions)
                let r = try await s.respond(to: "A \(colour) jelly creature with a \(style) nature\(signature.isEmpty ? "" : " and \(signature)") visits the park.",
                                            generating: ParkVisitorOut.self, options: GenerationOptions(temperature: 0.8))
                guard let name = ParkPool.clean(r.content.name, limit: 12), !name.contains(" "),
                      let blurb = ParkPool.clean(r.content.personality, limit: 56),
                      let greeting = ParkPool.clean(r.content.greeting, limit: 48) else { return nil }
                return ParkWrittenText(name: name, blurb: blurb, greeting: greeting)
            } catch { return nil }
        }
        #endif
        return nil
    }

    /// A short line a visitor says when the friendship reaches `level` (Pal, Friend, Best friend).
    static func levelLine(name: String, style: String, level: ParkFriendLevel) async -> String? {
        guard available, level > .stranger else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let s = LanguageModelSession(instructions: instructions)
                let r = try await s.respond(to: "\(name), a \(style) jelly creature, has just become the player's \(level.title.lowercased()). Write what \(name) says, in 8 words or fewer.",
                                            generating: ParkLineOut.self, options: GenerationOptions(temperature: 0.8))
                return ParkPool.clean(r.content.line, limit: 48)
            } catch { return nil }
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "A cute jelly creature visiting a park")
struct ParkVisitorOut {
    @Guide(description: "A cute one-word first name, at most 10 letters")
    var name: String
    @Guide(description: "One short kid-friendly sentence about its personality, at most 8 words")
    var personality: String
    @Guide(description: "What it says to say hello, one short kid-friendly sentence, at most 7 words")
    var greeting: String
}

@available(iOS 26.0, *)
@Generable(description: "One line a jelly creature says")
struct ParkLineOut {
    @Guide(description: "One short kid-friendly sentence, at most 8 words")
    var line: String
}
#endif
