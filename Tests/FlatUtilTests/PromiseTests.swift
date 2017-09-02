
import Foundation
import XCTest
@testable import FlatUtil

enum PromiseTestError: Error {
    case this, that
}

class PromiseTests: XCTestCase {

    func testResolve() {
        let p = Promise.resolve(2)
        let pv = p.await()
        XCTAssertNotNil(pv)
        XCTAssertEqual(pv, 2)
    }

    func testReject() {
        let p = Promise<Int>.reject(PromiseTestError.this)
        let pv = p.await()
        XCTAssertNil(pv)
    }

    func testThen() {
        let p = Promise.resolve(2).then({ $0 * 2 })
        let pv = p.await()
        XCTAssertNotNil(pv)
        XCTAssertEqual(pv, 4)
    }

    func testCatch() {
        let p = Promise<Int>.reject(PromiseTestError.that).catch({ _ in
            return 2
        })
        let pv = p.await()
        XCTAssertNotNil(pv)
        XCTAssertEqual(pv, 2)
    }

    func testAwait() {
        let p = Promise(operation: { () -> Result<Int> in
            usleep(100_000)
            return .value(2 + 2)
        })
        let pv = p.await()
        XCTAssertNotNil(pv)
        XCTAssertEqual(pv, 4)
    }

    func testAll() {
        let p = Promise<[Int]>.all([1,2,3,4].map { i in
            Promise { () -> Result<Int> in
                usleep(UInt32(i) * 10_000)
                return .value(i * i)
            }
        })
        let pv = p.await()
        XCTAssertNotNil(pv)
        XCTAssertEqual(pv!, [1,4,9,16])
    }

    func testRace() {
        var p = Promise<[Int]>.race([2,3,4,1].map { i in
            Promise { () -> Result<Int> in
                usleep(UInt32(i) * 10_000)
                return .value(i * i)
            }
        })
        var pv = p.await()
        XCTAssertNotNil(pv)
        XCTAssertEqual(pv!, 1)

        p = Promise<[Int]>.race([2,3,4,1].map { i in
            Promise { () -> Result<Int> in
                usleep(UInt32(i) * 10_000)
                guard i != 1 else {
                    return .error(PromiseTestError.that)
                }
                return .value(i * i)
            }
        })
        pv = p.await()
        XCTAssertNil(pv)
    }
}
