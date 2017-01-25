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

// for `strtod()`
#if os(macOS)
    import Darwin
#else
    import Glibc
#endif

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

func parse(json: String) -> Result<JValue> {

    func isNumber(_ cp: UInt8) -> Bool {
        return cp > 47 && cp < 58
    }

    // Reads characters until a non-separator character is found.
    // Returns the position of the non-seperator character.
    func consumeSeparators(at i: ParsingPosition) -> Result<ParsingPosition> {
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
    func expect(keyword: String, at i: ParsingPosition) -> Result<ParsingPosition> {
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

    func expectNumber(at i: ParsingPosition) -> Result<ParsingState<Double>> {

        var chars: [Character] = []

        func expectDigits(
            at i: ParsingPosition
        ) -> Result<ParsingPosition> {
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

        func expectInt(at i: ParsingPosition) -> Result<ParsingPosition> {
            return expect(keyword: "0", at: i).map { p in
                chars.append(Character("0"))
                return p
            }.orElse {
                return expectDigits(at: i)
            }
        }

        func expectFrac(at i: ParsingPosition) -> Result<ParsingPosition> {
            return expect(keyword: ".", at: i).flatMap { p in
                chars.append(".")
                return expectDigits(at: p)
            }
        }

        func expectExp(at i: ParsingPosition) -> Result<ParsingPosition> {
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

        func expectDecimal(at i: ParsingPosition) -> Result<ParsingPosition> {
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

        func expectDouble(at i: ParsingPosition) -> Result<ParsingState<Double>> {
            return expectDecimal(at: i).flatMap { p in
                let dbl = strtod(String(chars), nil)
                if errno == ERANGE {
                    var msg = "Number is too big to be represented by a double precision float number."
                    if dbl == 0.0 {
                        msg = "Number is too small to be represented by a double precision float number."
                    }
                    return i.error(message: msg)
                }
                return .value(ParsingState(dbl, p))
            }
        }

        return expect(keyword: "-", at: i).flatMap { p in
            return expectDouble(at: p).map {
                ParsingState($0.value * -1, $0.position)
            }
        }.orElse {
            return expectDouble(at: i)
        }
    }

    func expectString(at i: ParsingPosition) -> Result<ParsingState<String>> {
        func expectEscapedcharacter(at i: ParsingPosition) -> Result<ParsingState<Character>> {
            switch i.character {
            case 110:
                return i.advance().map {
                    ParsingState(Character("\n"), $0)
                }
            case 34:
                return i.advance().map {
                    ParsingState(Character("\""), $0)
                }
            case 92:
                return i.advance().map {
                    ParsingState(Character("\\"), $0)
                }
            case 47:    // "\/"
                return i.advance().map {
                    ParsingState(Character(UnicodeScalar(47)), $0)
                }
            case 98:    // "\b", Back space
                return i.advance().map {
                    ParsingState(Character(UnicodeScalar(8)), $0)
                }
            case 102:   // "\f", Form feed
                return i.advance().map {
                    ParsingState(Character(UnicodeScalar(12)), $0)
                }
            case 114:
                return i.advance().map {
                    ParsingState(Character("\r"), $0)
                }
            case 116:
                return i.advance().map {
                    ParsingState(Character("\t"), $0)
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
                    return .value(ParsingState(Character(us), p))
                }
            default:
                return i.error(message: "Invalid escape sequence.")
            }
        }

        func expectCharacter(after: [Character], at i: ParsingPosition) -> Result<ParsingState<[Character]>> {
            let chr = i.character
            switch chr {
            case let c where c < 32 || c == 127:
                // Control characters.
                // CHECK: Is this enough?
                return i.error(message: "Control character appears in a string.")
            case 34:
                // "\""
                return i.advance().map { ParsingState(after, $0) }
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
                return ParsingState(String(ps.value), ps.position)
            }
        }
    }

    func expectArray(at i: ParsingPosition) -> Result<ParsingState<[JValue]>> {
        return expect(keyword: "[", at: i).flatMap { p in
            return consumeSeparators(at: p).flatMap { p in
                return expect(keyword: "]", at: p).map {
                    ParsingState([], $0)
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
                                return .value(ParsingState(a, pos))
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

    func expectObject(at i: ParsingPosition) -> Result<ParsingState<[String:JValue]>> {
        var dict = [String:JValue]()
        func expectItem(at i: ParsingPosition) -> Result<ParsingState<[String:JValue]>> {
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
                                    return .value(ParsingState(dict, p))
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
                    ParsingState([:], $0)
                }.orElse {
                    return expectItem(at: p).flatMap { ps in
                        return consumeSeparators(at: ps.position).flatMap { p in
                            expect(keyword: "}", at: p).map {
                                ParsingState(ps.value, $0)
                            }
                        }
                    }
                }
            }
        }
    }

    func expectValue(at i: ParsingPosition) -> Result<ParsingState<JValue>> {
        return consumeSeparators(at: i).flatMap { j in
            switch j.character {
            case 123:   // "{"
                return expectObject(at: j).flatMap { ps in
                    return .value(ParsingState(.object(ps.value), ps.position))
                }
            case 91:    // "["
                return expectArray(at: j).flatMap { ps in
                    return .value(ParsingState(.array(ps.value), ps.position))
                }
            case 34:    // "\""
                return expectString(at: j).map { ps in
                    return ParsingState(.string(ps.value), ps.position)
                }
            case 110:   // "n"
                return expect(keyword: "null", at: j).map {
                    ParsingState(.null, $0)
                }
            case 116:   // "t"
                return expect(keyword: "true", at: j).map {
                    ParsingState(.bool(true), $0)
                }
            case 102:   // "f"
                return expect(keyword: "false", at: j).map {
                    ParsingState(.bool(false), $0)
                }
            case let chr where chr == 45 || isNumber(chr):    // "-", or number.
                return expectNumber(at: j).map { ps in
                    return ParsingState(.number(ps.value), ps.position)
                }
            default:
                return j.error(message: "Unexpected character.")
            }
        }
    }

    let utf8 = (json + "\n").utf8
    let start = ParsingPosition(string: utf8, index: utf8.startIndex, line: 0, column: 0)
    return consumeSeparators(at: start).flatMap {
        return expectObject(at: $0).flatMap { .value(.object($0.value)) }
    }
}
