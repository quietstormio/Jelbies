//
//  TrainCardSnapshotTests.swift
//  Renders the Train card for every step at phone width (portrait ~ 440 pt, landscape ~ 360 pt card) to $TRAIN_OUT (the simulator's render loop cannot
//  drive the 3D room here, so the card is captured on its own). Asserts only that each step renders.
//

import XCTest
import SwiftUI
@testable import BobV1

@MainActor
final class TrainCardSnapshotTests: XCTestCase {
    func testRenderEveryStep() throws {
        let out = ProcessInfo.processInfo.environment["TRAIN_OUT"] ?? NSTemporaryDirectory() + "train_cards"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let book = VoiceTraining(defaults: UserDefaults(suiteName: "TrainCardSnap")!, persists: false, random: { 0 })
        let v = VoiceCoordinator(training: book, input: FakeSpeechInput(), now: { 0 })
        let tr = TrainSession(subject: 0)
        v.train = tr
        book.debugReps(.jacks, word: "boing", reps: 0)
        let steps: [(String, TrainStep, Int)] = [
            ("01_pick", .pick, 0), ("02_demo", .demo(.sit), 0), ("03_say_now", .listen(.sit), 0), ("04_pips_1", .heard(.sit, reps: 1), 1),
            ("05_pips_2", .heard(.sit, reps: 2), 2), ("06_learned", .learned(.sit), 3), ("07_tryit", .tryIt(.sit), 3),
            ("08_tried", .tried(.sit, ok: true, heard: "sit"), 3), ("09_didnt_catch", .missed(.sit, why: .otherWord(expected: "sit", heard: "set")), 1)]
        for (name, step, reps) in steps {
            if reps > 0 { book.debugReps(.sit, word: "sit", reps: min(reps, 2)) }
            if reps == 3 { book.debugLearn(.sit, word: "sit") }
            if reps == 1 { tr.heardText = "set" }
            tr.go(step)
            for (tag, landscape, size) in [("P", false, CGSize(width: 402, height: 300)), ("L", true, CGSize(width: 400, height: 300))] {
                let view = ZStack(alignment: .bottomTrailing) { Color(red: 0.79, green: 0.63, blue: 0.5); TrainCard(voice: v, landscape: landscape).padding(10) }
                    .frame(width: size.width, height: size.height)
                let r = ImageRenderer(content: view); r.scale = 3
                let png = r.uiImage?.pngData()
                XCTAssertNotNil(png, name)
                try png?.write(to: URL(fileURLWithPath: "\(out)/\(tag)_\(name).png"))
            }
        }
    }
}
