import Foundation

/// A single monotonic time source for the whole pipeline.
///
/// Event timestamps, frame timestamps and gesture deadlines must all come from
/// the same clock or the physics quietly misbehaves. Wall-clock time is unusable
/// here: an NTP correction or a daylight-saving jump would make `dt` negative
/// and send the scroll engine backwards.
public enum MonotonicClock {
    /// Seconds since boot, unaffected by clock adjustments. Does not advance
    /// while the machine is asleep, which is what we want — a gesture
    /// interrupted by a lid close should not resume as though hours passed.
    @inlinable
    public static var now: Double { ProcessInfo.processInfo.systemUptime }
}
