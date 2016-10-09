
import Foundation
import XCTest
@testable import FlatUtil

class JSONTests: XCTestCase {

    func testObject() {
        let empty = "{ \n }"
        var jv = parse(json: empty).value!
        if case let .object(jo) = jv {
            XCTAssert(jo.count == 0)
            XCTAssertEqual(jv.json, "{}")
        } else {
            XCTAssert(false)
        }

        let single = "{ \"a\": \"b\" }"
        jv = parse(json: single).value!
        if case let .object(jo) = jv {
            XCTAssert(jo.count == 1)
            XCTAssertEqual(jo["a"]!, JValue.string("b"))
            XCTAssertEqual(jv.json, "{\"a\":\"b\"}")
        } else {
            XCTAssert(false)
        }

        let multi = "\n\t  \n  { \"1\"  : true,\n   \"2\" \t:\r\r\n  false,\"3\":\"3\" }"
        jv = parse(json: multi).value!
        if case let .object(jo) = jv {
            XCTAssertEqual(jo.count, 3)
            XCTAssertEqual(jo["1"]!, JValue.bool(true))
            XCTAssertEqual(jo["2"]!, JValue.bool(false))
            XCTAssertEqual(jo["3"]!, JValue.string("3"))
        } else {
            XCTAssert(false)
        }
    }

    func testArray() {
        let empty = "{ \"ary\": [] }"
        if case let .array(ary)? = parse(json: empty).value?["ary"] {
            XCTAssert(ary.isEmpty)
        } else {
            XCTAssert(false)
        }

        let strs = "{ \"ary\": [\"1\", \"2\", \"3\"] }"
        if case let .array(ary)? = parse(json: strs).value?["ary"] {
            XCTAssertEqual(ary.count, 3)
            XCTAssertEqual(ary[0], JValue.string("1"))
            XCTAssertEqual(ary[1], JValue.string("2"))
            XCTAssertEqual(ary[2], JValue.string("3"))
        } else {
            XCTAssert(false)
        }
    }

    func testEmptyString() {
        let str = "{\"str\":\"\"}"
        if case let .string(str)? = parse(json: str).value?["str"] {
            XCTAssert(str.isEmpty)
        } else {
            XCTAssert(false)
        }
    }

    func testEscapedCharacters() {
        var str = "{\"str\":\"\\/\\b\\r\\f\\n\\t\\\"\\\\\"}"
        if case let .string(str)? = parse(json: str).value?["str"] {
            let chars = str.characters
            XCTAssertEqual(chars.count, 8)
        } else {
            XCTAssert(false)
        }

        str = "{\"str\":\"\\u0046\\u004c\\n\\u0041\\u0054\\u002D!\"}"
        if case let .string(str)? = parse(json: str).value?["str"] {
            XCTAssertEqual(str, "FL\nAT-!")
        } else {
            XCTAssert(false)
        }
    }

    func testNumber() {
        let expectations: [String:Double] = [
            "{\"a\": 123}":123.0,
            "{\"a\": -0}":0.0,
            "{\"a\": -123}":-123.0,
            "{\"a\": 0.0123}":0.0123,
            "{\"a\": -0.123}":-0.123,
            "{\"a\": -0e2}":-0e2,
            "{\"a\": 1e-6}":1e-6,
            "{\"a\": 0.31415926e+1}":3.1415926,
            "{\"a\": 123.123E123}":123.123E123,
        ]
        for (s, d) in expectations {
            if case let .number(n)? = parse(json: s).value?["a"] {
                XCTAssertEqual(n, d)
            } else {
                XCTAssert(false)
            }
        }
    }

    func testLiterals() {
        let str = "{\"null\": null,\n\"true\": true,\n\"false\": false}"
        let jv = parse(json: str).value!
        guard
            case .null? = jv["null"],
            case let .bool(t)? = jv["true"],
            case let .bool(f)? = jv["false"]
        else {
            XCTAssert(false)
            return
        }
        XCTAssert(t)
        XCTAssertFalse(f)
    }
}
