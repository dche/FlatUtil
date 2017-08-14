
import Foundation
import XCTest
@testable import FlatUtil

class ObservableMathTests: XCTestCase {

    func testConcat() {
        let o1 = Observable.from(sequence: [1,2,3])
        let o2 = Observable.from(sequence: [4,5,6])
        let o = o1.concat(o2)

        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [1,2,3,4,5,6])
        })
    }

    func testCount() {
        let o = Observable.from(sequence: [1,2,3]).count()
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [3])
        })
        expectResults(observable: Observable<Int>.empty(), satisfy: {
            // Not [0].
            XCTAssertEqual($0, [])
        })
    }

    func testReduce() {
        let o = Observable.from(sequence: [1,2,3]).reduce({
            "\($0)"
        }, {
            $0 + "\($1)"
        })
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, ["123"])
        })

        let o1 = Observable<Int>.empty().reduce(+)
        expectResults(observable: o1, satisfy: {
            XCTAssert($0.isEmpty)
        })
    }

    func testAverage() {
        let o = Observable.from(sequence: [1.0,2.0,3.0]).average()
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [2.0])
        })
    }

    func testSum() {
        let o = Observable.from(sequence: [1.0,2.0,3.0]).sum()
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [6.0])
        })
    }

    func testMax() {
        let o = Observable.from(sequence: [1,2,3]).max()
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [3])
        })
    }

    func testMin() {
        let o = Observable.from(sequence: [3,1,2]).min()
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [1])
        })
    }
}
