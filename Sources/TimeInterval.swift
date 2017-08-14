//
// FlatUtil - TimeInterval.swift
//
// A representation of difference between two `Time` points.
//
// Copyright (c) 2016 The FlatUtil authors.
// Licensed under MIT License.

/// Interval between two `Time` points.
///
/// - note: There is NO negative interval.
public struct TimeInterval: Comparable, Hashable {

    public let seconds: Double

    public var hashValue: Int {
        return seconds.hashValue
    }

    /// Constructs a `TimeInterval` with given `seconds`.
    public init (_ seconds: Double) {
        self.seconds = abs(seconds)
    }
}

extension TimeInterval {

    public static let zero = TimeInterval(0)

    public static let infinity = TimeInterval(Double.infinity)

    public var isZero: Bool { return seconds == 0 }

    public var isInfinite: Bool { return seconds.isInfinite }

    public static func + (lhs: TimeInterval, rhs: TimeInterval) -> TimeInterval {
        return TimeInterval(lhs.seconds + rhs.seconds)
    }

    public static func - (lhs: TimeInterval, rhs: TimeInterval) -> TimeInterval {
        return TimeInterval(lhs.seconds - rhs.seconds)
    }

    public static func * (lhs: TimeInterval, rhs: Double) -> TimeInterval {
        return TimeInterval(lhs.seconds * rhs)
    }

    public static func * (lhs: TimeInterval, rhs: Int) -> TimeInterval {
        return lhs * Double(rhs)
    }

    public static func == (lhs: TimeInterval, rhs: TimeInterval) -> Bool {
        return lhs.seconds == rhs.seconds
    }

    public static func < (lhs: TimeInterval, rhs: TimeInterval) -> Bool {
        return lhs.seconds < rhs.seconds
    }

    public var nanoseconds: Double { return self.seconds * 1e9 }

    public var microseconds: Double { return self.seconds * 1e6 }

    public var milliseconds: Double { return self.seconds * 1e3 }

    public var minutes: Double { return self.seconds / 60 }

    public var hours: Double { return self.seconds / 3600 }

    public var days: Double { return self.seconds / 86400 }
}

extension Double {

    public var microseconds: TimeInterval { return TimeInterval(self * 1e-6) }

    public var milliseconds: TimeInterval { return TimeInterval(self * 1e-3) }

    public var seconds: TimeInterval { return TimeInterval(self) }

    public var minutes: TimeInterval { return TimeInterval(self * 60) }

    public var hours: TimeInterval { return TimeInterval(self * 3600) }

    public var days: TimeInterval { return TimeInterval(self * 86400) }
}
