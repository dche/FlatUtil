
import XCTest
@testable import FlatUtil

class RegexpTests: XCTestCase {

    let pattern = Regexp(pattern: "ab((cd)?[0-9]{2})")!

    func testFirstMatch() {
        var str = "ab123"
        XCTAssert(str ~= pattern)
        var mr = str.firstMatch(regexp: pattern)!
        XCTAssertEqual(mr.count, 3)
        XCTAssertEqual(mr[0], "ab12")
        XCTAssertEqual(mr[1], "12")
        XCTAssert(mr[2].isEmpty)

        str = "__abcd12"
        XCTAssert(str ~= pattern)
        mr = str.firstMatch(regexp: pattern)!
        XCTAssertEqual(mr.count, 3)
        XCTAssertEqual(mr[0], "abcd12")
        XCTAssertEqual(mr[1], "cd12")
        XCTAssertEqual(mr[2], "cd")
    }

    func testMatch() {
        let str = "ab12ab34//abcd5678_ab90"
        let mrs = str.match(regexp: pattern)
        XCTAssertEqual(mrs.count, 4)
        XCTAssertEqual(mrs[0][0], "ab12")
        XCTAssertEqual(mrs[1][0], "ab34")
        XCTAssertEqual(mrs[2][0], "abcd56")
        XCTAssertEqual(mrs[3][0], "ab90")
    }

    func testEmptyPattern() {
        let re = Regexp(pattern: "(a?)")!
        let str = "b"
        XCTAssert(str ~= re)
        let mr = str.firstMatch(regexp: re)!
        XCTAssertEqual(mr.count, 2)
        XCTAssertEqual(mr[0], "")
        XCTAssert(mr[1].isEmpty)
    }

    func testNotMatch() {
        let str = "ab1"
        XCTAssertFalse(str ~= pattern)
        let mr = str.firstMatch(regexp: pattern)
        XCTAssertNil(mr)
        let mrs = str.match(regexp: pattern)
        XCTAssert(mrs.isEmpty)
    }

    // SWIFT EVOLUTION:
    // func testBinding() {
    // }
}
