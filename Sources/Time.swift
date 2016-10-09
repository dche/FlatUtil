//
// FlatUtil - Time.swift
//
// A representation of time point.
//
// Copyright (c) 2016 The FlatUtil authors.
// Licensed under MIT License.

import Darwin

/// A representation of time point using double precision float number.
///
/// - note: The precision is microsecond.
public struct Time: Comparable, Hashable {

    public let secondsSinceEpoch: Double

    /// Constructs a `Time` with current time.
    public init() {
        var tv = timeval()
        gettimeofday(&tv, nil)
        secondsSinceEpoch = Double(tv.tv_sec) + Double(tv.tv_usec) * 1e-6
    }

    private init (secondsSinceEpoch: Double) {
        self.secondsSinceEpoch = secondsSinceEpoch
    }

    public var hashValue: Int {
        return secondsSinceEpoch.hashValue
    }

    public static var now: Time {
        return Time()
    }

    public static func + (lhs: Time, rhs: TimeInterval) -> Time {
        return Time(secondsSinceEpoch: lhs.secondsSinceEpoch + rhs.seconds)
    }

    public static func - (lhs: Time, rhs: TimeInterval) -> Time {
        return Time(secondsSinceEpoch: lhs.secondsSinceEpoch - rhs.seconds)
    }

    public static func - (lhs: Time, rhs: Time) -> TimeInterval {
        return TimeInterval(lhs.secondsSinceEpoch - rhs.secondsSinceEpoch)
    }

    public static func == (lhs: Time, rhs: Time) -> Bool {
        return lhs.secondsSinceEpoch == rhs.secondsSinceEpoch
    }

    public static func < (lhs: Time, rhs: Time) -> Bool {
        return lhs.secondsSinceEpoch < rhs.secondsSinceEpoch
    }
}
