//
//  HeadPortrait.swift
//  What a lobby avatar asks the stage for: Jelly `jelly` as he is (his colours, his outfit), or, with `colour`, that body in a Park visitor's colour wearing the visitor's one item
//  (the Park friend who plays beside a lone Jelbie). Drawn by MelonStage.headSnapshot with the room hidden, framed on the head.
//

import Foundation
import UIKit
import ObjectiveC
import simd

struct HeadPortraitKey: Hashable, Sendable {
    var jelly: Int
    var colour: ParkColour?
    var wear: WearLook?
    /// A Show rival's body tint and name: drawn with `LocalRivalSource.palette`, exactly as the stage paints a borrowed body.
    var rivalTint: SIMD3<Float>? = nil
    var rivalName: String? = nil
    /// A Park friend's species signature (his spikes, wings, daisy ...): drawn on the borrowed body. nil (a Show rival, or no signature) = none.
    var feature: JellyFeature? = nil
    /// nil: the head portrait. 0 / 1 / 2: the Studio's full-body action shot seen from the left / front / right (see MelonStage.renderSnapshot).
    var pose: Int? = nil
    /// Another creature on this body (a Park friend or a rival): no feature, no wear of his.
    var borrowed: Bool { colour != nil || rivalTint != nil }
    /// How far above the body's centre the camera looks, and how tall the picture is (world units): the head, a hat and a little body.
    static var focusUp: Float { UserDefaults.standard.object(forKey: "HeadFocus") != nil ? UserDefaults.standard.float(forKey: "HeadFocus") : 0.30 }          // (-HeadFocus / -HeadSpan: capture aids)
    /// How far below the body's top the picture's centre sits, as a fraction of the picture's height (the crown, a hat, Moss's daisy and a margin above; the face and the chin below).
    static var topFraction: Float { UserDefaults.standard.object(forKey: "HeadTop") != nil ? UserDefaults.standard.float(forKey: "HeadTop") : 0.33 }
    /// The action shot (pose != nil): where the floor under him lands in the square picture, as a fraction of its height from the top. The renderer pins it (whatever the orientation),
    /// so the Studio's podium disc can sit at exactly this height under the picture.
    static let actionFloorFraction: CGFloat = 0.885
    /// The action shot's camera pitch above level (rad): high enough that a tutu reads as a skirt, low enough that the shoes show.
    static let actionPitch: Float = 0.36
    /// The action shot's span as a multiple of the body's height (floor to crown): the room above him for a hat. 1.42 clipped the knob of the party cone, the tallest hat in the catalogue; 1.52 keeps it whole.
    static let actionHeadroom: Float = 1.52
    // MARK: the lobby head portrait (2026-11-16, the owner: "should include their whole face, doesn't need to have the clothes")
    /// The picture shows the WHOLE face: from below the mouth (rest y 0.665) up past the brows (0.945) to the crown, with some room above it for a species feature. The camera looks down at the body like the room
    /// camera (26 degrees), so the front of the face is nearer and lower on the picture than the body's middle: the camera therefore aims at the FRONT of the face, `faceTargetForward` ahead of the body's centre,
    /// at `faceCentreBelowTop` under the crown, and the (square) picture is `faceSpan` tall. Worked out against the face's points (HeadPortraitFrameTests): mouth about -0.7, eyes -0.3, crown +0.75 of the picture's half height.
    static let faceSpan: Float = 1.28
    static let faceCentreBelowTop: Float = 0.26
    static let faceTargetForward: Float = 0.60
    /// The face's points in rest coordinates (body y up from the soles; x across): where the eyes, brows and mouth are. (Contracts.swift BobForm; the mouth is drawn at y 0.665 in Shaders.metal.)
    static let eyeY: Float = Float(BobForm.eyeY), eyeX: Float = Float(BobForm.eyeX), browY: Float = Float(BobForm.browY), browHalfLen: Float = Float(BobForm.browHalfLen), mouthY: Float = 0.665
    /// The point the portrait's camera looks at, for a body at `centre` (xz) facing `dir` whose crown is at `topY`.
    static func faceTarget(centre c: SIMD3<Float>, facing dir: SIMD3<Float>, topY: Float, scale: Float = 1) -> SIMD3<Float> {
        SIMD3<Float>(c.x + dir.x * faceTargetForward * scale, topY - faceCentreBelowTop * scale, c.z + dir.z * faceTargetForward * scale)
    }
    /// What a head portrait draws of the outfit: NOTHING (no hat, glasses, scarf, jersey, band or shoes: the face is the picture). The action shot (`pose`) keeps the outfit.
    static func outfitDrawn(_ o: [WearSlot: WearLook], pose: Int?) -> [WearSlot: WearLook] { pose == nil ? [:] : o }
    /// The camera of a head portrait / action shot: `target` looked at from `dist` away along the facing `dir` raised by `pitch` (nil: a hair above level), the picture `span` tall at the target.
    static func eye(target: SIMD3<Float>, dir: SIMD3<Float>, span: Float, aspect: Float, pitch: Float?) -> SIMD3<Float> {
        let th = tanf(GameCamera.fovY / 2)
        let dist = (span / 2) / min(th, th * aspect)
        guard let pitch else { return target + dir * dist + SIMD3(0, dist * 0.12, 0) }
        return target + (dir * cosf(pitch) + SIMD3<Float>(0, sinf(pitch), 0)) * dist
    }
    /// The pitch a head portrait looks down at (like the room camera, where the face was approved).
    static var portraitPitch: Float {
        let down = GameCamera.baseEye - GameCamera.baseTarget
        return asinf(min(max(down.y / max(simd_length(down), 1e-3), 0), 0.9))
    }
    static var span: Float { UserDefaults.standard.object(forKey: "HeadSpan") != nil ? UserDefaults.standard.float(forKey: "HeadSpan") : 1.5 }
}

private nonisolated(unsafe) var feetFractionKey: UInt8 = 0
extension UIImage {
    /// The action shot's lowest drawn pixel, as a fraction of the picture's height from the top (set by MelonStage.renderSnapshot); nil on any other picture.
    var feetFraction: CGFloat? {
        get { (objc_getAssociatedObject(self, &feetFractionKey) as? NSNumber).map { CGFloat($0.doubleValue) } }
        set { objc_setAssociatedObject(self, &feetFractionKey, newValue.map { NSNumber(value: Double($0)) }, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
