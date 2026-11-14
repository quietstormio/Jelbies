import Foundation
extension Date {
    /// `self <= other` / `self >= other` WITHOUT Foundation's `Date.<=` / `Date.>=` operators. Those two are `@backDeployed(before: iOS 27.2)`: on an iOS 27.2 beta
    /// seed older than the SDK the OS has no such symbol, the weak import is null and the call jumps to address 0 (13 crashes on the test phone, 2026-11-14,
    /// in Bedtime.read). Compare dates with these (or `<` / `>`), never with `<=` / `>=`. scripts/check-date-ops.sh checks a built app.
    @inline(__always) func isAtOrBefore(_ other: Date) -> Bool { timeIntervalSinceReferenceDate <= other.timeIntervalSinceReferenceDate }
    @inline(__always) func isAtOrAfter(_ other: Date) -> Bool { timeIntervalSinceReferenceDate >= other.timeIntervalSinceReferenceDate }
}
