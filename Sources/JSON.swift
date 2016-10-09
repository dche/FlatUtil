//
// FlatUtil - JSON.swift
//
// A simple JSON library.
//
// NOTE: JSON parser designed in this file is just a proof of concept of the
//       usability of `Result` monad.
//
// Copyright (c) 2016 The FlatUtil authors.
// Licensed under MIT License.

/* JSON Specification

object
    {}
    { members }
members
    pair
    pair , members
pair
    string : value
array
    []
    [ elements ]
elements
    value
    value , elements
value
    string
    number
    object
    array
    true
    false
    null
string
    ""
    " chars "
chars
    char
    char chars
char
    any-Unicode-character-
        except-"-or-\-or-
        control-character
    \"
    \\
    \/
    \b
    \f
    \n
    \r
    \t
    \u four-hex-digits
number
    int
    int frac
    int exp
    int frac exp
int
    digit
    digit1-9 digits
    - digit
    - digit1-9 digits
frac
    . digits
exp
    e digits
digits
    digit
    digit digits
e
    e
    e+
    e-
    E
    E+
    E-
 */

import Darwin   // for `strtod()`

enum JValue: Equatable {
    case object([String:JValue])
    case array([JValue])
    case number(Double)
    case string(String)
    case bool(Bool)
    case null

    /// The `String` representation of `self` that satisfies the JSON syntax.
    var json: String {
        switch self {
        case let .object(dict):
            let m = dict.map {
                "\(JValue.string($0).json):\($1.json)"
            }.joined(separator: ",")
            return "{\(m)}"
        case let .array(ary):
            let m = ary.map { $0.json }.joined(separator: ",")
            return "[\(m)]"
        case let .number(d):
            return "\(d)"
        case let .string(str):
            return "\"\(str)\""
        case let .bool(b):
            return "\(b)"
        case .null:
            return "null"
        }
    }

    subscript(attr: String) -> JValue? {
        switch self {
        case let .object(dict):
            return dict[attr]
        default:
            return nil
        }
    }

    subscript(i: Int) -> JValue? {
        switch self {
        case let .array(ary) where i >= 0 && i < ary.count:
            return ary[i]
        default:
            return nil
        }
    }

    static func == (lhs: JValue, rhs: JValue) -> Bool {
        switch (lhs, rhs) {
        case let (.object(ld), .object(rd)):
            return ld == rd
        case let (.array(la), .array(ra)):
            return la == ra
        case let (.number(ld), .number(rd)):
            return ld == rd
        case let (.string(ls), .string(rs)):
            return ls == rs
        case let (.bool(lb), .bool(rb)):
            return lb == rb
        case (.null, .null):
            return true
        default:
            return false
        }
    }
}

struct JSONParsingError: Error {
    let line: Int
    let column: Int
    let reason: String
}

func parse(json: String) -> Result<JValue> {

    func isNumber(_ cp: UInt8) -> Bool {
        return cp > 47 && cp < 58
    }

    struct Position {
        let string: String.UTF8View
        let index: String.UTF8View.Index
        let line: Int
        let column: Int

        var character: UInt8 {
            return string[index]
        }

        func error<T>(message: String) -> Result<T> {
            let err =
                JSONParsingError(line: line, column: column, reason: message)
            return .error(err)
        }

        func newline() -> Result<Position> {
            let idx = string.index(index, offsetBy: 1)
            guard idx < string.endIndex else {
                return self.error(message: "Unexpected end of file.")
            }
            let pos =
                Position(string: string, index: idx, line: line + 1, column: 0)
            return .value(pos)
        }

        func advance() -> Result<Position> {
            let idx = string.index(index, offsetBy: 1)
            guard idx < string.endIndex else {
                return self.error(message: "Unexpected end of file.")
            }
            let pos =
                Position(string: string, index: idx, line: line, column: column + 1)
            return .value(pos)
        }
    }

    struct ParseState<T> {
        let value: T
        let position: Position

        init (_ value: T, _ position: Position) {
            self.value = value
            self.position = position
        }
    }

    // Reads characters until a non-separator character is found.
    // Returns the position of the non-seperator character.
    func consumeSeparators(at i: Position) -> Result<Position> {
        switch i.character {
        case 10:
             // "\n"
            return i.newline().flatMap { consumeSeparators(at: $0) }
        case 32, 9, 13:
            // " ", "\t", "\r"
            return i.advance().flatMap { consumeSeparators(at: $0) }
        case let chr where chr == 47:
            // "//". Yes, line comment is supported.
            switch i.advance() {
            case let .value(p) where p.character == 47:
                var np = p
                while true {
                    switch np.advance() {
                    case let .value(p) where p.character == 10:
                        return p.advance().flatMap { consumeSeparators(at: $0) }
                    case let .value(p):
                        np = p
                        continue
                    case let err:
                        return err
                    }
                }
                break
            default:
                return .value(i)
            }
        default:
            return .value(i)
        }
    }

    // Reads a specific string starting from position `i`.
    func expect(keyword: String, at i: Position) -> Result<Position> {
        var j = i
        for ecp in keyword.utf8 {
            guard ecp == j.character else {
                return j.error(message: "Not found expected string \"\(keyword)\".")
            }
            let rp = j.advance()
            switch rp {
            case let .value(p):
                j = p
            default:
                return rp
            }
        }
        return .value(j)
    }

    func expectNumber(at i: Position) -> Result<ParseState<Double>> {

        var chars: [Character] = []

        func expectDigits(
            at i: Position
        ) -> Result<Position> {
            switch i.character {
            case let chr where isNumber(chr):
                chars.append(Character(UnicodeScalar(chr)))
                return i.advance().flatMap { expectDigits(at: $0) }
            default:
                // XXX: expect at least 1 digit.
                // Not a number is not an error.
                return .value(i)
            }
        }

        func expectInt(at i: Position) -> Result<Position> {
            return expect(keyword: "0", at: i).map { p in
                chars.append(Character("0"))
                return p
            }.orElse {
                return expectDigits(at: i)
            }
        }

        func expectFrac(at i: Position) -> Result<Position> {
            return expect(keyword: ".", at: i).flatMap { p in
                chars.append(".")
                return expectDigits(at: p)
            }
        }

        func expectExp(at i: Position) -> Result<Position> {
            return expect(keyword: "e", at: i).orElse {
                return expect(keyword: "E", at: i)
            }.flatMap { p in
                chars.append("e")
                return expect(keyword: "-", at: p).flatMap { p in
                    chars.append("-")
                    return expectDigits(at: p)
                }.orElse {
                    return expect(keyword: "+", at: p).flatMap { p in
                        return expectDigits(at: p)
                    }.orElse {
                        return expectDigits(at: p)
                    }
                }
            }
        }

        func expectDecimal(at i: Position) -> Result<Position> {
            return expectInt(at: i).flatMap { p in
                expectFrac(at: p).flatMap { p in
                    return expectExp(at: p).orElse {
                        return .value(p)
                    }
                }.orElse {
                    return expectExp(at: p).orElse {
                        return .value(p)
                    }
                }
            }
        }

        func expectDouble(at i: Position) -> Result<ParseState<Double>> {
            return expectDecimal(at: i).flatMap { p in
                let dbl = strtod(String(chars), nil)
                if errno == ERANGE {
                    var msg = "Number is too big to be represented by a double precision float number."
                    if dbl == 0.0 {
                        msg = "Number is too small to be represented by a double precision float number."
                    }
                    return i.error(message: msg)
                }
                return .value(ParseState(dbl, p))
            }
        }

        return expect(keyword: "-", at: i).flatMap { p in
            return expectDouble(at: p).map {
                ParseState($0.value * -1, $0.position)
            }
        }.orElse {
            return expectDouble(at: i)
        }
    }

    func expectString(at i: Position) -> Result<ParseState<String>> {
        func expectEscapedcharacter(at i: Position) -> Result<ParseState<Character>> {
            switch i.character {
            case 110:
                return i.advance().map {
                    ParseState(Character("\n"), $0)
                }
            case 34:
                return i.advance().map {
                    ParseState(Character("\""), $0)
                }
            case 92:
                return i.advance().map {
                    ParseState(Character("\\"), $0)
                }
            case 47:    // "\/"
                return i.advance().map {
                    ParseState(Character(UnicodeScalar(47)), $0)
                }
            case 98:    // "\b", Back space
                return i.advance().map {
                    ParseState(Character(UnicodeScalar(8)), $0)
                }
            case 102:   // "\f", Form feed
                return i.advance().map {
                    ParseState(Character(UnicodeScalar(12)), $0)
                }
            case 114:
                return i.advance().map {
                    ParseState(Character("\r"), $0)
                }
            case 116:
                return i.advance().map {
                    ParseState(Character("\t"), $0)
                }
            case 117:   // "\u"
                return i.advance().flatMap { j in
                    var u: UInt32 = 0
                    var p = j
                    for _ in 0 ..< 4 {
                        var b: UInt8 = 0
                        switch p.character {
                        case let c where isNumber(c):
                            // 0 - 9
                            b = c - 48
                        case let c where c > 96 && c < 103:
                            // a - f
                            b = c - 87
                        case let c where c > 64 && c < 71:
                            // A - F
                            b = c - 55
                        default:
                            return i.error(message: "Invalid escape sequence.")
                        }
                        u = u << 4 + UInt32(b)
                        switch p.advance() {
                        case let .value(n):
                            p = n
                        default:
                            return i.error(message: "Invalid escape sequence.")
                        }
                    }
                    guard let us = UnicodeScalar(u) else {
                        return i.error(message: "Invalid escape sequence.")
                    }
                    return .value(ParseState(Character(us), p))
                }
            default:
                return i.error(message: "Invalid escape sequence.")
            }
        }

        func expectCharacter(after: [Character], at i: Position) -> Result<ParseState<[Character]>> {
            let chr = i.character
            switch chr {
            case let c where c < 32 || c == 127:
                // Control characters.
                // CHECK: Is this enough?
                return i.error(message: "Control character appears in a string.")
            case 34:
                // "\""
                return i.advance().map { ParseState(after, $0) }
            case 92:
                // "\"
                let ps = i.advance().flatMap {
                    expectEscapedcharacter(at: $0)
                }
                // NOTE: do not use `Result#flatMap` to avoid deep stack.
                switch ps {
                case let .value(p):
                    var str = after
                    str.append(p.value)
                    return expectCharacter(after: str, at: p.position)
                case let .error(e):
                    return .error(e)
                }
            default:
                // ditto.
                switch i.advance() {
                case let .value(p):
                    var str = after
                    str.append(Character(UnicodeScalar(chr)))
                    return expectCharacter(after: str, at: p)
                case let .error(e):
                    return .error(e)
                }
            }
        }

        return expect(keyword: "\"", at: i).flatMap { p in
            return expectCharacter(after: [], at: p).map { ps in
                return ParseState(String(ps.value), ps.position)
            }
        }
    }

    func expectArray(at i: Position) -> Result<ParseState<[JValue]>> {
        return expect(keyword: "[", at: i).flatMap { p in
            return consumeSeparators(at: p).flatMap { p in
                return expect(keyword: "]", at: p).map {
                    ParseState([], $0)
                }.orElse {
                    var ary = [JValue]()
                    var pos = p
                    while true {
                        switch expectValue(at: pos) {
                        case let .value(ps):
                            ary.append(ps.value)
                            let r: Result<[JValue]> =
                                consumeSeparators(at: ps.position).flatMap { p in
                                    return expect(keyword: ",", at: p).flatMap { p in
                                        return consumeSeparators(at: p).map { p in
                                            pos = p
                                            return []
                                        }
                                    }.orElse {
                                        expect(keyword: "]", at: p).map { p in
                                            pos = p
                                            return ary
                                        }
                                    }
                                }
                            switch r {
                            case let .value(a) where a.isEmpty:
                                continue
                            case let .value(a):
                                return .value(ParseState(a, pos))
                            case let .error(err):
                                return .error(err)
                            }
                        case let .error(err):
                            return .error(err)
                        }
                    }
                }
            }
        }
    }

    func expectObject(at i: Position) -> Result<ParseState<[String:JValue]>> {
        var dict = [String:JValue]()
        func expectItem(at i: Position) -> Result<ParseState<[String:JValue]>> {
            return expectString(at: i).flatMap { ps in
                let nm = ps.value
                return consumeSeparators(at: ps.position).flatMap { p in
                    return expect(keyword: ":", at: p).flatMap { p in
                        return expectValue(at: p).flatMap { ps in
                            dict[nm] = ps.value
                            return consumeSeparators(at: ps.position).flatMap { p in
                                return expect(keyword: ",", at: p).flatMap { p in
                                    return consumeSeparators(at: p).flatMap { p in
                                        return expectItem(at: p)
                                    }
                                }.orElse {
                                    return .value(ParseState(dict, p))
                                }
                            }
                        }
                    }
                }
            }
        }

        return expect(keyword: "{", at: i).flatMap { p in
            return consumeSeparators(at: p).flatMap { p in
                return expect(keyword: "}", at: p).map {
                    ParseState([:], $0)
                }.orElse {
                    return expectItem(at: p).flatMap { ps in
                        return consumeSeparators(at: ps.position).flatMap { p in
                            expect(keyword: "}", at: p).map {
                                ParseState(ps.value, $0)
                            }
                        }
                    }
                }
            }
        }
    }

    func expectValue(at i: Position) -> Result<ParseState<JValue>> {
        return consumeSeparators(at: i).flatMap { j in
            switch j.character {
            case 123:   // "{"
                return expectObject(at: j).flatMap { ps in
                    return .value(ParseState(.object(ps.value), ps.position))
                }
            case 91:    // "["
                return expectArray(at: j).flatMap { ps in
                    return .value(ParseState(.array(ps.value), ps.position))
                }
            case 34:    // "\""
                return expectString(at: j).map { ps in
                    return ParseState(.string(ps.value), ps.position)
                }
            case 110:   // "n"
                return expect(keyword: "null", at: j).map {
                    ParseState(.null, $0)
                }
            case 116:   // "t"
                return expect(keyword: "true", at: j).map {
                    ParseState(.bool(true), $0)
                }
            case 102:   // "f"
                return expect(keyword: "false", at: j).map {
                    ParseState(.bool(false), $0)
                }
            case let chr where chr == 45 || isNumber(chr):    // "-", or number.
                return expectNumber(at: j).map { ps in
                    return ParseState(.number(ps.value), ps.position)
                }
            default:
                return j.error(message: "Unexpected character.")
            }
        }
    }

    let utf8 = (json + "\n").utf8
    let start = Position(string: utf8, index: utf8.startIndex, line: 0, column: 0)
    return consumeSeparators(at: start).flatMap {
        return expectObject(at: $0).flatMap { .value(.object($0.value)) }
    }
}
