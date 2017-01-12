//
// FlatUtil - Regexp.swift
//
// A simple wrapper of `NSRegularExpression`.
//
// Copyright (c) 2016 The FlatUtil authors.
// Licensed under MIT License.

import Foundation

#if os(Linux)
    public typealias NSRegularExpression = RegularExpression
    public typealias NSTextCheckingResult = TextCheckingResult
#endif

/// A simple wrapper of `NSRegularExpression`.
///
/// - Example
///
/// ```swift
/// import FlatUtil
///
/// let re = Regexp(":ab(c+)")!
/// assert("abc" ~= re)
/// let mr = "abc".firstMatch(regexp: re)
/// assert(mr.count = 2)
/// assert(mr[0] == "abc")
/// assert(mr[1] == "c")
/// ````
public struct Regexp: Equatable, Hashable {

    /// Result of regular expression matching.
    public struct MatchResult {

        private let matches: [String]

        fileprivate init (string: String, results: NSTextCheckingResult) {
            var ms = [String](repeating: "", count: results.numberOfRanges)
            // SWIFT EVOLUTION: Don't use NSString.
            let ns = NSString(string: string)
            var rg = results.range
            if rg.length > 0 {
                ms[0] = String.init(ns.substring(with: results.range))
                for i in 1 ..< results.numberOfRanges {
#if os(Linux)
                    rg = results.range(at: i)
#else
                    rg = results.rangeAt(i)
#endif
                    if rg.length < 1 { continue }
                    ms[i] = String.init(ns.substring(with: rg))
                }
            }
            self.matches = ms
        }

        /// Number of capture groups.
        public var count: Int {
            return matches.count
        }

        /// Returns the content of `i`th capture group.
        public subscript (i: Int) -> String {
            return matches[i]
        }

        // SWIFT EVOLUTION: let binding `MatchResult` to a tuple.
        // public static func ~=(lhs: MatchResult, rhs: (String) -> Bool {
        //     return false
        // }
    }

    fileprivate let nsre: NSRegularExpression

    /// Constructs a `Regexp` from given `NSRegularExpression`.
    public init (_ re: NSRegularExpression) {
        self.nsre = re
    }

    public typealias Options = NSRegularExpression.Options

    /// Constructs a `Regexp` from a `String`; returns `nil` if the string
    /// is not a valid regular expression pattern.
    public init? (pattern re: String, options: Options = []) {
        do {
            self.nsre = try NSRegularExpression(pattern: re, options: options)
        } catch {
            return nil
        }
    }

    public var hashValue: Int {
        return self.nsre.hashValue
    }

    public static func == (lhs: Regexp, rhs: Regexp) -> Bool {
        return lhs.nsre == rhs.nsre
    }
}

extension String {

    /// Matches `self` with pattern `regexp`, and returns _all_ match results.
    public func match(regexp: Regexp) -> [Regexp.MatchResult] {
        let r = NSRange(0 ..< self.characters.count)
        return regexp.nsre.matches(in: self, options: [], range: r).map {
            Regexp.MatchResult(string: self, results: $0)
        }
    }

    /// Matches `self` with pattern `regexp`, and returns the first match
    /// result.
    ///
    /// Returns `nil` if `self` does not match the pattern.
    public func firstMatch(regexp: Regexp) -> Regexp.MatchResult? {
        let mr = regexp.nsre.firstMatch(in: self, options: [], range: NSRange(0 ..< self.characters.count))
        return mr.map { Regexp.MatchResult(string: self, results: $0) }
    }

    public static func ~= (lhs: String, rhs: Regexp) -> Bool {
        return lhs.firstMatch(regexp: rhs) != nil
    }
}
