//
//  ParkMusicTests.swift
//  The park playlist (2026-11-06): six tracks, Skip cycles only park songs, "Park · title" with Skip, every file bundled and decodable.
//

import XCTest
@testable import BobV1

@MainActor
final class ParkMusicTests: XCTestCase {
    private func isSceneOn(_ e: MusicEvent) -> Bool { if case .sceneOn = e { return true } else { return false } }

    func testParkPlaylistHasSixTracksAndCafeIsUnchanged() {
        XCTAssertEqual(ParkMusic.tracks.map(\.title), ["Sunny Lawn", "Picnic Hour", "Dandelion Drift", "Duck Pond", "Swing Set Breeze", "Cloud Watching"])
        XCTAssertEqual(ParkMusic.tracks.map(\.track), [.park1, .park2, .park3, .park4, .park5, .park6])
        XCTAssertTrue(MusicScene.park.isPlaylist)
        XCTAssertEqual(MusicScene.park.tracks, ParkMusic.tracks.map(\.track))
        XCTAssertEqual(CafeMusic.tracks.count, 8)
        XCTAssertEqual(MusicScene.cafe.tracks, CafeMusic.tracks.map(\.track))
    }

    func testSkipCyclesThroughParkTracksOnlyAndAdvancesAtTheEnd() {
        var rnd = 0.0
        var d = MusicDirector(length: { _ in 90 }, rand: { rnd += 0.37; return rnd.truncatingRemainder(dividingBy: 1) })
        var input = MusicInput(); input.scene = .none
        _ = d.update(dt: 1, input: input)
        input.scene = .park
        var ev = d.update(dt: 1, input: input)
        guard case .sceneOn(let first, _)? = ev.first(where: isSceneOn) else { return XCTFail("the park starts a track") }
        let park = Set(ParkMusic.tracks.map(\.track))
        XCTAssertTrue(park.contains(first))
        var seen = [first]
        for _ in 0..<(ParkMusic.tracks.count - 1) {
            for _ in 0..<2 { _ = d.update(dt: 1, input: input) }
            ev = d.skip()
            guard case .sceneOn(let t, _)? = ev.first else { return XCTFail("skip in the park plays the next park track") }
            XCTAssertTrue(park.contains(t), "only park songs")
            XCTAssertFalse(seen.contains(t), "no repeat until the list is through")
            seen.append(t)
        }
        XCTAssertEqual(Set(seen), park)
        var advanced = false
        for _ in 0..<(Int(d.sceneTrack!.loopEnd) + 5) { if d.update(dt: 1, input: input).contains(where: isSceneOn) { advanced = true; break } }
        XCTAssertTrue(advanced, "the park playlist advances at the end of a track")
    }

    func testNowPlayingSaysParkTitleAndCanSkip() {
        func np(_ t: SceneTrack?) -> NowPlaying {
            NowPlaying.make(muted: false, musicOn: true, musicVolume: 1, otherAudioPlaying: false, mode: .day, scene: .park, current: nil, inGap: false, layerOn: false, sceneTrack: t)
        }
        for (t, title) in ParkMusic.tracks {
            XCTAssertEqual(np(t).line, "Park · \(title)")
            XCTAssertTrue(np(t).canSkip)
        }
        XCTAssertEqual(np(.park4).line, "Park · Duck Pond")
        XCTAssertEqual(np(nil).line, "Park · Playlist")
    }

    func testEveryParkTrackIsBundledAndLoops() {
        let b = Bundle(for: AudioHub.self)
        for t in ParkMusic.tracks {
            guard let len = SceneRender.fileLength(t.track, bundle: b) else { XCTFail("\(t.track) is not bundled"); continue }
            XCTAssertEqual(t.track.loopStartFrame, 2_000, "\(t.track)")
            XCTAssertGreaterThan(t.track.loopEndFrame, t.track.loopStartFrame, "\(t.track)")
            XCTAssertLessThanOrEqual(t.track.loopEndFrame, len, "\(t.track): the loop ends inside the file")
            XCTAssertNotNil(SceneRender.render(t.track, bundle: b), "\(t.track) decodes to a playable loop")
        }
    }
}
