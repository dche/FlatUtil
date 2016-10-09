
import XCTest
@testable import FlatUtil

class ResultTests: XCTestCase {

    enum TestError: Error {
        case a, b, c, d
    }

    func testValue() {
        let v: Result<Int> = .value(1)
        let e: Result<Int> = .error(TestError.a)
        XCTAssertNotNil(v.value)
        XCTAssertEqual(v.value!, 1)
        XCTAssertNil(e.value)
    }

    func testError() {
        let v: Result<Int> = .value(1)
        let e: Result<Int> = .error(TestError.a)
        XCTAssertNil(v.error)
        XCTAssertNil(e.value)
        XCTAssertNotNil(e.error)
        XCTAssertEqual(e.error! as! TestError, TestError.a)
    }

    func testFlatMap() {
        let v: Result<Int> = .value(1)
        let e: Result<Int> = .error(TestError.a)
        let op: (Int) -> Result<String> = { i in
            return .value("\(i)")
        }
        let strv: Result<String> = v.flatMap(op)
        XCTAssertNotNil(strv.value)
        XCTAssertEqual(strv.value!, "1")
        let ev: Result<String> = e.flatMap(op)
        XCTAssertNil(ev.value)
        XCTAssertEqual(ev.error! as! TestError, TestError.a)
    }

    func testMap() {
        let v: Result<Int> = .value(1)
        let e: Result<Int> = .error(TestError.b)
        let op: (Int) -> String = { i in
            return "\(i)"
        }
        let strv: Result<String> = v.map(op)
        XCTAssertNotNil(strv.value)
        XCTAssertEqual(strv.value!, "1")
        let ev: Result<String> = e.map(op)
        XCTAssertNil(ev.value)
        XCTAssertEqual(ev.error! as! TestError, TestError.b)
    }

    func testOrElse() {
        let v: Result<String> = .value("1")
        let e: Result<String> = .error(TestError.b)
        let op: () -> Result<String> = {
            return .value("\(2)")
        }
        let strv: Result<String> = v.orElse(op)
        XCTAssertNotNil(strv.value)
        XCTAssertEqual(strv.value!, "1")
        let ev: Result<String> = e.orElse(op)
        XCTAssertNotNil(ev.value)
        XCTAssertEqual(ev.value!, "2")
    }
}
