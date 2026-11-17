//
//  NightEmoteFeetTests.swift
//  night-emotes-r1: the feet / arms invariants (leash, ring, join, collar) per night kind, every character, bare and with shoes (EmoteFeetTests.emote, isolated per kind).
//

import XCTest
@testable import BobV1

extension EmoteFeetTests {
    func testNightMoonGaze() throws { try emote("moonGaze", "idle moonGaze") }
    func testNightSleepySway() throws { try emote("sleepySway", "idle sleepySway") }
    func testNightNodOff() throws { try emote("nodOff", "idle nodOff") }
    func testNightLullabyHum() throws { try emote("lullabyHum", "idle lullabyHum") }
    func testNightStarCount() throws { try emote("starCount", "idle starCount") }
}
