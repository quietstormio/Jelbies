//
//  HeadPortrait.swift
//  What a lobby avatar asks the stage for: Jelly `jelly` as he is (his colours, his outfit), or, with `colour`, that body in a Park visitor's colour wearing the visitor's one item
//  (the Park friend who plays beside a lone Jelbie). Drawn by MelonStage.headSnapshot with the room hidden, framed on the head.
//

import Foundation
import UIKit
import ObjectiveC

struct HeadPortraitKey: Hashable, Sendable {
    var jelly: Int
    var colour: ParkColour?
    var wear: WearLook?
    /// A Show rival's body tint and name: drawn with `LocalRivalSource.palette`, exactly as the stage paints a borrowed body.
    var rivalTint: SIMD3<Float>? = nil
    var rivalName: String? = nil
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
