//
//  VoiceGesture.swift
//  Voice v1: "double-tap, then hold, on empty space" opens listen mode. Pure classifier: the screen feeds it tap-ups and touch-downs
//  (time, point, whether a Blob was under the finger). The second down must come within 0.35 s and 40 pt of the previous EMPTY tap-up.
//  Anything on a Blob resets (a double-tap-hold on Bob is petting / holding him, not voice).
//

import CoreGraphics

nonisolated enum VoiceGestureTuning {
    static let window: Double = 0.35
    /// A first tap longer than this is a hold, not a tap, and does not arm the gesture.
    static let maxTapDuration: Double = 0.35
    static let radius: CGFloat = 40
}

nonisolated struct VoiceGesture {
    enum Result: Equatable { case none, beginVoice }

    private var lastUp: (time: Double, point: CGPoint)?

    init() {}

    /// A finished tap. Only taps on empty space arm the gesture.
    mutating func tapUp(time: Double, downTime: Double, point: CGPoint, hitBlob: Bool) {
        let isTap = time - downTime <= VoiceGestureTuning.maxTapDuration + 1e-9
        lastUp = hitBlob || !isTap ? nil : (time, point)
    }

    /// A finger went down. `.beginVoice` when it is the second down of the gesture (the host then starts listening for as long as the finger stays).
    mutating func touchDown(time: Double, point: CGPoint, hitBlob: Bool) -> Result {
        defer { lastUp = nil }       // every down consumes the pending tap
        guard !hitBlob, let up = lastUp else { return .none }
        let dt = time - up.time
        let dist = hypot(point.x - up.point.x, point.y - up.point.y)
        return dt >= 0 && dt <= VoiceGestureTuning.window + 1e-9 && dist <= VoiceGestureTuning.radius ? .beginVoice : .none
    }

    mutating func reset() { lastUp = nil }
}
